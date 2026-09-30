import SwiftUI

/// The calendar mode of the open card (2026-09-30): this month as a grid
/// on the left — today on a white disc, a dot under each day with
/// something — and today's remaining items on the right, each a row that
/// opens the item. Reached by a two-finger swipe from the now-playing
/// card, or from the next-item preview.
struct CalendarPanelView: View {
    let data: CalendarModeData
    let contentColor: Color
    let reduceMotion: Bool
    let emit: (NotchIntent) -> Void

    private let cell = CGSize(width: 25, height: 15)

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            grid
                .padding(.leading, 14)
                .padding(.top, 4)
            Rectangle()
                .fill(contentColor.opacity(0.12))
                .frame(width: 1)
                .padding(.vertical, 10)
                .padding(.horizontal, 10)
            today
                .padding(.top, 4)
                .padding(.trailing, 6)
        }
        .foregroundStyle(contentColor)
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(data.monthTitle)
                .font(.system(size: 11, weight: .semibold))
                .frame(height: 16, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(Array(data.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(contentColor.opacity(0.4))
                        .frame(width: cell.width, height: 11)
                }
            }
            ForEach(Array(data.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        dayCell(day)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Int?) -> some View {
        ZStack {
            if let day {
                let isToday = day == data.today
                if isToday {
                    Circle().fill(contentColor).frame(width: 15, height: 15)
                }
                Text("\(day)")
                    .font(.system(size: 9.5, weight: isToday ? .semibold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.black : contentColor.opacity(0.85))
                if data.markedDays.contains(day) {
                    Circle()
                        .fill(isToday ? Color.black : contentColor)
                        .frame(width: 2.5, height: 2.5)
                        .offset(y: 5.5)
                }
            }
        }
        .frame(width: cell.width, height: cell.height)
    }

    private var today: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Today")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(contentColor.opacity(0.55))
                .padding(.horizontal, 10)
                .frame(height: 16, alignment: .leading)
            if data.items.isEmpty {
                Text("Nothing more today")
                    .font(.system(size: 10.5))
                    .foregroundStyle(contentColor.opacity(0.45))
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
            }
            ForEach(Array(data.items.prefix(3).enumerated()), id: \.offset) { _, item in
                Button {
                    if let url = item.url { emit(.open(url)) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.symbolName)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.system(size: 11.5, weight: .medium))
                                .lineLimit(1)
                            Text(item.when.isEmpty ? item.compactText : item.when)
                                .font(.system(size: 9.5))
                                .monospacedDigit()
                                .foregroundStyle(contentColor.opacity(0.6))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ListRowButtonStyle(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
