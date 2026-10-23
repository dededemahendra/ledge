import Foundation

/// What the open island's Agents card lists (2026-10-23): one row per
/// Claude Code session. Built by `AppModel` from the agent monitor's
/// sessions; pure here, so NotchKit stays free of the service.
public struct AgentPanelData: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public enum Mark: Sendable, Equatable {
            case waiting(String), working(since: Date), done(at: Date), failed(String), idle
        }
        public let id: String
        public let name: String
        /// The host app's icon as PNG.
        public let icon: Data?
        public let mark: Mark
        /// `ledge://agent/<session id, percent-encoded>`.
        public let url: URL

        public init(id: String, name: String, icon: Data?, mark: Mark, url: URL) {
            self.id = id
            self.name = name
            self.icon = icon
            self.mark = mark
            self.url = url
        }
    }

    public let rows: [Row]

    public init(rows: [Row]) {
        self.rows = rows
    }
}
