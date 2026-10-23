import SwiftUI

/// A running countdown's ring (2026-09-29): emptying clockwise from the top,
/// the Dynamic Island's own timer glyph. The leading ear draws it at 14 pt,
/// the tab at about 20.
struct TimerRing: View {
    let fill: Double
    let color: Color
    var reduceMotion: Bool = false
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: fill)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Ticks arrive every quarter second; ease between them
                // so the ring drains, not steps.
                .animation(reduceMotion ? nil : .linear(duration: 0.25), value: fill)
        }
        .frame(width: size, height: size)
    }
}

/// An item's short form in the tab (2026-10-23): about 20 pt, no text, the
/// same drawings the leading ear uses.
struct TabGlyph: View {
    let display: NotchController.ActivityDisplay
    let controller: NotchController
    var contentColor: Color = .white
    var tintColor: (NotchController.ActivityDisplay.Tint?) -> Color? = { _ in nil }

    var body: some View {
        glyph
            .frame(width: 20, height: 20)
    }

    @ViewBuilder private var glyph: some View {
        switch display.id {
        case NotchController.callActivityID:
            call
        case NotchController.agentWaitingActivityID:
            AgentGlyph(color: AgentColors.waiting, turning: false, count: display.badge,
                       reduceMotion: controller.reduceMotion, size: 15)
        case NotchController.agentRunActivityID, NotchController.agentActivityID:
            AgentGlyph(color: AgentColors.orange, turning: display.id == NotchController.agentRunActivityID,
                       count: display.badge, reduceMotion: controller.reduceMotion, size: 15)
        case NotchController.timerActivityID:
            if let fill = display.barFill {
                TimerRing(fill: fill, color: tintColor(display.tint) ?? contentColor,
                          reduceMotion: controller.reduceMotion, size: 18)
            } else {
                symbol(display.symbolName ?? "stopwatch")
            }
        case NotchController.githubRunActivityID:
            if let segments = display.segments, !segments.isEmpty {
                CheckRing(segments: segments, reduceMotion: controller.reduceMotion)
            } else {
                GitHubRunRing(color: tintColor(display.tint) ?? contentColor, count: display.badge,
                              reduceMotion: controller.reduceMotion)
            }
        case NotchController.liveActivityID:
            if let crest = controller.tabCrestImage {
                Image(nsImage: crest)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())
            } else {
                symbol("iphone")
            }
        case NotchController.mediaActivityID:
            SpinningArtwork(isPlaying: controller.media?.isPlaying ?? false, reduceMotion: controller.reduceMotion) {
                Group {
                    if let image = controller.mediaArtworkImage {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        Circle().fill(contentColor.opacity(0.25))
                    }
                }
                .frame(width: 20, height: 20)
            }
        default:
            symbol(display.symbolName ?? "circle.fill")
        }
    }

    @ViewBuilder private var call: some View {
        let name = display.symbolName ?? "mic.fill"
        if name == "mic.slash.fill" {
            symbol(name, color: tintColor(.warning) ?? contentColor)
        } else if let icon = controller.tabArtworkImage {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(tintColor(.positive) ?? Color(nsColor: .systemGreen))
                        .frame(width: 6, height: 6)
                        .offset(x: 1, y: 1)
                }
        } else {
            symbol("mic.fill", color: tintColor(.positive) ?? contentColor)
        }
    }

    private func symbol(_ name: String, color: Color? = nil) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(color ?? tintColor(display.tint) ?? contentColor)
    }
}
