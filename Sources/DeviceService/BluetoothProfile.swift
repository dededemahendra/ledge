import Foundation

/// One Bluetooth device as `system_profiler SPBluetoothDataType` lists it.
public struct BluetoothPeripheral: Sendable, Equatable {
    public let name: String
    public let minorType: String?
    public let levels: PeripheralLevels?
    public let isConnected: Bool

    public init(name: String, minorType: String?, levels: PeripheralLevels?, isConnected: Bool) {
        self.name = name
        self.minorType = minorType
        self.levels = levels
        self.isConnected = isConnected
    }
}

/// Battery levels for peripherals the HID service does not cover — any
/// headset that reports charge over Bluetooth's hands-free profile —
/// read from `system_profiler`'s JSON (2026-09-30): `device_batteryLevelMain`,
/// `…Left`, `…Right`, `…Case` as "85%" strings under `device_connected` /
/// `device_not_connected`. A child process, a second or so, run only on a
/// Bluetooth route change and never on the main actor.
public enum BluetoothProfile {
    public static func parse(json: Data) -> [BluetoothPeripheral] {
        guard let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var devices: [BluetoothPeripheral] = []
        for section in sections {
            for (key, connected) in [("device_connected", true), ("device_not_connected", false)] {
                for entry in (section[key] as? [[String: Any]]) ?? [] {
                    for (name, value) in entry {
                        let props = value as? [String: Any] ?? [:]
                        devices.append(BluetoothPeripheral(
                            name: name,
                            minorType: props["device_minorType"] as? String,
                            levels: levels(from: props),
                            isConnected: connected
                        ))
                    }
                }
            }
        }
        return devices
    }

    static func levels(from props: [String: Any]) -> PeripheralLevels? {
        func percent(_ key: String) -> Int? {
            guard let text = props[key] as? String else { return nil }
            let digits = text.trimmingCharacters(in: CharacterSet(charactersIn: "% "))
            guard let value = Int(digits), (0...100).contains(value) else { return nil }
            return value
        }
        let levels = PeripheralLevels(
            main: percent("device_batteryLevelMain"),
            left: percent("device_batteryLevelLeft"),
            right: percent("device_batteryLevelRight"),
            case: percent("device_batteryLevelCase")
        )
        return levels.isEmpty ? nil : levels
    }

    /// Runs the profiler off the main actor and parses its output.
    public static func run() async -> [BluetoothPeripheral] {
        await Task.detached(priority: .utility) { () -> [BluetoothPeripheral] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return [] }
            let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            process.waitUntilExit()
            return parse(json: data)
        }.value
    }
}
