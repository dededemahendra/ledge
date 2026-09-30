import AppKit
import SwiftUI
import OSLog

/// Owns the window and keeps it in step with the display and the controller.
@MainActor
public final class NotchPresenter {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "notch")

    public let controller: NotchController
    private var window: NotchWindow?
    private var observers: [NSObjectProtocol] = []
    private var trackingMonitor: Any?
    private var clickOutsideMonitor: Any?
    private var escapeMonitor: Any?
    private var scrollMonitor: Any?
    private var swipe = SwipeToSkipTracker()
    /// How long the cursor must rest on the island before it counts as
    /// hovering — see `HoverIntentTracker`. A pass-through to the menu bar
    /// crosses the notch in well under 100 ms; 0.2 s filters it while a
    /// deliberate stop still feels immediate.
    public static let hoverDwell: TimeInterval = 0.2
    private var hover = HoverIntentTracker(dwell: NotchPresenter.hoverDwell)

    /// Settings (2026-09-30): a new dwell starts a fresh tracker; a hover
    /// in progress simply begins again.
    public func setHoverDwell(_ seconds: TimeInterval) {
        guard seconds != hover.dwell else { return }
        hover = HoverIntentTracker(dwell: seconds)
    }
    private var dwellTimer: Timer?
    /// Pending order-out after a collapse to `.hidden` — see
    /// `syncWindowToVisibility`.
    private var hideTask: Task<Void, Never>?
    private var skipHintTask: Task<Void, Never>?
    /// Registered on `NSWorkspace.shared.notificationCenter`, NOT
    /// `NotificationCenter.default` like `observers` — a token from one
    /// center cannot be removed via the other, so this is tracked and torn
    /// down separately.
    private var reduceMotionObserver: NSObjectProtocol?
    private var lockObserver: LockScreenObserver?

    public init() {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let rect = NSScreen.builtIn.flatMap { NotchGeometry.notchRect(for: $0.snapshot()) }
        controller = NotchController(
            metrics: NotchMetrics(notchRect: rect ?? .zero),
            reduceMotion: reduceMotion
        )
    }

    public func start() {
        rebuildForCurrentScreen()

        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildForCurrentScreen() }
            }
        )

        // Reduce Motion, spec §5: read once at init is not enough for an
        // always-running agent — a user who flips it while Ledge is already
        // running must get the crossfade without quitting and relaunching.
        reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.controller.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        }

        // Swipe to skip (2026-09-29): a two-finger horizontal swipe over the
        // island skips a track. A LOCAL monitor is enough — scroll events
        // go to the window under the cursor, and ours takes mouse events
        // exactly while the cursor is on the island (`setAcceptsMouse`).
        // Only the scalar facts cross onto the actor; `NSEvent` is not
        // `Sendable`.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let deltaX = event.scrollingDeltaX
            let inverted = event.isDirectionInvertedFromDevice
            let phase: SwipeToSkipTracker.Phase
            if event.momentumPhase != [] {
                phase = .momentum
            } else {
                switch event.phase {
                case .began:            phase = .began
                case .changed:          phase = .changed
                case .ended, .cancelled: phase = .ended
                default:                phase = .none
                }
            }
            MainActor.assumeIsolated {
                self?.handleSwipe(deltaX: deltaX, phase: phase, invertedFromDevice: inverted)
            }
            return event
        }

        // Lock screen, spec §7: raise the window above the lock shield and
        // switch the controller to display-only while `loginwindow` owns
        // the screen. Built last, as the spec sequenced it; nothing else
        // depends on it and it can be removed without touching anything.
        let lock = LockScreenObserver { [weak self] locked in
            self?.setLocked(locked)
        }
        lock.start()
        lockObserver = lock

        // Mouse tracking: the window is click-through, so hover is observed globally
        // and filtered against the island rect. Mouse-moved monitors need no permission.
        trackingMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }

        // Click-outside dismissal, spec §5. Global monitors only see events
        // NOT delivered to one of this app's own windows (Apple's own
        // documentation: "your handler will not be called for events that
        // are sent to your own application's windows") — a tap ON the
        // island is instead consumed by `NotchRootView`'s `.onTapGesture`
        // via the normal responder chain, and a click inside our 640x320
        // canvas but outside the island's claimed `interactivePath` falls
        // through to whatever is beneath us, which IS "another
        // application" from the system's perspective. So "global monitor
        // fired" and "click landed outside the island" are the same
        // condition here; no extra geometry check is needed. Mouse
        // monitors need no permission, same as the one above.
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissIfExpanded() }
        }

        // Escape dismissal, spec §5, as a LOCAL monitor per the fix-wave
        // review. NOTE (flagged, not silently worked around): `NotchWindow`
        // hardwires `canBecomeKey` to false, so this window can never
        // become key. A local monitor observes events already routed into
        // THIS app's dispatch, which for keyDown structurally requires a
        // key window — so this is unlikely to fire while some other app
        // has focus, the realistic case for a background accessory app. A
        // GLOBAL keyDown monitor would fire reliably instead, but per
        // Apple's documentation key-event global monitoring additionally
        // requires Accessibility/Input Monitoring trust, a permission
        // nothing else in this app needs — a real product tradeoff, not
        // an implementation detail, so it is left for a human to decide
        // rather than granted unasked. Implemented as specified; see the
        // fix-wave report.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // Escape
            // `NSEvent` is not `Sendable` in this SDK, so it must not cross
            // back out of `assumeIsolated`'s return — only the `Bool`
            // verdict does, and `event` itself (already a plain parameter
            // of this closure, never having crossed an isolation boundary)
            // is handled below instead.
            let consumed: Bool = MainActor.assumeIsolated {
                guard let self, self.controller.state == .expanded else { return false }
                self.dismissIfExpanded()
                return true
            }
            return consumed ? nil : event   // nil consumes the keypress
        }
    }

    public func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if let reduceMotionObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(reduceMotionObserver)
        }
        reduceMotionObserver = nil
        if let trackingMonitor { NSEvent.removeMonitor(trackingMonitor) }
        trackingMonitor = nil
        dwellTimer?.invalidate()
        dwellTimer = nil
        hideTask?.cancel()
        hideTask = nil
        if let clickOutsideMonitor { NSEvent.removeMonitor(clickOutsideMonitor) }
        clickOutsideMonitor = nil
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        skipHintTask?.cancel()
        skipHintTask = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        lockObserver?.stop()
        lockObserver = nil
        window?.orderOut(nil)
        window = nil
    }

    /// Screen locked/unlocked (`LockScreenObserver`). Nothing is drawn on
    /// the lock screen (2026-10-01): macOS 27 composites the lock screen
    /// over every user window, so raising the island there only ever
    /// bought an unlock that collapsed a card the user never saw — ears
    /// drawn outside a shrinking shape, then a window left out (user's
    /// recording). Now the island is simply hidden while locked, its state
    /// untouched, and shown again exactly as it was.
    public private(set) var isLocked = false

    public func setLocked(_ locked: Bool) {
        isLocked = locked
        controller.setLocked(locked)
        if !locked, window == nil { rebuildForCurrentScreen() }
        syncWindowToVisibility()
    }

    /// Opens or collapses the panel on demand (e.g. the menu bar's "Toggle
    /// Panel" item), independent of hover.
    ///
    /// `NotchController.click()`/`dismiss()` only ever touch the model. Without
    /// a resync here, a toggle fired with the cursor away from the notch (the
    /// realistic case — the status item lives at the other end of the menu
    /// bar) would flip `controller.state` to `.expanded` while the window
    /// stayed `orderOut`, so nothing would appear on screen. See
    /// `syncWindowToVisibility()`.
    public func toggle() {
        if controller.state == .expanded {
            controller.dismiss()
        } else {
            controller.click()
        }
        syncWindowToVisibility()
    }

    /// The shared action behind click-outside and Escape dismissal. Routes
    /// through the presenter rather than `controller.dismiss()` alone, so
    /// the window resyncs — see `toggle()`.
    private func dismissIfExpanded() {
        guard controller.state == .expanded else { return }
        controller.dismiss()
        syncWindowToVisibility()
    }

    /// Latest visible activities, rendered by `NotchRootView`.
    public func setActivities(_ activities: [NotchController.ActivityDisplay], overflow: Int) {
        controller.setActivities(activities, overflow: overflow)
        // Was its own copy of `syncWindowToVisibility()`'s body; consolidated
        // so an activity expiring goes through the same hover re-evaluation
        // every other mutation does — see item 8 in the fix-wave report.
        syncWindowToVisibility()
    }

    /// Re-evaluates hover against the CURRENT geometry and resyncs the window
    /// accordingly. `AppModel.prune()` calls this on every 250ms tick,
    /// unconditionally — fix-wave item 3.
    ///
    /// Without this, `isHovered` only updates on `.mouseMoved`
    /// (`updateHover()`) or a geometry change (`syncWindowToVisibility()`'s
    /// other callers, per that method's own doc comment). A genuinely missed
    /// `.mouseMoved` event — the cursor warped programmatically, Mission
    /// Control, secure input, waking from sleep with the pointer somewhere
    /// new — could then leave `isHovered` latched `true` forever, and
    /// because `ActivityQueue.prune(hovered:)` honours it, every activity
    /// would stop expiring indefinitely. Self-locking: the mutation that
    /// would clear it is the very expiry it is suppressing.
    ///
    /// Just forwards to `syncWindowToVisibility()`, the existing single
    /// choke point for this. Safe to call every tick without recursion risk:
    /// `reevaluateHover()` itself never calls back into
    /// `syncWindowToVisibility()` (see that method's doc comment), and each
    /// step here is cheap when nothing has actually changed — a
    /// `Path.contains` check, then re-asserting the window's current
    /// order/interactive region.
    public func reevaluateHoverForExpiry() {
        syncWindowToVisibility()
    }

    /// Review Focus 2 and 3: no notch, or no built-in screen, means no island.
    private func rebuildForCurrentScreen() {
        guard
            let screen = NSScreen.builtIn,
            let rect = NotchGeometry.notchRect(for: screen.snapshot())
        else {
            Self.log.info("no notched built-in display; island hidden")
            // Sleep/display-hot-plug case: if the built-in display
            // disappears while the panel is open (or an activity is live)
            // and later returns, a new window must not resurrect stale
            // state with no user action. `setHovered(false)` first, THEN
            // `dismiss()`: `dismiss()` re-derives via `recomputeState()`,
            // which reads `isHovered` — clearing hover first means that
            // re-derive never briefly lands on a stale `.peek`.
            // `dismiss()` is a no-op unless `state == .expanded`, so this is
            // safe to call unconditionally. A live activity legitimately
            // reappearing once the window comes back (still within its TTL)
            // is correct, not stale, and recomputeState still allows that.
            hover.reset()
            dwellTimer?.invalidate()
            dwellTimer = nil
            controller.setHovered(false)
            controller.dismiss()
            // Zeroed, not left stale: makes `NotchController.click()`'s
            // no-island guard correctly reject a "Toggle Panel" press that
            // lands during this exact gap too, not only on a permanently
            // notch-less Mac.
            controller.metrics = NotchMetrics(notchRect: .zero)
            window?.orderOut(nil)
            window = nil
            return
        }

        controller.metrics = NotchMetrics(notchRect: rect)

        if let window {
            window.reposition(for: screen)
        } else {
            let created = NotchWindow(
                screen: screen,
                content: AnyView(NotchRootView(controller: controller, onTap: { [weak self] in
                    self?.tapOnIsland()
                }))
            )
            window = created
        }
        syncWindowToVisibility()
    }

    /// Keeps the claimed region in step with what is actually drawn, and keeps
    /// the window ordered in only while the island has something to show.
    /// Spec §5: "Ordered out entirely when state is `.hidden`, so idle
    /// compositing cost is zero" — enforced here as the single choke point so
    /// every caller (rebuild, hover, `toggle()`) gets it for free.
    ///
    /// Also the single choke point for re-evaluating hover against the
    /// CURRENT geometry, not just on the next mouse-moved event: if the
    /// island shrinks under a stationary cursor (`toggle()` closing the
    /// panel, or an activity expiring via `setActivities`), `isHovered`
    /// would otherwise stay latched true — and `AppModel.prune()` reads
    /// that flag to suppress ALL expiry, so a stale `true` hangs activities
    /// indefinitely on an idle machine until the mouse next moves. Calls
    /// `reevaluateHover()`, never `updateHover()`, specifically to avoid
    /// recursing back into this method.
    private func syncWindowToVisibility() {
        reevaluateHover()
        refreshInteractiveRegion()
        guard let window else { return }
        // The canvas takes mouse events only while the cursor is on the
        // island — see `NotchWindow.setAcceptsMouse` for the bug this
        // closes. Re-derived here, on the same choke point as everything
        // else, so every path that can change hover or visibility (mouse
        // moved, the 250ms tick, an activity arriving/expiring, a toggle,
        // a screen change) keeps the flag honest. The RAW pointer fact,
        // not the dwell-promoted `controller.isHovered`: a click on a
        // visible island during the dwell must still land on it.
        window.setAcceptsMouse(Self.shouldAcceptMouse(visible: controller.isVisible, hovered: hover.isPointerInside))
        if isLocked {
            // Hidden outright while the screen is locked; no retract, no
            // level change. Unlocking re-syncs and orders it straight in.
            hideTask?.cancel()
            hideTask = nil
            window.orderOut(nil)
        } else if controller.isVisible {
            hideTask?.cancel()
            hideTask = nil
            window.orderFrontRegardless()
        } else if hideTask == nil {
            // Keep the window up while the island retracts into the notch
            // (`NotchAnimation.hideSettle`); ordering it out here, on the
            // first frame of the collapse, cut every unhover and blip expiry
            // to a hard cut. Mouse acceptance is already off (above), so
            // clicks fall through meanwhile; a hover returning cancels this.
            hideTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(NotchAnimation.hideSettle))
                guard !Task.isCancelled, let self, !self.controller.isVisible else { return }
                self.window?.orderOut(nil)
                self.hideTask = nil
            }
        }
    }

    /// Pure, so it can be pinned by `NotchPresenterTests` without a window:
    /// mouse events are wanted only when there is an island to click AND the
    /// cursor is on it. Everything else must fall through.
    nonisolated static func shouldAcceptMouse(visible: Bool, hovered: Bool) -> Bool {
        visible && hovered
    }

    /// The previewed next event (`NotchController.upcoming`) changes the
    /// peek's shape, so it goes through the presenter for the window resync.
    public func setUpcoming(_ upcoming: UpcomingEvent?) {
        guard upcoming != controller.upcoming else { return }
        controller.setUpcoming(upcoming)
        syncWindowToVisibility()
    }

    /// The card's calendar mode; can change the card's shape.
    public func setCalendarMode(_ data: CalendarModeData?) {
        guard data != controller.calendarMode else { return }
        controller.setCalendarMode(data)
        syncWindowToVisibility()
    }

    /// A song-change caption (`NotchController.caption`) grows the island,
    /// so it goes through the presenter for the window resync.
    public func setCaption(_ caption: String?) {
        controller.setCaption(caption)
        syncWindowToVisibility()
    }

    private func handleSwipe(deltaX: CGFloat, phase: SwipeToSkipTracker.Phase, invertedFromDevice: Bool) {
        guard controller.isVisible else { return }
        guard let direction = swipe.track(deltaX: deltaX, phase: phase, invertedFromDevice: invertedFromDevice) else { return }
        // Modes first (2026-09-30): on the open card the swipe changes mode;
        // on the preview it opens the calendar. Only the compact island
        // with music still skips a track.
        if controller.swipe(direction) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            syncWindowToVisibility()
            return
        }
        guard controller.media != nil else { return }
        controller.emit(direction == .next ? .next : .previous)
        controller.setSkipHint(direction == .next ? .next : .previous)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        skipHintTask?.cancel()
        skipHintTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(NotchController.skipHintDuration))
            guard !Task.isCancelled else { return }
            self?.controller.setSkipHint(nil)
        }
    }

    /// A tap on the island itself (`NotchRootView.onTap`). Routed through
    /// `NotchController.tap()` for the decision and resynced here for the
    /// same reason `toggle()` is.
    private func tapOnIsland() {
        controller.tap()
        syncWindowToVisibility()
    }

    /// Keeps the claimed region in step with what is actually drawn.
    private func refreshInteractiveRegion() {
        guard let window else { return }
        guard controller.isVisible else {
            window.interactivePath = nil     // Review Focus 4
            return
        }
        window.setInteractiveShape(NotchShape(forgivingParameters()), in: Self.canvas)
    }

    /// Claim/detect a little more than is actually drawn when collapsed or
    /// peeking, for hover forgiveness — those are the narrow, easy-to-miss
    /// states; `.activity`/`.expanded` are already big targets. The ONE
    /// definition either hover detection (`reevaluateHover`) or the claimed
    /// interactive region (`refreshInteractiveRegion`) uses: they used to
    /// each apply their own version of this (+8/+4 gated to hidden/peek in
    /// one, ±4/+4 unconditional in the other), leaving a 4pt band at
    /// `.activity`/`.expanded` where the controller believed it was
    /// hovered — suppressing TTL expiry — but clicks passed through.
    private func forgivingParameters() -> NotchShapeParameters {
        var parameters = controller.parameters
        guard controller.state == .hidden || controller.state == .peek else { return parameters }
        parameters.width += 8
        parameters.height += 4
        return parameters
    }

    /// Global `.mouseMoved` monitors fire at high frequency for the whole
    /// screen. The brief's version recomputed the interactive path and
    /// reordered the window on *every* such event for as long as the island
    /// was visible — wasted CPU on every pixel of cursor travel, and a
    /// standing risk of visible flicker from reordering the window that
    /// often. Gating on the hover boolean actually changing makes the common
    /// case (moving around inside, or outside, the region) a single cheap
    /// `CGRect.contains` check with no further work.
    private func updateHover() {
        if reevaluateHover() {
            syncWindowToVisibility()
        }
    }

    /// Recomputes whether the cursor is within the island's (forgiveness-
    /// widened) region and updates `controller.isHovered` if that disagrees
    /// with the last known value. Returns whether it changed.
    ///
    /// Tests the same `NotchShape` path `refreshInteractiveRegion` claims for
    /// clicks (fix-wave item 2) — translated into global screen coordinates —
    /// rather than a separately-computed `CGRect`. The two used to disagree
    /// at exactly the corners that make this shape not a rectangle: the
    /// rounded bottom corners are inside the old rect but outside the path
    /// (a dead zone that read as hovered, suppressing TTL expiry, even
    /// though a click there would have passed through), and the concave
    /// outer fillets are outside the old rect but inside the path (a band
    /// where clicks were claimed with no hover ever having been reported).
    ///
    /// Deliberately does NOT call `syncWindowToVisibility()` itself: it is
    /// called FROM `syncWindowToVisibility()` (so geometry changes
    /// re-evaluate hover too — see that method's doc comment), and calling
    /// back into it unconditionally here would recurse. `updateHover()`
    /// (the mouse-moved path) calls both, in order, itself.
    ///
    /// Hover intent (2026-09-29): the geometric fact goes through
    /// `HoverIntentTracker`, and the controller hears only the promoted
    /// value — `true` once the cursor has rested on the island for
    /// `hoverDwell`, `false` the moment it leaves.
    @discardableResult
    private func reevaluateHover() -> Bool {
        guard let screen = NSScreen.builtIn else { return false }
        let point = Self.localPoint(NSEvent.mouseLocation, on: screen.frame)
        let inside = Self.islandPath(for: forgivingParameters()).contains(point)
        let change = hover.pointer(inside: inside, at: Date())
        armDwellTimer()
        switch change {
        case .none:      return false
        case .hovered:   controller.setHovered(true);  return true
        case .unhovered: controller.setHovered(false); return true
        }
    }

    /// Checks back exactly when a running dwell elapses, so the island
    /// opens on time under a perfectly still cursor (no further mouse
    /// events come, and the 250 ms tick is too coarse). Re-armed only
    /// when the due time changes, so the flood of mouse-moved events
    /// during a dwell costs nothing here.
    private func armDwellTimer() {
        guard let due = hover.pendingUntil else {
            dwellTimer?.invalidate()
            dwellTimer = nil
            return
        }
        if let dwellTimer, dwellTimer.isValid, abs(dwellTimer.fireDate.timeIntervalSince(due)) < 0.001 { return }
        dwellTimer?.invalidate()
        let timer = Timer(fire: due, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dwellTimer = timer
    }
}

