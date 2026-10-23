import AgentWire
import CallService
import Foundation
import Testing
@testable import AgentService

private let terminal = CallAppInfo(bundleID: "com.apple.Terminal", name: "Terminal", pid: 902)

private func message(status: Int32 = 0, seconds: Double = 83, pids: [Int32] = [900, 901, 902]) -> CommandMessage {
    CommandMessage(label: "npm run build", status: status, seconds: seconds, cwd: "/tmp", pids: pids, stamp: 1)
}

@MainActor @Test func passedAndFailedCommandsBecomeMoments() {
    let passed = CommandMonitor.moment(for: message(status: 0), frontmostPID: nil, app: terminal)
    #expect(passed == CommandMoment(label: "npm run build", passed: true, seconds: 83, app: terminal))
    #expect(CommandMonitor.moment(for: message(status: 2), frontmostPID: nil, app: terminal)?.passed == false)
}

/// Ctrl-C: the user's own doing.
@MainActor @Test func anInterruptedCommandIsQuiet() {
    #expect(CommandMonitor.moment(for: message(status: 130), frontmostPID: nil, app: terminal) == nil)
}

@MainActor @Test func aShortCommandIsQuiet() {
    #expect(CommandMonitor.moment(for: message(seconds: 9.9), frontmostPID: nil, app: terminal) == nil)
}

/// Already looking at that terminal: nothing to tell.
@MainActor @Test func aCommandInTheFrontmostTerminalIsQuiet() {
    #expect(CommandMonitor.moment(for: message(), frontmostPID: 902, app: terminal) == nil)
    #expect(CommandMonitor.moment(for: message(), frontmostPID: 77, app: terminal) != nil)
}

@MainActor @Test func theTerminalIsFoundFromTheParentChain() throws {
    var seenChain: [Int32] = []
    let monitor = CommandMonitor(frontmostPID: { nil }, appFor: { chain in
        seenChain = chain
        return terminal
    })
    var moments: [CommandMoment] = []
    monitor.onMoment = { moments.append($0) }
    monitor.receive(try JSONEncoder().encode(message()))
    #expect(seenChain == [900, 901, 902])
    #expect(moments.first?.app == terminal)
}
