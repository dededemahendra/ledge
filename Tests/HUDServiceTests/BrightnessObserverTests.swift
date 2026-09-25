import Testing
import CoreGraphics
@testable import HUDService

@Test func bridgeLoadsAndReadsARealBrightnessValue() throws {
    // Verified working on the target machine: rc=0, value in 0...1.
    let bridge = try #require(DisplayServicesBridge(), "DisplayServices must dlopen")
    let level = try #require(bridge.brightness(for: CGMainDisplayID()))
    #expect(level >= 0 && level <= 1)
}

@Test func backendPrefersNotificationsWhenRegistrationWorks() {
    #expect(BrightnessObserver.backend(canRegister: true, canRead: true) == .notifications)
}

@Test func backendFallsBackToPollingWhenRegistrationIsUnusable() {
    #expect(BrightnessObserver.backend(canRegister: false, canRead: true) == .polling)
}

@Test func backendIsUnavailableWhenBrightnessCannotEvenBeRead() {
    #expect(BrightnessObserver.backend(canRegister: false, canRead: false) == .unavailable)
    #expect(BrightnessObserver.backend(canRegister: true, canRead: false) == .unavailable,
            "registration is worthless if the value cannot be read")
}

@Test func availabilityReflectsTheBackend() {
    #expect(BrightnessObserver.availability(for: .notifications) == .available)
    #expect(BrightnessObserver.availability(for: .polling) == .available)
    #expect(BrightnessObserver.availability(for: .unavailable)
            == .unavailable(reason: "DisplayServices brightness unavailable"))
}

@Test func pollIntervalIsCheapEnoughToJustify() {
    #expect(BrightnessObserver.pollInterval == 0.1)
}
