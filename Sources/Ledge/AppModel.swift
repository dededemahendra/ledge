import AppKit
import Foundation
import ActivityKit
import NotchKit
import PowerService
import HUDService
import MediaService
import DeviceService
import OSLog

/// Consumes service streams, maintains the queue, drives the controller.
/// The only place where services and UI meet.
@MainActor
final class AppModel {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "model")

    private let presenter: NotchPresenter
    private let power = PowerService()
    private let hud = HUDService()
    private let media = MediaService()
    private let device = DeviceService()

    private var queue = ActivityQueue()
    private var tasks: [Task<Void, Never>] = []
    private var pruneTimer: Timer?
    /// The last payload `MediaService` sent, kept around because a
    /// `NotchIntent.seek(fraction:)` and the 1Hz position tick both need the
    /// live duration/elapsed/timestamp/rate — none of which `NotchController`
    /// carries (it only ever gets the already-computed `MediaPresentation`).
    private var mediaPayload = MediaPayload()
    private var positionTimer: Timer?
    /// Every service's status text, joined; compared on each prune tick so
    /// the menu rows follow ANY availability change — power and devices
    /// have no change hook of their own (review, 2026-09-29).
    private var statusFingerprint = ""

    init(presenter: NotchPresenter) {
        self.presenter = presenter
    }

    var powerStatus: String { power.availability.statusText }
    var hudStatus: String { hud.availability.statusText }
    var mediaStatus: String { media.availability.statusText }
    var deviceStatus: String { device.availability.statusText }

    /// What the menu should say — only problems (2026-09-29, minimal menu).
    /// A service that is fine contributes nothing. The Accessibility grant
    /// is the one problem the user can fix from here, so its row opens the
    /// right Settings pane.
    struct Issue {
        let text: String
        let fix: (() -> Void)?
    }

    var issues: [Issue] {
        var issues: [Issue] = []
        func note(_ name: String, _ availability: ServiceAvailability) {
            switch availability {
            case .available: break
            case .needsPermission(let what): issues.append(Issue(text: "\(name) needs \(what)", fix: nil))
            case .unavailable(let reason): issues.append(Issue(text: "\(name) unavailable — \(reason)", fix: nil))
            }
        }
        note("Power", power.availability)
        note("HUD", hud.availability)
        note("Media", media.availability)
        note("Devices", device.availability)
        if case .needsPermission = hud.systemHUDReplacement {
            issues.append(Issue(text: "System HUD needs Accessibility…", fix: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }))
        }
        return issues
    }

    var isPanelOpen: Bool { presenter.controller.state == .expanded }
    var isSuppressingStockOSD: Bool { hud.isSuppressingStockOSD }
    var systemHUDStatus: String {
        switch hud.systemHUDReplacement {
        case .available:                 return "replaced"
        case .needsPermission(let what): return "needs \(what) — grant in System Settings › Privacy & Security"
        case .unavailable:               return "off"
        }
    }
    /// Fires on the main actor whenever any status row's text may have
    /// changed: the Accessibility grant landing, media giving up or
    /// recovering. `AppDelegate` refreshes every row from it — cheaper to
    /// reason about than one hook per service, and the rows are four
    /// strings.
    var onStatusChange: (() -> Void)? {
        didSet {
            hud.onSystemHUDReplacementChange = { [weak self] _ in self?.onStatusChange?() }
            media.onAvailabilityChange = { [weak self] _ in self?.onStatusChange?() }
        }
    }

    func toggleStockOSDSuppression() {
        hud.setSuppressStockOSD(!hud.isSuppressingStockOSD)
    }

    func start() {
        let stream = power.start()
        tasks.append(Task { [weak self] in
            for await event in stream {
                self?.handle(event)
            }
        })

        let hudStream = hud.start()
        tasks.append(Task { [weak self] in
            for await event in hudStream {
                self?.handle(event)
            }
        })

        let mediaStream = media.start()
        tasks.append(Task { [weak self] in
            for await payload in mediaStream {
                self?.handle(payload)
            }
        })

        // The panel's output picker follows CoreAudio's device list; set
        // before `start()` so the initial enumeration is not missed.
        device.onOutputsChange = { [weak self] outputs in
            self?.presenter.controller.setOutputs(outputs.map {
                OutputOption(id: $0.id, name: $0.name, symbolName: $0.symbolName, isCurrent: $0.isCurrent)
            })
        }
        let deviceStream = device.start()
        tasks.append(Task { [weak self] in
            for await event in deviceStream {
                self?.handle(event)
            }
        })

        // The other direction: the panel's buttons/scrubber emit `NotchIntent`s
        // through the controller; this is the one place they get turned into
        // outbound `MediaCommand`s.
        presenter.controller.onIntent = { [weak self] intent in
            self?.handle(intent)
        }

        // Expiry is driven here, not inside the queue, so the queue stays pure.
        // Built with `Timer(...)` + `RunLoop.main.add(forMode: .common)`,
        // not `Timer.scheduledTimer`, which only schedules on `.default` --
        // TTL expiry would otherwise stall while a menu is tracking or a
        // drag is in progress (same fix as PowerService's run-loop source).
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.prune() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pruneTimer = timer
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        pruneTimer?.invalidate()
        pruneTimer = nil
        stopPositionTicking()
        hud.stop()
        power.stop()
        media.stop()
        device.stop()
    }

    /// Devices ride the same `ActivityRecord` shape as power: a title for
    /// the detail row, a glyph for the leading ear, an optional battery
    /// percentage for the trailing ear. Same id for every device event, so
    /// AirPods connecting right after a keyboard coalesces into one slot.
    private func handle(_ event: DeviceEvent) {
        // The system's own product render for AirPods (`DeviceArtwork`),
        // read from disk here — one small file, once per route change —
        // rather than on the service's CoreAudio callback. Only Bluetooth
        // routes can be AirPods; everything else keeps the glyph.
        var artwork: Data?
        if case .outputChanged(let name, .bluetooth, _) = event {
            artwork = DeviceArtwork.load(forDeviceNamed: name)
        }
        queue.insert(
            ActivityRecord(
                id: ActivityKind.device.rawValue,
                kind: .device,
                insertedAt: Date(),
                ttl: ActivityKind.device.defaultTTL,
                title: event.activityTitle,
                compactText: event.compactText,
                symbolName: event.symbolName,
                artwork: artwork
            )
        )
        publish()
    }

    private func handle(_ event: PowerEvent) {
        // The display dims on battery and brightens on AC by itself; the
        // HUD service must not read that as a brightness key.
        hud.notePowerSourceChanged()
        queue.insert(
            ActivityRecord(
                id: ActivityKind.power.rawValue,
                kind: .power,
                insertedAt: Date(),
                ttl: ActivityKind.power.defaultTTL,
                title: event.activityTitle,
                compactText: event.compactText,
                symbolName: event.symbolName
            )
        )
        publish()
    }

    /// Presentation fields (`symbolName`/`barFill`) ride on `ActivityRecord`
    /// itself, same as `compactText` — not a side-table keyed by activity id.
    /// `ActivityRecord` already carries `title`/`detail`, which are equally
    /// presentational, and a side-table would need hand-maintained
    /// synchronisation with `insert`/coalesce/`prune` that no test covers.
    private func handle(_ event: HUDEvent) {
        queue.insert(
            ActivityRecord(
                id: ActivityKind.hud.rawValue,
                kind: .hud,
                insertedAt: Date(),
                ttl: ActivityKind.hud.defaultTTL,
                title: event.activityTitle,
                compactText: event.compactText,
                symbolName: event.symbolName,
                barFill: event.barFill
            )
        )
        publish()
    }

    /// Never logs `payload.title`/`.artist`/`.album` — someone's listening
    /// history — and doesn't log anything else about this event either,
    /// matching `handle(_ event: PowerEvent)`/`handle(_ event: HUDEvent)`
    /// above, neither of which logs on this path.
    private func handle(_ payload: MediaPayload) {
        mediaPayload = payload

        // Music apps only (`MediaSourcePolicy`): a browser tab or a video
        // call is not "now playing" for the island, however loudly
        // MediaRemote reports it. Falls into the nothing-playing branch so
        // the artwork, the panel and the position tick all go away too.
        guard payload.hasMedia, let title = payload.title,
              MediaSourcePolicy.isAllowed(bundleIdentifier: payload.bundleIdentifier) else {
            queue.remove(kind: .media)
            presenter.controller.setMedia(nil)
            stopPositionTicking()
            publish()
            return
        }

        queue.insert(
            ActivityRecord(
                id: ActivityKind.media.rawValue,
                kind: .media,
                insertedAt: Date(),
                ttl: nil,                     // sticky — the island's resting state
                title: title,
                detail: payload.artist
            )
        )
        refreshMediaPresentation()
        payload.isPlaying ? startPositionTicking() : stopPositionTicking()
        publish()
    }

    private func handle(_ intent: NotchIntent) {
        switch intent {
        case .togglePlayPause: media.send(.togglePlayPause)
        case .next:             media.send(.nextTrack)
        case .previous:         media.send(.previousTrack)
        case .toggleShuffle:    media.send(.toggleShuffle)
        case .toggleRepeat:     media.send(.toggleRepeat)
        case .selectOutput(let id): device.setDefaultOutput(uid: id)
        case .openSource:           openSourceApp()
        case .seek(let fraction):
            // The scrubber only knows its own width, not the track's
            // duration — this is the one place both are in scope.
            guard let duration = mediaPayload.duration, duration > 0 else { return }
            media.send(.seek(seconds: duration * fraction))
        }
    }

    /// Brings the app that is playing to the front. LaunchServices first
    /// (`openApplication(at:)` with `activates`), keyed by bundle id: it
    /// works from a background agent like this one, where macOS 14's
    /// cooperative activation would refuse a bare
    /// `NSRunningApplication.activate()` because Ledge is never the active
    /// app itself. The pid path is the fallback for a running app that
    /// LaunchServices cannot locate by bundle id (an unbundled binary).
    private func openSourceApp() {
        if let bundleID = mediaPayload.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return
        }
        if let pid = mediaPayload.processIdentifier,
           let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            app.activate()
        }
    }

    /// 1Hz, and only while something is playing — `MediaService`'s own
    /// `MediaPosition.elapsed` extrapolates locally from the last known
    /// `elapsedTime`/`timestamp`/`rate`; the adapter itself is never polled.
    ///
    /// Built with `Timer(...)` + `RunLoop.main.add(forMode: .common)`, not
    /// `Timer.scheduledTimer` — same fix, and same reason, as `pruneTimer`
    /// above: `.scheduledTimer` only schedules on `.default` mode, which
    /// stalls while a menu is tracking or **a drag is in progress**, and
    /// this task adds exactly such a drag — the panel's scrub bar, right
    /// next to the elapsed-time label this timer drives. `.common` keeps
    /// that label ticking even while the user is mid-drag on the scrubber.
    private func startPositionTicking() {
        guard positionTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMediaPresentation() }
        }
        RunLoop.main.add(timer, forMode: .common)
        positionTimer = timer
    }

    private func stopPositionTicking() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func refreshMediaPresentation() {
        guard mediaPayload.hasMedia, let title = mediaPayload.title else { return }
        let elapsed = MediaPosition.elapsed(
            at: Date(),
            elapsedTime: mediaPayload.elapsedTime ?? 0,
            timestamp: mediaPayload.timestamp ?? Date(),
            rate: mediaPayload.isPlaying ? (mediaPayload.playbackRate ?? 1) : 0,
            duration: mediaPayload.duration
        )
        presenter.controller.setMedia(
            MediaPresentation(
                title: title,
                artist: mediaPayload.artist,
                artwork: mediaPayload.artworkData,
                isPlaying: mediaPayload.isPlaying,
                elapsed: elapsed,
                duration: mediaPayload.duration,
                isShuffling: mediaPayload.isShuffling,
                repeatMode: mediaPayload.repeatSetting.map {
                    switch $0 {
                    case .off: .off
                    case .one: .one
                    case .all: .all
                    }
                }
            )
        )
    }

    private func prune() {
        // Fix-wave item 3: ask the presenter to re-evaluate hover against
        // current geometry FIRST, unconditionally, rather than only trusting
        // whatever `.mouseMoved`/geometry-change last left `isHovered` at —
        // see `NotchPresenter.reevaluateHoverForExpiry()`'s doc comment for
        // why a missed mouse event could otherwise latch it and freeze all
        // expiry indefinitely.
        presenter.reevaluateHoverForExpiry()
        let before = queue.count
        evictUnavailableServices()
        queue.prune(at: Date(), hovered: presenter.controller.isHovered)
        if queue.count != before { publish() }

        let fingerprint = [powerStatus, hudStatus, systemHUDStatus, mediaStatus, deviceStatus].joined(separator: "|")
        if fingerprint != statusFingerprint {
            statusFingerprint = fingerprint
            onStatusChange?()
        }
    }

    /// Spec §9: "Service dies at runtime → its activities are evicted from
    /// the queue." Polled every 250ms tick here — the same cadence as TTL
    /// pruning above — rather than reacting to the moment each service
    /// transitions, because the three services that can report
    /// `.unavailable` each do so through a different mechanism (`power`: a
    /// poll finding no battery/power sources; `hud`: computed once at
    /// `start()`; `media`: its restart policy giving up after repeated
    /// adapter failures), some of which produce no event at all on the
    /// stream `AppModel` would otherwise be listening on. Polling
    /// `availability` here is the one place that catches all three
    /// uniformly, so a dead service's activity cannot sit on the island
    /// forever.
    ///
    /// Unconditional, unlike TTL expiry: a service that no longer exists is
    /// a correctness problem, not a UX nicety hover should be able to pin to
    /// the island indefinitely — `remove(kind:)` itself has no hover
    /// parameter to honour.
    private func evictUnavailableServices() {
        if !power.availability.isAvailable { queue.remove(kind: .power) }
        if !hud.availability.isAvailable { queue.remove(kind: .hud) }
        if !device.availability.isAvailable { queue.remove(kind: .device) }
        if !media.availability.isAvailable {
            queue.remove(kind: .media)
            // The activity is not the only thing a dead media service leaves
            // behind: `controller.media` is what hover opens the panel for,
            // and the position tick keeps advancing it. Clear both, or a
            // stale now-playing card stays one hover away after the adapter
            // has given up.
            if presenter.controller.media != nil {
                presenter.controller.setMedia(nil)
                stopPositionTicking()
            }
        }
    }

    private func publish() {
        let display = queue.visible.map { record in
            NotchController.ActivityDisplay(
                id: record.id,
                title: record.title,
                detail: record.detail,
                compactText: record.compactText,
                symbolName: record.symbolName,
                barFill: record.barFill,
                artwork: record.artwork
            )
        }
        // `setActivities` sets the count itself — do not also call
        // `setActivityCount`, or overflow gets counted twice.
        presenter.setActivities(display, overflow: queue.overflowCount)
    }
}
