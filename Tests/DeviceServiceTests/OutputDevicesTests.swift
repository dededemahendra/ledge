import Testing
import Foundation
@testable import DeviceService

@Test func outputDevicesShareTheRouteBlipsGlyphs() {
    let pods = OutputDevice(id: "bt-1", name: "AirPods Pro", transport: .bluetooth, isCurrent: false)
    #expect(pods.symbolName == DeviceEvent.glyph(name: "AirPods Pro", transport: .bluetooth))
    #expect(pods.symbolName == "airpods.pro")
    #expect(OutputDevice(id: "b", name: "MacBook Air Speakers", transport: .builtIn, isCurrent: true).symbolName == "laptopcomputer")
    #expect(OutputDevice(id: "j", name: "External Headphones", transport: .builtIn, isCurrent: false).symbolName == "headphones")
    #expect(OutputDevice(id: "a", name: "Living Room", transport: .airPlay, isCurrent: false).symbolName == "airplay.audio")
}

/// Against the real CoreAudio on this machine: there is always at least the
/// built-in output, exactly one device is the default, and every listed
/// device has a name and a UID.
@Test func theCatalogListsThisMachinesOutputsWithExactlyOneCurrent() {
    let outputs = OutputDeviceCatalog.currentOutputs()
    #expect(!outputs.isEmpty, "a Mac always has a built-in output")
    #expect(outputs.filter(\.isCurrent).count == 1, "exactly one default output: \(outputs)")
    #expect(outputs.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
    #expect(Set(outputs.map(\.id)).count == outputs.count, "UIDs are unique")
}

/// Setting the default to the device that already is the default must be a
/// no-op that succeeds — the only write that is safe to make in a test.
@Test func settingTheCurrentDefaultAgainSucceedsAndChangesNothing() {
    let before = OutputDeviceCatalog.currentOutputs()
    guard let current = before.first(where: \.isCurrent) else { return }
    #expect(OutputDeviceCatalog.setDefaultOutput(uid: current.id))
    #expect(OutputDeviceCatalog.currentOutputs().first(where: \.isCurrent)?.id == current.id)
    #expect(!OutputDeviceCatalog.setDefaultOutput(uid: "no-such-device-uid"), "an unknown UID is refused, not crashed on")
}
