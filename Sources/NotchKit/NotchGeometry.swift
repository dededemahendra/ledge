import CoreGraphics

/// Derives the notch rectangle from a display description.
///
/// Result is in **island space**: x measured from the screen's left edge,
/// `y = 0` at the screen's top edge, growing downward.
///
/// `notchRect(for:)` returns `nil` whenever a notch cannot be established.
/// Never guesses: a wrong rect would put the island over live pixels or over
/// the camera. A screen without one gets `virtualNotchRect(for:)` instead,
/// chosen deliberately by `placement(among:)`, never as a guess at a real one.
public enum NotchGeometry {
    public static func notchRect(for screen: some ScreenDescribing) -> CGRect? {
        guard screen.hasNotch else { return nil }

        let height = screen.safeAreaTopInset
        guard height > 0 else { return nil }

        guard
            let leadingEdge = screen.auxiliaryTopLeftMaxX,
            let trailingEdge = screen.auxiliaryTopRightMinX
        else { return nil }

        // Width is a difference of two global values, so the desktop offset
        // cancels and it needs no adjustment.
        let width = trailingEdge - leadingEdge
        guard width > 0 else { return nil }

        // The auxiliary edges arrive in global desktop coordinates, so subtract
        // the screen's own origin to land in the screen-relative space this
        // function promises. A no-op on the primary display, where frame.minX is
        // 0; not a no-op for a built-in panel docked beside an external primary.
        return CGRect(x: leadingEdge - screen.frame.minX, y: 0, width: width, height: height)
    }

    /// The notch a screen without one gets instead (2026-10-21): the
    /// pill's middle, centred at the top edge. 44 pt wide, not the
    /// measured notch's 179, so the pill's ears sit close as on the
    /// iPhone; 32 pt tall, the measured notch's height, which every layout
    /// was built against. Same island space as `notchRect(for:)`.
    public static let virtualNotchSize = CGSize(width: 44, height: 32)

    public static func virtualNotchRect(for screen: some ScreenDescribing) -> CGRect {
        CGRect(
            x: (screen.frame.width - virtualNotchSize.width) / 2,
            y: 0,
            width: virtualNotchSize.width,
            height: virtualNotchSize.height
        )
    }

    /// Where the island lives, given every connected screen: on the real
    /// notch if any screen has one, otherwise on a virtual notch on the
    /// first screen — the main display, the one carrying the menu bar.
    /// `nil` only with no screens at all.
    public static func placement<Screen: ScreenDescribing>(among screens: [Screen]) -> IslandPlacement? {
        for (index, screen) in screens.enumerated() {
            if let rect = notchRect(for: screen) {
                return IslandPlacement(screenIndex: index, notchRect: rect, isVirtual: false)
            }
        }
        guard let main = screens.first else { return nil }
        return IslandPlacement(screenIndex: 0, notchRect: virtualNotchRect(for: main), isVirtual: true)
    }
}

/// The screen the island lives on, by its index in the list it was chosen
/// from, and the notch it hangs from there.
public struct IslandPlacement: Sendable, Equatable {
    public let screenIndex: Int
    public let notchRect: CGRect
    /// No notch on that screen: `notchRect` is `NotchGeometry.virtualNotchRect`.
    public let isVirtual: Bool
}
