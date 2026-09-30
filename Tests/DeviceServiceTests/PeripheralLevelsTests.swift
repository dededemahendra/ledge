import Testing
import Foundation
@testable import DeviceService

@Test func registryKeysBecomeLevelsAndUnknownsAreDropped() {
    let pods = PeripheralLevels.parse(properties: ["Product": "AirPods Pro", "BatteryPercentLeft": 90, "BatteryPercentRight": 85, "BatteryPercentCase": 60])
    #expect(pods == PeripheralLevels(left: 90, right: 85, case: 60))
    #expect(pods?.hasBuds == true)
    let mouse = PeripheralLevels.parse(properties: ["Product": "Magic Mouse", "BatteryPercent": 40])
    #expect(mouse == PeripheralLevels(main: 40))
    #expect(PeripheralLevels.parse(properties: ["BatteryPercentLeft": 255, "BatteryPercentCase": -1]) == nil, "the driver's unknowns are not levels")
    #expect(PeripheralLevels.parse(properties: ["Product": "Keyboard"]) == nil)
}

@Test func theProfilerJSONIsRead() {
    let json = """
    {"SPBluetoothDataType":[{"controller_properties":{"x":1},
      "device_connected":[{"Dede's AirPods Pro":{"device_batteryLevelLeft":"90%","device_batteryLevelRight":"85%","device_batteryLevelCase":"60%","device_minorType":"Headphones"}},
                          {"Galaxy Buds2":{"device_batteryLevelMain":"73%","device_minorType":"Headset"}}],
      "device_not_connected":[{"JBL Charge 5":{"device_minorType":"Speaker"}}]}]}
    """.data(using: .utf8)!
    let devices = BluetoothProfile.parse(json: json)
    #expect(devices.count == 3)
    #expect(devices.first { $0.name == "Dede's AirPods Pro" }?.levels == PeripheralLevels(left: 90, right: 85, case: 60))
    #expect(devices.first { $0.name == "Galaxy Buds2" }?.levels == PeripheralLevels(main: 73))
    #expect(devices.first { $0.name == "JBL Charge 5" }?.levels == nil)
    #expect(devices.first { $0.name == "JBL Charge 5" }?.isConnected == false)
    #expect(BluetoothProfile.parse(json: Data("nope".utf8)).isEmpty)
}

@Test func budsBecomeThreeReadingsWithTheProductsOwnGlyphs() {
    let pro = DeviceEvent.outputChanged(name: "Dede's AirPods Pro", transport: .bluetooth, battery: PeripheralLevels(left: 90, right: 85, case: 60))
    #expect(pro.compactText == nil, "buds use the readings, not one figure")
    #expect(pro.parts == [
        .init(symbolName: "airpodpro.left", text: "90"),
        .init(symbolName: "airpodpro.right", text: "85"),
        .init(symbolName: "airpodspro.chargingcase.wireless", text: "60"),
    ])
    let plain = DeviceEvent.outputChanged(name: "AirPods", transport: .bluetooth, battery: PeripheralLevels(left: 50, right: 48))
    #expect(plain.parts?.map(\.symbolName) == ["airpod.gen3.left", "airpod.gen3.right"], "no case reported: no case shown")
    let buds = DeviceEvent.outputChanged(name: "Galaxy Buds2", transport: .bluetooth, battery: PeripheralLevels(left: 70, right: 65, case: 40))
    #expect(buds.parts == [.init(symbolName: nil, text: "L 70"), .init(symbolName: nil, text: "R 65"), .init(symbolName: nil, text: "Case 40")])
    #expect(buds.symbolName == "earbuds")
    let single = DeviceEvent.outputChanged(name: "Galaxy Buds2", transport: .bluetooth, battery: PeripheralLevels(main: 73))
    #expect(single.parts == nil && single.compactText == "73%")
    #expect(DeviceEvent.glyph(name: "Beats Fit Pro", transport: .bluetooth) == "beats.fitpro")
    #expect(DeviceEvent.glyph(name: "Redmi Buds 4", transport: .bluetooth) == "earbuds")
}
