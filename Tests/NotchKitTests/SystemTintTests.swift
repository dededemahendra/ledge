import Testing
import AppKit
@testable import NotchKit

@Test func systemColourNamesResolveInBothSpellings() {
    #expect(SystemTint.color(named: "systemIndigoColor") == .systemIndigo)
    #expect(SystemTint.color(named: "indigo") == .systemIndigo)
    #expect(SystemTint.color(named: "SystemTealColor") == .systemTeal)
    #expect(SystemTint.color(named: "systemGrayColor") == .systemGray)
    #expect(SystemTint.color(named: "chartreuse") == nil, "unknown: the island's white")
}
