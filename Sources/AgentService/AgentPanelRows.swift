import Foundation
import CallService

/// One session on the card (2026-10-23).
public struct AgentRow: Sendable, Equatable, Identifiable {
    public enum Mark: Sendable, Equatable {
        case waiting(String), working(since: Date), done(at: Date), failed(String), idle
    }
    public let id: String
    public let name: String
    public let host: CallAppInfo?
    public let mark: Mark
}

public enum AgentPanelRows {
    /// In the sessions' order.
    public static func make(_ sessions: [AgentSession]) -> [AgentRow] {
        sessions.map { s in
            let mark: AgentRow.Mark
            switch s.state {
            case .waiting(let w): mark = .waiting(AgentNotice.detail(w))
            case .working: mark = .working(since: s.turnStart ?? s.stateSince)
            case .finished: mark = .done(at: s.stateSince)
            case .failed(let r): mark = .failed(AgentNotice.reason(r))
            case .idle: mark = .idle
            }
            return AgentRow(id: s.id, name: s.name, host: s.host, mark: mark)
        }
    }
}
