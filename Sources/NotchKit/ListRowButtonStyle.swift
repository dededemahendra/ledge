import SwiftUI

/// Press feedback for a full-width list row: a dip in opacity and the
/// slightest settle, on mouse-down. Not `PressableButtonStyle`'s 0.88
/// shrink — a wide row that shrinks reads as broken, not pressed.
struct ListRowButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(
                reduceMotion ? NotchAnimation.reduced : .spring(response: 0.2, dampingFraction: 1.0),
                value: configuration.isPressed
            )
    }
}
