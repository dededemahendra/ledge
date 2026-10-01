import SwiftUI

/// The open card for a match an iPhone Live Activity is running
/// (2026-10-01). The ears above already carry each side's crest and
/// figure, so this says what they cannot: who is playing, which period,
/// and the clock — which keeps time, because the card is read every
/// second. Nothing here repeats the ears (user's call: "double
/// information").
struct ScorePanelView: View {
    let score: NotchController.ActivityDisplay.Score
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
            HStack(alignment: .center, spacing: 10) {
                name(score.home.name, alignment: .leading)
                clock
                name(score.away.name, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20)
    }

    private func name(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(contentColor.opacity(0.9))
            .lineLimit(2)
            .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
            .frame(maxWidth: .infinity, alignment: alignment)
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
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(contentColor)
                    .contentTransition(.numericText())
            }
        }
        .fixedSize()
    }
}
