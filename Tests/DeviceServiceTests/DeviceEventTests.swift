import Testing
import CoreAudio
@testable import DeviceService

@Test func theFirstRouteIsABaselineAndNotNews() {
    var d = DeviceEventDeriver()
    #expect(d.outputChanged(uid: "bt-1", name: "AirPods Pro", transport: .bluetooth, batteryPercent: 80) == nil,
            "whatever is in use at launch is not a change")
    #expect(d.outputChanged(uid: "usb-1", name: "Studio Display", transport: .usb, batteryPercent: nil)
            == .outputChanged(name: "Studio Display", transport: .usb, batteryPercent: nil))
}

@Test func theSameRouteReportedTwiceIsSilent() {
    var d = DeviceEventDeriver()
    _ = d.outputChanged(uid: "builtin", name: "MacBook Air Speakers", transport: .builtIn, batteryPercent: nil)
    _ = d.outputChanged(uid: "bt-1", name: "AirPods Pro", transport: .bluetooth, batteryPercent: 80)
    #expect(d.outputChanged(uid: "bt-1", name: "AirPods Pro", transport: .bluetooth, batteryPercent: 79) == nil,
            "CoreAudio re-notifying for the same device must not re-announce it")
}

@Test func switchingBackToTheBuiltInSpeakersIsAnnouncedByName() {
    var d = DeviceEventDeriver()
    _ = d.outputChanged(uid: "bt-1", name: "AirPods Pro", transport: .bluetooth, batteryPercent: 80)
    #expect(d.outputChanged(uid: "builtin", name: "MacBook Air Speakers", transport: .builtIn, batteryPercent: nil)
            == .outputChanged(name: "MacBook Air Speakers", transport: .builtIn, batteryPercent: nil),
            "CoreAudio cannot say whether the AirPods disconnected or were merely switched away from — say where sound goes now")
}

@Test func presentationCarriesNameGlyphAndBattery() {
    let pods = DeviceEvent.outputChanged(name: "Dede's AirPods Pro", transport: .bluetooth, batteryPercent: 87)
    #expect(pods.activityTitle == "Dede's AirPods Pro")
    #expect(pods.compactText == "87%")
    #expect(pods.symbolName == "airpods.pro")

    let unknownBattery = DeviceEvent.outputChanged(name: "Sony WH-1000XM5", transport: .bluetooth, batteryPercent: nil)
    #expect(unknownBattery.compactText == nil, "never invent a battery level")
    #expect(unknownBattery.symbolName == "headphones")

    #expect(DeviceEvent.outputChanged(name: "AirPods Max", transport: .bluetooth, batteryPercent: 50).symbolName == "airpods.max")
    #expect(DeviceEvent.outputChanged(name: "Living Room", transport: .airPlay, batteryPercent: nil).symbolName == "airplay.audio")
    #expect(DeviceEvent.outputChanged(name: "Studio Display", transport: .usb, batteryPercent: nil).symbolName == "speaker.wave.2")
    #expect(DeviceEvent.outputChanged(name: "MacBook Air Speakers", transport: .builtIn, batteryPercent: nil).symbolName == "laptopcomputer")
    #expect(DeviceEvent.outputChanged(name: "External Headphones", transport: .builtIn, batteryPercent: nil).symbolName == "headphones",
            "the headphone jack is the built-in device renamed — the name wins over the transport")
}

@Test func transportMappingCoversTheCommonTypesAndDefaultsToOther() {
    #expect(OutputRouteObserver.transport(fromRaw: kAudioDeviceTransportTypeBuiltIn) == .builtIn)
    #expect(OutputRouteObserver.transport(fromRaw: kAudioDeviceTransportTypeBluetooth) == .bluetooth)
    #expect(OutputRouteObserver.transport(fromRaw: kAudioDeviceTransportTypeBluetoothLE) == .bluetooth)
    #expect(OutputRouteObserver.transport(fromRaw: kAudioDeviceTransportTypeUSB) == .usb)
    #expect(OutputRouteObserver.transport(fromRaw: kAudioDeviceTransportTypeAirPlay) == .airPlay)
    #expect(OutputRouteObserver.transport(fromRaw: 0xDEAD_BEEF) == .other)
}

@Test func batteryNameMatchingIsLooseInBothDirectionsButNeverEmpty() {
    #expect(PeripheralBattery.matches(candidate: "airpods pro", wanted: "dede's airpods pro"))
    #expect(PeripheralBattery.matches(candidate: "dede's airpods pro", wanted: "airpods pro"))
    #expect(PeripheralBattery.matches(candidate: "airpods pro", wanted: "airpods pro"))
    #expect(!PeripheralBattery.matches(candidate: "magic mouse", wanted: "airpods pro"))
    #expect(!PeripheralBattery.matches(candidate: "", wanted: "airpods pro"), "an empty product would match everything")
}

/// Best match, not first match (review, 2026-09-29).
@Test func batteryMatchPrefersExactThenTheLongestProductName() {
    let plain = PeripheralBattery.Candidate(product: "Dede's AirPods", percent: 40)
    let pro = PeripheralBattery.Candidate(product: "Dede's AirPods Pro", percent: 87)
    let mouse = PeripheralBattery.Candidate(product: "Magic Mouse", percent: 60)
    #expect(PeripheralBattery.best(among: [plain, pro, mouse], wanted: "Dede's AirPods Pro") == pro, "exact wins")
    #expect(PeripheralBattery.best(among: [plain, pro, mouse], wanted: "Dede's AirPods") == plain, "exact wins even when a longer name also matches")
    #expect(PeripheralBattery.best(among: [plain, pro], wanted: "Dede's AirPods Pro (2nd gen)") == pro, "no exact: the longest matching product")
    #expect(PeripheralBattery.best(among: [mouse], wanted: "AirPods Pro") == nil)
}
