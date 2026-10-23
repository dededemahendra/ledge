import Foundation

/// Reads a Claude Code transcript line (JSONL) for the one thing the hooks
/// do not report: the user pressing esc.
public enum AgentTranscript {
    public static let markers: Set<String> = ["[Request interrupted by user]", "[Request interrupted by user for tool use]"]

    /// A `user` line whose content is exactly a marker, or holds a `text` item that is exactly one.
    public static func isInterrupt(_ line: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "user",
              let message = object["message"] as? [String: Any] else { return false }
        if let text = message["content"] as? String { return markers.contains(text) }
        guard let items = message["content"] as? [[String: Any]] else { return false }
        return items.contains { item in
            item["type"] as? String == "text" && (item["text"] as? String).map(markers.contains) == true
        }
    }
}
