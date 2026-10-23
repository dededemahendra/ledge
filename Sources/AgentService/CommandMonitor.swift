import AppKit
import Foundation
import OSLog
import AgentWire
import CallService

/// A long command that finished, as the island tells it (2026-10-23).
public struct CommandMoment: Sendable, Equatable {
    public let label: String
    public let passed: Bool
    public let seconds: Double
    /// The terminal it ran in, when one was found.
    public let app: CallAppInfo?

    public init(label: String, passed: Bool, seconds: Double, app: CallAppInfo?) {
        self.label = label
        self.passed = passed
        self.seconds = seconds
        self.app = app
    }
}

/// Long commands as Ledge hears them (2026-10-23): puts the zsh block in,
/// listens on its own socket, finds the terminal each command ran in, and
/// keeps quiet for short, interrupted or in-front ones.
@MainActor
public final class CommandMonitor {
    public enum Status: Equatable { case off, ready, problem(String) }

    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "commands")
    static let threshold: Double = 10
    /// zsh's status for a command stopped with Ctrl-C.
    static let interrupted: Int32 = 130

    public private(set) var status: Status = .off
    public var onMoment: ((CommandMoment) -> Void)?

    private let zshrc: ZshrcFile
    private let socket: URL
    private let helper: URL
    private let helperSource: URL?
    private let frontmostPID: () -> pid_t?
    private let appFor: @MainActor ([Int32]) -> CallAppInfo?
    private var listener: AgentListener?

    public init(zshrc: ZshrcFile = ZshrcFile(url: AgentSocket.home.appending(path: ".zshrc")),
                socket: URL = AgentSocket.commandsSocketURL(),
                helper: URL = AgentSocket.helperURL(),
                helperSource: URL? = AgentPaths.live.helperSource,
                frontmostPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
                appFor: @escaping @MainActor ([Int32]) -> CallAppInfo? = CommandMonitor.terminal(for:)) {
        self.zshrc = zshrc
        self.socket = socket
        self.helper = helper
        self.helperSource = helperSource
        self.frontmostPID = frontmostPID
        self.appFor = appFor
    }

    /// Copy the helper, listen, then put the block in, so a block is never
    /// one nobody hears. A failure undoes the listening.
    public func enable() {
        guard AgentListener.fits(socket) else {
            fail("Your home folder's path is too long for Ledge's socket")
            return
        }
        if let helperSource {
            do {
                try AgentMonitor.installHelper(from: helperSource, to: helper)
            } catch {
                fail("Can't copy the helper: \(error.localizedDescription)")
                return
            }
        }
        do {
            try startListening()
        } catch .inUse {
            fail("Another Ledge is listening for commands")
            return
        } catch {
            fail("Can't listen for commands")
            return
        }
        do {
            try zshrc.install()
        } catch {
            stopListening()
            fail(Self.describe(error))
            return
        }
        status = .ready
        Self.log.info("commands enabled")
    }

    /// Stop listening and take the block out of `~/.zshrc`.
    public func disable() {
        stopListening()
        do {
            try zshrc.uninstall()
            status = .off
            Self.log.info("commands disabled")
        } catch {
            status = .problem(Self.describe(error))
            Self.log.error("could not remove the zsh block")
        }
    }

    /// Stop listening, keep the block (Ledge quitting).
    public func suspend() {
        stopListening()
    }

    /// The moment a finished command makes, or nil to keep quiet.
    static func moment(for message: CommandMessage, frontmostPID: pid_t?, app: CallAppInfo?) -> CommandMoment? {
        guard message.status != interrupted, message.seconds.isFinite, message.seconds >= threshold else { return nil }
        if let app, let frontmostPID, app.pid == frontmostPID { return nil }
        return CommandMoment(label: message.label, passed: message.status == 0, seconds: message.seconds, app: app)
    }

    /// The first app up the helper's parent chain. The helper itself has
    /// usually exited by now, so its shell's turn comes next.
    public static func terminal(for pids: [Int32]) -> CallAppInfo? {
        let me = ProcessInfo.processInfo.processIdentifier
        for pid in pids {
            if let app = AgentHostLookup.resolve(pid, ownPID: me, lookup: .live) { return app }
        }
        return nil
    }

    /// One line from the socket (also the tests' way in).
    func receive(_ line: Data) {
        // The socket takes any local writer: only a label the helper itself
        // would have made reaches the island.
        guard let message = try? JSONDecoder().decode(CommandMessage.self, from: line),
              message.v == 1, message.event == "command",
              CommandTrim.label(message.label) == message.label else {
            Self.log.debug("dropped an unreadable line")
            return
        }
        let app = appFor(message.pids)
        guard let moment = Self.moment(for: message, frontmostPID: frontmostPID(), app: app) else { return }
        onMoment?(moment)
    }

    private func startListening() throws(AgentListener.Failure) {
        if listener?.isListening == true, FileManager.default.fileExists(atPath: socket.path) { return }
        listener?.stop()
        let listener = AgentListener(url: socket) { [weak self] line in self?.receive(line) }
        try listener.start()
        self.listener = listener
    }

    private func stopListening() {
        listener?.stop()
        listener = nil
    }

    private func fail(_ text: String) {
        stopListening()
        status = .problem(text)
        Self.log.error("commands problem")
    }

    private static func describe(_ problem: ZshrcFile.Problem) -> String {
        switch problem {
        case .unreadable(let reason): "Can't read ~/.zshrc: \(reason)"
        case .broken: "Ledge's block in ~/.zshrc is incomplete; fix it by hand"
        case .unwritable(let reason): "Can't write ~/.zshrc: \(reason)"
        }
    }
}
