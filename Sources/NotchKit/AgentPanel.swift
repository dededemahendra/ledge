import Foundation

/// What the open island's Agents card lists (2026-10-23): a hero for the
/// session most worth a look, then a row for each of the others. Built by
/// `AppModel` from the agent monitor's sessions; pure here, so NotchKit
/// stays free of the service.
public struct AgentPanelData: Sendable, Equatable {
    public struct Hero: Sendable, Equatable {
        public enum Kind: Sendable, Equatable { case needsYou, failed, working }
        public let id: String
        public let kind: Kind
        public let name: String
        /// The host app's icon as PNG.
        public let icon: Data?
        public let detail: String
        /// True when the detail is a shell command (drawn monospaced).
        public let isCommand: Bool
        public let since: Date?
        /// `ledge://agent/<session id, percent-encoded>`.
        public let url: URL

        public init(id: String, kind: Kind, name: String, icon: Data?, detail: String,
                    isCommand: Bool, since: Date?, url: URL) {
            self.id = id
            self.kind = kind
            self.name = name
            self.icon = icon
            self.detail = detail
            self.isCommand = isCommand
            self.since = since
            self.url = url
        }
    }

    public struct Row: Sendable, Equatable, Identifiable {
        public enum Mark: Sendable, Equatable {
            case waiting(String, since: Date)
            case working(String, since: Date)
            /// The text is already "Done in 3m 20s", or "Done" when the length is unknown.
            case done(String, at: Date)
            /// The text is already "Rate limited".
            case failed(String, at: Date)
            case idle
        }
        public let id: String
        public let name: String
        public let mark: Mark
        public let url: URL

        public init(id: String, name: String, mark: Mark, url: URL) {
            self.id = id
            self.name = name
            self.mark = mark
            self.url = url
        }
    }

    public let hero: Hero?
    public let rows: [Row]

    public init(hero: Hero?, rows: [Row]) {
        self.hero = hero
        self.rows = rows
    }
}
