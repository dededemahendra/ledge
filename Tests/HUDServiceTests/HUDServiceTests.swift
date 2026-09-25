import Testing
import ActivityKit
@testable import HUDService

@Test func availabilityIsAvailableWhenEitherChannelWorks() {
    #expect(HUDService.composedAvailability(volume: .available, brightness: .available)
            == .available)
    #expect(HUDService.composedAvailability(
        volume: .available, brightness: .unavailable(reason: "x")) == .available,
        "a working volume HUD is still worth having")
    #expect(HUDService.composedAvailability(
        volume: .unavailable(reason: "y"), brightness: .available) == .available)
}

@Test func availabilityIsUnavailableOnlyWhenBothFail() {
    #expect(HUDService.composedAvailability(
        volume: .unavailable(reason: "no device"),
        brightness: .unavailable(reason: "no DisplayServices"))
        == .unavailable(reason: "no volume or brightness source"))
}
