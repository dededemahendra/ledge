import SwiftUI

/// One transport control in Apple Music's idiom (2026-09-29, user's call:
/// "make the controls like Apple Music"): a glyph on a soft rounded
/// highlight that appears under the pointer, a FILLED highlight with a
/// dark glyph while the control is on (how Music marks shuffle and
/// repeat), a dimmed, disabled glyph when the source cannot do the thing.
/// Press feedback is `PressableButtonStyle`'s, on mouse-down.
struct MusicControlButton: View {
    enum Mode: Equatable {
        case idle, active, unavailable
    }

    let symbol: String
    let label: String
    let size: CGFloat
    let weight: Font.Weight
    let mode: Mode
    var width: CGFloat = 34
    let contentColor: Color
    let reduceMotion: Bool
    let action: () -> Void

    // Spelled-out `State`, like every other in this module (no macro plugin).
    private var _hovered: State<Bool> = State(initialValue: false)
    private var hovered: Bool {
        get { _hovered.wrappedValue }
        nonmutating set { _hovered.wrappedValue = newValue }
    }

    init(
        symbol: String, label: String, size: CGFloat, weight: Font.Weight = .semibold,
        mode: Mode = .idle, width: CGFloat = 34, contentColor: Color, reduceMotion: Bool,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.label = label
        self.size = size
        self.weight = weight
        self.mode = mode
        self.width = width
        self.contentColor = contentColor
        self.reduceMotion = reduceMotion
        self.action = action
    }

    var body: some View {
        let animation = NotchAnimation.textAnimation(reduceMotion: reduceMotion)
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(highlight)
                Image(systemName: symbol)
                    .font(.system(size: size, weight: weight))
                    .foregroundStyle(glyphColor)
                    .id(symbol)
                    .transition(.blurReplace)
            }
            .frame(width: width, height: 30)
            .contentShape(Rectangle())
            .animation(animation, value: symbol)
            .animation(animation, value: hovered)
            .animation(animation, value: mode)
        }
        .buttonStyle(PressableButtonStyle(reduceMotion: reduceMotion))
        .disabled(mode == .unavailable)
        .onHover { hovered = $0 }
        .accessibilityLabel(label)
        .accessibilityValue(mode == .active ? "on" : (mode == .unavailable ? "unavailable" : ""))
    }

    private var highlight: Color {
        switch mode {
        case .active:      return contentColor.opacity(0.92)
        case .idle:        return contentColor.opacity(hovered ? 0.12 : 0)
        case .unavailable: return .clear
        }
    }

    private var glyphColor: Color {
        switch mode {
        case .active:      return .black
        case .idle:        return contentColor.opacity(0.95)
        case .unavailable: return contentColor.opacity(0.3)
        }
    }
}
