import SwiftUI

/// The open card for a match an iPhone Live Activity is running
/// (2026-10-01). Hovering hands the whole pair down from the ears into
/// this card — the crests fly, the ears empty — the way the now-playing
/// artwork hands off to the media panel. So the card carries everything:
/// each side's crest, name and figure, with the period and the clock
/// between them, and the clock keeps time because the activity's own
/// card is read every second.
struct ScorePanelView: View {
    let score: NotchController.ActivityDisplay.Score
    let homeCrest: NSImage?
    let awayCrest: NSImage?
    let contentColor: Color
    let crestNamespace: Namespace.ID

    var body: some View {
        VStack(spacing: 8) {
            if let title = score.title {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(contentColor.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            HStack(alignment: .top, spacing: 8) {
                side(score.home, crest: homeCrest, geometryID: NotchRootView.homeCrestGeometryID, crestLeading: true)
                clock
                side(score.away, crest: awayCrest, geometryID: NotchRootView.awayCrestGeometryID, crestLeading: false)
            }
        }
        .padding(.horizontal, 18)
    }

    /// A crest over its name, the figure beside it — crest outward, as in
    /// the ear it came from.
    private func side(_ team: NotchController.ActivityDisplay.Score.Side, crest: NSImage?,
                      geometryID: String, crestLeading: Bool) -> some View {
        let badge = VStack(spacing: 5) {
            Group {
                if let crest {
                    Image(nsImage: crest).resizable().interpolation(.high)
                } else {
                    Circle().fill(contentColor.opacity(0.18))
                }
            }
            .frame(width: 32, height: 32)
            .matchedGeometryEffect(id: geometryID, in: crestNamespace)
            Text(team.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(contentColor.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 76)
        }
        let figure = Text(team.value)
            .font(.system(size: 26, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(contentColor)
            .contentTransition(.numericText())
        return HStack(spacing: 7) {
            if crestLeading { badge; figure } else { figure; badge }
        }
        .frame(maxWidth: .infinity, alignment: crestLeading ? .leading : .trailing)
    }

    /// The period over the running clock, under the hole.
    @ViewBuilder private var clock: some View {
        VStack(spacing: 1) {
            if let status = score.status {
                Text(status)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(contentColor.opacity(0.55))
                    .lineLimit(1)
            }
            if let clock = score.clock {
                Text(clock)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(contentColor.opacity(0.85))
                    .contentTransition(.numericText())
            }
        }
        .fixedSize()
        .padding(.top, 6)
    }
}
