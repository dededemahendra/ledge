import AppKit
import OSLog
@preconcurrency import ScreenCaptureKit
import ActivityKit

public enum LiveActivityEvent: Sendable, Equatable {
    /// An activity is running and this is what its card says.
    case showing(LiveActivityContent)
    /// The activity has ended.
    case ended
}

/// An iPhone Live Activity on the Mac (2026-10-01).
///
/// The menu bar's pill carries no readable content — for a third-party
/// activity the Mac draws nothing in it at all — and everything the
/// activity says lives in the card the pill opens. That card is an
/// ordinary window of `MenuBarAgent`, its Accessibility tree full of the
/// figures (names, scores, the period, a running clock), and it keeps
/// answering after it has been moved out of sight. So the island presses
/// the pill once, takes one picture of the card for the crests, moves the
/// window off the screen and then simply reads it, once a second, for as
/// long as the activity runs. One brief flash when an activity arrives,
/// and a live score after that.
///
/// Needs Accessibility to find and press the pill and to read the card,
/// and Screen Recording for that one picture.
@MainActor
public final class LiveActivityService {
    private nonisolated static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "live-activity")

    /// Where the card is parked while it is being read: far off any
    /// screen, where nothing composites it.
    static let parking = CGPoint(x: 12_000, y: -8_000)
    /// How big a crest is cut, in points.
    static let crestSize: CGFloat = 24

    public private(set) var availability: ServiceAvailability = .available
    public var hasScreenAccess: Bool { CGPreflightScreenCaptureAccess() }
    public private(set) var location: PillLocation?
    public private(set) var content: LiveActivityContent?

    private var enabled = true
    /// How long to wait before opening the card again after it has been
    /// closed, and when it was last opened — see `reopen`.
    private var reopenDelay: Duration = .zero
    private var openedAt: ContinuousClock.Instant?
    private var hasAskedForAccess = false
    private var timer: Timer?
    private var continuation: AsyncStream<LiveActivityEvent>.Continuation?
    /// The card window we are holding open, and the crests cut from it.
    private var card: AXUIElement?
    private var crests: (home: Data?, away: Data?, names: String)?
    private var opening: Task<Void, Never>?
    /// While the user is looking at the system's own card, it stays where
    /// the system put it and is not parked again until this passes.
    private var showUntil: Date?

    public init() {}

    public func start() -> AsyncStream<LiveActivityEvent> {
        let (stream, continuation) = AsyncStream<LiveActivityEvent>.makeStream()
        self.continuation = continuation
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
        return stream
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        opening?.cancel()
        opening = nil
        closeCard()
        continuation?.finish()
        continuation = nil
    }

    /// Off: nothing is polled, nothing is opened, and a card being held
    /// is given back.
    public func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        if enabled { poll() } else { finish() }
    }

    #if DEBUG
    /// Debug only (`ledge://probe/card`): what the open card says, as the
    /// reader sees it — every element with its place in the card, and
    /// what that was understood to mean. For fitting the island to a kind
    /// of activity that has not been seen before.
    public func probeCard() -> [String] {
        guard let card, let read = PillLocator.cardContent(of: card) else { return ["no card"] }
        var lines = ["card \(Int(read.size.width))x\(Int(read.size.height)) pt, \(read.elements.count) parts"]
        for element in read.elements.sorted(by: { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }) {
            lines.append("  \(element.kind == .image ? "image" : " text") \(Int(element.frame.minX)),\(Int(element.frame.minY)) \(Int(element.frame.width))x\(Int(element.frame.height))  \(element.text)")
        }
        let parsed = CardReader.read(read.elements, cardSize: read.size)
        lines.append("match: \(parsed.isMatch)")
        lines.append("home: \(parsed.home?.name ?? "-") \(parsed.home?.value ?? "-")")
        lines.append("away: \(parsed.away?.name ?? "-") \(parsed.away?.value ?? "-")")
        lines.append("status: \(parsed.status ?? "-") | clock: \(parsed.clock ?? "-") | title: \(parsed.title ?? "-")")
        return lines
    }
    #endif

    /// How long the system's own card stays put once it has been asked
    /// for — from the island or from the menu bar's pill.
    static let showDuration: TimeInterval = 8

    /// Shows the system's own card where it belongs, for a few seconds —
    /// a click on the island. It is parked again afterwards.
    public func press() {
        guard let card, let location else {
            if let location { PillLocator.press(location) }
            return
        }
        PillLocator.move(card, to: CGPoint(x: location.frame.midX - 178, y: location.frame.maxY))
        showUntil = Date().addingTimeInterval(Self.showDuration)
    }

    private func poll() {
        guard enabled else { return }
        guard PillLocator.isTrusted else {
            availability = .needsPermission("Accessibility")
            finish()
            return
        }
        guard let found = PillLocator.find() else {
            availability = hasScreenAccess ? .available : .needsPermission("Screen Recording")
            finish()
            return
        }
        if found != location {
            if location == nil {
                Self.log.notice("live activity: pill at \(Int(found.frame.minX), privacy: .public),\(Int(found.frame.minY), privacy: .public)")
            }
            location = found
        }
        guard hasScreenAccess else {
            availability = .needsPermission("Screen Recording")
            if !hasAskedForAccess {
                hasAskedForAccess = true
                Self.log.notice("live activity: pill showing, asking for Screen Recording")
                _ = CGRequestScreenCaptureAccess()
            }
            return
        }
        availability = .available

        // The card the island reads. Adopt one that is already open (our
        // own, after a relaunch), else open it.
        if card == nil, let existing = PillLocator.expandedWindow() {
            adopt(existing)
        }
        guard let card else {
            if opening == nil { open() }
            return
        }
        // Gone — the system closed it, or the user did.
        guard PillLocator.expandedWindow() != nil else {
            self.card = nil
            reopen()
            return
        }
        // Where the card is now decides what to do with it. Parked
        // already: leave it alone — writing a position it already has is
        // what made the pill fight the island once before. On screen when
        // the island did not put it there: the user pressed the pill
        // themselves, and pulling it away from under them was the glitch
        // they reported (2026-10-05) — the pill looked dead because every
        // press was undone within the second. It stays for a few seconds,
        // then goes back out of sight.
        let onScreen = PillLocator.position(of: card).map { $0.minX < Self.parking.x / 2 } ?? false
        if let until = showUntil {
            if Date() >= until {
                showUntil = nil
                PillLocator.move(card, to: Self.parking)
            }
        } else if onScreen {
            showUntil = Date().addingTimeInterval(Self.showDuration)
            Self.log.notice("live activity: the card was opened from the menu bar; leaving it a moment")
        }
        read(card)
    }

    private func adopt(_ window: AXUIElement) {
        card = window
        openedAt = ContinuousClock().now
        PillLocator.move(window, to: Self.parking)
        if content == nil { Self.log.notice("live activity: reading the card") }
    }

    /// The card closed under us — the system dismisses this popover on
    /// all sorts of outside events. Opening it again shows it for the
    /// blink it takes to park it, so a dismissal storm must not become a
    /// strobe (2026-10-03, user's report): each close that follows hard
    /// on an open doubles the wait, up to ten seconds, and a card that
    /// survives a while earns the wait back.
    private func reopen() {
        let now = ContinuousClock().now
        if let openedAt, now - openedAt < .seconds(15) {
            reopenDelay = reopenDelay == .zero ? .seconds(1) : min(reopenDelay * 2, .seconds(10))
            Self.log.notice("live activity: card dismissed quickly; waiting \(self.reopenDelay.components.seconds, privacy: .public)s")
        } else {
            reopenDelay = .zero
        }
        openedAt = nil
        guard opening == nil else { return }
        let wait = reopenDelay
        opening = Task { @MainActor [weak self] in
            if wait > .zero { try? await Task.sleep(for: wait) }
            guard !Task.isCancelled, let self else { return }
            self.opening = nil
            self.open()
        }
    }

    /// Presses the pill, waits for the card, takes the one picture the
    /// crests come from, and parks it.
    private func open() {
        guard opening == nil, let location else { return }
        opening = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.opening = nil }
            guard PillLocator.press(location) else { return }
            let clock = ContinuousClock()
            let start = clock.now
            var window: AXUIElement?
            while window == nil, clock.now - start < CardPeek.timeout {
                try? await Task.sleep(for: CardPeek.step)
                window = PillLocator.expandedWindow()
            }
            guard let window else {
                Self.log.notice("live activity: the card did not come up")
                return
            }
            await self.photograph(window, at: location)
            guard !Task.isCancelled else { return }
            self.adopt(window)
            self.read(window)
        }
    }

    /// The one picture: the crests, cut at the rectangles the card's own
    /// tree gives for them. Everything else the island shows is text.
    private func photograph(_ window: AXUIElement, at location: PillLocation) async {
        guard let content = PillLocator.cardContent(of: window),
              let home = content.elements.filter({ $0.kind == .image }).min(by: { $0.frame.minX < $1.frame.minX }),
              let away = content.elements.filter({ $0.kind == .image }).max(by: { $0.frame.minX < $1.frame.minX }),
              home.frame.minX != away.frame.minX
        else { return }
        let names = home.text + "|" + away.text
        guard crests?.names != names else { return }
        let scale = CaptureGeometry.scale(at: CGPoint(x: location.frame.midX, y: location.frame.midY))
        guard let scWindow = await CardPeek.popover(below: location.frame),
              let image = try? await CardPeek.capture(scWindow, scale: scale),
              let bounds = CardCropper.opaqueBounds(of: image), let card = image.cropping(to: bounds)
        else {
            Self.log.notice("live activity: no picture for the crests")
            return
        }
        crests = (
            home: CardCropper.crest(from: card, at: home.frame, scale: scale, size: Self.crestSize)?.png,
            away: CardCropper.crest(from: card, at: away.frame, scale: scale, size: Self.crestSize)?.png,
            names: names
        )
        Self.log.notice("live activity: crests cut \(Int(home.frame.width), privacy: .public) pt")
    }

    /// Reads the card and publishes it when anything it says has changed.
    private func read(_ window: AXUIElement) {
        guard let read = PillLocator.cardContent(of: window) else { return }
        var parsed = CardReader.read(read.elements, cardSize: read.size)
        parsed.home?.crest = crests?.home
        parsed.away?.crest = crests?.away
        guard parsed != content else { return }
        if content == nil {
            Self.log.notice("live activity: \(parsed.isMatch ? "a match" : "a card", privacy: .public) with \(read.elements.count, privacy: .public) parts")
            if !parsed.isMatch { recordShape(read) }
        }
        content = parsed
        continuation?.yield(.showing(parsed))
    }

    /// An activity the island has no shape of its own for writes down
    /// what its card looks like, so the island can be fitted to it later
    /// (2026-10-03: an F1 session showed only a cut sentence, and the
    /// session was over before its card could be read). The newest one
    /// only, in the user's own log folder, never the shared system log.
    private func recordShape(_ read: (size: CGSize, elements: [CardElement])) {
        var lines = ["\(Date().formatted(.iso8601)) — card \(Int(read.size.width))x\(Int(read.size.height)) pt, \(read.elements.count) parts"]
        for element in read.elements.sorted(by: { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }) {
            lines.append("  \(element.kind == .image ? "image" : " text") \(Int(element.frame.minX)),\(Int(element.frame.minY)) \(Int(element.frame.width))x\(Int(element.frame.height))  \(element.text)")
        }
        let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Ledge")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: directory.appending(path: "card-shape.txt"), atomically: true, encoding: .utf8)
    }

    /// The activity has gone, or the island has been switched off: give
    /// the card back and say so once.
    private func finish() {
        opening?.cancel()
        opening = nil
        reopenDelay = .zero
        openedAt = nil
        closeCard()
        guard location != nil || content != nil else { return }
        location = nil
        content = nil
        crests = nil
        Self.log.notice("live activity: gone")
        continuation?.yield(.ended)
    }

    /// Puts the card back where the system had it and closes it, so the
    /// menu bar is left exactly as it was found.
    private func closeCard() {
        guard let card else { return }
        self.card = nil
        showUntil = nil
        if let location {
            PillLocator.move(card, to: CGPoint(x: location.frame.midX - 204, y: location.frame.maxY))
            PillLocator.press(location)
        }
    }
}
