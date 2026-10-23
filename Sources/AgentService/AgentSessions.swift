import Foundation
import AgentWire
import CallService

/// What Ledge learned about a message's process, resolved outside the machine.
public struct AgentFacts: Sendable, Equatable {
    public let claudePID: Int32?
    public let isHeadless: Bool
    public let host: CallAppInfo?
    public init(claudePID: Int32?, isHeadless: Bool, host: CallAppInfo?) {
        self.claudePID = claudePID
        self.isHeadless = isHeadless
        self.host = host
    }
}

public struct AgentSession: Sendable, Equatable, Identifiable {
    public enum Waiting: Sendable, Equatable {
        case permission(String)
        case question(String?)
        case plan
        case input(String?)
    }
    public enum State: Sendable, Equatable {
        case idle, working, waiting(Waiting), finished(took: TimeInterval), failed(reason: String)
    }
    public let id: String
    public var name: String
    /// The name before any " 2" suffix, so a clash can be re-resolved.
    var baseName: String
    public var project: String
    public var transcript: String?
    public var host: CallAppInfo?
    public var claudePID: Int32?
    public var state: State
    public var stateSince: Date
    public var turnStart: Date?
    public var lastStamp: Int64
    public var lastEvent: Date
    /// What a working session is doing now ("Thinking", "Running make test").
    public var action: String?
    /// True when `action` is a shell command, which is drawn monospaced.
    public var actionIsCommand: Bool

    /// A session as a preview or a test sample (2026-10-23).
    public init(id: String, name: String, project: String, state: AgentSession.State,
                stateSince: Date = Date(), turnStart: Date? = nil) {
        let shown = AgentNames.display(name)
        self.id = id
        self.name = shown
        self.baseName = shown
        self.project = project
        self.transcript = nil
        self.host = nil
        self.claudePID = nil
        self.state = state
        self.stateSince = stateSince
        self.turnStart = turnStart
        self.lastStamp = 0
        self.lastEvent = stateSince
        self.action = nil
        self.actionIsCommand = false
    }

    init(id: String, name: String, baseName: String, project: String, transcript: String?, host: CallAppInfo?,
         claudePID: Int32?, state: State, stateSince: Date, turnStart: Date?, lastStamp: Int64, lastEvent: Date,
         action: String? = nil, actionIsCommand: Bool = false) {
        self.id = id
        self.name = name
        self.baseName = baseName
        self.project = project
        self.transcript = transcript
        self.host = host
        self.claudePID = claudePID
        self.state = state
        self.stateSince = stateSince
        self.turnStart = turnStart
        self.lastStamp = lastStamp
        self.lastEvent = lastEvent
        self.action = action
        self.actionIsCommand = actionIsCommand
    }
}

public enum AgentMoment: Sendable, Equatable {
    case waiting(AgentSession), finished(AgentSession), failed(AgentSession)
}

