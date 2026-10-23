import Testing
import Foundation
import AgentWire
import CallService
@testable import AgentService

private let vscode = CallAppInfo(bundleID: "com.microsoft.VSCode", name: "Code", pid: 7)

/// A claude pid that is alive, so the exit watcher doesn't retire the session at once.
private let livePID = ProcessInfo.processInfo.processIdentifier

@MainActor private func lookup(arguments: [String] = ["claude"]) -> AgentHostLookup {
    AgentHostLookup(name: { $0 == 42 || $0 == livePID ? "claude" : "other" }, arguments: { _ in arguments },
                    app: { $0 == 42 || $0 == livePID ? vscode : nil })
}

private struct Rig {
    let dir: URL
    let paths: AgentPaths
    var settings: AgentSettingsFile { AgentSettingsFile(url: paths.settingsFile) }
}

private func rig(withHelper: Bool = true, settings: String? = nil, shortSocket: Bool = false) throws -> Rig {
    let dir = FileManager.default.temporaryDirectory.appending(path: "ledge-m-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var source: URL?
    if withHelper {
        let url = dir.appending(path: "source-hook")
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        source = url
    }
    let settingsURL = dir.appending(path: "claude/settings.json")
    if let settings {
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(settings.utf8).write(to: settingsURL)
    }
    return Rig(dir: dir, paths: AgentPaths(settingsFile: settingsURL, socket: shortSocket ? URL(fileURLWithPath: "/tmp/ledge-m-\(UInt32.random(in: 0...UInt32.max)).sock") : dir.appending(path: "s.sock"),
                                            helper: dir.appending(path: "support/Ledge/ledge-agent-hook"),
                                            helperSource: source))
}

private func line(_ event: String, session: String = "s1", transcript: String? = nil, tool: String? = nil,
                  summary: String? = nil, pids: [Int32] = [10, 42, 7]) throws -> Data {
    try JSONEncoder().encode(AgentMessage(event: event, session: session, stamp: Int64(Date().timeIntervalSince1970 * 1e6),
                                          pids: pids, project: "/p/ledge", transcript: transcript, tool: tool, summary: summary))
}

@MainActor private func waitFor(_ condition: () -> Bool) async {
    for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
}

@MainActor @Test func enablingCopiesTheHelperAndInstallsTheHooks() throws {
    let r = try rig()
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    monitor.enable()
    #expect(FileManager.default.isExecutableFile(atPath: r.paths.helper.path))
    #expect(r.settings.isInstalled(helper: r.paths.helper.path))
    #expect(monitor.status == .ready(lastHeard: nil))
}

@MainActor @Test func aMissingHelperIsAProblem() throws {
    let r = try rig(withHelper: false)
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    monitor.enable()
    #expect(monitor.status == .problem("The helper is missing from Ledge.app"))
}

@MainActor @Test func anUnreadableSettingsFileIsAProblem() throws {
    let r = try rig(settings: "[]")
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    monitor.enable()
    guard case .problem(let text) = monitor.status else { Issue.record("expected a problem"); return }
    #expect(text.hasPrefix("Can't read settings.json"))
}

@MainActor @Test func disablingRemovesTheHooks() throws {
    let r = try rig()
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    monitor.enable()
    monitor.disable()
    #expect(!r.settings.isInstalled(helper: r.paths.helper.path))
    #expect(monitor.status == .off)
}

@MainActor @Test func suspendingKeepsTheHooks() throws {
    let r = try rig()
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    monitor.enable()
    monitor.suspend()
    #expect(r.settings.isInstalled(helper: r.paths.helper.path))
}

@MainActor @Test func aLineUpdatesTheSessionsAndSaysTheMoment() throws {
    let r = try rig()
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    monitor.enable()
    var moments: [AgentMoment] = []
    monitor.onMoment = { moments.append($0) }
    let now = Date()
    monitor.receive(try line("PermissionRequest", tool: "Bash", summary: "make test"), now: now)
    #expect(monitor.sessions.sessions.count == 1)
    guard case .waiting = monitor.sessions.sessions[0].state else { Issue.record("expected waiting"); return }
    #expect(moments.count == 1)
    #expect(monitor.status == .ready(lastHeard: now))
}

@MainActor @Test func headlessLinesAreIgnored() throws {
    let r = try rig()
    let monitor = AgentMonitor(paths: r.paths, host: lookup(arguments: ["claude", "-p", "x"]), listens: false)
    monitor.receive(try line("UserPromptSubmit"))
    #expect(monitor.sessions.sessions.isEmpty)
}

@MainActor @Test func anInterruptLineInTheTranscriptIdlesTheSession() async throws {
    let r = try rig()
    let transcript = r.dir.appending(path: "t.jsonl")
    try Data("{\"type\":\"summary\"}\n".utf8).write(to: transcript)
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    monitor.receive(try line("UserPromptSubmit", transcript: transcript.path, pids: [10, livePID, 7]))
    #expect(monitor.sessions.sessions[0].state == .working)

    let interrupt = "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"[Request interrupted by user]\"}]}}\n"
    let handle = try FileHandle(forWritingTo: transcript)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(interrupt.utf8))
    try handle.close()

    await waitFor { monitor.sessions.sessions[0].state == .idle }
    #expect(monitor.sessions.sessions[0].state == .idle)
}

