import SwiftUI

/// Claude's orange, `#D97757` (2026-10-23).
enum AgentColors {
    static var orange: Color { Color(red: 0.851, green: 0.467, blue: 0.341) }
    static var waiting: Color { Color(nsColor: .systemYellow) }
    static var done: Color { Color(nsColor: .systemGreen) }
    static var failed: Color { Color(nsColor: .systemRed) }
}

/// The agents' leading glyph (2026-10-23): an asterisk, turning once every
/// 2.4 s while one works (still under Reduce Motion), and the count of
/// sessions it stands for when more than one, at its bottom trailing corner.
struct AgentGlyph: View {
    let color: Color
    let turning: Bool
    let count: Int?
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            if turning, !reduceMotion {
                TimelineView(.animation) { context in
                    let turn = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 2.4) / 2.4
                    asterisk.rotationEffect(.degrees(turn * 360))
                }
            } else {
                asterisk
            }
        }
        .frame(width: 14, height: 14)
        .overlay(alignment: .bottomTrailing) {
            if let count, count > 1 {
                Text("\(count)")
                    .font(.system(size: 8, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .offset(x: 3, y: 3)
            }
        }
    }

    private var asterisk: some View {
        Image(systemName: "asterisk")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
    }
}

/// The Agents card of the open island (2026-10-23): a row per Claude Code
/// session, its host's icon, its name, and at the right what it is doing. A
/// click brings its window forward through `.open`; the controller drops
/// that on the lock screen, which keeps the card inert there.
struct AgentPanelView: View {
    let data: AgentPanelData
    let contentColor: Color
    let reduceMotion: Bool
    let emit: (NotchIntent) -> Void

    static let maxRows = 6

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

    private var shown: [AgentPanelData.Row] { Array(data.rows.prefix(Self.maxRows)) }
    private var more: Int { max(0, data.rows.count - Self.maxRows) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            reveal(Text("AGENTS")
                .font(.system(size: 9.5, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(contentColor.opacity(0.5))
                .frame(height: 14), order: 0)
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
                reveal(button(row), order: 1 + index)
            }
            if more > 0 {
                reveal(Text("\(more) more")
                    .font(.system(size: 10.5))
                    .foregroundStyle(contentColor.opacity(0.5))
                    .padding(.leading, 22), order: 1 + shown.count)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.top, 6)
        .foregroundStyle(contentColor)
        .onAppear { revealed = true }
    }

    private func button(_ row: AgentPanelData.Row) -> some View {
        Button {
            emit(.open(row.url))
        } label: {
            label(row)
                .frame(height: 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(ListRowButtonStyle(reduceMotion: reduceMotion))
    }

    private func label(_ row: AgentPanelData.Row) -> some View {
        HStack(spacing: 6) {
            icon(row)
            Text(row.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(contentColor.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            mark(row.mark)
        }
    }

    private func icon(_ row: AgentPanelData.Row) -> some View {
        Group {
            if let image = row.icon.flatMap(NSImage.init(data:)) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                AgentGlyph(color: AgentColors.orange, turning: false, count: nil, reduceMotion: reduceMotion)
            }
        }
        .frame(width: 16, height: 16)
    }

    private func word(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private func mark(_ mark: AgentPanelData.Row.Mark) -> some View {
        switch mark {
        case .waiting(let detail):
            word(detail, AgentColors.waiting)
        case .working(let since):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                word(GitHubPanelView.clock(context.date.timeIntervalSince(since)), AgentColors.orange)
            }
        case .done(let at):
            TimelineView(.periodic(from: .now, by: 30)) { context in
                word(Self.doneText(at, now: context.date), AgentColors.done)
            }
        case .failed(let reason):
            word(reason, AgentColors.failed)
        case .idle:
            word("Idle", contentColor.opacity(0.5))
        }
    }

    /// "Done just now" under a minute, else "Done 2 min. ago".
    static func doneText(_ at: Date, now: Date) -> String {
        if now.timeIntervalSince(at) < 60 { return "Done just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .numeric
        return "Done " + formatter.localizedString(for: at, relativeTo: now)
    }
}
