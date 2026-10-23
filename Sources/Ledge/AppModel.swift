import AppKit
import Foundation
import ActivityKit
import NotchKit
import PowerService
import HUDService
import MediaService
import DeviceService
import CalendarService
import TimerService
import FocusService
import LiveActivityService
import SettingsKit
import UpdateService
import GitHubService
import CallService
import LedgeSettings
import OSLog

/// Consumes service streams, maintains the queue, drives the controller.
/// The only place where services and UI meet.
@MainActor
final class AppModel {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "model")

    private let presenter: NotchPresenter
    let settings: AppSettings
    private let power = PowerService()
    private let hud = HUDService()
    private let media = MediaService()
    private let device = DeviceService()
    private let calendar = CalendarService()
    private let focus = FocusService()
    private let liveActivities = LiveActivityService()
    private let call = CallService()
    private let favorites = MusicFavorites()

    private var queue = ActivityQueue()
    private var tasks: [Task<Void, Never>] = []
    private var pruneTimer: Timer?
    /// The last payload `MediaService` sent, kept around because a
    /// `NotchIntent.seek(fraction:)` and the 1Hz position tick both need the
    /// live duration/elapsed/timestamp/rate — none of which `NotchController`
    /// carries (it only ever gets the already-computed `MediaPresentation`).
    private var mediaPayload = MediaPayload()
    /// The title the caption last announced, so a resumed or paused track
    /// is not re-announced; only a NEW title is.
    private var captionedTitle: String?
    private var captionTask: Task<Void, Never>?
    init(presenter: NotchPresenter, settings: AppSettings = AppSettings()) {
        self.settings = settings
        self.presenter = presenter
    }

    /// What needs attention — only problems (2026-09-29). A service that is
    /// fine contributes nothing. Shown in Settings › Permissions since
    /// 2026-10-21, no longer in the menu; `fix`, where there is one, is
    /// that row's button and opens the right System Settings pane.
    struct Issue: Identifiable {
        let text: String
        let fix: (() -> Void)?
        var id: String { text }
    }

    var issues: [Issue] {
        var issues: [Issue] = []
        func note(_ name: String, _ availability: ServiceAvailability) {
            switch availability {
            case .available: break
            case .needsPermission(let what): issues.append(Issue(text: "\(name) needs \(what)", fix: nil))
            case .unavailable(let reason): issues.append(Issue(text: "\(name) unavailable: \(reason)", fix: nil))
            }
        }
        note("Power", power.availability)
        note("HUD", hud.availability)
        note("Media", media.availability)
        note("Devices", device.availability)
        note("Calendar", calendar.availability)
        note("Focus", focus.availability)
        if settings.showsCalls { note("Calls", call.availability) }
        if let login = LoginItem.issue {
            issues.append(Issue(text: login.text, fix: login.fix))
        }
        if case .needsPermission = focus.detail {
            issues.append(Issue(text: "Focus needs Full Disk Access for its icon, colour and name", fix: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }))
        }
        if settings.showsLiveActivities, case .needsPermission(let what) = liveActivities.availability, what == "Screen Recording" {
            issues.append(Issue(text: "Live Activities need Screen Recording", fix: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }))
        }
        if case .needsPermission = hud.systemHUDReplacement {
            issues.append(Issue(text: "System HUD needs Accessibility", fix: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }))
        }
        return issues
    }

    var isPanelOpen: Bool { presenter.controller.state == .expanded }
    var isSuppressingStockOSD: Bool { hud.isSuppressingStockOSD }

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
        favorites.onChange = { [weak self] in self?.refreshMediaPresentation() }

        let deviceStream = device.start()
        tasks.append(Task { [weak self] in
            for await event in deviceStream {
                self?.handle(event)
            }
        })

        // The other direction: the panel's buttons/scrubber emit `NotchIntent`s
        // through the controller; this is the one place they get turned into
        // outbound `MediaCommand`s.
        let calendarStream = calendar.start()
        tasks.append(Task { [weak self] in
            for await reminder in calendarStream {
                self?.handle(reminder)
            }
        })

        let focusStream = focus.start()
        tasks.append(Task { [weak self] in
            for await event in focusStream {
                self?.handle(event)
            }
        })

        let liveActivityStream = liveActivities.start()
        tasks.append(Task { [weak self] in
            for await event in liveActivityStream {
                self?.handle(event)
            }
        })

        presenter.controller.onIntent = { [weak self] intent in
            self?.handle(intent)
        }

        settings.onChange = { [weak self] in self?.applySettings() }
        applySettings()

        // Expiry is driven here, not inside the queue, so the queue stays pure.
        // Built with `Timer(...)` + `RunLoop.main.add(forMode: .common)`,
        // not `Timer.scheduledTimer`, which only schedules on `.default` --
        // TTL expiry would otherwise stall while a menu is tracking or a
        // drag is in progress (same fix as PowerService's run-loop source).
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.prune()
                self?.refreshUpcoming()
                self?.refreshTimer()
                self?.refreshCall()
                self?.refreshCharging()
                self?.refreshLiveActivityOnHover()
                self?.showPendingUpdate()
                self?.refreshGitHub()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pruneTimer = timer

        // Updates (2026-10-22): a minute after launch, then once a day.
        let firstCheck = Timer(timeInterval: 60, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForUpdates() }
        }
        let daily = Timer(timeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForUpdates() }
        }
        RunLoop.main.add(firstCheck, forMode: .common)
        RunLoop.main.add(daily, forMode: .common)
        updateTimers = [firstCheck, daily]

        // GitHub asks at once on wake (2026-10-22).
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.github.checkNow() }
        }
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        pruneTimer?.invalidate()
        pruneTimer = nil
        updateTimers.forEach { $0.invalidate() }
        updateTimers.removeAll()
        checkTask?.cancel()
        checkTask = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        githubConnecting?.cancel()
        githubConnecting = nil
        github.stop()
        call.stop()
        clearMediaTask?.cancel()
        clearMediaTask = nil
        hud.stop()
        liveActivities.stop()
        power.stop()
        media.stop()
        device.stop()
    }

    // MARK: - Updates (2026-10-22)

    /// What the last update check found, for Settings › About.
    enum UpdateStatus: Equatable {
        case notChecked, off, checking
        case upToDate(Date)
        case available(ReleaseInfo, Date)
        case failed(Date)
    }

    private(set) var updateStatus: UpdateStatus = .notChecked
    var hasUpdate: Bool { if case .available = updateStatus { true } else { false } }
    private var updateTimers: [Timer] = []
    private var checkTask: Task<Void, Never>?
    /// Found while locked: shown at the first tick after unlock.
    private var pendingUpdate: ReleaseInfo?
    private static let lastAnnouncedKey = "lastAnnouncedUpdate"
    private static let runningVersion = AppVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") ?? AppVersion("0")!

    /// One check now: the timers, About's Check now, and the debug probe,
    /// which pretends to be `version`, announces regardless and remembers
    /// nothing. Off, it makes no request.
    func checkForUpdates(pretending version: AppVersion? = nil) {
        guard settings.checksForUpdates || version != nil else {
            updateStatus = .off
            return
        }
        // One check at a time (2026-10-22): a timer firing during a manual
        // check would otherwise announce the same version twice.
        guard checkTask == nil else { return }
        // An update already found stays in About until the user updates
        // (2026-10-22), through a check under way or one that fails.
        if !hasUpdate { updateStatus = .checking }
        let checker = UpdateChecker(currentVersion: version ?? Self.runningVersion)
        let lastAnnounced = version == nil
            ? UserDefaults.standard.string(forKey: Self.lastAnnouncedKey).flatMap(AppVersion.init) : nil
        checkTask = Task { @MainActor [weak self] in
            let finding = await checker.check(lastAnnounced: lastAnnounced)
            guard let self else { return }
            // Cancelled: whoever cancelled it has already cleared or replaced
            // `checkTask` (2026-10-22), so leave it alone.
            guard !Task.isCancelled else { return }
            self.checkTask = nil
            // Switched off while asking: the answer is dropped.
            guard self.settings.checksForUpdates || version != nil else { return }
            self.apply(finding, remember: version == nil)
        }
    }

    private func apply(_ finding: UpdateFinding?, remember: Bool) {
        let now = Date()
        switch finding {
        case nil:
            if !hasUpdate { updateStatus = .failed(now) }
        case .upToDate?:
            updateStatus = .upToDate(now)
        case .available(let release, let announce)?:
            updateStatus = .available(release, now)
            guard announce else { return }
            if remember { UserDefaults.standard.set(release.version.description, forKey: Self.lastAnnouncedKey) }
            pendingUpdate = release
            showPendingUpdate()
        }
    }

    /// The update blip, once, on an unlocked screen.
    private func showPendingUpdate() {
        guard let release = pendingUpdate, !presenter.isLocked else { return }
        pendingUpdate = nil
        let version = release.version.description
        queue.insert(ActivityRecord(
            id: NotchController.updateActivityID, kind: .update, insertedAt: Date(),
            ttl: ActivityKind.update.defaultTTL, title: UpdateNotice.title(version),
            compactText: version, symbolName: UpdateNotice.symbolName, tint: .positive, url: release.pageURL
        ))
        showCaption(UpdateNotice.caption(version), for: ActivityKind.update.defaultTTL ?? NotchController.captionDuration)
        publish()
    }

    // MARK: - GitHub (2026-10-22)

    private let github = GitHubMonitor()
    private var githubClock = RunningClock()
    private var githubRunShown: ActivityRecord?
    private var githubPanelShown: GitHubPanelData?
    private var githubWasLocked = false
    private var githubWasShowing = false
    /// What happened while the screen was locked: one blip after unlock.
    private var githubMissed: [GitHubEvent] = []
    private var githubConnecting: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    /// The debug probe's made-up rounds stand in for GitHub's while it plays.
    private var githubProbeSnapshot: GitHubSnapshot?
    private static let githubKeychain = GitHubKeychain(service: "\(Bundle.main.bundleIdentifier ?? "Ledge").github")
    private let githubAvatars = GitHubAvatars()
    /// Pictures already fetched, for drawing at once (2026-10-22).
    private var githubAvatarImages: [URL: Data] = [:]
    private var githubAvatarLoading: Set<URL> = []
    /// Pictures that did not come this round: not asked for again until the
    /// next one (2026-10-22), or a failing picture would be asked for over
    /// and over.
    private var githubAvatarFailed: Set<URL> = []
    /// Oldest first, to keep `githubAvatarImages` to `GitHubAvatars.limit`.
    private var githubAvatarOrder: [URL] = []
    /// The blip still waiting for its picture; a newer blip replaces it.
    private var githubBlipTask: Task<Void, Never>?
    /// The caption the last GitHub blip put up, so taking the blip away
    /// takes its caption too, and nobody else's (2026-10-22).
    private var githubCaptionShown: String?
    /// Bumped on disconnect: a blip or picture from before it is dropped.
    private var githubGeneration = 0

    /// Where the login came from, once connected.
    private(set) var githubSource: GitHubTokenSource?
    /// Connected in Settings, but there is neither a pasted token nor `gh`.
    private(set) var githubNeedsToken = false
    var githubStatus: GitHubMonitor.Status { github.status }
    var githubLogin: String? { github.snapshot?.login }
    var githubHidesOrganisations: Bool { github.snapshot?.hidesSomeOrganisations ?? false }
    /// The sidebar badge: GitHub no longer takes the login.
    var githubNeedsAttention: Bool { github.status == .signInAgain }

    /// The account card's picture, once it has loaded (2026-10-22).
    var githubAvatar: Data? { github.snapshot?.avatarURL.flatMap { githubAvatarImages[$0] } }

    /// The account card's line: open PRs, failing, running, waiting for
    /// the user's review (2026-10-22).
    struct GitHubStats: Equatable {
        let open: Int
        let failing: Int
        let running: Int
        let waiting: Int
    }

    var githubStats: GitHubStats? {
        guard let snapshot = githubSnapshot else { return nil }
        return GitHubStats(open: snapshot.mineTotal,
                           failing: snapshot.mine.filter { $0.checks?.state == .failed }.count,
                           running: GitHubEvents.running(in: snapshot).count,
                           waiting: snapshot.requestedTotal)
    }

    /// Fresh only: see `GitHubMonitor.current(at:)` (2026-10-22).
    private var githubSnapshot: GitHubSnapshot? { githubProbeSnapshot ?? github.current(at: Date()) }

    func connectGitHub() {
        githubNeedsToken = false
        if settings.githubConnected { startGitHub() } else { settings.githubConnected = true }
    }

    /// Stops asking, and forgets a pasted token.
    func disconnectGitHub() {
        Self.githubKeychain.delete()
        settings.githubConnected = false
    }

    /// A token pasted in Settings: kept in the Keychain, then used.
    func saveGitHubToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, Self.githubKeychain.save(trimmed) else { return }
        connectGitHub()
    }

    /// Settings' Check now, or Try again after GitHub refused the login
    /// (which reads the login again: the user may have signed in anew).
    func checkGitHubNow() {
        guard settings.githubConnected else { return }
        if github.status == .signInAgain || githubNeedsToken || !github.isRunning { startGitHub() } else { github.checkNow() }
    }

    /// A pasted token wins over `gh`'s: pasting one is the user choosing it.
    /// Nothing is read until the user has connected (2026-10-22).
    private func startGitHub() {
        guard settings.githubConnected else { return }
        githubConnecting?.cancel()
        githubNeedsToken = false
        githubConnecting = Task { @MainActor [weak self] in
            let pasted = Self.githubKeychain.read()
            let fromGH = pasted == nil ? await GitHubToken.fromGH() : nil
            guard let self, !Task.isCancelled, self.settings.githubConnected else { return }
            self.githubConnecting = nil
            guard let token = pasted ?? fromGH else {
                self.githubNeedsToken = true
                return
            }
            self.githubSource = pasted != nil ? .keychain : .gh
            self.github.onRound = { [weak self] snapshot, events in self?.handleGitHubRound(snapshot, events) }
            self.github.start(GitHubClient(token: token, userAgent: "Ledge/\(Self.runningVersion)"))
        }
    }

    private func stopGitHub() {
        githubConnecting?.cancel()
        githubConnecting = nil
        github.stop()
        githubSource = nil
        githubNeedsToken = false
        githubMissed = []
        githubClock = RunningClock()
        githubAvatarImages = [:]
        githubAvatarOrder = []
        githubAvatarLoading = []
        githubAvatarFailed = []
        githubBlipTask?.cancel()
        githubBlipTask = nil
        githubGeneration += 1
        githubRunShown = nil
        queue.remove(kind: .githubRun)
        queue.remove(kind: .github)
        clearGitHubCaption()
        publish()
        publishGitHubPanel()
    }

    private func handleGitHubRound(_ snapshot: GitHubSnapshot, _ events: [GitHubEvent]) {
        githubAvatarFailed.removeAll()
        if let url = snapshot.avatarURL { loadGitHubAvatar(url) }
        let wanted = events.filter(isWanted)
        if presenter.isLocked {
            githubMissed += wanted
        } else if let blip = GitHubNotice.burst(wanted) {
            showGitHub(blip)
        }
        publishGitHubPanel()
    }

    private func isWanted(_ event: GitHubEvent) -> Bool {
        switch event {
        case .checksPassed, .checksFailed: return settings.githubChecksFinished
        case .reviewed, .commented:        return settings.githubReviews
        case .merged, .closed:             return settings.githubMerges
        case .reviewRequested:             return settings.githubReviewRequests
        case .runPassed, .runFailed:       return settings.githubMyRuns
        }
    }

    /// A blip waits at most a second for its person's picture, then shows
    /// its disc (2026-10-22). One at a time: a newer blip replaces one still
    /// waiting, and nothing lands after a disconnect.
    private func showGitHub(_ blip: GitHubBlip) {
        githubBlipTask?.cancel()
        let generation = githubGeneration
        githubBlipTask = Task { @MainActor [weak self] in
            let avatar = await self?.githubAvatar(blip.avatarURL, within: 1)
            // Replaced, disconnected, or locked while the picture came.
            guard let self, !Task.isCancelled, generation == self.githubGeneration, !self.presenter.isLocked else { return }
            self.githubBlipTask = nil
            self.queue.insert(ActivityRecord(
                id: NotchController.githubActivityID, kind: .github, insertedAt: Date(),
                ttl: ActivityKind.github.defaultTTL, title: blip.title, compactText: blip.word,
                symbolName: blip.symbolName, artwork: avatar, tint: blip.tintName.map { .system($0) }, url: blip.url
            ))
            self.publish()
            self.githubCaptionShown = blip.caption
            self.showCaption(blip.caption, for: ActivityKind.github.defaultTTL ?? NotchController.captionDuration)
        }
    }

    /// Clears the caption only while it is still the GitHub blip's: a
    /// song, meeting or update caption that replaced it stays (2026-10-22).
    private func clearGitHubCaption() {
        defer { githubCaptionShown = nil }
        guard let shown = githubCaptionShown, presenter.controller.caption == shown else { return }
        presenter.setCaption(nil)
    }

    /// A picture from memory, else from GitHub's image server within
    /// `seconds`; `nil` if it has not come by then (2026-10-22).
    private func githubAvatar(_ url: URL?, within seconds: Double) async -> Data? {
        guard let url else { return nil }
        if let data = githubAvatarImages[url] { return data }
        let avatars = githubAvatars
        let generation = githubGeneration
        let data = await withTaskGroup(of: Data?.self) { group in
            group.addTask { await avatars.image(at: url) }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let data, generation == githubGeneration { rememberGitHubAvatar(data, for: url) }
        return data
    }

    /// Keeps at most `GitHubAvatars.limit` pictures, oldest out first
    /// (2026-10-22).
    private func rememberGitHubAvatar(_ data: Data, for url: URL) {
        if githubAvatarImages[url] == nil { githubAvatarOrder.append(url) }
        githubAvatarImages[url] = data
        if githubAvatarOrder.count > GitHubAvatars.limit { githubAvatarImages[githubAvatarOrder.removeFirst()] = nil }
    }

    /// Fetches a picture in the background, then redraws the panel if it
    /// came; one that did not is left until the next round (2026-10-22).
    private func loadGitHubAvatar(_ url: URL) {
        guard githubAvatarImages[url] == nil, !githubAvatarLoading.contains(url), !githubAvatarFailed.contains(url) else { return }
        githubAvatarLoading.insert(url)
        let generation = githubGeneration
        Task { @MainActor [weak self] in
            let data = await self?.githubAvatar(url, within: 10)
            guard let self, generation == self.githubGeneration else { return }
            self.githubAvatarLoading.remove(url)
            if data == nil {
                self.githubAvatarFailed.insert(url)
            } else {
                self.publishGitHubPanel()
            }
        }
    }

    /// Every tick: what was missed while locked, the running item's clock,
    /// and the lock screen rule (no GitHub there at all).
    private func refreshGitHub() {
        let locked = presenter.isLocked
        if !locked, !githubMissed.isEmpty {
            let missed = githubMissed
            githubMissed = []
            if let blip = GitHubNotice.burst(missed) { showGitHub(blip) }
        }
        if locked, queue.ordered.contains(where: { $0.kind == .github }) {
            queue.remove(kind: .github)
            clearGitHubCaption()
            publish()
        }
        let now = Date()
        let running = locked ? [] : (githubSnapshot.map(GitHubEvents.running(in:)) ?? []).filter {
            $0.source == .checks ? settings.githubChecksRunning : settings.githubMyRuns
        }
        if let lead = githubClock.lead(of: running, now: now) {
            let record = ActivityRecord(
                id: NotchController.githubRunActivityID, kind: .githubRun,
                insertedAt: githubRunShown?.insertedAt ?? now, ttl: nil,
                title: lead.item.source == .run ? "Run going" : "Checks running", detail: lead.item.caption,
                compactText: TimerText.format(seconds: now.timeIntervalSince(lead.since).rounded(.down)),
                tint: .system(GitHubNotice.runningTintName), url: lead.item.url,
                badge: lead.count > 1 ? lead.count : nil,
                segments: lead.item.segments.map(Self.activitySegment)
            )
            // Republished only when what the island draws changes.
            if record.compactText != githubRunShown?.compactText || record.badge != githubRunShown?.badge
                || record.url != githubRunShown?.url || record.segments != githubRunShown?.segments {
                githubRunShown = record
                queue.insert(record)
                publish()
            }
        } else if githubRunShown != nil {
            githubRunShown = nil
            queue.remove(kind: .githubRun)
            publish()
        }
        // The panel follows a lock, and a round going stale or fresh again.
        let showing = githubSnapshot != nil
        if locked != githubWasLocked || showing != githubWasShowing {
            githubWasLocked = locked
            githubWasShowing = showing
            publishGitHubPanel()
        }
    }

    /// The panel's list, or none: not connected, nothing to list, or locked.
    private func publishGitHubPanel() {
        var data: GitHubPanelData?
        if !presenter.isLocked, let snapshot = githubSnapshot {
            let list = GitHubPanelRows.make(snapshot)
            if list.hero != nil || !list.rows.isEmpty {
                data = GitHubPanelData(
                    hero: list.hero.map { hero in
                        GitHubPanelData.Hero(
                            id: hero.id, kind: Self.heroKind(hero.kind), tag: hero.tag, title: hero.title,
                            detail: hero.detail, segments: hero.segments.map(Self.heroSegment), since: hero.startedAt,
                            avatar: hero.avatarURL.flatMap { githubAvatarImages[$0] }, url: hero.url
                        )
                    },
                    rows: list.rows.map { GitHubPanelData.Row(id: $0.id, mark: Self.panelMark($0.mark), title: $0.title, repo: $0.repo, url: $0.url) },
                    more: list.more, moreURL: GitHubPanelRows.moreURL
                )
                if let url = list.hero?.avatarURL { loadGitHubAvatar(url) }
            }
        }
        guard data != githubPanelShown else { return }
        githubPanelShown = data
        presenter.setGitHubPanel(data)
    }

    private static func panelMark(_ mark: GitHubRow.Mark) -> GitHubPanelData.Row.Mark {
        switch mark {
        case .running: .running
        case .passed:  .passed
        case .failed:  .failed
        case .none:    .none
        case .review:  .review
        }
    }

    private static func heroKind(_ kind: GitHubHero.Kind) -> GitHubPanelData.Hero.Kind {
        switch kind {
        case .running: .running
        case .failed:  .failed
        case .review:  .review
        }
    }

    private static func heroSegment(_ segment: CheckSegment) -> IslandCheck {
        switch segment {
        case .passed:  .passed
        case .failed:  .failed
        case .running: .running
        }
    }

    private static func activitySegment(_ segment: CheckSegment) -> ActivitySegment {
        switch segment {
        case .passed:  .passed
        case .failed:  .failed
        case .running: .running
        }
    }

    private static func displaySegment(_ segment: ActivitySegment) -> IslandCheck {
        switch segment {
        case .passed:  .passed
        case .failed:  .failed
        case .running: .running
        }
    }

    #if DEBUG
    /// `ledge://probe/github`, debug builds only (2026-10-22): plays
    /// `GitHubSample.story` through the island a step every three seconds,
    /// as real rounds would land, with no network; the last step stays half
    /// a minute so the panel can be hovered.
    private func playGitHubStory() {
        let story = GitHubSample.story(login: "you", start: Date())
        Task { @MainActor [weak self] in
            var previous: GitHubSnapshot?
            for snapshot in story {
                guard let self else { return }
                self.githubProbeSnapshot = snapshot
                self.handleGitHubRound(snapshot, GitHubEvents.between(previous, snapshot))
                previous = snapshot
                try? await Task.sleep(for: .seconds(3))
            }
            try? await Task.sleep(for: .seconds(30))
            self?.githubProbeSnapshot = nil
            self?.publishGitHubPanel()
        }
    }

    /// `ledge://probe/github-panel`, debug builds only (2026-10-22): pins the
    /// GitHub panel open on `GitHubSample.panelSnapshot` for twenty seconds,
    /// for screenshots, with no network.
    private func openGitHubPanelProbe() {
        githubProbeSnapshot = GitHubSample.panelSnapshot(login: "you", now: Date())
        publishGitHubPanel()
        presenter.debugOpen(.github)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            self?.presenter.controller.dismiss()
            self?.githubProbeSnapshot = nil
            self?.publishGitHubPanel()
        }
    }
    #endif

    // MARK: - Settings previews (2026-10-22)

    /// What only arrives as events, kept for the Settings previews: the
    /// last volume level, the last Focus that came on, and the last
    /// headphones that reported a charge.
    private var lastVolume: Double?
    private var lastFocus: PreviewContent.Focus?
    private var lastHeadphones: PreviewContent.Headphones?

    /// The user's own content for the Settings previews: what the island
    /// already shows or has seen. A nil field becomes a labelled sample.
    func previewContent() -> PreviewContent {
        let controller = presenter.controller
        let items = (controller.upcoming.map { [$0] } ?? []) + (controller.calendarMode?.items ?? [])
        let output = controller.outputs.first(where: \.isCurrent)?.name
        return PreviewContent(
            media: controller.media,
            mediaSource: controller.media == nil ? nil : mediaPayload.bundleIdentifier,
            nextEvent: items.first { $0.kind == .event },
            nextReminder: items.first { $0.kind == .reminder },
            batteryPercent: power.availability.isAvailable ? power.latest?.percent : nil,
            headphones: lastHeadphones.flatMap { $0.name == output ? $0 : nil },
            focus: lastFocus,
            volume: lastVolume,
            timer: controller.activities.first { $0.id == NotchController.timerActivityID },
            availableUpdate: { if case .available(let release, _) = updateStatus { return release.version.description }; return nil }(),
            pullRequest: githubSnapshot?.mine.first
        )
    }

    /// Devices ride the same `ActivityRecord` shape as power: a title for
    /// the detail row, a glyph for the leading ear, an optional battery
    /// percentage for the trailing ear. Same id for every device event, so
    /// AirPods connecting right after a keyboard coalesces into one slot.
    /// The live charging state (2026-10-01): a white bolt battery and the
    /// live percentage, sticky while the charger is in and under
    /// everything else — the plug-in blip keeps its green for its three
    /// seconds, this does not shout. Republished only when the figure or
    /// glyph changes.
    private var chargingShown: (symbol: String, text: String)?

    private func refreshCharging() {
        guard settings.showsBattery, let latest = power.latest, latest.isPluggedIn else {
            if chargingShown != nil {
                chargingShown = nil
                queue.remove(kind: .charging)
                publish()
            }
            return
        }
        // Plugged in is the bolt battery, full is the full battery; the
        // system's "attached but holding" is not a third face (2026-10-01).
        let symbol = latest.isCharged ? "battery.100percent" : "battery.100percent.bolt"
        let text = "\(latest.percent)%"
        guard chargingShown?.symbol != symbol || chargingShown?.text != text else { return }
        chargingShown = (symbol, text)
        queue.insert(ActivityRecord(
            id: NotchController.chargingActivityID, kind: .charging, insertedAt: Date(), ttl: nil,
            title: latest.isCharged ? "Charged" : "Charging", compactText: text, symbolName: symbol,
            // The battery fills to the charge, as the phone's does.
            barFill: Double(latest.percent) / 100,
            // Green on the battery alone (user's call): the figure stays white.
            tint: .positive
        ))
        publish()
    }

    /// What cannot be checked at event time: the system HUD replacement,
    /// the hover dwell, the calendar lead time, the login item. Everything
    /// else is a `guard` where the event lands.
    private func applySettings() {
        hud.setSuppressStockOSD(settings.showsVolumeBrightness)
        // Calls (2026-10-22): off undoes any mute Ledge applied and takes the
        // pill away at once, with no ended moment.
        if settings.showsCalls {
            call.start()
        } else {
            call.stop()
            if queue.ordered.contains(where: { $0.kind == .call }) {
                queue.remove(kind: .call)
                publish()
            }
            callShown = nil
            callLiveApp = nil
            presenter.setCallPanel(nil)
        }
        liveActivities.setEnabled(settings.showsLiveActivities)
        if !settings.showsLiveActivities, queue.ordered.contains(where: { $0.kind == .liveActivity }) {
            queue.remove(kind: .liveActivity)
            publish()
        }
        presenter.setHoverDwell(settings.hoverDwell)
        presenter.setShowsOnLockScreen(settings.showsOnLockScreen)
        calendar.setLeadTime(TimeInterval(settings.calendarLeadMinutes * 60))
        calendar.setDisabledCalendars(settings.disabledCalendarIDs)
        LoginItem.setEnabled(settings.launchAtLogin)
        if !settings.checksForUpdates {
            checkTask?.cancel()
            checkTask = nil
            // …and a blip still waiting for unlock (2026-10-22).
            pendingUpdate = nil
            updateStatus = .off
        } else if updateStatus == .off {
            checkForUpdates()
        }
        // GitHub (2026-10-22): connect when switched on, stop when off;
        // a switch for a moment applies from the next round, and at once
        // to the running item and the panel.
        if settings.githubConnected {
            if !github.isRunning, githubConnecting == nil, !githubNeedsToken { startGitHub() }
        } else if github.isRunning || githubConnecting != nil || githubNeedsToken {
            stopGitHub()
        }
        publishGitHubPanel()
    }

    /// The Calendar pane's list.
    var availableCalendars: [CalendarInfo] { calendar.availableCalendars() }

    /// The Permissions pane's rows.
    struct PermissionRow: Identifiable {
        let id: String
        let name: String
        let detail: String
        let isGranted: Bool
        let settingsURL: URL?
    }

    var permissionRows: [PermissionRow] {
        func pane(_ anchor: String) -> URL? { URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") }
        return [
            PermissionRow(id: "ax", name: "Accessibility",
                          detail: "Replaces the system's volume and brightness overlay with the island.",
                          isGranted: hud.systemHUDReplacement.isAvailable, settingsURL: pane("Privacy_Accessibility")),
            PermissionRow(id: "cal", name: "Calendars and Reminders",
                          detail: "Meeting and reminder blips, and the next item on hover.",
                          isGranted: calendar.availability.isAvailable, settingsURL: pane("Privacy_Calendars")),
            PermissionRow(id: "fda", name: "Full Disk Access",
                          detail: "A Focus's own icon, colour and name. Without it: the moon and On/Off.",
                          isGranted: focus.detail.isAvailable, settingsURL: pane("Privacy_AllFiles")),
            PermissionRow(id: "screen", name: "Screen Recording",
                          detail: "Cuts the crests from an iPhone Live Activity's card, once, when it arrives.",
                          isGranted: liveActivities.hasScreenAccess, settingsURL: pane("Privacy_ScreenCapture")),
        ]
    }

    /// A device blip (2026-09-30): the product's flat glyph — the phone's
    /// AirPods panel idiom, not a render — and, for buds, left, right and
    /// case readings side by side; one figure for everything else that
    /// reports a battery.
    private func handle(_ event: DeviceEvent) {
        if case .outputChanged(let name, _, let levels?) = event, !levels.isEmpty {
            lastHeadphones = PreviewContent.Headphones(name: name, main: levels.main, left: levels.left,
                                                       right: levels.right, case: levels.`case`)
        }
        guard settings.showsDevices else { return }
        queue.insert(
            ActivityRecord(
                id: ActivityKind.device.rawValue,
                kind: .device,
                insertedAt: Date(),
                ttl: ActivityKind.device.defaultTTL,
                title: event.activityTitle,
                compactText: event.compactText,
                symbolName: event.symbolName,
                parts: event.parts?.map { ActivityPart(symbolName: $0.symbolName, text: $0.text) }
            )
        )
        publish()
    }

    private func handle(_ event: PowerEvent) {
        // The display dims on battery and brightens on AC by itself; the
        // HUD service must not read that as a brightness key.
        hud.notePowerSourceChanged()
        guard settings.showsBattery else { return }
        queue.insert(
            ActivityRecord(
                id: ActivityKind.power.rawValue,
                kind: .power,
                insertedAt: Date(),
                ttl: ActivityKind.power.defaultTTL,
                title: event.activityTitle,
                compactText: event.compactText,
                symbolName: event.symbolName,
                barFill: event.barFill,
                tint: event.tint.map { $0 == .positive ? ActivityTint.positive : .warning }
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
        if case .volume(let level, _) = event { lastVolume = level }
        if case .capsLock = event {
            guard settings.showsCapsLock else { return }
        } else {
            guard settings.showsVolumeBrightness else { return }
        }
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
        // Music apps only (`MediaSourcePolicy`): a browser tab or a video
        // call is not "now playing" for the island, however loudly
        // MediaRemote reports it.
        guard payload.hasMedia, let title = payload.title,
              MediaSourcePolicy.isAllowed(bundleIdentifier: payload.bundleIdentifier, enabled: settings.mediaSources) else {
            if payload.hasMedia {
                Self.log.debug("media: ignoring a source the island does not follow (\(payload.bundleIdentifier ?? "?", privacy: .private))")
            }
            holdThenClearMedia()
            return
        }
        // It is ours: whatever was about to clear the card no longer is.
        clearMediaTask?.cancel()
        clearMediaTask = nil

        mediaPayload = payload
        if let override = positionOverride, override.isSuperseded(by: payload) || !override.isFresh(at: Date()) {
            positionOverride = nil
        }

        // A new song announces itself for a few seconds (the reference
        // app's caption row); pause/resume of the same song does not. The
        // favourite star follows the track the same way.
        if title != captionedTitle {
            captionedTitle = title
            // A meeting or update blip owns the caption line for its
            // lifetime (2026-10-22): a track change under it posts none.
            if settings.showsSongCaption, !presenter.controller.isCalendarLeading, !presenter.controller.isUpdateLeading, !presenter.controller.isGitHubLeading {
                showCaption(payload.artist.map { "\(title) · \($0)" } ?? title)
            }
            favorites.trackChanged(bundleIdentifier: payload.bundleIdentifier)
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
        publish()
    }

    /// A meeting reminder (2026-09-29): calendar glyph left, countdown
    /// right, the title and start time in the caption line for the blip's
    /// lifetime, and a click that joins the call — or, with no call link,
    /// opens Calendar (`Self.openCalendarURL`, resolved in `handle(_:)`).
    private func handle(_ reminder: MeetingReminder) {
        guard allowedCalendarKinds.contains(reminder.event.kind) else { return }
        queue.insert(
            ActivityRecord(
                id: NotchController.calendarActivityID,   // == ActivityKind.calendar.rawValue
                kind: .calendar,
                insertedAt: Date(),
                ttl: ActivityKind.calendar.defaultTTL,
                title: reminder.event.title,
                compactText: reminder.compactText,
                symbolName: reminder.event.symbolName,
                tint: Self.ringTint(for: reminder.event),
                url: reminder.event.joinURL ?? reminder.event.detailURL ?? Self.openAppURL(for: reminder.event.kind)
            )
        )
        showCaption(reminder.captionText(), for: ActivityKind.calendar.defaultTTL ?? NotchController.captionDuration)
        publish()
    }

    /// A Focus turning on or off (2026-09-30): its own symbol in its own
    /// colour left and its NAME right, where "On" would be (user's call),
    /// the island stretching to fit it; "Off" with the symbol uncoloured.
    /// Without the Focus database (Full Disk Access) it is the moon and
    /// On/Off. A symbol this macOS lacks falls back to the moon.
    private func handle(_ event: FocusEvent) {
        if event.isOn, let mode = event.mode {
            lastFocus = PreviewContent.Focus(name: mode.name, symbolName: mode.symbolName, tintName: mode.tintColorName)
        }
        guard settings.showsFocus else { return }
        let symbol = NSImage(systemSymbolName: event.symbolName, accessibilityDescription: nil) == nil
            ? (event.isOn ? "moon.fill" : "moon") : event.symbolName
        queue.insert(
            ActivityRecord(
                id: NotchController.focusActivityID,
                kind: .focus,
                insertedAt: Date(),
                ttl: ActivityKind.focus.defaultTTL,
                title: event.mode?.name ?? "Focus",
                compactText: event.isOn ? (event.mode?.name ?? "On") : "Off",
                symbolName: symbol,
                tint: event.isOn ? event.mode?.tintColorName.map { .system($0) } : nil
            )
        )
        publish()
    }

    private var liveContent: LiveActivityContent?

    /// An iPhone Live Activity (2026-10-01): what its card says, read a
    /// second at a time. A match becomes a scoreline — a crest and a
    /// figure in each ear, around the notch, as the phone's island draws
    /// it; anything else becomes the phone glyph and the card's own state
    /// line. A click shows the system's card where the menu bar puts it.
    private func handle(_ event: LiveActivityEvent) {
        switch event {
        case .showing(let content):
            guard settings.showsLiveActivities else { return }
            liveContent = content
            publishLiveActivity()
        case .ended:
            liveContent = nil
            queue.remove(kind: .liveActivity)
            publish()
        }
    }

    /// A rest on the island asks the activity's card for a fresh reading,
    /// once per rest (2026-10-05). Between rests the island keeps what it
    /// last read: opening that card shows it for a blink, and doing it
    /// every time a click dismissed it made the menu bar flicker all day.
    private var hasAskedThisHover = false

    private func refreshLiveActivityOnHover() {
        let controller = presenter.controller
        guard controller.isHovered, controller.isLiveActivityLeading else {
            hasAskedThisHover = false
            return
        }
        guard !hasAskedThisHover else { return }
        hasAskedThisHover = true
        liveActivities.refresh()
    }

    private func publishLiveActivity() {
        guard let content = liveContent else { return }
        var score: ActivityScore?
        if let home = content.home, let away = content.away {
            score = ActivityScore(
                home: .init(name: home.name, value: home.value, crest: home.crest),
                away: .init(name: away.name, value: away.value, crest: away.crest),
                status: content.status, clock: content.clock, title: content.title
            )
        }
        // Not a match: the island says what state the card is in, in the
        // trailing ear, and keeps the phone glyph.
        let line = score == nil ? content.compactLine : nil
        queue.insert(
            ActivityRecord(
                id: NotchController.liveActivityID,
                kind: .liveActivity,
                insertedAt: Date(),
                ttl: nil,
                title: content.title ?? "Live Activity",
                compactText: line,
                symbolName: "iphone",
                url: URL(string: "ledge://live-activity"),
                score: score,
                lines: score == nil ? content.lines : []
            )
        )
        publish()
    }

    /// A reminder's ring in its list's colour (2026-10-21), grey for a
    /// list without one, the way Reminders draws it. An event's calendar
    /// glyph stays white.
    private static func ringTint(for event: MeetingEvent) -> ActivityTint? {
        guard event.kind == .reminder else { return nil }
        return event.color.map(\.visibleOnBlack).map { .color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .system("gray")
    }

    /// The same colour for the hover preview and the card's rows.
    private static func itemTint(for event: MeetingEvent) -> UpcomingEvent.Tint? {
        event.color.map(\.visibleOnBlack).map { UpcomingEvent.Tint(red: $0.red, green: $0.green, blue: $0.blue) }
    }

    /// Stands in for "open the Calendar (or Reminders) app" on an item
    /// without a call link; never handed to the system as a URL.
    private static func openAppURL(for kind: MeetingEvent.Kind) -> URL {
        URL(string: kind == .event ? "ledge://calendar" : "ledge://reminders")!
    }

    private var allowedCalendarKinds: Set<MeetingEvent.Kind> {
        var kinds: Set<MeetingEvent.Kind> = []
        if settings.showsCalendarEvents { kinds.insert(.event) }
        if settings.showsReminders { kinds.insert(.reminder) }
        return kinds
    }

    /// The next event for the hover preview (`NotchController.upcoming`),
    /// refreshed on the 250 ms tick so the countdown stays honest while the
    /// cursor rests. The caption's time formatting is cached per event.
    private var upcomingCaption: (id: String, day: Date, text: String)?
    private var agendaTexts: [String: (day: Date, caption: String, time: String)] = [:]

    private func refreshUpcoming() {
        let now = Date()
        let day = Calendar.current.startOfDay(for: now)
        // The card's calendar mode (2026-09-30): this month's grid with its
        // marks, and today's remaining items, texts cached per item and day.
        if calendar.availability.isAvailable {
            let today = calendar.upcoming(at: now, limit: 8, allowing: allowedCalendarKinds)
                .filter { Calendar.current.isDate($0.start, inSameDayAs: now) }
                .prefix(3)
                .map { event -> UpcomingEvent in
                    if agendaTexts[event.id]?.day != day {
                        agendaTexts[event.id] = (day, event.captionText(at: now), event.startTimeText())
                    }
                    let texts = agendaTexts[event.id]!
                    return UpcomingEvent(
                        title: event.title, symbolName: event.symbolName, compactText: event.countdownText(at: now),
                        caption: texts.caption, time: event.isUnderWay(at: now) ? "Now" : texts.time,
                        url: event.joinURL ?? event.detailURL ?? Self.openAppURL(for: event.kind),
                        tint: Self.itemTint(for: event),
                        kind: event.kind == .reminder ? .reminder : .event,
                        isPastDue: event.isPastDue(at: now)
                    )
                }
            var marks: Set<Int> = []
            if settings.showsCalendarEvents { marks.formUnion(calendar.markedEventDays) }
            if settings.showsReminders { marks.formUnion(calendar.markedReminderDays) }
            presenter.setCalendarMode(CalendarModeData(now: now, calendar: Calendar.current, markedDays: marks, items: Array(today)))
        } else {
            presenter.setCalendarMode(nil)
        }
        if agendaTexts.count > 64 { agendaTexts = [:] }

        guard let event = calendar.nextEvent(at: now, allowing: allowedCalendarKinds) else {
            presenter.setUpcoming(nil)
            return
        }
        // Keyed on the day too: "Tomorrow at 06:15" becomes "06:15" at midnight.
        if upcomingCaption?.id != event.id || upcomingCaption?.day != day {
            upcomingCaption = (event.id, day, event.captionText(at: now))
        }
        presenter.setUpcoming(UpcomingEvent(
            title: event.title,
            symbolName: event.symbolName,
            compactText: event.countdownText(at: now),
            caption: upcomingCaption?.text ?? event.title,
            url: event.joinURL ?? event.detailURL ?? Self.openAppURL(for: event.kind),
            tint: Self.itemTint(for: event),
            kind: event.kind == .reminder ? .reminder : .event,
            isPastDue: event.isPastDue(at: now)
        ))
    }

    /// A click on a calendar item: the join link, else the item's own deep
    /// link (`MeetingEvent.detailURL`), else — or if the system refuses the
    /// deep link — the item's app. `ledge://calendar|reminders` are this
    /// model's own stand-ins for "the app", never handed to the system.
    private func open(_ url: URL) {
        // The call's app (2026-10-22): a stand-in, never handed to the system.
        if url.scheme == "ledge", url.host() == "call" {
            if let app = callLiveApp { activateApp(bundleID: app.bundleID, pid: app.pid) }
            return
        }
        if url.scheme == "ledge", url.host() == "live-activity" {
            liveActivities.press()
            return
        }
        let appFor: [String: String] = [
            "ledge": url.host() == "reminders" ? "com.apple.reminders" : "com.apple.iCal",
            "ical": "com.apple.iCal",
            "x-apple-reminderkit": "com.apple.reminders",
        ]
        if url.scheme != "ledge", NSWorkspace.shared.open(url) { return }
        if let bundle = url.scheme.flatMap({ appFor[$0] }),
           let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
        }
    }

    // MARK: - Clock timers in the island (2026-09-29)

    /// `ledge://probe/menubar`, debug builds only — see `MenuBarProbe`.
    /// The app's own timer that once lived behind this scheme was removed
    /// the same day at the user's request (the Clock's timers are what
    /// they wanted); the scheme stays registered for the probe alone.
    /// The Settings window, opened by `ledge://settings` (Shortcuts, Raycast).
    var onOpenSettings: (() -> Void)?
    #if DEBUG
    var onSnapshotSettings: ((URL) -> Void)?
    #endif

    func openURL(_ url: URL) {
        if url.scheme == "ledge", url.host() == "settings" {
            onOpenSettings?()
            return
        }
        // Opens the system's expanded view of the iPhone Live Activity
        // (also what a click on the island does) — for Shortcuts and
        // the shell.
        if url.scheme == "ledge", url.host() == "live-activity" {
            liveActivities.press()
            return
        }
        #if DEBUG
        if url.scheme == "ledge", url.host() == "probe", url.path() == "/update" {
            checkForUpdates(pretending: AppVersion("0.0.0"))
            return
        }
        if url.scheme == "ledge", url.host() == "probe", url.path() == "/github" {
            Self.log.notice("probe: github story")
            playGitHubStory()
            return
        }
        if url.scheme == "ledge", url.host() == "probe", url.path() == "/github-panel" {
            Self.log.notice("probe: github panel")
            openGitHubPanelProbe()
            return
        }
        if url.scheme == "ledge", url.host() == "probe", url.path() == "/settings" {
            let dir = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Ledge")
            onSnapshotSettings?(dir)
            Self.log.notice("probe: settings panes to \(dir.path, privacy: .public)")
            return
        }
        if url.scheme == "ledge", url.host() == "probe", url.path() == "/card" {
            let dir = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Ledge")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? liveActivities.probeCard().joined(separator: "\n")
                .write(to: dir.appending(path: "card-probe.txt"), atomically: true, encoding: .utf8)
            Self.log.notice("probe: card written")
            return
        }
        if url.scheme == "ledge", url.host() == "probe", url.path() == "/call-ax" {
            CallAppProbe.arm()
            Self.log.notice("probe: call controls armed for ten minutes")
            return
        }
        if url.scheme == "ledge", url.host() == "probe", url.path() == "/menubar" {
            let dir = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Ledge")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appending(path: "menubar-probe.txt")
            try? MenuBarProbe.dump().joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            Self.log.notice("probe: written to \(file.path, privacy: .public)")
            return
        }
        #endif
        Self.log.notice("ignored url \(url.absoluteString, privacy: .public)")
    }

    /// The Clock app's own timers and stopwatches (`ClockTimerObserver`):
    /// whatever it is running takes the island — a Siri "set a timer for
    /// ten minutes" lands here without touching this app. A click opens
    /// the Clock on the matching tab.
    private var timerShown: ActivityRecord?

    /// The live call's record as last published, the app on the mic, and
    /// each app's icon as PNG (2026-10-22).
    private var callShown: ActivityRecord?
    private var callLiveApp: CallAppInfo?
    private var callIcons: [String: Data] = [:]

    /// Calls (2026-10-22): the app on the mic and its clock while the call
    /// lasts, a red crossed-out mic when muted, a red hang-up and the
    /// length for 3 s when it ends. Republished only when what shows
    /// changes. Never logs which app or how long.
    private func refreshCall() {
        #if DEBUG
        for file in CallAppProbe.tick() { Self.log.notice("probe: wrote \(file, privacy: .public)") }
        #endif
        guard settings.showsCalls else { return }
        let now = Date()
        // The calendar's meetings (2026-10-22), whatever the "Calendar
        // events" switch says: that switch is about blips.
        let events = calendar.availability.isAvailable ? calendar.upcoming(at: now, limit: 50, allowing: [.event]) : []
        let candidates = events.map {
            MeetingCandidate(id: $0.id, title: $0.title, start: $0.start, end: $0.end, joinURL: $0.joinURL)
        }
        let update = call.refresh(at: now, hidden: Set(settings.hiddenCallApps), meetings: candidates)
        switch update.state {
        case .live(let app, let since):
            let icon = update.meeting.map { serviceIcon($0.service) } ?? callIcon(for: app)
            callLiveApp = app
            let next = CallMeetingMatcher.next(after: now, in: candidates, excluding: update.meeting)
                .flatMap { next in events.first { $0.id == next.id } }
                .map(nextMeetingText)
            presenter.setCallPanel(CallPanelData(
                appName: app.name, icon: icon, since: since, isMuted: update.isMuted, canMute: update.canMute,
                micName: update.micName, meetingTitle: update.meeting?.title, meetingEnd: update.meeting?.end,
                isCameraOn: update.isCameraOn, nextMeeting: next, mutedInMeet: update.mutedOnlyInApp
            ))
            let record = ActivityRecord(
                id: NotchController.callActivityID, kind: .call, insertedAt: callShown?.insertedAt ?? now, ttl: nil,
                title: "On a call · \(app.name)",
                compactText: TimerText.format(seconds: now.timeIntervalSince(since).rounded(.down)),
                symbolName: update.isMuted ? "mic.slash.fill" : "mic.fill",
                artwork: icon, tint: .positive, url: URL(string: "ledge://call")
            )
            guard record.title != callShown?.title || record.compactText != callShown?.compactText
                    || record.symbolName != callShown?.symbolName || record.artwork != callShown?.artwork else { return }
            callShown = record
            queue.insert(record)
            publish()
        case .ended(let app, let length):
            callShown = nil
            callLiveApp = nil
            presenter.setCallPanel(nil)
            queue.insert(ActivityRecord(
                id: NotchController.callActivityID, kind: .call, insertedAt: now, ttl: 3,
                title: "Call ended · \(app.name)",
                compactText: TimerText.format(seconds: length.rounded(.down)),
                symbolName: "phone.down.fill"
            ))
            publish()
        case .idle:
            // An ended moment runs out on its own; only a live call is taken
            // away here (hidden, or Calls unable to read the mic).
            guard callShown != nil else { return }
            callShown = nil
            callLiveApp = nil
            presenter.setCallPanel(nil)
            queue.remove(kind: .call)
            publish()
        }
    }

    /// "1:1 at 15:00", formatted once per event rather than every tick
    /// (tidy-up, 2026-10-22). An event's id includes its start.
    private var nextMeetingTextCache: (id: String, title: String, text: String)?

    private func nextMeetingText(_ event: MeetingEvent) -> String {
        if let cached = nextMeetingTextCache, cached.id == event.id, cached.title == event.title { return cached.text }
        let text = "\(event.title) at \(event.startTimeText())"
        nextMeetingTextCache = (event.id, event.title, text)
        return text
    }

    private func callIcon(for app: CallAppInfo) -> Data? {
        if let cached = callIcons[app.bundleID] { return cached }
        let png = Self.appIconPNG(app.bundleID)
        callIcons[app.bundleID] = png
        return png
    }

    private static func appIconPNG(_ bundleID: String) -> Data? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        return icon.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:])
    }

    /// A meeting service's icon (2026-10-22): its own Mac app's when one is
    /// installed, else its glyph on a tile of its colour — Meet's always,
    /// having no Mac app. No third-party logo is bundled.
    private var serviceIcons: [MeetingService: Data] = [:]

    private func serviceIcon(_ service: MeetingService) -> Data? {
        if let cached = serviceIcons[service] { return cached }
        let installed = (CallMeetingMatcher.apps[service] ?? []).lazy.compactMap(Self.appIconPNG).first
        let tileColour: NSColor = switch service {
        case .meet:     NSColor(red: 0, green: 0xA6 / 255.0, blue: 0x7E / 255.0, alpha: 1)
        case .zoom:     NSColor(red: 0x0B / 255.0, green: 0x5C / 255.0, blue: 1, alpha: 1)
        case .teams:    NSColor(red: 0x5B / 255.0, green: 0x5F / 255.0, blue: 0xC7 / 255.0, alpha: 1)
        case .webex:    NSColor(red: 0, green: 0x8E / 255.0, blue: 0xD8 / 255.0, alpha: 1)
        case .facetime: .systemGreen
        }
        let png = installed ?? CallTile.png(symbol: "video.fill", color: tileColour)
        if let png { serviceIcons[service] = png }
        return png
    }
    private let clock = ClockTimerObserver()
    private var clockOddities: [String] = []

    private func refreshTimer() {
        let now = Date()
        let snapshot = clock.refresh(at: now)
        if snapshot.oddities != clockOddities {
            clockOddities = snapshot.oddities
            if !clockOddities.isEmpty {
                Self.log.notice("clock: unparsed records — \(self.clockOddities.joined(separator: "; "), privacy: .public)")
            }
        }
        if settings.showsClockTimers, let featured = snapshot.featured(at: now) {
            show(clockRecord(for: featured, at: now))
        } else if timerShown != nil {
            // Stopped or dismissed in the Clock.
            timerShown = nil
            queue.remove(kind: .timer)
            publish()
            Self.log.notice("clock: nothing running")
        }
    }

    /// The island's record for a Clock item: ring and clock while a timer
    /// runs, the pause glyph when paused, "Done" once it has rung and
    /// waits to be dismissed, the stopwatch glyph and a rising clock for a
    /// stopwatch. The click opens the Clock on that tab.
    private func clockRecord(for featured: ClockTimerSnapshot.Featured, at now: Date) -> ActivityRecord {
        switch featured {
        case .timer(let timer):
            let remaining = timer.remaining(at: now)
            let fired = timer.hasFired(at: now)
            return ActivityRecord(
                id: NotchController.timerActivityID, kind: .timer, insertedAt: timerShown?.insertedAt ?? now, ttl: nil,
                title: timer.title ?? "Timer",
                compactText: fired ? "Done" : TimerText.format(seconds: remaining.rounded(.up)),
                symbolName: fired ? "timer" : (timer.isRunning ? "stopwatch" : "pause.fill"),
                barFill: timer.isRunning && !fired ? (timer.fraction(at: now) * 200).rounded() / 200 : nil,
                // Orange, the phone's own timer colour (2026-10-01).
                tint: .system("orange"),
                url: URL(string: "clock-timer://")
            )
        case .stopwatch(let watch):
            return ActivityRecord(
                id: NotchController.timerActivityID, kind: .timer, insertedAt: timerShown?.insertedAt ?? now, ttl: nil,
                title: "Stopwatch",
                compactText: TimerText.format(seconds: watch.elapsed(at: now).rounded(.down)),
                symbolName: "stopwatch",
                tint: .system("orange"),
                url: URL(string: "clock-stopwatch://")
            )
        }
    }

    /// Republishes the timer record only when what the island would draw
    /// changes — text, ring or glyph — so the 250 ms tick costs nothing
    /// between seconds.
    private func show(_ record: ActivityRecord) {
        guard record.compactText != timerShown?.compactText || record.barFill != timerShown?.barFill
                || record.symbolName != timerShown?.symbolName else { return }
        if timerShown == nil {
            Self.log.notice("clock timer in the island as \(record.compactText ?? "", privacy: .public) (\(record.title, privacy: .private))")
        }
        timerShown = record
        queue.insert(record)
        publish()
    }

    private func handle(_ intent: NotchIntent) {
        switch intent {
        case .open(let url):
            open(url)
        case .togglePlayPause:
            act(playing: !isPlayingNow, elapsed: livePosition(at: Date()), then: .togglePlayPause)
        case .next:
            act(playing: isPlayingNow, elapsed: 0, then: .nextTrack)
        case .previous:
            act(playing: isPlayingNow, elapsed: 0, then: .previousTrack)
        case .toggleShuffle:    media.send(.toggleShuffle)
        case .toggleRepeat:     media.send(.toggleRepeat)
        case .selectOutput(let id): device.setDefaultOutput(uid: id)
        case .openSource:           openSourceApp()
        case .toggleFavorite:       favorites.toggle()
        case .toggleMute:           call.toggleMute()
        case .hideCallApp:
            // The next refresh hands over to another app on the mic or ends
            // the call quietly, and the service undoes Ledge's mute.
            if let app = callLiveApp {
                call.dismissCurrent()
                settings.hideCallApp(app.bundleID)
            }
        case .seek(let fraction):
            // The scrubber only knows its own width, not the track's
            // duration — this is the one place both are in scope.
            guard let duration = mediaPayload.duration, duration > 0 else { return }
            act(playing: isPlayingNow, elapsed: duration * fraction, then: .seek(seconds: duration * fraction))
        }
    }

    private func showCaption(_ text: String, for duration: TimeInterval = NotchController.captionDuration) {
        presenter.setCaption(text)
        captionTask?.cancel()
        captionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.presenter.setCaption(nil)
        }
    }

    /// A payload the island cannot show — a browser tab, or nothing
    /// playing at all — does not take the card away at once (2026-10-01,
    /// from a recording). With a music app and a browser both holding
    /// audio, MediaRemote hands "now playing" back and forth a second at
    /// a time; clearing on every handover made the island collapse and
    /// grow again, re-announcing the song each time it came back, because
    /// clearing forgets which title was announced. The card is given a
    /// moment instead, and any payload the island can show cancels the
    /// departure. Nothing on screen clears straight away: there is
    /// nothing to flicker.
    private var clearMediaTask: Task<Void, Never>?
    private static let mediaClearGrace: Duration = .milliseconds(1500)

    private func holdThenClearMedia() {
        guard presenter.controller.media != nil else {
            clearMedia()
            return
        }
        guard clearMediaTask == nil else { return }
        clearMediaTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: AppModel.mediaClearGrace)
            guard !Task.isCancelled, let self else { return }
            self.clearMediaTask = nil
            self.clearMedia()
        }
    }

    /// The card and everything that belongs to it: the queue's entry, the
    /// presentation, the caption, and the payload the scrubber and the
    /// position tick read.
    private func clearMedia() {
        clearMediaTask?.cancel()
        clearMediaTask = nil
        mediaPayload = MediaPayload()
        positionOverride = nil
        queue.remove(kind: .media)
        presenter.controller.setMedia(nil)
        clearCaption()
        publish()
    }

    private func clearCaption() {
        captionTask?.cancel()
        captionTask = nil
        captionedTitle = nil
        presenter.setCaption(nil)
    }

    /// Brings the app that is playing to the front.
    private func openSourceApp() {
        activateApp(bundleID: mediaPayload.bundleIdentifier, pid: mediaPayload.processIdentifier.map { pid_t($0) })
    }

    /// Brings an app to the front: the one playing, or the one on a call.
    /// LaunchServices first (`openApplication(at:)` with `activates`), keyed
    /// by bundle id: it works from a background agent like this one, where
    /// macOS 14's cooperative activation would refuse a bare
    /// `NSRunningApplication.activate()` because Ledge is never the active
    /// app itself. The pid path is the fallback for a running app that
    /// LaunchServices cannot locate by bundle id (an unbundled binary).
    private func activateApp(bundleID: String?, pid: pid_t?) {
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return
        }
        if let pid, let app = NSRunningApplication(processIdentifier: pid) {
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
    /// What the user just did, shown before the player confirms it — see
    /// `PositionOverride`. Cleared when the adapter reports something at
    /// least as new, or after its lifetime.
    private var positionOverride: PositionOverride?

    private var isPlayingNow: Bool {
        if let override = positionOverride, override.isFresh(at: Date()) { return override.playing }
        return mediaPayload.isPlaying
    }

    /// The live position now, from the override if one is fresh, else from
    /// the adapter's last report.
    private func livePosition(at now: Date) -> Double {
        if let override = positionOverride, override.isFresh(at: now) {
            return MediaPosition.elapsed(
                at: now, elapsedTime: override.elapsedTime, timestamp: override.timestamp,
                rate: override.playing ? (mediaPayload.playbackRate ?? 1) : 0, duration: mediaPayload.duration
            )
        }
        return MediaPosition.elapsed(
            at: now, elapsedTime: mediaPayload.elapsedTime ?? 0, timestamp: mediaPayload.timestamp ?? now,
            rate: mediaPayload.isPlaying ? (mediaPayload.playbackRate ?? 1) : 0, duration: mediaPayload.duration
        )
    }

    /// Acts on playback optimistically: the card reflects the action now,
    /// the command goes out, and the adapter's report reconciles.
    private func act(playing: Bool, elapsed: Double, then command: MediaCommand) {
        positionOverride = PositionOverride(elapsedTime: elapsed, timestamp: Date(), playing: playing)
        refreshMediaPresentation()
        media.send(command)
    }

    /// Anchor-based (2026-09-30): the card gets the position as of `now`
    /// and the rate, and draws every frame from there itself — nothing
    /// ticks here any more.
    private func refreshMediaPresentation() {
        guard mediaPayload.hasMedia, let title = mediaPayload.title else { return }
        let now = Date()
        let playing = isPlayingNow
        presenter.controller.setMedia(
            MediaPresentation(
                title: title,
                artist: mediaPayload.artist,
                artwork: mediaPayload.artworkData,
                isPlaying: playing,
                elapsed: livePosition(at: now),
                duration: mediaPayload.duration,
                anchor: now,
                rate: playing ? (mediaPayload.playbackRate ?? 1) : 0,
                isShuffling: mediaPayload.isShuffling,
                repeatMode: mediaPayload.repeatSetting.map {
                    switch $0 {
                    case .off: .off
                    case .one: .one
                    case .all: .all
                    }
                },
                favorite: favorites.state
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
        if !calendar.availability.isAvailable {
            queue.remove(kind: .calendar)
            presenter.setUpcoming(nil)
        }
        if !focus.availability.isAvailable { queue.remove(kind: .focus) }
        if !liveActivities.availability.isAvailable { queue.remove(kind: .liveActivity) }
        if !call.availability.isAvailable {
            queue.remove(kind: .call)
            callShown = nil
            callLiveApp = nil
            presenter.setCallPanel(nil)
        }
        if !power.availability.isAvailable { queue.remove(kind: .charging) }
        if !media.availability.isAvailable {
            queue.remove(kind: .media)
            // The activity is not the only thing a dead media service leaves
            // behind: `controller.media` is what hover opens the panel for,
            // and the position tick keeps advancing it. Clear both, or a
            // stale now-playing card stays one hover away after the adapter
            // has given up.
            if presenter.controller.media != nil {
                presenter.controller.setMedia(nil)
            }
        }
    }

    private static func displayTint(_ tint: ActivityTint) -> NotchController.ActivityDisplay.Tint {
        switch tint {
        case .positive:           return .positive
        case .warning:            return .warning
        case .system(let name):   return .system(name)
        case let .color(red, green, blue): return .color(red: red, green: green, blue: blue)
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
                artwork: record.artwork,
                tint: record.tint.map(Self.displayTint),
                url: record.url,
                parts: record.parts?.map { .init(symbolName: $0.symbolName, text: $0.text) },
                score: record.score.map {
                    .init(home: .init(name: $0.home.name, value: $0.home.value, crest: $0.home.crest),
                          away: .init(name: $0.away.name, value: $0.away.value, crest: $0.away.crest),
                          status: $0.status, clock: $0.clock, title: $0.title)
                },
                lines: record.lines,
                badge: record.badge,
                segments: record.segments?.map(Self.displaySegment)
            )
        }
        // `setActivities` sets the count itself — do not also call
        // `setActivityCount`, or overflow gets counted twice.
        presenter.setActivities(display, overflow: queue.overflowCount)
    }
}