/// The per-session state machine (2026-10-23). Pure: no clock, no processes.
public struct AgentSessions: Sendable, Equatable {
    public static let forgetAfter: TimeInterval = 3600
    private static let waitingNotifications: Set<String> = [
        "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input",
    ]
    private static let handled: Set<String> = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "Notification", "Stop", "StopFailure",
    ]

    public init() {}

    /// Most recently active first.
    public private(set) var sessions: [AgentSession] = []

    public mutating func apply(_ message: AgentMessage, facts: AgentFacts, now: Date) -> AgentMoment? {
        let existing = sessions.firstIndex { $0.id == message.session }
        if message.event == "SessionEnd" {
            if let existing { sessions.remove(at: existing) }
            return nil
        }
        guard !facts.isHeadless, Self.handled.contains(message.event) else { return nil }

        var session: AgentSession
        var needsName = existing == nil
        if let existing {
            session = sessions[existing]
            if message.stamp < session.lastStamp { return nil }
        } else {
            let base = Self.baseName(message)
            session = AgentSession(id: message.session, name: base, baseName: base,
                                   project: Self.projectName(message), transcript: message.transcript,
                                   host: nil, claudePID: nil, state: .idle, stateSince: now,
                                   turnStart: nil, lastStamp: message.stamp, lastEvent: now)
        }

        session.lastStamp = message.stamp
        session.lastEvent = now
        if let transcript = message.transcript { session.transcript = transcript }
        if let host = facts.host { session.host = host }
        if let pid = facts.claudePID { session.claudePID = pid }
        if let title = message.title.map(AgentNames.display), title != session.baseName {
            session.baseName = title
            needsName = true
        }

        let moment = transition(&session, message, now: now)

        sessions.removeAll { $0.id == session.id }
        if needsName { session.name = Self.freeName(for: session.baseName, among: sessions) }
        sessions.append(session)
        sortSessions()
        return moment.map { $0(session) }
    }

    public mutating func interrupt(session id: String, now: Date) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].state = .idle
        sessions[i].stateSince = now
        sessions[i].turnStart = nil
        sessions[i].action = nil
        sessions[i].actionIsCommand = false
    }

    public mutating func processExited(_ pid: Int32) {
        sessions.removeAll { $0.claudePID == pid }
    }

    public mutating func forget(now: Date) {
        sessions.removeAll { session in
            switch session.state {
            case .working, .waiting: false
            case .idle, .finished, .failed: now.timeIntervalSince(session.stateSince) >= Self.forgetAfter
            }
        }
    }

    /// Sessions working or waiting, by id, with their transcript paths.
    public var transcriptsToWatch: [String: String] {
        var out: [String: String] = [:]
        for s in sessions {
            guard let path = s.transcript else { continue }
            switch s.state {
            case .working, .waiting: out[s.id] = path
            case .idle, .finished, .failed: break
            }
        }
        return out
    }

    public var claudePIDs: Set<Int32> { Set(sessions.compactMap(\.claudePID)) }

    // MARK: - The table

    private func transition(_ s: inout AgentSession, _ m: AgentMessage, now: Date) -> ((AgentSession) -> AgentMoment)? {
        switch m.event {
        case "SessionStart":
            set(&s, .idle, now: now)
            s.turnStart = nil
            clearAction(&s)
        case "UserPromptSubmit":
            set(&s, .working, now: now)
            s.turnStart = now
            s.action = "Thinking"
            s.actionIsCommand = false
        case "PreToolUse":
            if m.tool == "AskUserQuestion" || m.tool == "ExitPlanMode" { return wait(&s, m, now: now) }
            work(&s, now: now)
            s.action = AgentNotice.action(tool: m.tool, summary: m.summary)
            s.actionIsCommand = m.tool == "Bash"
        case "PostToolUse", "PostToolUseFailure":
            work(&s, now: now)
        case "PermissionRequest":
            return wait(&s, m, now: now)
        case "Notification":
            guard let kind = m.notification, Self.waitingNotifications.contains(kind) else { return nil }
            // Already waiting: keep the existing detail, which (e.g. "Bash: make test") is more specific than the notification's text.
            if case .waiting = s.state { return nil }
            enter(&s, .waiting(.input(m.message)), now: now)
            return { .waiting($0) }
        case "Stop":
            switch s.state {
            case .finished, .failed: return nil
            default: break
            }
            let took = now.timeIntervalSince(s.turnStart ?? s.stateSince)
            set(&s, .finished(took: took), now: now)
            s.turnStart = nil
            clearAction(&s)
            return { .finished($0) }
        case "StopFailure":
            switch s.state {
            case .finished, .failed: return nil
            default: break
            }
            set(&s, .failed(reason: m.error ?? ""), now: now)
            s.turnStart = nil
            clearAction(&s)
            return { .failed($0) }
        default:
            break
        }
        return nil
    }

    private func wait(_ s: inout AgentSession, _ m: AgentMessage, now: Date) -> ((AgentSession) -> AgentMoment)? {
        let kind: AgentSession.Waiting
        switch m.tool {
        case "AskUserQuestion": kind = .question(m.summary)
        case "ExitPlanMode": kind = .plan
        default:
            let tool = m.tool ?? "Claude"
            kind = .permission(m.summary.map { tool + ": " + $0 } ?? tool)
        }
        return enter(&s, .waiting(kind), now: now)
    }

    /// Enter waiting; a moment only when coming from a state that was not waiting.
    @discardableResult
    private func enter(_ s: inout AgentSession, _ state: AgentSession.State, now: Date) -> ((AgentSession) -> AgentMoment)? {
        var wasWaiting = false
        if case .waiting = s.state { wasWaiting = true }
        if s.turnStart == nil { s.turnStart = now }
        if wasWaiting {
            s.state = state
            return nil
        }
        set(&s, state, now: now)
        return { .waiting($0) }
    }

    private func clearAction(_ s: inout AgentSession) {
        s.action = nil
        s.actionIsCommand = false
    }

    private func work(_ s: inout AgentSession, now: Date) {
        set(&s, .working, now: now)
        if s.turnStart == nil { s.turnStart = now }
    }

    private func set(_ s: inout AgentSession, _ state: AgentSession.State, now: Date) {
        if s.state != state { s.stateSince = now }
        s.state = state
    }

    // MARK: - Names and order

    private static func projectName(_ m: AgentMessage) -> String {
        let path = m.project ?? m.cwd ?? ""
        return (path as NSString).lastPathComponent
    }

    private static func baseName(_ m: AgentMessage) -> String {
        if let title = m.title { return AgentNames.display(title) }
        return AgentNames.display(projectName(m))
    }

    private static func freeName(for base: String, among others: [AgentSession]) -> String {
        let taken = Set(others.map(\.name))
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// Newest `lastEvent` first; on a tie the session just applied goes behind the others.
    private mutating func sortSessions() {
        sessions = sessions.enumerated().sorted { a, b in
            a.element.lastEvent != b.element.lastEvent ? a.element.lastEvent > b.element.lastEvent : a.offset < b.offset
        }.map(\.element)
    }
}
