import AppKit
import SwiftUI
import CoreGraphics

/// The island's host: a borderless, non-activating panel of fixed oversized
/// size, anchored to the top centre of the built-in display.
///
/// The window never animates or resizes — the island animates inside it.
@MainActor
public final class NotchWindow: NSPanel {
    private static var normalLevel: NSWindow.Level {
        NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    }

    private static var lockedLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
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
        ignoresMouseEvents = false      // hit testing decides, not a blanket flag
        level = Self.normalLevel      // must be set after isFloatingPanel, which clobbers it
        contentView = hostingView

        reposition(for: screen)
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public func setContent(_ content: AnyView) {
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

    public func setLocked(_ locked: Bool) {
        level = locked ? Self.lockedLevel : Self.normalLevel
    }
}
