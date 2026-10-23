import Foundation
import OSLog
import AgentWire
import CallService

public struct AgentPaths: Sendable {
    public let settingsFile: URL
    public let socket: URL
    public let helper: URL
    public let helperSource: URL?

    public init(settingsFile: URL, socket: URL, helper: URL, helperSource: URL?) {
        self.settingsFile = settingsFile
        self.socket = socket
        self.helper = helper
        self.helperSource = helperSource
    }

    public static var live: AgentPaths {
        let source = Bundle.main.bundleURL.appending(path: "Contents/MacOS/ledge-agent-hook")
        return AgentPaths(
            settingsFile: AgentSocket.home.appending(path: ".claude/settings.json"),
            socket: AgentSocket.socketURL(),
            helper: AgentSocket.helperURL(),
            helperSource: FileManager.default.fileExists(atPath: source.path) ? source : nil)
    }
}

/// Claude Code sessions as Ledge sees them (2026-10-23): sets the hooks up,
/// listens, and keeps `sessions` current.
@MainActor
public final class AgentMonitor {
    public enum Status: Sendable, Equatable { case off, ready(lastHeard: Date?), problem(String) }

    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "agents")

    public private(set) var status: Status = .off
    public private(set) var sessions = AgentSessions()
    public var onMoment: ((AgentMoment) -> Void)?
    public var onChange: (() -> Void)?

    private let paths: AgentPaths
    private let host: AgentHostLookup
    private let listens: Bool
    private var listener: AgentListener?
    private lazy var watchers = AgentWatchers(
        onExit: { [weak self] pid in self?.processExited(pid) },
        onLine: { [weak self] session, line in self?.transcriptLine(session: session, line: line) })
    private var lastHeard: Date?
    private var isEnabled = false

    public init(paths: AgentPaths = .live, host: AgentHostLookup = .live, listens: Bool = true) {
        self.paths = paths
        self.host = host
        self.listens = listens
    }

    /// Copy the helper, install the hooks, listen. Idempotent; also the Repair button.
    public func enable() {
        guard let source = paths.helperSource else {
            fail("The helper is missing from Ledge.app")
            return
        }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: paths.helper.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: paths.helper)
            try fm.copyItem(at: source, to: paths.helper)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.helper.path)
        } catch {
            fail("Can't copy the helper: \(error.localizedDescription)")
            return
        }
        do {
            try AgentSettingsFile(url: paths.settingsFile).install(helper: paths.helper.path)
        } catch {
            switch error {
            case .notAnObject: fail("Can't read settings.json: it isn't a JSON object")
            case .unreadable(let reason): fail("Can't read settings.json: \(reason)")
            }
            return
        }
        if listens {
            do {
                try startListening()
            } catch {
                fail("Can't listen for sessions: \(describe(error))")
                return
            }
        }
        isEnabled = true
        status = .ready(lastHeard: lastHeard)
        Self.log.info("agents enabled")
        onChange?()
    }

    /// Stop listening and remove Ledge's hooks.
    public func disable() {
        isEnabled = false
        stopListening()
        lastHeard = nil
        do {
            try AgentSettingsFile(url: paths.settingsFile).uninstall()
        } catch {
            Self.log.error("could not remove hooks")
        }
        sessions = AgentSessions()
        status = .off
        Self.log.info("agents disabled")
        onChange?()
    }

    /// Stop listening, keep the hooks (Ledge quitting).
    public func suspend() {
        isEnabled = false
        stopListening()
        sessions = AgentSessions()
    }

    /// One line from the socket (also the tests' and the probe's way in).
    public func receive(_ line: Data, now: Date = Date()) {
        guard let message = try? JSONDecoder().decode(AgentMessage.self, from: line), message.v == 1 else {
            Self.log.debug("dropped an unreadable line")
            return
        }
        receive(message, facts: host.facts(for: message.pids), now: now)
    }

    /// The probe's way in: a message with made-up facts.
    public func receive(_ message: AgentMessage, facts: AgentFacts, now: Date = Date()) {
        let moment = sessions.apply(message, facts: facts, now: now)
        syncWatchers()
        lastHeard = now
        if isEnabled, case .ready = status { status = .ready(lastHeard: now) }
        Self.log.debug("received an event, \(self.sessions.sessions.count) sessions")
        if let moment { onMoment?(moment) }
        onChange?()
    }

    public func tick(now: Date) {
        let before = sessions
        sessions.forget(now: now)
        guard sessions != before else { return }
        syncWatchers()
        onChange?()
    }

    public func focus(sessionID: String) {
        guard let session = sessions.sessions.first(where: { $0.id == sessionID }) else { return }
        AgentWindows.focus(session)
    }

    public func isLooking(at session: AgentSession) -> Bool {
        AgentWindows.isLooking(at: session)
    }

    // MARK: - Internals

    private func startListening() throws(AgentListener.Failure) {
        if listener?.isListening == true, FileManager.default.fileExists(atPath: paths.socket.path) { return }
        listener?.stop()
        let listener = AgentListener(url: paths.socket) { [weak self] line in
            guard let self, self.isEnabled else { return }
            self.receive(line)
        }
        try listener.start()
        self.listener = listener
    }

    private func stopListening() {
        listener?.stop()
        listener = nil
        watchers.stopAll()
    }

    private func syncWatchers() {
        watchers.sync(pids: sessions.claudePIDs, transcripts: sessions.transcriptsToWatch)
    }

    private func processExited(_ pid: Int32) {
        sessions.processExited(pid)
        syncWatchers()
        Self.log.debug("a claude process exited")
        onChange?()
    }

    private func transcriptLine(session: String, line: Data) {
        guard AgentTranscript.isInterrupt(line) else { return }
        sessions.interrupt(session: session, now: Date())
        syncWatchers()
        Self.log.debug("an interrupt was seen")
        onChange?()
    }

    private func fail(_ text: String) {
        isEnabled = false
        stopListening()
        status = .problem(text)
        Self.log.error("agents problem")
        onChange?()
    }

    private func describe(_ error: AgentListener.Failure) -> String {
        switch error {
        case .pathTooLong: "the socket path is too long"
        case .system(let reason): reason
        }
    }
}
