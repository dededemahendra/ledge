import Foundation

/// Ledge's hook entries in Claude Code's settings.json.
public enum AgentHooks {
    public static let events: [String] = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd",
    ]
    public static let matcherEvents: Set<String> = [
        "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest",
    ]
    public static let marker = "Ledge/ledge-agent-hook"

    public static func command(helper: String) -> String {
        "[ -x \"\(helper)\" ] && \"\(helper)\" || true"
    }

    private static func ledgeGroup(event: String, helper: String) -> OrderedJSON {
        let hook: OrderedJSON = .object([
            (key: "type", value: .string("command")),
            (key: "command", value: .string(command(helper: helper))),
            (key: "async", value: .bool(true)),
            (key: "timeout", value: .number("5")),
        ])
        var members: [(key: String, value: OrderedJSON)] = []
        if matcherEvents.contains(event) { members.append((key: "matcher", value: .string("*"))) }
        members.append((key: "hooks", value: .array([hook])))
        return .object(members)
    }

    private static func isLedge(_ hook: OrderedJSON) -> Bool {
        guard case .string(let c)? = hook["command"] else { return false }
        return c.contains(marker)
    }

    /// Takes Ledge's hooks out of every group of every event. Groups emptied by that go too;
    /// events emptied by that go when `pruneEvents` is set (`events` keeps its place otherwise).
    private static func strip(_ settings: OrderedJSON, keepingEvents keep: Set<String>) -> OrderedJSON {
        guard case .object(var top) = settings,
              let hi = top.lastIndex(where: { $0.key == "hooks" }),
              case .object(let events) = top[hi].value else { return settings }
        var newEvents: [(key: String, value: OrderedJSON)] = []
        for event in events {
            guard case .array(let groups) = event.value else { newEvents.append(event); continue }
            var newGroups: [OrderedJSON] = []
            var touched = false
            for group in groups {
                guard case .object(var members) = group,
                      let gi = members.lastIndex(where: { $0.key == "hooks" }),
                      case .array(let hooks) = members[gi].value else { newGroups.append(group); continue }
                let kept = hooks.filter { !isLedge($0) }
                if kept.count == hooks.count { newGroups.append(group); continue }
                touched = true
                if kept.isEmpty { continue }
                members[gi].value = .array(kept)
                newGroups.append(.object(members))
            }
            if touched && newGroups.isEmpty && !keep.contains(event.key) { continue }
            newEvents.append((key: event.key, value: touched ? .array(newGroups) : event.value))
        }
        if newEvents.isEmpty && !events.isEmpty {
            top.remove(at: hi)
        } else {
            top[hi].value = .object(newEvents)
        }
        return .object(top)
    }

    public static func removing(from settings: OrderedJSON) -> OrderedJSON {
        strip(settings, keepingEvents: [])
    }

    public static func installing(into settings: OrderedJSON, helper: String) -> OrderedJSON {
        guard case .object(var top) = strip(settings, keepingEvents: Set(events)) else { return settings }
        var hooksIndex = top.lastIndex { $0.key == "hooks" }
        if hooksIndex == nil {
            top.append((key: "hooks", value: .object([])))
            hooksIndex = top.count - 1
        }
        guard let hi = hooksIndex, case .object(var evs) = top[hi].value else { return .object(top) }
        for event in events {
            let group = ledgeGroup(event: event, helper: helper)
            if let ei = evs.lastIndex(where: { $0.key == event }), case .array(var groups) = evs[ei].value {
                groups.append(group)
                evs[ei].value = .array(groups)
            } else {
                evs.append((key: event, value: .array([group])))
            }
        }
        top[hi].value = .object(evs)
        return .object(top)
    }

    /// Ledge's entries are there for all ten events and point at `helper`.
    public static func isInstalled(in settings: OrderedJSON, helper: String) -> Bool {
        let want = command(helper: helper)
        return events.allSatisfy { event in
            guard case .array(let groups)? = settings["hooks"]?[event] else { return false }
            return groups.contains { group in
                guard case .array(let hooks)? = group["hooks"] else { return false }
                return hooks.contains { $0["command"] == .string(want) }
            }
        }
    }
}

/// Reads and edits the settings file, touching only Ledge's own entries.
public struct AgentSettingsFile: Sendable {
    public enum Problem: Error, Equatable {
        case notAnObject
        case unreadable(String)
    }

    public let url: URL

    public init(url: URL) { self.url = url }

    private var backupURL: URL { url.appendingPathExtension("ledge-backup") }

    /// Missing file: nil. Otherwise the original bytes and what they parse to.
    private func read() throws(Problem) -> (data: Data, json: OrderedJSON)? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw .unreadable(error.localizedDescription) }
        let json: OrderedJSON
        do { json = try OrderedJSON.parse(data) } catch { throw .unreadable("\(error)") }
        guard case .object = json else { throw .notAnObject }
        return (data, json)
    }

    public func install(helper: String) throws(Problem) {
        let existing = try read()
        let before = existing?.json ?? .object([])
        let after = AgentHooks.installing(into: before, helper: helper)
        if existing != nil && after == before { return }
        try write(after, original: existing?.data)
    }

    public func uninstall() throws(Problem) {
        guard let existing = try read() else { return }
        let after = AgentHooks.removing(from: existing.json)
        if after == existing.json { return }
        try write(after, original: existing.data)
    }

    public func isInstalled(helper: String) -> Bool {
        guard let existing = try? read() else { return false }
        return AgentHooks.isInstalled(in: existing.json, helper: helper)
    }

    private func write(_ json: OrderedJSON, original: Data?) throws(Problem) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let original, !fm.fileExists(atPath: backupURL.path) {
                try original.write(to: backupURL, options: .atomic)
            }
            try json.written().write(to: url, options: .atomic)
        } catch {
            throw .unreadable(error.localizedDescription)
        }
    }
}
