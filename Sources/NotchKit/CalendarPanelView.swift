import SwiftUI

/// The calendar mode of the open card (2026-09-30): "Up next", then up to
/// four items — glyph, title, when — each a row that opens the item
/// (join link, or the event in its app). Reached by a two-finger swipe
/// from the now-playing card, or from the next-item preview.
struct CalendarPanelView: View {
    let items: [UpcomingEvent]
    let contentColor: Color
    let reduceMotion: Bool
    let emit: (NotchIntent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Up next")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(contentColor.opacity(0.55))
                .padding(.horizontal, 14)
                .frame(height: 20, alignment: .bottomLeading)
            ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { _, item in
                Button {
                    if let url = item.url { emit(.open(url)) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbolName)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 16)
                        Text(item.title)
                            .font(.system(size: 12.5, weight: .regular))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(item.when.isEmpty ? item.compactText : item.when)
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(contentColor.opacity(0.6))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ListRowButtonStyle(reduceMotion: reduceMotion))
            }
        }
        .foregroundStyle(contentColor)
    }
}
