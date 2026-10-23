import Foundation

/// How a session's name reads on the island (2026-10-23): sentence case
/// without hyphens, underscores or dots.
public enum AgentNames {
    /// Runs of `-`, `_` and `.` become a space, whitespace collapses, the first
    /// character is uppercased and the rest stays as typed; empty is "Claude".
    public static func display(_ raw: String) -> String {
        var out = ""
        var pendingSpace = false
        for ch in raw {
            if ch == "-" || ch == "_" || ch == "." || ch.isWhitespace {
                pendingSpace = true
                continue
            }
            if pendingSpace, !out.isEmpty { out.append(" ") }
            pendingSpace = false
            out.append(ch)
        }
        guard let first = out.first else { return "Claude" }
        return first.uppercased() + out.dropFirst()
    }
}
