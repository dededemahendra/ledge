import Foundation

/// One line from a Claude Code hook to the app (2026-10-23). Foundation only,
/// because the helper that sends it links this library too.
public struct AgentMessage: Codable, Sendable, Equatable {
    public var v: Int
    public var event: String
    public var session: String
    public var cwd: String?
    public var project: String?
    public var transcript: String?
    public var title: String?
    public var tool: String?
    public var summary: String?
    public var notification: String?
    public var message: String?
    public var error: String?
    public var source: String?
    public var reason: String?
    /// The subagent that sent the event (`agent_id`); nil for the main thread.
    public var agent: String?
    /// The helper process's start, from the kernel, in microseconds since 1970.
    public var stamp: Int64
    /// The helper's parents, nearest first.
    public var pids: [Int32]

    public init(event: String, session: String, stamp: Int64, pids: [Int32] = [], cwd: String? = nil,
                project: String? = nil, transcript: String? = nil, title: String? = nil, tool: String? = nil,
                summary: String? = nil, notification: String? = nil, message: String? = nil,
                error: String? = nil, source: String? = nil, reason: String? = nil, agent: String? = nil) {
        self.v = 1
        self.event = event
        self.session = session
        self.stamp = stamp
        self.pids = pids
        self.cwd = cwd
        self.project = project
        self.transcript = transcript
        self.title = title
        self.tool = tool
        self.summary = summary
        self.notification = notification
        self.message = message
        self.error = error
        self.source = source
        self.reason = reason
        self.agent = agent
    }
}
