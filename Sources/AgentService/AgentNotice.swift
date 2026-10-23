import Foundation
import AgentWire

/// How one agent moment looks on the island (2026-10-23).
public struct AgentBlip: Sendable, Equatable {
    public let sessionID: String
    public let title: String
    /// The trailing ear's word.
    public let word: String
    /// An Apple system colour by name (`SystemTint`).
    public let tintName: String
    /// "name · detail".
    public let caption: String
    public let ttl: TimeInterval
}

public enum AgentNotice {
    /// Claude's orange, #D97757.
    public static let orange = (red: 0.851, green: 0.467, blue: 0.341)
    public static let waitingTintName = "yellow"

    public static func blip(for moment: AgentMoment) -> AgentBlip {
        switch moment {
        case .waiting(let s):
            guard case .waiting(let waiting) = s.state else { return plain(s, "Waiting", "Waiting", "yellow", 8) }
            let word: String
            switch waiting {
            case .permission: word = "Allow?"
            case .question: word = "Question"
            case .plan: word = "Plan"
            case .input: word = "Waiting"
            }
            return AgentBlip(sessionID: s.id, title: "Waiting · \(s.name)", word: word, tintName: waitingTintName,
                             caption: "\(s.name) · \(detail(waiting))", ttl: 8)
        case .finished(let s):
            guard case .finished(let took) = s.state else { return plain(s, "Done", "Done", "green", 3) }
            return AgentBlip(sessionID: s.id, title: "Done · \(s.name)", word: "Done", tintName: "green",
                             caption: "\(s.name) · \(duration(took))", ttl: 3)
        case .failed(let s):
            guard case .failed(let error) = s.state else { return plain(s, "Failed", "Failed", "red", 3) }
            return AgentBlip(sessionID: s.id, title: "Failed · \(s.name)", word: "Failed", tintName: "red",
                             caption: "\(s.name) · \(reason(error))", ttl: 3)
        }
    }

    public static func detail(_ waiting: AgentSession.Waiting, home: String = AgentSocket.home.path) -> String {
        let text: String
        switch waiting {
        case .permission(let what): text = what
        case .question(let q): text = q ?? "Asks a question"
        case .plan: text = "Plan ready"
        case .input(let message): text = message ?? "Needs you"
        }
        return shortened(text, home: home)
    }

    /// The home folder as "~" (2026-10-23): "/Users/x/Developer/a" → "~/Developer/a".
    /// Only a whole path component matches: "/Users/xy/a" stays.
    public static func shortened(_ text: String, home: String = AgentSocket.home.path) -> String {
        var home = home
        while home.count > 1, home.hasSuffix("/") { home.removeLast() }
        guard home.count > 1, text.contains(home) else { return text }
        let pathChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        var out = ""
        var rest = Substring(text)
        while let r = rest.range(of: home) {
            out += rest[..<r.lowerBound]
            let next = rest[r.upperBound...].unicodeScalars.first
            if let next, pathChars.contains(next) {
                out += home
            } else {
                out += "~"
            }
            rest = rest[r.upperBound...]
        }
        return out + rest
    }

    /// Claude's error code in words.
    public static func reason(_ error: String) -> String {
        switch error {
        case "rate_limit": "Rate limited"
        case "overloaded": "Overloaded"
        case "authentication_failed": "Signed out"
        case "billing_error": "Billing"
        default: "API error"
        }
    }

    /// What a tool call reads as while it runs ("Running make test").
    public static func action(tool: String?, summary: String?, home: String = AgentSocket.home.path) -> String {
        guard let tool else { return "Thinking" }
        let summary = summary.map { shortened($0, home: home) }
        func with(_ verb: String, _ fallback: String) -> String { summary.map { "\(verb) \($0)" } ?? fallback }
        switch tool {
        case "Bash": return with("Running", "Running a command")
        case "Edit", "MultiEdit", "NotebookEdit": return with("Editing", "Editing a file")
        case "Write": return with("Writing", "Writing a file")
        case "Read": return with("Reading", "Reading a file")
        case "Grep", "Glob": return with("Searching", "Searching")
        case "WebFetch": return with("Fetching", "Fetching a page")
        case "WebSearch": return with("Searching the web for", "Searching the web")
        case "Agent", "Task": return "Running a subagent"
        case "TodoWrite": return "Planning"
        default:
            if tool.hasPrefix("mcp__") { return summary ?? "Using a tool" }
            return "Using \(tool)"
        }
    }

    /// "45s", "3m 20s", "3m", "1h 4m", "1h".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 60 { return "\(total)s" }
        if total < 3600 {
            let (m, s) = (total / 60, total % 60)
            return s == 0 ? "\(m)m" : "\(m)m \(s)s"
        }
        let (h, m) = (total / 3600, total % 3600 / 60)
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// A moment whose session no longer carries its state: just the name.
    private static func plain(_ s: AgentSession, _ title: String, _ word: String, _ tint: String,
                              _ ttl: TimeInterval) -> AgentBlip {
        AgentBlip(sessionID: s.id, title: "\(title) · \(s.name)", word: word, tintName: tint, caption: s.name, ttl: ttl)
    }
}
