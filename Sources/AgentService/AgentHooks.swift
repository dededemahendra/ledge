import Foundation
import Darwin

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

    /// The helper's path in single quotes for the shell, a `'` in it written `'\''` (2026-10-23).
    public static func command(helper: String) -> String {
        let quoted = "'" + helper.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "[ -x \(quoted) ] && \(quoted) || true"
    }

    /// Every `hooks` an object, and every copy of each of the ten events in it a list (2026-10-23).
    /// Anything else is someone's content Ledge can't read, and it is left alone.
    public static func hasExpectedShape(_ settings: OrderedJSON) -> Bool {
        guard case .object(let top) = settings else { return true }
        for member in top where member.key == "hooks" {
            guard case .object(let evs) = member.value else { return false }
            for ev in evs where events.contains(ev.key) {
                guard case .array = ev.value else { return false }
            }
        }
        return true
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
        guard hasExpectedShape(settings), case .object(var top) = settings,
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
    /// Settings of an unexpected shape come back unchanged.
    public static func installing(into settings: OrderedJSON, helper: String) -> OrderedJSON {
        guard hasExpectedShape(settings), case .object(var top) = settings else { return settings }
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
            guard let ei = evs.lastIndex(where: { $0.key == event }) else {
                evs.append((key: event, value: .array([group])))
                continue
            }
            // Always a list: `hasExpectedShape` turned anything else away.
            guard case .array(var groups) = evs[ei].value else { continue }
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
        /// `hooks` is not an object, or one of the ten events in it is not a list (2026-10-23).
        case unexpectedShape(String)
        case unwritable(String)
    }

    static let shapeReason = "hooks has an unexpected shape"

    public let url: URL
    /// Tests stand in for another program writing the file with these: just
    /// before Ledge reads it again to write, and just after it has written.
    var beforeRecheck: (@Sendable () -> Void)?
    var afterWrite: (@Sendable () -> Void)?

    public init(url: URL) { self.url = url }

    /// The file itself: a symlinked settings.json stays a link and its target gets the change.
    private var target: URL { url.resolvingSymlinksInPath() }

    private var backupURL: URL { target.appendingPathExtension("ledge-backup") }

    /// Missing file: nil. Otherwise the original bytes and what they parse to.
    private func read() throws(Problem) -> (data: Data, json: OrderedJSON)? {
        guard let data = try bytes() else { return nil }
        return (data, try parse(data))
    }

    /// The file's bytes; nil when it is missing.
    private func bytes() throws(Problem) -> Data? {
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        do { return try Data(contentsOf: target) } catch { throw .unreadable(error.localizedDescription) }
    }

    private func parse(_ data: Data) throws(Problem) -> OrderedJSON {
        let json: OrderedJSON
        do { json = try OrderedJSON.parse(data) } catch { throw .unreadable("\(error)") }
        guard case .object = json else { throw .notAnObject }
        return json
    }

    public func install(helper: String) throws(Problem) {
        try edit(creating: true) { AgentHooks.installing(into: $0, helper: helper) }
    }

    public func uninstall() throws(Problem) {
        try edit(creating: false) { AgentHooks.removing(from: $0) }
    }

    public func isInstalled(helper: String) -> Bool {
        guard let existing = try? read() else { return false }
        return AgentHooks.isInstalled(in: existing.json, helper: helper)
    }

    /// Reads, changes, and writes only when that changed something. Just before
    /// writing it reads the bytes again: when another program changed the file
    /// meanwhile, the change is made once more on the new bytes (2026-10-23).
    private func edit(creating: Bool, _ change: (OrderedJSON) -> OrderedJSON) throws(Problem) {
        var existing = try read()
        var rechecked = false
        while true {
            guard existing != nil || creating else { return }
            let before = existing?.json ?? .object([])
            guard AgentHooks.hasExpectedShape(before) else { throw .unexpectedShape(Self.shapeReason) }
            let after = change(before)
            if existing != nil && after == before { return }
            if !rechecked {
                rechecked = true
                beforeRecheck?()
                let now = try bytes()
                if now != existing?.data {
                    if let now { existing = (now, try parse(now)) } else { existing = nil }
                    continue
                }
            }
            try write(after, original: existing?.data)
            afterWrite?()
            return
        }
    }

    private func write(_ json: OrderedJSON, original: Data?) throws(Problem) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let original, !fm.fileExists(atPath: backupURL.path) {
                let mode = (try? fm.attributesOfItem(atPath: target.path))?[.posixPermissions] as? Int
                try writeBackup(original, mode: mode_t(mode ?? 0o600))
            }
            try json.written().write(to: target, options: .atomic)
        } catch {
            throw .unwritable(error.localizedDescription)
        }
    }

    /// The backup is created with the original's permissions (2026-10-23), so a
    /// private settings file's copy is never readable by others, even briefly.
    private func writeBackup(_ data: Data, mode: mode_t) throws {
        let path = backupURL.path
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, mode)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var failure: Int32 = fchmod(fd, mode) == 0 ? 0 : errno
        if failure == 0 {
            failure = data.withUnsafeBytes { raw -> Int32 in
                var offset = 0
                while offset < raw.count {
                    let n = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                    if n > 0 { offset += n } else if n == 0 { return EIO } else if errno != EINTR { return errno }
                }
                return 0
            }
        }
        close(fd)
        guard failure == 0 else {
            unlink(path)
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
    }
}
