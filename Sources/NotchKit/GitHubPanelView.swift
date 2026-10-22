import SwiftUI

/// The GitHub panel of the open island (2026-10-22): a heading, then up to
/// four rows (the user's runs going now, their PRs, PRs waiting for their
/// review), each with its mark, its title, and its repo dim at the end. A
/// click opens it on GitHub; the last row says how many more there are.
/// The reveal and the rows follow `CalendarPanelView`.
struct GitHubPanelView: View {
    let data: GitHubPanelData
    let contentColor: Color
    let reduceMotion: Bool
    let emit: (NotchIntent) -> Void

    /// Spelled-out `State`, as elsewhere here.
    private var _revealed: State<Bool> = State(initialValue: false)
    private var revealed: Bool {
        get { _revealed.wrappedValue }
        nonmutating set { _revealed.wrappedValue = newValue }
    }

    private func reveal<V: View>(_ view: V, order: Int) -> some View {
        view
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 3)
            .animation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1.0).delay(Double(order) * 0.022),
                value: revealed
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            reveal(Text("GITHUB")
                .font(.system(size: 9.5, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(contentColor.opacity(0.5))
                .frame(height: 14), order: 0)
            ForEach(Array(data.rows.enumerated()), id: \.element.id) { index, row in
                reveal(button(row.url) { label(row) }, order: 1 + index)
            }
            if data.more > 0 {
                reveal(button(data.moreURL) {
                    Text("\(data.more) more on GitHub")
                        .font(.system(size: 10.5))
                        .foregroundStyle(contentColor.opacity(0.5))
                        .padding(.leading, 17)
                }, order: 1 + data.rows.count)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.top, 8)
        .foregroundStyle(contentColor)
        .onAppear { revealed = true }
    }

    private func button<Label: View>(_ url: URL, @ViewBuilder label: () -> Label) -> some View {
        Button {
            emit(.open(url))
        } label: {
            label()
                .frame(height: 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(ListRowButtonStyle(reduceMotion: reduceMotion))
    }

    private func label(_ row: GitHubPanelData.Row) -> some View {
        HStack(spacing: 6) {
            mark(row.mark)
            Text(row.title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(contentColor.opacity(0.92))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(row.repo)
                .font(.system(size: 10.5))
                .foregroundStyle(contentColor.opacity(0.5))
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// A check dot in GitHub's own colours, or an eye for a review
    /// request, in an 11 pt column so the titles line up.
    private func mark(_ mark: GitHubPanelData.Row.Mark) -> some View {
        Group {
            switch mark {
            case .review:
                Image(systemName: "eye.fill")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .systemBlue))
            case .running:
                Circle().fill(Color(nsColor: .systemYellow)).frame(width: 7, height: 7)
            case .passed:
                Circle().fill(Color(nsColor: .systemGreen)).frame(width: 7, height: 7)
            case .failed:
                Circle().fill(Color(nsColor: .systemRed)).frame(width: 7, height: 7)
            case .none:
                Circle().fill(contentColor.opacity(0.3)).frame(width: 7, height: 7)
            }
        }
        .frame(width: 11)
    }
}

/// The running item's glyph (2026-10-22): an arc turning once every 1.2 s,
/// the island's "working" idiom, and the count of what runs when more than
/// one does. Still under Reduce Motion.
struct GitHubRunRing: View {
    let color: Color
    let count: Int?
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.25), lineWidth: 2)
            TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
                let turn = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.2) / 1.2
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(turn * 360 - 90))
            }
            if let count, count > 1 {
                Text("\(count)")
                    .font(.system(size: 8, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .frame(width: 14, height: 14)
    }
}
