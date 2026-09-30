import SwiftUI

/// The calendar mode of the open card (2026-09-30, after the reference
/// app): the weekday and a big day number on the left with today's items
/// as chips in their calendars' colours, and this month as a grid on the
/// right — the month's name in red, weekends dimmed, busy days in red,
/// today on a white disc. Each chip opens its item.
struct CalendarPanelView: View {
    let data: CalendarModeData
    let contentColor: Color
    let reduceMotion: Bool
    let emit: (NotchIntent) -> Void

    private let cell = CGSize(width: 22, height: 16)
    /// Softer than the system red (2026-10-01, user's call: "too hard"):
    /// pulled a little toward white, used at less than full strength.
    private var accent: Color { Color(nsColor: .systemRed).mix(with: .white, by: 0.2) }

    /// The reveal (2026-09-30): the date first, then the chips one by one,
    /// then the grid row by row — each rising 6 pt as it fades in, on the
    /// mode's own spring. Spelled-out `State`, as elsewhere here.
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
                .padding(.leading, 16)
                .padding(.top, 8)
            Spacer(minLength: 8)
            grid
                .padding(.trailing, 14)
                .padding(.top, 8)
        }
        .foregroundStyle(contentColor)
        .onAppear { revealed = true }
    }

    private var todayColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            reveal(Text(data.weekdayTitle)
                .font(.system(size: 9.5, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(accent.opacity(0.9)), order: 0)
            reveal(Text("\(data.dayNumber)")
                .font(.system(size: 30, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(contentColor.opacity(0.95))
                .frame(height: 32), order: 0)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(data.items.prefix(3).enumerated()), id: \.offset) { index, item in
                    reveal(chip(item), order: 1 + index)
                }
            }
            .padding(.top, 4)
        }
        .frame(width: 168, alignment: .leading)
    }

    private func chip(_ item: UpcomingEvent) -> some View {
        let color = item.tint.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? contentColor
        return Button {
            if let url = item.url { emit(.open(url)) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 9, weight: .medium))
                Text(item.title)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(color.mix(with: .white, by: 0.55))
            .padding(.horizontal, 8)
            .frame(height: 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(ListRowButtonStyle(reduceMotion: reduceMotion))
    }

    private var grid: some View {
        VStack(alignment: .trailing, spacing: 2) {
            reveal(Text(data.monthShort)
                .font(.system(size: 9.5, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(accent.opacity(0.9))
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
