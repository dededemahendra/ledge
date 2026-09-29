import SwiftUI

/// Press feedback for the island's controls, on press-DOWN rather than on
/// release — the moment feedback lags the finger, the feeling of directness
/// is gone. `configuration.isPressed` flips the instant AppKit delivers the
/// mouse-down, which is exactly the property that makes this feel alive.
///
/// Critically damped on purpose: overshoot belongs to momentum gestures (a
/// flick, a thrown card), not to a tap. A bouncing button reads as a toy.
///
/// A light dip, not a squash (2026-09-29, user's call: the control
/// interactions were "too much"): 7% smaller and a fifth dimmer, settling
/// in a fifth of a second. The 12%/35% version read as the button
/// flinching.
struct PressableButtonStyle: ButtonStyle {
    static let pressedScale: CGFloat = 0.93
    static let pressedOpacity: Double = 0.8

    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Reduced motion still gets feedback — a dim, not a shrink.
            // "Gentler equivalent", never "nothing".
            .scaleEffect(configuration.isPressed && !reduceMotion ? Self.pressedScale : 1)
            .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
            .animation(
                reduceMotion
                    ? NotchAnimation.reduced
                    : .spring(response: 0.2, dampingFraction: 1.0),
                value: configuration.isPressed
            )
    }
}
