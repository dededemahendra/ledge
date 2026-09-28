import Testing
import Foundation
@testable import DeviceService

@Test func airPodsFamiliesMapToTheirRendersNewestFirst() {
    #expect(DeviceArtwork.candidateFiles(forDeviceNamed: "Dede's AirPods Pro").first?.hasPrefix("B788") == true,
            "Pro 3 render preferred, Pro 2 as fallback")
    #expect(DeviceArtwork.candidateFiles(forDeviceNamed: "Dede's AirPods Pro").count == 2)
    #expect(DeviceArtwork.candidateFiles(forDeviceNamed: "AirPods Max").first?.hasPrefix("B515d") == true)
    #expect(DeviceArtwork.candidateFiles(forDeviceNamed: "AirPods").first?.hasPrefix("B768") == true)
    #expect(DeviceArtwork.candidateFiles(forDeviceNamed: "airpods max") == DeviceArtwork.candidateFiles(forDeviceNamed: "AIRPODS MAX"),
            "case-insensitive")
}

@Test func nonAirPodsDevicesHaveNoRender() {
    #expect(DeviceArtwork.candidateFiles(forDeviceNamed: "Sony WH-1000XM5").isEmpty)
    #expect(DeviceArtwork.candidateFiles(forDeviceNamed: "MacBook Air Speakers").isEmpty)
    #expect(DeviceArtwork.candidateFiles(forDeviceNamed: "Beats Studio Pro").isEmpty, "no Beats render ships on the system")
}

@Test func loadFallsBackThroughCandidatesAndToNil() throws {
    // A fake root with only the SECOND AirPods Pro candidate present.
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ledge-artwork-\(UUID().uuidString)")
    let fallback = root.appendingPathComponent("B698_Translate.ca/assets")
    try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: fallback.appendingPathComponent("AirPodsPro1-2_translator_996x702.png"))
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(DeviceArtwork.load(forDeviceNamed: "AirPods Pro", root: root.path) == Data([0x89, 0x50, 0x4E, 0x47]),
            "the missing preferred file is skipped, the present fallback is used")
    #expect(DeviceArtwork.load(forDeviceNamed: "AirPods Max", root: root.path) == nil,
            "nothing present means nil, never a crash — the ear falls back to the glyph")
    #expect(DeviceArtwork.load(forDeviceNamed: "Sony", root: root.path) == nil)
}

/// Pinned against THIS machine so a macOS update that moves the renders is
/// noticed here rather than as a silently glyph-only island.
@Test func theRendersExistOnThisSystem() {
    for name in ["AirPods Pro", "AirPods Max", "AirPods"] {
        #expect(DeviceArtwork.load(forDeviceNamed: name) != nil, "\(name) render missing from HeadphoneAssets.framework")
    }
}
