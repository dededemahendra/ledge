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

    private let cell = CGSize(width: 22, height: 15)
    private var accent: Color { Color(nsColor: .systemRed) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            todayColumn
                .padding(.leading, 16)
                .padding(.top, 6)
            Spacer(minLength: 8)
            grid
                .padding(.trailing, 14)
                .padding(.top, 6)
        }
        .foregroundStyle(contentColor)
    }

    private var todayColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(data.weekdayTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
            Text("\(data.dayNumber)")
                .font(.system(size: 30, weight: .regular, design: .rounded))
                .monospacedDigit()
                .frame(height: 32)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(data.items.prefix(3).enumerated()), id: \.offset) { _, item in
                    chip(item)
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
                    .font(.system(size: 9, weight: .semibold))
                Text(item.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(color.mix(with: .white, by: 0.35))
            .padding(.horizontal, 7)
            .frame(height: 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.28), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(ListRowButtonStyle(reduceMotion: reduceMotion))
    }

    private var grid: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(data.monthShort)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
                .frame(height: 14)
            HStack(spacing: 0) {
                ForEach(Array(data.weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(contentColor.opacity(data.weekendColumns[index] ? 0.35 : 0.9))
                        .frame(width: cell.width, height: 12)
                }
            }
            ForEach(Array(data.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { column, day in
                        dayCell(day, weekend: data.weekendColumns[column])
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Int?, weekend: Bool) -> some View {
        ZStack {
            if let day {
                let isToday = day == data.today
                let marked = data.markedDays.contains(day)
                if isToday {
                    Circle().fill(contentColor).frame(width: 15, height: 15)
                }
                Text("\(day)")
                    .font(.system(size: 9.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(
                        isToday ? Color.black
                        : marked ? accent
                        : contentColor.opacity(weekend ? 0.35 : 0.9)
                    )
            }
        }
        .frame(width: cell.width, height: cell.height)
    }
}
