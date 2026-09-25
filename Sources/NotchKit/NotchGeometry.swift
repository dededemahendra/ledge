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

        let width = trailingEdge - leadingEdge
        guard width > 0 else { return nil }

        return CGRect(x: leadingEdge, y: 0, width: width, height: height)
    }
}
