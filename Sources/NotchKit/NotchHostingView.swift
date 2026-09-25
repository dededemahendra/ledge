import AppKit
import SwiftUI

/// Hosting view that claims only the points inside `interactivePath`.
///
/// The window is a large transparent canvas; without this, it would swallow
/// every click across the top of the screen. Returning `nil` lets the event
/// fall through to whatever is underneath.
@MainActor
public final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// Interactive region in this view's own coordinate space.
    /// `nil` means claim nothing.
    public var interactivePath: CGPath?

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard let interactivePath else { return nil }
        // `point` arrives already in this view's own frame-relative space: the
        // window is borderless and this view fills it exactly, so that space
        // coincides with the (non-flipped) superview's coordinates — the same
        // bottom-left-origin convention `setInteractiveShape` flips into.
        // Deliberately *not* routed through `convert(_:from:)`: `NSHostingView`
        // reports `isFlipped == true`, so AppKit's own coordinate conversion
        // would silently apply a second, unwanted flip on top of that one.
        guard interactivePath.contains(point) else { return nil }
        return super.hitTest(point)
    }

    public override var allowsVibrancy: Bool { false }
}
