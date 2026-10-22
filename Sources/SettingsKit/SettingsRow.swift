import SwiftUI
import AppKit

/// A white symbol on a rounded, coloured square: System Settings' own
/// icon, for the sidebar and for every row (2026-10-22).
public struct SettingsTile: View {
    let symbol: String
    let color: Color
    let size: CGFloat

    public init(symbol: String, color: Color, size: CGFloat = 24) {
        self.symbol = symbol
        self.color = color
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size / 4, style: .continuous)
                .fill(color.gradient)
            Image(systemName: symbol)
                .font(.system(size: size / 2, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// One option (2026-10-22): its icon, its name, a line on what it does,
/// and its control. Pointing at it shows its scene in the pane's strip.
public struct SettingsRow<Icon: View, Control: View>: View {
    let title: String
    let detail: String?
    let scene: PreviewScene?
    let director: PreviewDirector?
    let icon: Icon
    let control: Control

    public init(_ title: String, detail: String? = nil, scene: PreviewScene? = nil, director: PreviewDirector? = nil,
                @ViewBuilder icon: () -> Icon, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.scene = scene
        self.director = director
        self.icon = icon()
        self.control = control()
    }

    public var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { inside in
            guard let scene, let director else { return }
            if inside { director.point(at: scene) } else { director.leave(scene) }
        }
    }
}

extension SettingsRow where Icon == SettingsTile {
    public init(_ title: String, detail: String? = nil, symbol: String, color: Color,
                scene: PreviewScene? = nil, director: PreviewDirector? = nil,
                @ViewBuilder control: () -> Control) {
        self.init(title, detail: detail, scene: scene, director: director,
                  icon: { SettingsTile(symbol: symbol, color: color, size: 22) }, control: control)
    }
}

/// Allowed or Not allowed, for a permission row (2026-10-22).
public struct StatusPill: View {
    let isOn: Bool
    let onText: String
    let offText: String

    public init(isOn: Bool, on: String = "Allowed", off: String = "Not allowed") {
        self.isOn = isOn
        onText = on
        offText = off
    }

    public var body: some View {
        let color = Color(nsColor: isOn ? .systemGreen : .systemOrange)
        Text(isOn ? onText : offText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
    }
}
