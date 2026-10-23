import Testing
import Foundation
import Darwin
import AgentWire
import CallService
@testable import AgentService

private let vscode = CallAppInfo(bundleID: "com.microsoft.VSCode", name: "Code", pid: 7)

/// A claude pid that is alive, so the exit watcher doesn't retire the session at once.
private let livePID = ProcessInfo.processInfo.processIdentifier

@MainActor private func lookup(arguments: [String] = ["claude"]) -> AgentHostLookup {
    AgentHostLookup(name: { $0 == 42 || $0 == livePID ? "claude" : "other" },
                    arguments: { $0 == 42 || $0 == livePID ? arguments : ["other"] },
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

// MARK: - Final fix wave (2026-10-23)

@MainActor @Test func theInstalledHelperLosesTheQuarantineFlag() throws {
    let r = try rig()
    let source = try #require(r.paths.helperSource)
    let flag = Array("0081;6718a2b0;Safari;".utf8)
    let set = flag.withUnsafeBytes { setxattr(source.path, "com.apple.quarantine", $0.baseAddress, $0.count, 0, 0) }
    #expect(set == 0)
    // An older helper is in place: it is replaced, never removed first.
    let folder = r.paths.helper.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: r.paths.helper)

    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    monitor.enable()
    #expect(monitor.status == .ready(lastHeard: nil))
    let size = getxattr(r.paths.helper.path, "com.apple.quarantine", nil, 0, 0, 0)
    let error = errno
    #expect(size == -1 && error == ENOATTR)
    #expect(FileManager.default.isExecutableFile(atPath: r.paths.helper.path))
    let attributes = try FileManager.default.attributesOfItem(atPath: r.paths.helper.path)
    #expect(attributes[.posixPermissions] as? Int == 0o755)
    #expect(try Data(contentsOf: r.paths.helper) == Data(contentsOf: source))
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["ledge-agent-hook"])
}

@MainActor @Test func aHomeTooLongForTheSocketInstallsNothing() throws {
    let r = try rig()
    let longHome = URL(fileURLWithPath: "/Users/" + String(repeating: "a", count: 80))
    let paths = AgentPaths(settingsFile: r.paths.settingsFile, socket: AgentSocket.socketURL(home: longHome),
                           helper: r.paths.helper, helperSource: r.paths.helperSource)
    let monitor = AgentMonitor(paths: paths, host: lookup(), listens: true)
    monitor.enable()
    #expect(monitor.status == .problem("Your home folder's path is too long for Ledge's socket"))
    #expect(!FileManager.default.fileExists(atPath: r.paths.settingsFile.path))
    #expect(!FileManager.default.fileExists(atPath: r.paths.helper.path))
}

@MainActor @Test func enablingChecksTheHooksAreThere() throws {
    let r = try rig(settings: #"{"theme":"dark"}"#)
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    let url = r.paths.settingsFile
    // Another program writes its own copy over Ledge's change.
    monitor.settingsFile.afterWrite = { try? Data(#"{"theme":"light"}"#.utf8).write(to: url) }
    monitor.enable()
    #expect(monitor.status == .problem("Can't install Ledge's hooks: settings.json didn't keep them"))
}

@MainActor @Test func hooksOfAnUnexpectedShapeAreAProblem() throws {
    let r = try rig(settings: #"{"hooks":{"Stop":{"mine":true}}}"#)
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    monitor.enable()
    #expect(monitor.status == .problem("Can't read settings.json: hooks has an unexpected shape"))
}

@MainActor @Test func aFailedWriteReadsAsWrite() throws {
    let r = try rig(settings: "{}")
    let folder = r.paths.settingsFile.deletingLastPathComponent()
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    monitor.enable()
    guard case .problem(let text) = monitor.status else { Issue.record("expected a problem"); return }
    #expect(text.hasPrefix("Can't write settings.json: "))
}

@MainActor @Test func hooksThatWontComeOutStayAProblemUntilRepaired() throws {
    let r = try rig()
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    monitor.enable()
    #expect(!monitor.hooksLeftBehind)
    let installed = try Data(contentsOf: r.paths.settingsFile)
    let folder = r.paths.settingsFile.deletingLastPathComponent()
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
    monitor.disable()
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
    guard case .problem(let text) = monitor.status else { Issue.record("expected a problem"); return }
    #expect(text.hasPrefix("Can't remove Ledge's hooks: "))
    #expect(monitor.hooksLeftBehind)
    #expect(try Data(contentsOf: r.paths.settingsFile) == installed)
    // Repair while off: removal again.
    monitor.disable()
    #expect(monitor.status == .off)
    #expect(!monitor.hooksLeftBehind)
    #expect(!r.settings.isInstalled(helper: r.paths.helper.path))

    try Data(#"{"hooks":{"Stop":{"mine":true}}}"#.utf8).write(to: r.paths.settingsFile)
    monitor.disable()
    #expect(monitor.status == .problem("Can't remove Ledge's hooks: hooks has an unexpected shape"))
    // Switching on again sets up as usual and clears it.
    try Data("{}".utf8).write(to: r.paths.settingsFile)
    monitor.enable()
    #expect(monitor.status == .ready(lastHeard: nil))
    #expect(!monitor.hooksLeftBehind)
}

@MainActor @Test func aSecondLedgeLeavesTheFirstListening() async throws {
    let r = try rig(shortSocket: true)
    let first = AgentMonitor(paths: r.paths, host: lookup(), listens: true)
    defer { first.suspend() }
    first.enable()
    #expect(first.status == .ready(lastHeard: nil))
    let second = AgentMonitor(paths: r.paths, host: lookup(), listens: true)
    second.enable()
    #expect(second.status == .problem("Another Ledge is listening for sessions"))
    #expect(FileManager.default.fileExists(atPath: r.paths.socket.path))
    #expect(AgentSocket.send(try line("UserPromptSubmit", pids: [10, livePID, 7]) + Data("\n".utf8), to: r.paths.socket, timeout: 1))
    await waitFor { !first.sessions.sessions.isEmpty }
    #expect(first.sessions.sessions.count == 1)
    #expect(second.sessions.sessions.isEmpty)
}

@MainActor @Test func anInterruptAfterALongTranscriptLineStillLands() async throws {
    let r = try rig()
    let transcript = r.dir.appending(path: "t.jsonl")
    try Data().write(to: transcript)
    let monitor = AgentMonitor(paths: r.paths, host: lookup(), listens: false)
    monitor.receive(try line("UserPromptSubmit", transcript: transcript.path, pids: [10, livePID, 7]))
    #expect(monitor.sessions.sessions[0].state == .working)

    let long = #"{"type":"user","message":{"role":"user","content":""# + String(repeating: "x", count: 2_000_000) + "\"}}\n"
    let interrupt = #"{"type":"user","message":{"role":"user","content":"[Request interrupted by user]"}}"# + "\n"
    let handle = try FileHandle(forWritingTo: transcript)
    try handle.write(contentsOf: Data((long + "\n" + interrupt).utf8))
    try handle.close()

    await waitFor { monitor.sessions.sessions[0].state == .idle }
    #expect(monitor.sessions.sessions[0].state == .idle)
}
