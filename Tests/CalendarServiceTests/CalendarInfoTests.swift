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

/// A list's colour drawn as a thin ring on the black island (2026-10-21):
/// Apple's own colours pass untouched, a near-black one is lifted until it
/// shows, keeping its hue.
@Test func aDarkListColourIsLiftedToShowOnBlack() {
    let blue = CalendarInfo.RGB(red: 0, green: 0.48, blue: 1)
    let brown = CalendarInfo.RGB(red: 0.64, green: 0.52, blue: 0.37)
    #expect(blue.visibleOnBlack == blue)
    #expect(brown.visibleOnBlack == brown)

    let navy = CalendarInfo.RGB(red: 0, green: 0, blue: 0.2)
    let lifted = navy.visibleOnBlack
    #expect(abs(lifted.luminance - CalendarInfo.RGB.minimumLuminanceOnBlack) < 0.001)
    #expect(lifted.blue > lifted.red && lifted.blue > lifted.green, "still blue")
    #expect(CalendarInfo.RGB(red: 0, green: 0, blue: 0).visibleOnBlack.luminance >= CalendarInfo.RGB.minimumLuminanceOnBlack - 0.001)
}