extension NotchPresenter {
    /// The fixed canvas every claimed path (clicks in `refreshInteractiveRegion`,
    /// hover in `reevaluateHover`) is built against — same size and origin
    /// `NotchWindow` uses for its content view. `internal`, not `private`, so
    /// `islandPath(for:)`/`localPoint(_:on:)` are directly testable via
    /// `@testable import NotchKit` without faking `NSScreen`/`NSEvent`.
    /// `nonisolated`: a pure constant with no access to actor state — without
    /// this, `@MainActor` on the class would make even reading it implicitly
    /// async from a synchronous test context, same reasoning as
    /// `HUDService.composedAvailability`.
    nonisolated static let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)

    /// The island's claimed path for `parameters`, in the same canvas-local,
    /// top-left-origin, y-down space `NotchShape.path(in:)` and
    /// `NotchWindow.setInteractiveShape` both already use. The ONE
    /// definition of "what counts as the island" both click hit-testing and
    /// hover now derive from — see `reevaluateHover`'s doc comment.
    /// `nonisolated`: pure function of its parameter, same reasoning as `canvas`.
    nonisolated static func islandPath(for parameters: NotchShapeParameters) -> Path {
        NotchShape(parameters).path(in: canvas)
    }

    /// Converts a point in AppKit global screen coordinates (e.g.
    /// `NSEvent.mouseLocation`) into the local space `islandPath(for:)` is
    /// defined in, given the screen the island's canvas is anchored to.
    /// Mirrors `NotchWindow.reposition(for:)`'s placement — canvas centred
    /// horizontally, top edge welded to the screen's top edge — and undoes
    /// the flip `NotchWindow.setInteractiveShape` applies before AppKit hit
    /// testing. `canvas`'s own width/height cancel out of this derivation
    /// (`NotchShape.path(in:)` only ever reads `rect.midX`/`rect.minY`),
    /// leaving just the offset from the screen's horizontal centre and the
    /// vertical distance below its top edge. `nonisolated`: pure function of
    /// its parameters, same reasoning as `canvas`.
    nonisolated static func localPoint(_ globalPoint: CGPoint, on screenFrame: CGRect) -> CGPoint {
        CGPoint(
            x: globalPoint.x - screenFrame.midX + canvas.width / 2,
            y: screenFrame.maxY - globalPoint.y
        )
    }
}
