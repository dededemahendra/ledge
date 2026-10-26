import SwiftUI

/// Claude's orange, `#D97757` (2026-10-23).
enum AgentColors {
    static var orange: Color { Color(red: 0.851, green: 0.467, blue: 0.341) }
    static var waiting: Color { Color(nsColor: .systemYellow) }
    static var done: Color { Color(nsColor: .systemGreen) }
    static var failed: Color { Color(nsColor: .systemRed) }
}

/// The agents' leading glyph (2026-10-23): Claude's mark (an asterisk until
/// 2026-10-26, user's call: "claude real logo"), held still (the asterisk
/// turned while one worked; the user's call the same day: "dont rotate the
/// claude logo"), and the count of sessions it stands for when more than
/// one, at its bottom trailing corner.
struct AgentGlyph: View {
    let color: Color
    let count: Int?
    /// 13 pt in the ears; the round tab draws it a touch larger (2026-10-23).
    var size: CGFloat = 13

    var body: some View {
        ClaudeMark()
            .fill(color)
            .frame(width: size, height: size)
            .frame(width: size + 1, height: size + 1)
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
}

/// The Agents card of the open island (2026-10-23, the user's pick of
/// "hero plus rows"): the session most worth a look as a card (needs you,
/// failed, working), then the others as rows. A click brings its window
/// forward through `.open`; the controller drops that on the lock screen,
/// which keeps the card inert there. Follows `GitHubPanelView`.
struct AgentPanelView: View {
    let data: AgentPanelData
    let contentColor: Color
    let reduceMotion: Bool
    let emit: (NotchIntent) -> Void

    /// Rows under a hero, and without one.
    static let maxRowsWithHero = 3
    static let maxRowsWithoutHero = 6

    /// About 45 % of the row, so a long name leaves room for what it is doing.
    private static let nameMaxWidth: CGFloat = 138

    /// The name's own width, held to `nameMaxWidth`.
    private static func nameWidth(_ name: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let width = (name as NSString).size(withAttributes: [.font: font]).width
        return min(ceil(width) + 1, nameMaxWidth)
    }

    private static let ageFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .numeric
        return formatter
    }()

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

