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
    /// Registered on `NSWorkspace.shared.notificationCenter`, NOT
    /// `NotificationCenter.default` like `observers` — a token from one
    /// center cannot be removed via the other, so this is tracked and torn
    /// down separately.
    private var reduceMotionObserver: NSObjectProtocol?

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
        if let clickOutsideMonitor { NSEvent.removeMonitor(clickOutsideMonitor) }
        clickOutsideMonitor = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        window?.orderOut(nil)
        window = nil
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
            controller.setHovered(false)
            controller.dismiss()
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
                    self?.toggle()
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
        if controller.isVisible {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }

    /// Keeps the claimed region in step with what is actually drawn.
    private func refreshInteractiveRegion() {
        guard let window else { return }
        guard controller.isVisible else {
            window.interactivePath = nil     // Review Focus 4
            return
        }
        let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
        window.setInteractiveShape(NotchShape(forgivingParameters()), in: canvas)
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
    /// Deliberately does NOT call `syncWindowToVisibility()` itself: it is
    /// called FROM `syncWindowToVisibility()` (so geometry changes
    /// re-evaluate hover too — see that method's doc comment), and calling
    /// back into it unconditionally here would recurse. `updateHover()`
    /// (the mouse-moved path) calls both, in order, itself.
    @discardableResult
    private func reevaluateHover() -> Bool {
        guard let screen = NSScreen.builtIn else { return false }
        let mouse = NSEvent.mouseLocation
        let parameters = forgivingParameters()

        // Island hit region in global screen coordinates.
        let region = CGRect(
            x: screen.frame.midX - parameters.width / 2,
            y: screen.frame.maxY - parameters.height,
            width: parameters.width,
            height: parameters.height
        )

        let hovered = region.contains(mouse)
        guard hovered != controller.isHovered else { return false }
        controller.setHovered(hovered)
        return true
    }
}
