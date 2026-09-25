import CoreGraphics

/// Derives the notch rectangle from a display description.
///
/// Result is in **island space**: x measured from the screen's left edge,
/// `y = 0` at the screen's top edge, growing downward.
///
/// Returns `nil` whenever a notch cannot be established. Never guesses:
/// a wrong rect would put the island over live pixels or over the camera.
public enum NotchGeometry {
    public static func notchRect(for screen: some ScreenDescribing) -> CGRect? {
        guard screen.isBuiltIn else { return nil }

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
}
