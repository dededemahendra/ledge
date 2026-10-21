import AppKit
import SwiftUI
import CoreGraphics

/// The island's host: a borderless, non-activating panel of fixed oversized
/// size, anchored to the top centre of the island's host display: the
/// notched built-in one, or the main display with a virtual notch.
///
/// The window never animates or resizes — the island animates inside it.
@MainActor
public final class NotchWindow: NSPanel {
    private static var normalLevel: NSWindow.Level {
        NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    }

    /// Exposed so hit testing can be asserted directly in tests.
    public let hostingView: NotchHostingView<AnyView>

    public var interactivePath: CGPath? {
        get { hostingView.interactivePath }
        set { hostingView.interactivePath = newValue }
    }

    public init(screen: NSScreen, content: AnyView = AnyView(EmptyView())) {
        hostingView = NotchHostingView(rootView: content)

        super.init(
            contentRect: CGRect(origin: .zero, size: NotchMetrics.canvasSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isFloatingPanel = true      // NB: also resets level to .floating as a side effect
        becomesKeyOnlyIfNeeded = true
        // Mouse-transparent until the cursor is actually on the island — see
        // `setAcceptsMouse`. This used to be `false` ("hit testing decides"),
        // and that was a bug (2026-09-28): a window that opts into mouse
        // events RECEIVES every click inside its frame; `hitTest` returning
        // nil merely discards the click, it does not hand it to the window
        // underneath. So for as long as the island was visible, the whole
        // 640×320 canvas — the menu bar around the notch and ~290pt of
        // whatever sits below it — was dead to clicks, and a click there
        // never reached the click-outside monitor either (global monitors
        // don't see events delivered to our own windows), so a pinned panel
        // could not be dismissed from there. Reported as "click the notch,
        // then can't click anything".
        ignoresMouseEvents = true
        level = Self.normalLevel      // must be set after isFloatingPanel, which clobbers it
        contentView = hostingView

        reposition(for: screen)
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    /// Swapping content invalidates the interactive region for exactly the reason
    /// `reposition(for:)` does: a path computed for the previous content would go
    /// on claiming clicks over what is now empty canvas. The caller sets a fresh
    /// shape immediately afterwards.
    public func setContent(_ content: AnyView) {
        interactivePath = nil
        hostingView.rootView = content
    }

    /// Anchors the canvas to the top centre of `screen`.
    /// Always clears `interactivePath`: a path computed for the previous
    /// geometry would claim clicks in the wrong place.
    public func reposition(for screen: NSScreen) {
        interactivePath = nil
        let size = NotchMetrics.canvasSize
        let origin = CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height
        )
        setFrame(CGRect(origin: origin, size: size), display: false)
    }

    /// Replaces the interactive region with a shape's path.
    /// `rect` is in the hosting view's coordinate space.
    ///
    /// SwiftUI shapes are drawn with y growing downward; AppKit views with y
    /// growing upward. Flip so the island hangs from the top of the canvas.
    public func setInteractiveShape(_ shape: some Shape, in rect: CGRect) {
        let base = shape.path(in: rect).cgPath
        var flip = CGAffineTransform(translationX: 0, y: rect.height)
            .scaledBy(x: 1, y: -1)
        interactivePath = base.copy(using: &flip) ?? base
    }

    /// Whether the window takes mouse events at all. `NotchPresenter` turns
    /// this on only while the cursor is inside the island's (forgiveness-
    /// widened) path and off the moment it leaves, so a click anywhere else
    /// on the canvas falls straight through to the window beneath, exactly
    /// as if this window did not exist. `hitTest` stays as the second line
    /// of defence for the band between the forgiving path and the exact
    /// one. Two mechanisms, one truth: both derive from the same
    /// `forgivingParameters()` path.
    public func setAcceptsMouse(_ accepts: Bool) {
        ignoresMouseEvents = !accepts
    }

    public var acceptsMouse: Bool { !ignoresMouseEvents }
}
