import AppKit
import ScreenCaptureKit

/// Pixels and their size in points — the crests cut from the card, the
/// one thing about a Live Activity that is not text.
public struct PillImage: Sendable, Equatable {
    public let png: Data
    public let size: CGSize

    public init(png: Data, size: CGSize) {
        self.png = png
        self.size = size
    }
}

public enum CaptureGeometry {
    /// The backing scale of the screen under a point given in top-left
    /// screen coordinates; AppKit's screens are bottom-left, so the point
    /// is flipped through the primary screen's height first.
    @MainActor
    public static func scale(at point: CGPoint) -> CGFloat {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let flipped = CGPoint(x: point.x, y: primaryHeight - point.y)
        return NSScreen.screens.first(where: { $0.frame.contains(flipped) })?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2
    }
}
