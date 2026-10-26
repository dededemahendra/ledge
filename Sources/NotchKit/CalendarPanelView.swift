import SwiftUI

extension Color {
    /// Calendar's red, softer than the system red (2026-10-01, user's
    /// call: "too hard"): pulled a little toward white, for the card's
    /// weekday and month and an overdue reminder's time.
    static var calendarRed: Color { Color(nsColor: .systemRed).mix(with: .white, by: 0.2) }
}

/// The calendar mode of the open card (2026-10-26, after the reference
/// app): two days side by side. Left, today: the weekday in red, a big
/// day number, then today's all-day chips and items, or "No events
/// today" over "Your day is clear". Right, the next day with something
/// on, under its name ("TOMORROW", "WEDNESDAY, 28 OCT"), its chips and
/// items the same way; with the week ahead clear, this month as a grid
/// instead (the 2026-09-30 layout). A column that runs out of room ends
/// on a count of the rest. Each chip and row opens its item.
struct CalendarPanelView: View {
    let data: CalendarModeData
    let contentColor: Color
    let reduceMotion: Bool
    let emit: (NotchIntent) -> Void

    private let cell = CGSize(width: 22, height: 16)
    private let lineHeight: CGFloat = 20
    private let lineSpacing: CGFloat = 3
    /// Lines under the big date, and under the next day's name: what the
    /// 136 pt of content room holds at `lineHeight`.
    private let todayRoom = 3
    private let nextRoom = 4
    private var accent: Color { .calendarRed }

    /// The reveal (2026-09-30): the date first, then the lines one by one,
    /// each rising as it fades in, on the mode's own spring. Spelled-out
    /// `State`, as elsewhere here.
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
        HStack(alignment: .top, spacing: 0) {
            todayColumn
                .frame(width: 152, alignment: .leading)
                .padding(.leading, 20)
            Spacer(minLength: 10)
            if let next = data.next {
                nextColumn(next)
                    .frame(width: 150, alignment: .leading)
                    .padding(.trailing, 20)
            } else {
                grid
                    .padding(.trailing, 14)
            }
        }
        .padding(.top, 8)
        .foregroundStyle(contentColor)
        .onAppear { revealed = true }
    }

    private var todayColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            reveal(Text(data.weekdayTitle)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(accent)
                .frame(height: 14), order: 0)
            reveal(Text("\(data.dayNumber)")
                .font(.system(size: 30))
                .monospacedDigit()
                .foregroundStyle(contentColor.opacity(0.95))
                .frame(height: 32), order: 0)
            let lines = CalendarLine.lines(allDay: data.allDay, items: data.items, room: todayRoom)
            if lines.isEmpty {
                reveal(VStack(alignment: .leading, spacing: 2) {
                    Text(data.isDayDone ? "No more events today" : "No events today")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(contentColor.opacity(0.92))
                    Text("Your day is clear")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(contentColor.opacity(0.45))
                }, order: 1)
                .padding(.top, 24)
            } else {
                column(lines, firstOrder: 1)
                    .padding(.top, 6)
            }
        }
    }

    private func nextColumn(_ day: CalendarDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            reveal(Text(day.title)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(contentColor.opacity(0.55))
                .lineLimit(1)
                .frame(height: 14), order: 0)
            column(CalendarLine.lines(allDay: day.allDay, items: day.items, room: nextRoom), firstOrder: 1)
                .padding(.top, 6)
        }
    }

    private func column(_ lines: [CalendarLine], firstOrder: Int) -> some View {
        VStack(alignment: .leading, spacing: lineSpacing) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                reveal(self.line(line), order: firstOrder + index)
            }
        }
    }

    @ViewBuilder private func line(_ line: CalendarLine) -> some View {
        switch line {
        case .allDay(let item): chip(item)
        case .item(let item): row(item)
        case .more(let text):
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(contentColor.opacity(0.45))
                .frame(height: 16)
        }
    }

    private func color(of item: UpcomingEvent) -> Color {
        item.tint.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? Color(nsColor: .systemGray)
    }

    private func open(_ item: UpcomingEvent) {
        if let url = item.url { emit(.open(url)) }
    }

    /// An all-day event as the reference app draws one (2026-10-26): a
    /// capsule in its calendar's colour at a low tint, the glyph (a star
    /// for a holiday, a gift for a birthday) and the title in the colour
    /// itself, pulled toward white. As wide as its title.
    private func chip(_ item: UpcomingEvent) -> some View {
        let color = color(of: item)
        return Button { open(item) } label: {
            HStack(spacing: 4) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(item.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(color.mix(with: .white, by: 0.25))
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .frame(height: 18)
            .background(Capsule().fill(color.opacity(0.22)))
            .contentShape(Capsule())
        }
        .buttonStyle(ListRowButtonStyle(reduceMotion: reduceMotion))
        .frame(height: lineHeight)
    }

    /// One item as Apple's Reminders and Calendar widgets list them
    /// (2026-10-21, user's call): the item's mark, its title, and its time
    /// at the trailing edge, red once a reminder is overdue. The item's
    /// colour is in the mark alone.
    private func row(_ item: UpcomingEvent) -> some View {
        Button { open(item) } label: {
            HStack(spacing: 6) {
                mark(item)
                Text(item.title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(contentColor.opacity(0.92))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(item.time)
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(item.isPastDue ? accent : contentColor.opacity(0.5))
                    .fixedSize()
            }
            .frame(height: lineHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ListRowButtonStyle(reduceMotion: reduceMotion))
    }

    /// A reminder's hollow ring in its list's colour, or an event's bar in
    /// its calendar's; without one, the system grey the ear's ring uses.
    /// Both in an 11 pt column, so the titles line up.
    @ViewBuilder private func mark(_ item: UpcomingEvent) -> some View {
        let color = color(of: item)
        switch item.kind {
        case .reminder:
            Circle()
                .strokeBorder(color, lineWidth: 1.5)
                .frame(width: 11, height: 11)
        case .event:
            Capsule()
                .fill(color)
                .frame(width: 3, height: 13)
                .frame(width: 11)
        }
    }

    private var grid: some View {
        VStack(alignment: .trailing, spacing: 2) {
            reveal(Text(data.monthShort)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(accent)
                .frame(height: 14), order: 0)
            reveal(HStack(spacing: 0) {
                ForEach(Array(data.weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(contentColor.opacity(data.weekendColumns[index] ? 0.25 : 0.5))
                        .frame(width: cell.width, height: 12)
                }
            }, order: 1)
            ForEach(Array(data.weeks.enumerated()), id: \.offset) { row, week in
                reveal(HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { column, day in
                        dayCell(day, weekend: data.weekendColumns[column])
                    }
                }, order: 2 + row)
            }
        }
    }

    private func dayCell(_ day: Int?, weekend: Bool) -> some View {
        ZStack {
            if let day {
                let isToday = day == data.today
                let marked = data.markedDays.contains(day)
                if isToday {
                    Circle().fill(contentColor.opacity(0.92)).frame(width: 16, height: 16)
                }
                Text("\(day)")
                    .font(.system(size: 10, weight: isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(
                        isToday ? Color.black
                        : marked ? accent.opacity(0.95)
                        : contentColor.opacity(weekend ? 0.3 : 0.75)
                    )
            }
        }
        .frame(width: cell.width, height: cell.height)
    }
}
