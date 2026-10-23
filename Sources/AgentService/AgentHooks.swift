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

    /// Takes Ledge's hooks out of a list of groups; groups emptied by that go too.
    private static func strip(groups: [OrderedJSON]) -> (groups: [OrderedJSON], touched: Bool) {
        var out: [OrderedJSON] = []
        var touched = false
        for group in groups {
            guard case .object(var members) = group,
                  let gi = members.lastIndex(where: { $0.key == "hooks" }),
                  case .array(let hooks) = members[gi].value else { out.append(group); continue }
            let kept = hooks.filter { !isLedge($0) }
            if kept.count == hooks.count { out.append(group); continue }
            touched = true
            if kept.isEmpty { continue }
            members[gi].value = .array(kept)
            out.append(.object(members))
        }
        return (out, touched)
    }

    /// Takes Ledge's hooks out of every group of every event, then the groups, events and
    /// `hooks` that became empty because of it.
    public static func removing(from settings: OrderedJSON) -> OrderedJSON {
        guard case .object(var top) = settings,
              let hi = top.lastIndex(where: { $0.key == "hooks" }),
              case .object(let events) = top[hi].value else { return settings }
        var newEvents: [(key: String, value: OrderedJSON)] = []
        for event in events {
            guard case .array(let groups) = event.value else { newEvents.append(event); continue }
            let (kept, touched) = strip(groups: groups)
            if touched && kept.isEmpty { continue }
            newEvents.append((key: event.key, value: touched ? .array(kept) : event.value))
        }
        if newEvents.isEmpty && !events.isEmpty {
            top.remove(at: hi)
        } else {
            top[hi].value = .object(newEvents)
        }
        return .object(top)
    }

    private static func holdsLedge(_ group: OrderedJSON) -> Bool {
        guard case .array(let hooks)? = group["hooks"] else { return false }
        return hooks.contains(where: isLedge)
    }

    private static func holdsOnlyLedge(_ group: OrderedJSON) -> Bool {
        guard case .array(let hooks)? = group["hooks"] else { return false }
        return !hooks.isEmpty && hooks.allSatisfy(isLedge)
    }

    /// Ledge's group keeps its place when it is alone in its group; otherwise it goes last.
    public static func installing(into settings: OrderedJSON, helper: String) -> OrderedJSON {
        guard case .object(var top) = settings else { return settings }
        var hooksIndex = top.lastIndex { $0.key == "hooks" }
        if hooksIndex == nil {
            top.append((key: "hooks", value: .object([])))
            hooksIndex = top.count - 1
        }
        guard let hi = hooksIndex, case .object(var evs) = top[hi].value else { return .object(top) }

        // Events outside the ten: take Ledge out, dropping what it empties.
        var rebuilt: [(key: String, value: OrderedJSON)] = []
        for ev in evs {
            guard !events.contains(ev.key), case .array(let groups) = ev.value else { rebuilt.append(ev); continue }
            let (kept, touched) = strip(groups: groups)
            if touched && kept.isEmpty { continue }
            rebuilt.append(touched ? (key: ev.key, value: .array(kept)) : ev)
        }
        evs = rebuilt

        for event in events {
            let group = ledgeGroup(event: event, helper: helper)
            guard let ei = evs.lastIndex(where: { $0.key == event }), case .array(var groups) = evs[ei].value else {
                evs.removeAll { $0.key == event }
                evs.append((key: event, value: .array([group])))
                continue
            }
            let mine = groups.indices.filter { holdsLedge(groups[$0]) }
            if mine.count == 1, holdsOnlyLedge(groups[mine[0]]) {
                groups[mine[0]] = group
            } else {
                groups = strip(groups: groups).groups
                groups.append(group)
            }
            evs[ei].value = .array(groups)
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

    /// The file itself: a symlinked settings.json stays a link and its target gets the change.
    private var target: URL { url.resolvingSymlinksInPath() }

    private var backupURL: URL { target.appendingPathExtension("ledge-backup") }

    /// Missing file: nil. Otherwise the original bytes and what they parse to.
    private func read() throws(Problem) -> (data: Data, json: OrderedJSON)? {
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        let data: Data
        do { data = try Data(contentsOf: target) } catch { throw .unreadable(error.localizedDescription) }
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
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let original, !fm.fileExists(atPath: backupURL.path) {
                try original.write(to: backupURL, options: .atomic)
            }
            try json.written().write(to: target, options: .atomic)
        } catch {
            throw .unreadable(error.localizedDescription)
        }
    }
}
