import Testing
@testable import CalendarService

@Test func calendarsGroupByAccountAlphabetically() {
    let list = [
        CalendarInfo(id: "3", title: "Work", source: "iCloud", kind: .event, color: nil),
        CalendarInfo(id: "1", title: "Holidays", source: "Google", kind: .event, color: .init(red: 1, green: 0, blue: 0)),
        CalendarInfo(id: "2", title: "Home", source: "iCloud", kind: .event, color: nil),
        CalendarInfo(id: "4", title: "Errands", source: "iCloud", kind: .reminder, color: nil),
    ]
    let groups = CalendarInfo.grouped(list)
    #expect(groups.map(\.source) == ["Google", "iCloud"])
    #expect(groups[1].calendars.map(\.title) == ["Errands", "Home", "Work"])
    #expect(CalendarInfo.grouped([]).isEmpty)
}
