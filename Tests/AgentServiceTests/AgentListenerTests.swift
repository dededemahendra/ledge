import Testing
import Foundation
import AgentWire
@testable import AgentService

private func shortSocket() -> URL {
    URL(fileURLWithPath: "/tmp/ledge-l-\(UInt32.random(in: 0...UInt32.max)).sock")
}

@MainActor private func waitFor(_ condition: () -> Bool) async {
    for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
}

@MainActor @Test func aLineSentToTheSocketArrives() async throws {
    let url = shortSocket()
    var got: [Data] = []
    let listener = AgentListener(url: url) { got.append($0) }
    try listener.start()
    defer { listener.stop() }
    #expect(AgentSocket.send(Data("hello\n".utf8), to: url, timeout: 1))
    await waitFor { !got.isEmpty }
    #expect(got == [Data("hello".utf8)])
}

@MainActor @Test func aStaleFileIsReplacedAndTheModeIs0600() async throws {
    let url = shortSocket()
    try Data("old".utf8).write(to: url)
    let listener = AgentListener(url: url) { _ in }
    try listener.start()
    defer { listener.stop() }
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect((attrs[.posixPermissions] as? Int) == 0o600)
    #expect(attrs[.type] as? FileAttributeType == .typeSocket)
}

@MainActor @Test func stoppingRemovesTheSocketFile() throws {
    let url = shortSocket()
    let listener = AgentListener(url: url) { _ in }
    try listener.start()
    listener.stop()
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@MainActor @Test func aTooLongPathFailsToStart() {
    let url = URL(fileURLWithPath: "/tmp/" + String(repeating: "x", count: 200))
    let listener = AgentListener(url: url) { _ in }
    #expect(throws: AgentListener.Failure.pathTooLong) { try listener.start() }
}

@MainActor @Test func anOversizedLineIsDropped() async throws {
    let url = shortSocket()
    var got: [Data] = []
    let listener = AgentListener(url: url) { got.append($0) }
    try listener.start()
    defer { listener.stop() }
    // From off the main actor, so the listener can read while the sender writes.
    await Task.detached { _ = AgentSocket.send(Data(repeating: 0x61, count: 20_000), to: url, timeout: 1) }.value
    _ = AgentSocket.send(Data("ok\n".utf8), to: url, timeout: 1)
    await waitFor { !got.isEmpty }
    #expect(got == [Data("ok".utf8)])
}
