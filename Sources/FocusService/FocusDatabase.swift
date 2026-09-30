import Foundation

/// One Focus as the Focus database describes it: its name, its SF Symbol
/// and Apple's name for its tint colour ("systemIndigoColor").
public struct FocusMode: Sendable, Equatable {
    public let identifier: String
    public let name: String
    public let symbolName: String?
    public let tintColorName: String?

    public init(identifier: String, name: String, symbolName: String?, tintColorName: String?) {
        self.identifier = identifier
        self.name = name
        self.symbolName = symbolName
        self.tintColorName = tintColorName
    }
}

/// Parsers for `~/Library/DoNotDisturb/DB/{Assertions,ModeConfigurations}.json`
/// (2026-09-30). Readable only with Full Disk Access — this app asks for it
/// only to show a Focus's own symbol, colour and name, and works without.
/// Layout as commonly documented, taken defensively: anything missing
/// yields `nil` rather than a guess.
public enum FocusDatabase {
    /// The active Focus's mode identifier — the first assertion record.
    public static func activeModeIdentifier(assertions: [String: Any]) -> String? {
        for entry in (assertions["data"] as? [[String: Any]]) ?? [] {
            for record in (entry["storeAssertionRecords"] as? [[String: Any]]) ?? [] {
                if let details = record["assertionDetails"] as? [String: Any],
                   let id = details["assertionDetailsModeIdentifier"] as? String {
                    return id
                }
            }
        }
        return nil
    }

    /// Every configured Focus, by identifier.
    public static func modes(configurations: [String: Any]) -> [String: FocusMode] {
        var modes: [String: FocusMode] = [:]
        for entry in (configurations["data"] as? [[String: Any]]) ?? [] {
            for (id, config) in (entry["modeConfigurations"] as? [String: Any]) ?? [:] {
                guard let config = config as? [String: Any], let mode = config["mode"] as? [String: Any] else { continue }
                let name = (mode["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Focus"
                modes[id] = FocusMode(
                    identifier: id,
                    name: name,
                    symbolName: mode["symbolImageName"] as? String,
                    tintColorName: mode["tintColorName"] as? String
                )
            }
        }
        return modes
    }
}

/// Reads and caches the two files. `nil` results mean "not readable" —
/// no Full Disk Access — and the caller falls back to sizes.
@MainActor
public final class FocusDatabaseReader {
    public static let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/DoNotDisturb/DB")
    public static let assertionsFile = directory.appending(path: "Assertions.json")
    public static let configurationsFile = directory.appending(path: "ModeConfigurations.json")

    private var modes: [String: FocusMode] = [:]
    private var modesReadAt: Date?

    public init() {}

    /// Whether the database can be read at all.
    public var isReadable: Bool {
        FileManager.default.isReadableFile(atPath: Self.assertionsFile.path)
            && (try? Data(contentsOf: Self.assertionsFile)) != nil
    }

    /// The active Focus, `nil` for none, `.some(nil)`… no: `nil` when the
    /// files cannot be read, `.some(mode)` / `.some(nil)` otherwise.
    public func activeMode() -> FocusMode?? {
        guard let assertionsData = try? Data(contentsOf: Self.assertionsFile),
              let assertions = (try? JSONSerialization.jsonObject(with: assertionsData)) as? [String: Any]
        else { return nil }
        guard let id = FocusDatabase.activeModeIdentifier(assertions: assertions) else { return .some(nil) }
        refreshModesIfNeeded()
        return .some(modes[id] ?? FocusMode(identifier: id, name: "Focus", symbolName: nil, tintColorName: nil))
    }

    private func refreshModesIfNeeded() {
        let modified = (try? FileManager.default.attributesOfItem(atPath: Self.configurationsFile.path))?[.modificationDate] as? Date
        guard modesReadAt == nil || modified != modesReadAt else { return }
        guard let data = try? Data(contentsOf: Self.configurationsFile),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }
        modes = FocusDatabase.modes(configurations: json)
        modesReadAt = modified
    }
}
