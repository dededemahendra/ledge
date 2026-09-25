import Testing
import Foundation
@testable import PowerService

private func description(
    percent: Int = 87,
    state: String = "AC Power",
    charging: Bool = true,
    charged: Bool = false,
    timeToFull: Int = 24
) -> [String: Any] {
    [
        "Current Capacity": percent,
        "Max Capacity": 100,
        "Power Source State": state,
        "Is Charging": charging,
        "Is Charged": charged,
        "Time to Full Charge": timeToFull,
    ]
}

@Test func parsesAChargingSource() throws {
    let s = try #require(PowerSnapshot.parse(description()))
    #expect(s.percent == 87)
    #expect(s.isPluggedIn)
    #expect(s.isCharging)
    #expect(s.isCharged == false)
    #expect(s.timeToFullMinutes == 24)
}

@Test func parsesABatterySource() throws {
    let s = try #require(PowerSnapshot.parse(
        description(percent: 41, state: "Battery Power", charging: false, timeToFull: -1)
    ))
    #expect(s.percent == 41)
    #expect(s.isPluggedIn == false)
    #expect(s.isCharging == false)
    #expect(s.timeToFullMinutes == nil, "a negative estimate means unknown, not -1 minutes")
}

@Test func parsesAFullyChargedSource() throws {
    let s = try #require(PowerSnapshot.parse(
        description(percent: 100, charging: false, charged: true, timeToFull: 0)
    ))
    #expect(s.isCharged)
    #expect(s.percent == 100)
}

@Test func percentIsScaledAgainstMaxCapacity() throws {
    var d = description(percent: 40)
    d["Max Capacity"] = 80
    let s = try #require(PowerSnapshot.parse(d))
    #expect(s.percent == 50)
}

@Test func percentIsClampedToZeroAndOneHundred() throws {
    var d = description(percent: 140)
    d["Max Capacity"] = 100
    #expect(try #require(PowerSnapshot.parse(d)).percent == 100)
    d["Current Capacity"] = -5
    #expect(try #require(PowerSnapshot.parse(d)).percent == 0)
}

@Test func missingKeysYieldNilRatherThanGuesses() {
    #expect(PowerSnapshot.parse([:]) == nil)
    #expect(PowerSnapshot.parse(["Current Capacity": 50]) == nil)
    #expect(PowerSnapshot.parse(["Max Capacity": 100]) == nil)
}

@Test func zeroMaxCapacityDoesNotDivideByZero() {
    var d = description()
    d["Max Capacity"] = 0
    #expect(PowerSnapshot.parse(d) == nil)
}

@Test func unexpectedTypesDoNotCrash() {
    var d = description()
    d["Current Capacity"] = "eighty-seven"
    #expect(PowerSnapshot.parse(d) == nil)
}
