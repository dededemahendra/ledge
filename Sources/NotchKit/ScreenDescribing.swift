import AppKit
import CoreGraphics

/// The subset of a display Ledge needs. Abstracted so geometry is testable
/// without a real `NSScreen`.
public protocol ScreenDescribing: Sendable {
    var frame: CGRect { get }
    var safeAreaTopInset: CGFloat { get }
    /// Right edge of the menu bar area to the left of the notch.
    ///
    /// Reported in **global desktop coordinates**, the same space as `frame` —
    /// Apple documents `NSScreen.auxiliaryTopLeftArea` as "specified in global
    /// screen coordinates". `NotchGeometry` subtracts `frame.minX` to convert.
    var auxiliaryTopLeftMaxX: CGFloat? { get }
    /// Left edge of the menu bar area to the right of the notch.
    /// Also in global desktop coordinates — see above.
    var auxiliaryTopRightMinX: CGFloat? { get }
    /// Whether this display reports a notch-shaped safe area (a non-zero top
    /// safe area alongside the menu-bar auxiliary areas either side of it) —
    /// NOT simply whether the display is the Mac's built-in panel. A genuine
    /// built-in display with no notch (no camera housing cut into the menu
    /// bar) reports `false` here just like an external display does.
    var hasNotch: Bool { get }
}

/// Snapshot of an `NSScreen`, taken on the main actor and safe to pass around.
public struct ScreenSnapshot: ScreenDescribing {
    public let frame: CGRect
    public let safeAreaTopInset: CGFloat
    public let auxiliaryTopLeftMaxX: CGFloat?
    public let auxiliaryTopRightMinX: CGFloat?
    public let hasNotch: Bool

    public init(
        frame: CGRect,
        safeAreaTopInset: CGFloat,
        auxiliaryTopLeftMaxX: CGFloat?,
        auxiliaryTopRightMinX: CGFloat?,
        hasNotch: Bool
    ) {
        self.frame = frame
        self.safeAreaTopInset = safeAreaTopInset
        self.auxiliaryTopLeftMaxX = auxiliaryTopLeftMaxX
        self.auxiliaryTopRightMinX = auxiliaryTopRightMinX
        self.hasNotch = hasNotch
    }
}

@MainActor
extension NSScreen {
    /// The notch-detection predicate behind `snapshot().hasNotch`.
    private var reportsNotchShapedSafeArea: Bool {
        safeAreaInsets.top > 0 && auxiliaryTopLeftArea != nil
    }

    /// The screen the island lives on and where on it — see
    /// `NotchGeometry.placement(among:)`. `nil` only with no screens.
    /// Review Focus 3: `NSScreen.screens` omits the built-in display when
    /// the lid is shut, so a closed MacBook gets the virtual notch.
    public static var islandHost: (screen: NSScreen, placement: IslandPlacement)? {
        let screens = screens
        guard let placement = NotchGeometry.placement(among: screens.map { $0.snapshot() }) else { return nil }
        return (screens[placement.screenIndex], placement)
    }

    public func snapshot() -> ScreenSnapshot {
        ScreenSnapshot(
            frame: frame,
            safeAreaTopInset: safeAreaInsets.top,
            auxiliaryTopLeftMaxX: auxiliaryTopLeftArea?.maxX,
            auxiliaryTopRightMinX: auxiliaryTopRightArea?.minX,
            hasNotch: reportsNotchShapedSafeArea
        )
    }
}