@MainActor @Test func aTranscriptLineThatIsNotAnInterruptChangesNothing() async throws {
    let r = try rig()
    let transcript = r.dir.appending(path: "t.jsonl")
    try Data().write(to: transcript)
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    var changes = 0
    monitor.receive(try line("UserPromptSubmit", transcript: transcript.path, pids: [10, livePID, 7]))
    monitor.onChange = { changes += 1 }

    let handle = try FileHandle(forWritingTo: transcript)
    try handle.write(contentsOf: Data("{\"type\":\"assistant\"}\n".utf8))
    try handle.close()

    try await Task.sleep(for: .milliseconds(400))
    #expect(monitor.sessions.sessions[0].state == .working)
    #expect(changes == 0)
}

@MainActor @Test func theHostIsResolvedFromThePids() throws {
    let r = try rig()
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    monitor.receive(try line("UserPromptSubmit", pids: [10, 42, 7]))
    #expect(monitor.sessions.sessions[0].host == vscode)
    #expect(monitor.sessions.sessions[0].claudePID == 42)
}

@MainActor @Test func aSessionWhoseClaudeIsGoneIsDropped() async throws {
    let r = try rig()
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    monitor.receive(try line("UserPromptSubmit"))      // pid 42 is not running
    await waitFor { monitor.sessions.sessions.isEmpty }
    #expect(monitor.sessions.sessions.isEmpty)
}

@MainActor @Test func neverEnabledAppliesTheSessionButStaysOff() throws {
    let r = try rig()
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    monitor.receive(try line("UserPromptSubmit"))
    #expect(monitor.sessions.sessions.count == 1)
    #expect(monitor.status == .off)
}

@MainActor @Test func aProblemSurvivesALaterLine() throws {
    let r = try rig(withHelper: false)
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    monitor.enable()
    monitor.receive(try line("UserPromptSubmit"))
    #expect(monitor.status == .problem("The helper is missing from Ledge.app"))
}

@MainActor @Test func aDeadPidDropsTheSessionAndStaysDropped() async throws {
    let r = try rig()
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    monitor.receive(try line("UserPromptSubmit"))      // pid 42 is not running
    await waitFor { monitor.sessions.sessions.isEmpty }
    #expect(monitor.sessions.sessions.isEmpty)
    try await Task.sleep(for: .milliseconds(100))
    monitor.tick(now: Date())
    #expect(monitor.sessions.sessions.isEmpty)
}

@MainActor @Test func enablingAgainRestartsAListenerWhoseSocketFileIsGone() async throws {
    let r = try rig(shortSocket: true)
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: true)
    defer { monitor.suspend() }
    monitor.enable()
    try FileManager.default.removeItem(at: r.paths.socket)
    monitor.enable()
    #expect(FileManager.default.fileExists(atPath: r.paths.socket.path))
    #expect(AgentSocket.send(try line("UserPromptSubmit", pids: [10, livePID, 7]) + Data("\n".utf8), to: r.paths.socket, timeout: 1))
    await waitFor { !monitor.sessions.sessions.isEmpty }
    #expect(monitor.sessions.sessions.count == 1)
}

@MainActor @Test func enablingTwiceKeepsOneListener() async throws {
    let r = try rig(shortSocket: true)
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: true)
    defer { monitor.suspend() }
    monitor.enable()
    monitor.enable()
    var changes = 0
    monitor.onChange = { changes += 1 }
    #expect(AgentSocket.send(try line("UserPromptSubmit", pids: [10, livePID, 7]) + Data("\n".utf8), to: r.paths.socket, timeout: 1))
    await waitFor { changes > 0 }
    try await Task.sleep(for: .milliseconds(100))
    #expect(changes == 1)
}
