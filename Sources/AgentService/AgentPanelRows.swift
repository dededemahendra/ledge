import Foundation
import CallService

/// The card's lead session (2026-10-23): the one most worth a look.
public struct AgentHero: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case needsYou, failed, working }
    public let id: String
    public let name: String
    public let host: CallAppInfo?
    public let kind: Kind
    public let detail: String
    /// True when the detail is a shell command (drawn monospaced).
    public let isCommand: Bool
    /// needsYou: waiting since; working: turn start; failed: nil.
    public let since: Date?
}

/// One of the other sessions on the card.
public struct AgentRow: Sendable, Equatable, Identifiable {
    public enum Mark: Sendable, Equatable {
        case waiting(detail: String, since: Date)
        case working(action: String, since: Date)
        case done(took: TimeInterval, at: Date)
        case failed(reason: String, at: Date)
        case idle
    }
    public let id: String
    public let name: String
    public let host: CallAppInfo?
    public let mark: Mark
}

public struct AgentCard: Sendable, Equatable {
    public let hero: AgentHero?
    /// The hero's session excluded.
    public let rows: [AgentRow]
}

public enum AgentPanelRows {
    /// A failure stays the hero this long.
    static let failedHeroWindow: TimeInterval = 600

    /// While any session is waiting or working, the rows leave out done and idle ones (2026-10-23).
    public static func card(_ sessions: [AgentSession], now: Date) -> AgentCard {
        let hero = pickHero(sessions, now: now)
        let live = sessions.contains {
            switch $0.state {
            case .waiting, .working: true
            default: false
            }
        }
        let rest = sessions.filter { s in
            if s.id == hero?.id { return false }
            if live {
                switch s.state {
                case .finished, .idle: return false
                default: break
                }
            }
            return true
        }
        let ordered = rest.enumerated().sorted { a, b in
            let (ga, gb) = (group(a.element), group(b.element))
            if ga != gb { return ga < gb }
            if a.element.lastEvent != b.element.lastEvent { return a.element.lastEvent > b.element.lastEvent }
            return a.offset < b.offset
        }.map(\.element)
        return AgentCard(hero: hero, rows: ordered.map(row))
    }

    private static func group(_ s: AgentSession) -> Int {
        switch s.state {
        case .waiting: 0
        case .working: 1
        case .failed: 2
        case .finished: 3
        case .idle: 4
        }
    }

    private static func pickHero(_ sessions: [AgentSession], now: Date) -> AgentHero? {
        let waiting = sessions.filter { if case .waiting = $0.state { true } else { false } }
        if let s = waiting.min(by: { $0.stateSince < $1.stateSince }), case .waiting(let w) = s.state {
            let text = AgentNotice.detail(w)
            var isCommand = false
            if case .permission(let what) = w, what.hasPrefix("Bash: ") { isCommand = true }
            return AgentHero(id: s.id, name: s.name, host: s.host, kind: .needsYou, detail: text,
                             isCommand: isCommand, since: s.stateSince)
        }
        let failed = sessions.filter {
            if case .failed = $0.state { return now.timeIntervalSince($0.stateSince) < failedHeroWindow }
            return false
        }
        if let s = failed.max(by: { $0.stateSince < $1.stateSince }), case .failed(let code) = s.state {
            return AgentHero(id: s.id, name: s.name, host: s.host, kind: .failed, detail: AgentNotice.reason(code),
                             isCommand: false, since: nil)
        }
        let working = sessions.filter { $0.state == .working }
        if let s = working.min(by: { ($0.turnStart ?? $0.stateSince) < ($1.turnStart ?? $1.stateSince) }) {
            let action = s.action ?? "Thinking"
            return AgentHero(id: s.id, name: s.name, host: s.host, kind: .working, detail: action,
                             isCommand: s.actionIsCommand && action.hasPrefix("Running "),
                             since: s.turnStart ?? s.stateSince)
        }
        return nil
    }

    private static func row(_ s: AgentSession) -> AgentRow {
        let mark: AgentRow.Mark
        switch s.state {
        case .waiting(let w): mark = .waiting(detail: AgentNotice.detail(w), since: s.stateSince)
        case .working: mark = .working(action: s.action ?? "Thinking", since: s.turnStart ?? s.stateSince)
        case .finished(let took): mark = .done(took: took, at: s.stateSince)
        case .failed(let r): mark = .failed(reason: AgentNotice.reason(r), at: s.stateSince)
        case .idle: mark = .idle
        }
        return AgentRow(id: s.id, name: s.name, host: s.host, mark: mark)
    }
}
