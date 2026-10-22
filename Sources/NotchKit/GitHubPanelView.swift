import SwiftUI

/// GitHub's colours on the island (2026-10-22): the system's own.
enum GitHubColors {
    static var passed: Color { Color(nsColor: .systemGreen) }
    static var failed: Color { Color(nsColor: .systemRed) }
    static var running: Color { Color(nsColor: .systemYellow) }
    static var review: Color { Color(nsColor: .systemBlue) }

    static func segment(_ segment: IslandCheck) -> Color {
        switch segment {
        case .passed: passed
        case .failed: failed
        case .running: running
        }
    }
}

/// The GitHub panel of the open island (2026-10-22, the user's pick of
/// three): what is most worth watching as a card (checks running with a
/// bar of them, checks failed, a review waiting), then the rest as rows,
/// each with its status symbol, its title, and its repo dim at the end. A
/// click opens it on GitHub; the last line says how many more there are.
/// The reveal follows `CalendarPanelView`.
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

    /// Rows are a touch shorter under a card, so two and the "more" line fit.
    private var rowHeight: CGFloat { data.hero == nil ? 20 : 19 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let hero = data.hero {
                reveal(heroCard(hero), order: 0)
                if !data.rows.isEmpty || data.more > 0 {
                    reveal(Rectangle()
                        .fill(contentColor.opacity(0.12))
                        .frame(height: 0.5)
                        .padding(.top, 6)
                        .padding(.bottom, 3), order: 1)
                }
            } else {
                reveal(Text("GITHUB")
                    .font(.system(size: 9.5, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(contentColor.opacity(0.5))
                    .frame(height: 14), order: 0)
            }
            ForEach(Array(data.rows.enumerated()), id: \.element.id) { index, row in
                reveal(button(row.url) { label(row) }, order: 2 + index)
            }
            if data.more > 0 {
                reveal(button(data.moreURL) {
                    Text("\(data.more) more on GitHub")
                        .font(.system(size: 10.5))
                        .foregroundStyle(contentColor.opacity(0.5))
                        .padding(.leading, 19)
                }, order: 2 + data.rows.count)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.top, 6)
        .foregroundStyle(contentColor)
        .onAppear { revealed = true }
    }

    private func heroCard(_ hero: GitHubPanelData.Hero) -> some View {
        Button {
            emit(.open(hero.url))
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    if let avatar = hero.avatar.flatMap(NSImage.init(data:)) {
                        Image(nsImage: avatar)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .frame(width: 14, height: 14)
                            .clipShape(Circle())
                    }
                    Text(hero.tag.uppercased())
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(accent(hero.kind))
                    Spacer(minLength: 4)
                    if hero.kind == .running, let since = hero.since {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(Self.clock(context.date.timeIntervalSince(since)))
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
                Text(hero.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(contentColor)
                    .lineLimit(1)
                    .padding(.top, 2)
                Text(hero.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(contentColor.opacity(0.55))
                    .lineLimit(1)
                    .padding(.top, 1)
                if !hero.segments.isEmpty {
                    SegmentBar(segments: hero.segments, reduceMotion: reduceMotion)
                        .padding(.top, 7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ListRowButtonStyle(reduceMotion: reduceMotion))
    }

    private func accent(_ kind: GitHubPanelData.Hero.Kind) -> Color {
        switch kind {
        case .running: GitHubColors.running
        case .failed: GitHubColors.failed
        case .review: GitHubColors.review
        }
    }

    /// "2:14" under an hour, "1:02" (hours:minutes) from an hour up, as the
    /// island's own clock reads.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 3600 { return String(format: "%d:%02d", total / 60, total % 60) }
        return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
    }

    private func button<Label: View>(_ url: URL, @ViewBuilder label: () -> Label) -> some View {
        Button {
            emit(.open(url))
        } label: {
            label()
                .frame(height: rowHeight)
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

    /// The row's status as a symbol in GitHub's colours, in a 13 pt column
    /// so the titles line up.
    private func mark(_ mark: GitHubPanelData.Row.Mark) -> some View {
        Group {
            switch mark {
            case .review:
                Image(systemName: "eye.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(GitHubColors.review)
            case .running:
                Image(systemName: "circle.dotted")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GitHubColors.running)
            case .passed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(GitHubColors.passed)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(GitHubColors.failed)
            case .none:
                Image(systemName: "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(contentColor.opacity(0.35))
            }
        }
        .frame(width: 13)
    }
}

/// The hero's checks (2026-10-22): a segment each, finished first, the ones
/// still going faint and breathing; past twelve, one bar filling.
struct SegmentBar: View {
    let segments: [IslandCheck]
    let reduceMotion: Bool

    private var _breathing: State<Bool> = State(initialValue: false)
    private var breathing: Bool {
        get { _breathing.wrappedValue }
        nonmutating set { _breathing.wrappedValue = newValue }
    }

    var body: some View {
        Group {
            if segments.count <= CheckRing.maxSegments {
                HStack(spacing: 3) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        Capsule()
                            .fill(GitHubColors.segment(segment))
                            .opacity(segment == .running ? (breathing ? 0.7 : 0.35) : 1)
                    }
                }
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(GitHubColors.running.opacity(0.25))
                        Capsule()
                            .fill(segments.contains(.failed) ? GitHubColors.failed : GitHubColors.running)
                            .frame(width: proxy.size.width * CheckRing.doneFraction(segments))
                    }
                }
            }
        }
        .frame(height: 4)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}

/// The running item's ring (2026-10-22, the user's pick): the hero's bar bent
/// into a circle, a segment per check from the top clockwise, finished first.
/// Past twelve the segments would be specks, so it fills smoothly instead,
/// red once one has failed.
struct CheckRing: View {
    static let maxSegments = 12

    let segments: [IslandCheck]
    let reduceMotion: Bool

    private var _breathing: State<Bool> = State(initialValue: false)
    private var breathing: Bool {
        get { _breathing.wrappedValue }
        nonmutating set { _breathing.wrappedValue = newValue }
    }

    static func doneFraction(_ segments: [IslandCheck]) -> Double {
        segments.isEmpty ? 0 : Double(segments.filter { $0 != .running }.count) / Double(segments.count)
    }

    var body: some View {
        ZStack {
            if segments.count <= Self.maxSegments {
                let slice = 1 / Double(max(segments.count, 1))
                let gap = segments.count > 1 ? min(0.05, slice * 0.3) : 0
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    Circle()
                        .trim(from: Double(index) * slice + gap / 2, to: Double(index + 1) * slice - gap / 2)
                        .stroke(GitHubColors.segment(segment), style: StrokeStyle(lineWidth: 2.2, lineCap: .butt))
                        .opacity(segment == .running ? (breathing ? 0.75 : 0.35) : 1)
                }
            } else {
                Circle()
                    .stroke(GitHubColors.running.opacity(0.25), lineWidth: 2.2)
                Circle()
                    .trim(from: 0, to: Self.doneFraction(segments))
                    .stroke(segments.contains(.failed) ? GitHubColors.failed : GitHubColors.running,
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
        }
        .rotationEffect(.degrees(-90))
        .frame(width: 14, height: 14)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}

/// A GitHub blip's leading glyph (2026-10-22, the user's pick): the person's
/// avatar with a small badge for what they did, or, for checks and runs,
/// the glyph on a disc in the event's colour.
struct GitHubBlipGlyph: View {
    let avatar: NSImage?
    let symbol: String
    let color: Color

    var body: some View {
        if let avatar {
            Image(nsImage: avatar)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 20, height: 20)
                .clipShape(Circle())
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: symbol)
                        .font(.system(size: 5.5, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 11, height: 11)
                        .background(Circle().fill(color))
                        .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                        .offset(x: 3, y: 2)
                }
        } else {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(color))
        }
    }
}

/// The running item's glyph for a run outside a PR, which has no per-check
/// detail (2026-10-22): an arc turning once every 1.2 s, and the count of
/// what runs when more than one does. Still under Reduce Motion.
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
