import AppKit
import CoreGraphics

/// The subset of a display Ledge needs. Abstracted so geometry is testable
/// without a real `NSScreen`.
public protocol ScreenDescribing: Sendable {
    var frame: CGRect { get }
    var safeAreaTopInset: CGFloat { get }
    /// Right edge of the menu bar area to the left of the notch.
    var auxiliaryTopLeftMaxX: CGFloat? { get }
    /// Left edge of the menu bar area to the right of the notch.
    var auxiliaryTopRightMinX: CGFloat? { get }
    var isBuiltIn: Bool { get }
}

/// Snapshot of an `NSScreen`, taken on the main actor and safe to pass around.
public struct ScreenSnapshot: ScreenDescribing {
    public let frame: CGRect
    public let safeAreaTopInset: CGFloat
    public let auxiliaryTopLeftMaxX: CGFloat?
    public let auxiliaryTopRightMinX: CGFloat?
    public let isBuiltIn: Bool

    public init(
        frame: CGRect,
        safeAreaTopInset: CGFloat,
        auxiliaryTopLeftMaxX: CGFloat?,
        auxiliaryTopRightMinX: CGFloat?,
        isBuiltIn: Bool
    ) {
        self.frame = frame
        self.safeAreaTopInset = safeAreaTopInset
        self.auxiliaryTopLeftMaxX = auxiliaryTopLeftMaxX
        self.auxiliaryTopRightMinX = auxiliaryTopRightMinX
        self.isBuiltIn = isBuiltIn
    }
}

@MainActor
extension NSScreen {
    /// The display carrying the notch, or `nil` in clamshell mode.
    /// Review Focus 3: `NSScreen.screens` omits the built-in display when the lid is shut.
    public static var builtIn: NSScreen? {
        screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }
    }

    public func snapshot() -> ScreenSnapshot {
        ScreenSnapshot(
            frame: frame,
            safeAreaTopInset: safeAreaInsets.top,
            auxiliaryTopLeftMaxX: auxiliaryTopLeftArea?.maxX,
            auxiliaryTopRightMinX: auxiliaryTopRightArea?.minX,
            isBuiltIn: safeAreaInsets.top > 0 && auxiliaryTopLeftArea != nil
        )
    }
}
