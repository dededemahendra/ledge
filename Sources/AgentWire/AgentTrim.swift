import Foundation

/// Turns a hook's stdin JSON into one short line (2026-10-23).
public enum AgentTrim {
    public static let maxField = 200
    public static let maxLine = 4096

    /// `nil` unless the input is a JSON object with string `session_id` and `hook_event_name`.
    public static func message(hookJSON: Data, environment: [String: String], stamp: Int64, pids: [Int32]) -> AgentMessage? {
        guard let object = (try? JSONSerialization.jsonObject(with: hookJSON)) as? [String: Any],
              let session = object["session_id"] as? String,
              let event = object["hook_event_name"] as? String else { return nil }
        func present(_ key: String) -> String? {
            guard let value = object[key] as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        func text(_ key: String) -> String? { present(key).map(cut) }
        func path(_ key: String) -> String? { present(key) }
        let cwd = path("cwd")
        var message = AgentMessage(
            event: cut(event), session: cut(session), stamp: stamp, pids: pids,
            cwd: cwd, project: environment["CLAUDE_PROJECT_DIR"] ?? cwd, transcript: path("transcript_path"),
            title: text("session_title"), tool: text("tool_name"),
            notification: text("notification_type"), message: text("message"),
            error: text("error"), source: text("source"), reason: text("reason"), agent: text("agent_id"))
        if let tool = object["tool_name"] as? String, let input = object["tool_input"] as? [String: Any] {
            message.summary = summary(tool: tool, input: input)
        }
        return message
    }

    /// One line about the tool call, or nil.
    public static func summary(tool: String, input: [String: Any]) -> String? {
        func string(_ key: String) -> String? {
            guard let value = input[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        let result: String?
        switch tool {
        case "Bash":
            result = string("command")?.split(whereSeparator: \.isNewline)
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map(String.init)
        case "Edit", "MultiEdit", "Write", "Read":
            result = string("file_path").map { ($0 as NSString).lastPathComponent }
        case "NotebookEdit":
            result = string("notebook_path").map { ($0 as NSString).lastPathComponent }
        case "Grep", "Glob":
            result = string("pattern")
        case "WebFetch":
            result = string("url").flatMap { URL(string: $0)?.host }
        case "WebSearch":
            result = string("query")
        case "Agent", "Task":
            result = string("description")
        case "AskUserQuestion":
            result = ((input["questions"] as? [[String: Any]])?.first?["question"] as? String)
        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.components(separatedBy: "__")
                result = parts.count >= 3 ? "\(parts[1]): \(parts[2...].joined(separator: "__"))" : nil
            } else {
                result = nil
            }
        }
        guard let result else { return nil }
        let short = cut(result)
        return short.isEmpty ? nil : short
    }

    /// The JSON line with its "\n", within `maxLine`, or nil when even the trimmed line is too long.
    /// Over the limit it drops `message`, then `summary`, then `title`; nothing else (`agent` included) is ever dropped.
    public static func line(_ message: AgentMessage) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var message = message
        let drops: [(inout AgentMessage) -> Void] = [
            { $0.message = nil }, { $0.summary = nil }, { $0.title = nil },
        ]
        var step = 0
        while true {
            if var data = try? encoder.encode(message) {
                data.append(0x0A)
                if data.count <= maxLine { return data }
            }
            guard step < drops.count else { return nil }
            drops[step](&message)
            step += 1
        }
    }

    /// Trimmed of surrounding whitespace, cut to `maxField` characters (199 and "…").
    public static func cut(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxField else { return trimmed }
        return String(trimmed.prefix(maxField - 1)) + "…"
    }
}
