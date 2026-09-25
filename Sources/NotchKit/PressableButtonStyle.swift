import SwiftUI

/// Press feedback for the island's controls, on press-DOWN rather than on
/// release — the moment feedback lags the finger, the feeling of directness
/// is gone. `configuration.isPressed` flips the instant AppKit delivers the
/// mouse-down, which is exactly the property that makes this feel alive.
///
/// Critically damped on purpose: overshoot belongs to momentum gestures (a
/// flick, a thrown card), not to a tap. A bouncing button reads as a toy.
struct PressableButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Reduced motion still gets feedback — a dim, not a shrink.
            // "Gentler equivalent", never "nothing".
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(
                reduceMotion
                    ? NotchAnimation.reduced
                    : .spring(response: 0.25, dampingFraction: 1.0),
                value: configuration.isPressed
            )
    }
}
