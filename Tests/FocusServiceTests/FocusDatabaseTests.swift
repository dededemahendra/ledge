import Testing
import Foundation
@testable import FocusService

private func assertions(_ modeID: String?) -> [String: Any] {
    let records: [[String: Any]] = modeID.map { [["assertionDetails": ["assertionDetailsModeIdentifier": $0, "assertionDetailsReason": "user"], "assertionStartDateTimestamp": 1.0]] } ?? []
    return ["data": [["storeAssertionRecords": records, "storeVersion": 1]]]
}
private func configurations() -> [String: Any] {
    ["data": [["modeConfigurations": [
        "com.apple.donotdisturb.mode.default": ["mode": ["name": "Do Not Disturb", "symbolImageName": "moon.fill", "tintColorName": "systemIndigoColor"]],
        "com.apple.focus.personal": ["mode": ["name": "Personal", "symbolImageName": "headphones", "tintColorName": "systemBlueColor"]],
        "custom": ["mode": ["name": "", "symbolImageName": "heart.fill"]],
    ]]]]
}

@Test func theActiveModeIsTheFirstAssertionAndNoneIsNil() {
    #expect(FocusDatabase.activeModeIdentifier(assertions: assertions("com.apple.focus.personal")) == "com.apple.focus.personal")
    #expect(FocusDatabase.activeModeIdentifier(assertions: assertions(nil)) == nil)
    #expect(FocusDatabase.activeModeIdentifier(assertions: [:]) == nil)
}

@Test func modesCarryNameSymbolAndTintWithSafeDefaults() {
    let modes = FocusDatabase.modes(configurations: configurations())
    #expect(modes["com.apple.donotdisturb.mode.default"] == FocusMode(identifier: "com.apple.donotdisturb.mode.default", name: "Do Not Disturb", symbolName: "moon.fill", tintColorName: "systemIndigoColor"))
    #expect(modes["com.apple.focus.personal"]?.tintColorName == "systemBlueColor")
    #expect(modes["custom"] == FocusMode(identifier: "custom", name: "Focus", symbolName: "heart.fill", tintColorName: nil), "an empty name falls back; a missing tint stays nil")
    #expect(FocusDatabase.modes(configurations: [:]).isEmpty)
}

@Test func transitionsBetweenModes() {
    let dnd = FocusMode(identifier: "a", name: "Do Not Disturb", symbolName: "moon.fill", tintColorName: "systemIndigoColor")
    let work = FocusMode(identifier: "b", name: "Work", symbolName: "desktopcomputer", tintColorName: "systemTealColor")
    #expect(FocusEvent.transition(from: nil, to: dnd) == .on(dnd))
    #expect(FocusEvent.transition(from: dnd, to: nil) == .off(dnd))
    #expect(FocusEvent.transition(from: dnd, to: work) == .on(work), "switching reads as the new one coming on")
    #expect(FocusEvent.transition(from: dnd, to: dnd) == nil)
    #expect(FocusEvent.transition(from: nil, to: nil) == nil)
    #expect(FocusEvent.on(work).symbolName == "desktopcomputer")
    #expect(FocusEvent.off(work).symbolName == "desktopcomputer" && FocusEvent.off(work).compactText == "Off")
    #expect(FocusEvent.on(nil).symbolName == "moon.fill" && FocusEvent.off(nil).symbolName == "moon")
}