    private var rowHeight: CGFloat { data.hero == nil ? 20 : 19 }
    private var limit: Int { data.hero == nil ? Self.maxRowsWithoutHero : Self.maxRowsWithHero }
    private var shown: [AgentPanelData.Row] { Array(data.rows.prefix(limit)) }
    private var more: Int { max(0, data.rows.count - limit) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let hero = data.hero {
                reveal(heroCard(hero), order: 0)
                if !data.rows.isEmpty {
                    reveal(Rectangle()
                        .fill(contentColor.opacity(0.12))
                        .frame(height: 0.5)
                        .padding(.top, 6)
                        .padding(.bottom, 3), order: 1)
                }
            } else {
                reveal(Text("AGENTS")
                    .font(.system(size: 9.5, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(contentColor.opacity(0.5))
                    .frame(height: 14), order: 0)
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
                reveal(button(row), order: 2 + index)
            }
            if more > 0 {
                reveal(Text("\(more) more")
                    .font(.system(size: 10.5))
                    .foregroundStyle(contentColor.opacity(0.5))
                    .padding(.leading, 20), order: 2 + shown.count)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.top, 6)
        .foregroundStyle(contentColor)
        .onAppear { revealed = true }
    }

    // MARK: - Hero

    private func heroCard(_ hero: AgentPanelData.Hero) -> some View {
        Button {
            emit(.open(hero.url))
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    heroGlyph(hero.kind)
                    Text(Self.tag(hero.kind))
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(accent(hero.kind))
                    if let icon = hero.icon.flatMap(NSImage.init(data:)) {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                    Spacer(minLength: 4)
                    if hero.kind != .failed, let since = hero.since {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(GitHubPanelView.clock(context.date.timeIntervalSince(since)))
                                .font(.system(size: 9.5, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(accent(hero.kind))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(contentColor.opacity(0.1)))
                        }
                    }
                }
                .frame(height: 16)
                Text(hero.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(contentColor)
                    .lineLimit(1)
                    .padding(.top, 2)
                Text(hero.detail)
                    .font(.system(size: 10, design: hero.isCommand ? .monospaced : .default))
                    .foregroundStyle(contentColor.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ListRowButtonStyle(reduceMotion: reduceMotion))
    }

    @ViewBuilder
    private func heroGlyph(_ kind: AgentPanelData.Hero.Kind) -> some View {
        switch kind {
        case .needsYou:
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AgentColors.waiting)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AgentColors.failed)
        case .working:
            AgentGlyph(color: AgentColors.orange, count: nil)
        }
    }

    private func accent(_ kind: AgentPanelData.Hero.Kind) -> Color {
        switch kind {
        case .needsYou: AgentColors.waiting
        case .failed: AgentColors.failed
        case .working: AgentColors.orange
        }
    }

    private static func tag(_ kind: AgentPanelData.Hero.Kind) -> String {
        switch kind {
        case .needsYou: "NEEDS YOU"
        case .failed: "FAILED"
        case .working: "WORKING"
        }
    }

    // MARK: - Rows

    private func button(_ row: AgentPanelData.Row) -> some View {
        Button {
            emit(.open(row.url))
        } label: {
            label(row)
                .frame(height: rowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(ListRowButtonStyle(reduceMotion: reduceMotion))
    }

    private func label(_ row: AgentPanelData.Row) -> some View {
        HStack(spacing: 6) {
            glyph(row.mark)
            Text(row.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(contentColor.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: Self.nameWidth(row.name), alignment: .leading)
                .layoutPriority(1)
            Text(middle(row.mark))
                .font(.system(size: 11))
                .foregroundStyle(middleColor(row.mark))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            right(row.mark)
        }
    }

    private func glyph(_ mark: AgentPanelData.Row.Mark) -> some View {
        Group {
            switch mark {
            case .waiting:
                Image(systemName: "hand.raised.fill").foregroundStyle(AgentColors.waiting)
            case .working:
                ClaudeMark().fill(AgentColors.orange).frame(width: 10, height: 10)
            case .done:
                Image(systemName: "checkmark").foregroundStyle(AgentColors.done)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AgentColors.failed)
            case .idle:
                Image(systemName: "moon.fill").foregroundStyle(contentColor.opacity(0.35))
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .frame(width: 14)
    }

    private func middle(_ mark: AgentPanelData.Row.Mark) -> String {
        switch mark {
        case .waiting(let text, _), .working(let text, _), .done(let text, _), .failed(let text, _): text
        case .idle: "Idle"
        }
    }

    private func middleColor(_ mark: AgentPanelData.Row.Mark) -> Color {
        if case .failed = mark { return AgentColors.failed }
        return contentColor.opacity(0.5)
    }

    @ViewBuilder
    private func right(_ mark: AgentPanelData.Row.Mark) -> some View {
        switch mark {
        case .waiting(_, let since):
            clock(since, AgentColors.waiting)
        case .working(_, let since):
            clock(since, AgentColors.orange)
        case .done(_, let at), .failed(_, let at):
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(Self.age(at, now: context.date))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(contentColor.opacity(0.5))
                    .lineLimit(1)
                    .fixedSize()
            }
        case .idle:
            EmptyView()
        }
    }

    private func clock(_ since: Date, _ color: Color) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(GitHubPanelView.clock(context.date.timeIntervalSince(since)))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// "just now" under a minute, else "2 min. ago".
    static func age(_ at: Date, now: Date) -> String {
        if now.timeIntervalSince(at) < 60 { return "just now" }
        return ageFormatter.localizedString(for: at, relativeTo: now)
    }
}
