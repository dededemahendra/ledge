import Testing
@testable import CallService

private func node(_ role: String, id: String? = nil, _ title: String? = nil, _ children: [AXSnapshot] = []) -> AXSnapshot {
    AXSnapshot(role: role, identifier: id, title: title, children: children)
}

/// Zoom's menu bar, shaped like the probe's recording (2026-10-23).
private func zoomMenuBar(muteItem: Bool = true, muteTitle: String = "Unmute audio") -> AXSnapshot {
    var items = [node("AXMenuItem", id: "onMuteAll:", "Mute all"), node("AXMenuItem", id: "onUnmuteAll:", "Ask all to unmute")]
    if muteItem { items.append(node("AXMenuItem", id: "onMuteAudio:", muteTitle)) }
    items.append(node("AXMenuItem", id: "onMuteVideo:", "Start video"))
    return node("AXMenuBar", nil, [
        node("AXMenuBarItem", "Apple"),
        node("AXMenuBarItem", "Meeting", [node("AXMenu", nil, items)]),
        node("AXMenuBarItem", "View"),
    ])
}

/// A browser window holding a control deep in its page, as Meet does.
private func window(_ title: String, button: String = "Turn off microphone") -> AXSnapshot {
    var deep = node("AXGroup", nil, [node("AXButton", button), node("AXButton", "Turn off camera"), node("AXButton", "Leave call")])
    for _ in 0..<10 { deep = node("AXGroup", nil, [deep]) }
    return node("AXWindow", title, [deep])
}

@Test func zoomsMuteItemIsFoundByItsIdentifier() {
    let found = MeetingMute.find(.zoom, menuBar: zoomMenuBar(), windows: [])
    #expect(found?.identifier == "onMuteAudio:")
    #expect(MeetingMute.isMuted(.zoom, title: found?.title) == true)
}

@Test func zoomUnmutedReadsFromTheTitle() {
    #expect(MeetingMute.isMuted(.zoom, title: "Mute audio") == false)
    #expect(MeetingMute.isMuted(.zoom, title: "Stummschalten") == nil)
}

@Test func zoomsMuteAllIsNotTheMuteItem() {
    #expect(MeetingMute.find(.zoom, menuBar: zoomMenuBar(muteItem: false), windows: []) == nil)
}

@Test func meetsMicrophoneButtonIsFoundInTheMeetWindow() {
    let found = MeetingMute.find(.meet, menuBar: nil, windows: [window("Personal: Home"), window("Personal: Meet - abc-defg-hij")])
    #expect(found?.title == "Turn off microphone")
    #expect(MeetingMute.isMuted(.meet, title: "Turn off microphone") == false)
    #expect(MeetingMute.isMuted(.meet, title: "Turn on microphone") == true)
}

@Test func onlyTheMeetWindowCounts() {
    #expect(MeetingMute.find(.meet, menuBar: nil, windows: [window("Personal: Home")]) == nil)
}

@Test func noMeetWindowNoControl() {
    #expect(MeetingMute.find(.meet, menuBar: nil as AXSnapshot?, windows: []) == nil)
}

@Test func whichAppsHaveAControl() {
    #expect(MeetingMute.kind(for: "us.zoom.xos") == .zoom)
    #expect(MeetingMute.kind(for: "company.thebrowser.dia") == .meet)
    #expect(MeetingMute.kind(for: "com.google.Chrome") == .meet)
    #expect(MeetingMute.kind(for: "com.apple.FaceTime") == nil)
}
