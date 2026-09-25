import Testing
import CoreAudio
@testable import HUDService

// Review Focus 2: not every device exposes a per-channel scalar.
@Test func strategyPrefersPerChannelScalarWhenAvailable() {
    #expect(VolumeObserver.strategy(hasScalar: true, hasVirtualMain: true) == .perChannelScalar)
    #expect(VolumeObserver.strategy(hasScalar: true, hasVirtualMain: false) == .perChannelScalar)
}

@Test func strategyFallsBackToVirtualMainVolume() {
    #expect(VolumeObserver.strategy(hasScalar: false, hasVirtualMain: true) == .virtualMainVolume,
            "Bluetooth and aggregate devices commonly expose only this")
}

@Test func strategyReportsUnavailableWhenNeitherExists() {
    #expect(VolumeObserver.strategy(hasScalar: false, hasVirtualMain: false) == .unavailable)
}

@Test func readingsAreClampedAndComparable() {
    #expect(VolumeReading(level: 1.4, muted: false).level == 1.0)
    #expect(VolumeReading(level: -1, muted: false).level == 0.0)
    #expect(VolumeReading(level: 0.5, muted: false) != VolumeReading(level: 0.5, muted: true))
}

@Test func unavailableStrategyMapsToAnUnavailableService() {
    #expect(VolumeObserver.availability(for: .unavailable)
            == .unavailable(reason: "output device reports no volume control"))
    #expect(VolumeObserver.availability(for: .perChannelScalar) == .available)
    #expect(VolumeObserver.availability(for: .virtualMainVolume) == .available)
}
