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

        // Mouse tracking: the window is click-through, so hover is observed globally
        // and filtered against the island rect. Mouse-moved monitors need no permission.
        trackingMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }
    }

    public func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if let trackingMonitor { NSEvent.removeMonitor(trackingMonitor) }
        trackingMonitor = nil
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

    /// Latest visible activities, rendered by `NotchRootView`.
    public func setActivities(_ activities: [NotchController.ActivityDisplay], overflow: Int) {
        controller.setActivities(activities, overflow: overflow)
        refreshInteractiveRegion()
        if controller.isVisible {
            window?.orderFrontRegardless()
        } else {
            window?.orderOut(nil)
        }
    }

    /// Review Focus 2 and 3: no notch, or no built-in screen, means no island.
    private func rebuildForCurrentScreen() {
        guard
            let screen = NSScreen.builtIn,
            let rect = NotchGeometry.notchRect(for: screen.snapshot())
        else {
            Self.log.info("no notched built-in display; island hidden")
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
                content: AnyView(NotchRootView(controller: controller))
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
    private func syncWindowToVisibility() {
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
        // Claim a little more than is drawn when collapsed, for hover forgiveness.
        var parameters = controller.parameters
        if controller.state == .hidden || controller.state == .peek {
            parameters.width += 8
            parameters.height += 4
        }
        window.setInteractiveShape(NotchShape(parameters), in: canvas)
    }

    /// Only acts when hover actually crosses the island's boundary.
    ///
    /// Global `.mouseMoved` monitors fire at high frequency for the whole
    /// screen. The brief's version recomputed the interactive path and
    /// reordered the window on *every* such event for as long as the island
    /// was visible — wasted CPU on every pixel of cursor travel, and a
    /// standing risk of visible flicker from reordering the window that
    /// often. Gating on the hover boolean actually changing makes the common
    /// case (moving around inside, or outside, the region) a single cheap
    /// `CGRect.contains` check with no further work.
    private func updateHover() {
        guard let screen = NSScreen.builtIn else { return }
        let mouse = NSEvent.mouseLocation
        let parameters = controller.parameters

        // Island hit region in global screen coordinates.
        let region = CGRect(
            x: screen.frame.midX - parameters.width / 2 - 4,
            y: screen.frame.maxY - parameters.height - 4,
            width: parameters.width + 8,
            height: parameters.height + 4
        )

        let hovered = region.contains(mouse)
        guard hovered != controller.isHovered else { return }
        controller.setHovered(hovered)
        syncWindowToVisibility()
    }
}
