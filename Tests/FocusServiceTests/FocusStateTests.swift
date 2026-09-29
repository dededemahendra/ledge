import Testing
@testable import FocusService

private let battery = MenuBarExtra(identifier: "com.apple.menuextra.battery", description: "Battery", value: "95%, charging")
private let focus = MenuBarExtra(identifier: "com.apple.menuextra.focusmodes", description: "Focus", value: "Work")

@Test func theFocusExtraNamesTheModeAndItsAbsenceMeansOff() {
    #expect(FocusState.current(in: [battery]) == nil)
    #expect(FocusState.current(in: [battery, focus]) == FocusState(name: "Work"))
    #expect(FocusState.current(in: [MenuBarExtra(identifier: "com.apple.menuextra.focusmodes", description: "Focus, Do Not Disturb, on")]) == FocusState(name: "Do Not Disturb"))
    #expect(FocusState.current(in: [MenuBarExtra(identifier: "com.apple.menuextra.focusmodes", description: "Focus")]) == FocusState(name: "Do Not Disturb"),
            "nothing but the word Focus: the plain one")
    #expect(FocusState.name(from: "Focus: Reading") == "Reading")
    #expect(FocusState.current(in: [MenuBarExtra(identifier: "com.apple.menuextra.donotdisturb", description: "Do Not Disturb")]) == FocusState(name: "Do Not Disturb"),
            "the older spelling of the extra counts too")
}

@Test func glyphsFollowAppleNamesAndFallBackToTheMoon() {
    #expect(FocusState(name: "Do Not Disturb").symbolName == "moon.fill")
    #expect(FocusState(name: "Work").symbolName == "briefcase.fill")
    #expect(FocusState(name: "Deep focus").symbolName == "moon.fill")
    #expect(FocusEvent.off(FocusState(name: "Work")).symbolName == "moon")
    #expect(FocusEvent.on(FocusState(name: "Work")).compactText == "On")
}

@Test func onlyTransitionsAreEventsAndTheFirstSampleIsSilent() {
    var deriver = FocusEventDeriver()
    let work = FocusState(name: "Work"), dnd = FocusState(name: "Do Not Disturb")
    #expect(deriver.sample(work) == nil, "already on at launch: not news")
    #expect(deriver.sample(work) == nil)
    #expect(deriver.sample(nil) == .off(work))
    #expect(deriver.sample(nil) == nil)
    #expect(deriver.sample(dnd) == .on(dnd))
    #expect(deriver.sample(work) == .on(work), "switching modes reads as the new one coming on")

    var fresh = FocusEventDeriver()
    #expect(fresh.sample(nil) == nil)
    #expect(fresh.sample(dnd) == .on(dnd))
}
