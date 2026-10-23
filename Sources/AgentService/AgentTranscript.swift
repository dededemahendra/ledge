import Foundation

/// Reads a Claude Code transcript line (JSONL) for the one thing the hooks
/// do not report: the user pressing esc.
public enum AgentTranscript {
    public static let markers: Set<String> = ["[Request interrupted by user]", "[Request interrupted by user for tool use]"]
    /// What every marker starts with, as bytes.
    static let markerPrefix = Data("[Request interrupted by user".utf8)

    /// Whether the line holds the markers' bytes at all; only such a line is parsed (2026-10-23),
    /// so a transcript's long lines (a big file read, a long answer) cost a byte search.
    static func mentionsInterrupt(_ line: Data) -> Bool {
        line.range(of: markerPrefix) != nil
    }

    /// A `user` line whose content is exactly a marker, or holds a `text` item that is exactly one.
    public static func isInterrupt(_ line: Data) -> Bool {
        guard mentionsInterrupt(line), let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "user",
              let message = object["message"] as? [String: Any] else { return false }
        if let text = message["content"] as? String { return markers.contains(text) }
        guard let items = message["content"] as? [[String: Any]] else { return false }
        return items.contains { item in
            item["type"] as? String == "text" && (item["text"] as? String).map(markers.contains) == true
        }
    }
}
