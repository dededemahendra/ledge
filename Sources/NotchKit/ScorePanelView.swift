import SwiftUI

/// The open card for a match an iPhone Live Activity is running
/// (2026-10-01): the island's own drawing of what the system card says,
/// not a picture of it — crests, names, the figures, and between them
/// the period and the clock, which keeps time because the card is read
/// every second.
struct ScorePanelView: View {
    let score: NotchController.ActivityDisplay.Score
    let homeCrest: NSImage?
    let awayCrest: NSImage?
    let contentColor: Color

    var body: some View {
        VStack(spacing: 10) {
            if let title = score.title {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(contentColor.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            HStack(spacing: 0) {
                side(score.home, crest: homeCrest, crestLeading: true)
                Spacer(minLength: 8)
                middle
                Spacer(minLength: 8)
                side(score.away, crest: awayCrest, crestLeading: false)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
    }

    /// A crest over its name, with the figure beside it — the card's own
    /// arrangement, at the island's weight.
    private func side(_ team: NotchController.ActivityDisplay.Score.Side, crest: NSImage?, crestLeading: Bool) -> some View {
        let badge = VStack(spacing: 4) {
            Group {
                if let crest {
                    Image(nsImage: crest).resizable().interpolation(.high)
                } else {
                    Circle().fill(contentColor.opacity(0.18))
                }
            }
            .frame(width: 34, height: 34)
            Text(team.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(contentColor.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 74)
        }
        let figure = Text(team.value)
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(contentColor)
            .contentTransition(.numericText())
            .offset(y: -6)
        return HStack(spacing: 8) {
            if crestLeading { badge; figure } else { figure; badge }
        }
    }

    /// The period and the clock, stacked under the hole.
    @ViewBuilder private var middle: some View {
        VStack(spacing: 3) {
            if let status = score.status {
                Text(status)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(contentColor.opacity(0.7))
                    .lineLimit(1)
            }
            if let clock = score.clock {
                Text(clock)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(contentColor.opacity(0.85))
                    .contentTransition(.numericText())
            }
        }
        .frame(minWidth: 44)
        .offset(y: -4)
    }
}
