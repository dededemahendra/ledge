import Testing
import Foundation
import Darwin
@testable import AgentWire

/// A throwaway home at /tmp/lh-<8 hex> (a socket path must fit in 104 bytes).
private func makeHome() -> URL {
    let hex = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
    let home = URL(fileURLWithPath: "/tmp/lh-\(hex)")
    try? FileManager.default.createDirectory(at: AgentSocket.supportDirectory(home: home), withIntermediateDirectories: true)
    return home
}

/// Accepts connections on `path` and keeps what each one sends until EOF.
private final class Listener: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var received: [Data] = []
    private var closed = false

    init(path: String) {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            let bytes = Array(path.utf8CString)
            raw.copyBytes(from: bytes.map { UInt8(bitPattern: $0) }.prefix(raw.count))
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) } }
        listen(fd, 8)
        let fd = self.fd
        Thread.detachNewThread { [self] in
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { return }
                var data = Data()
                var buf = [UInt8](repeating: 0, count: 8192)
                while true {
                    let n = read(client, &buf, buf.count)
                    if n <= 0 { break }
                    data.append(contentsOf: buf[0..<n])
                }
                close(client)
                lock.lock(); received.append(data); lock.unlock()
            }
        }
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        if !closed { closed = true; shutdown(fd, SHUT_RDWR); close(fd) }
    }

    /// Waits up to `seconds` for `count` connections to have finished.
    func wait(for count: Int = 1, seconds: TimeInterval = 3) -> [Data] {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            lock.lock(); let n = received.count; lock.unlock()
            if n >= count { break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        lock.lock(); defer { lock.unlock() }
        return received
    }
}

private func helperURL() -> URL {
    if let dir = Bundle.allBundles.first(where: { $0.bundlePath.hasSuffix(".xctest") })?
        .bundleURL.deletingLastPathComponent() {
        let url = dir.appending(path: "LedgeAgentHook")
        if FileManager.default.isExecutableFile(atPath: url.path) { return url }
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return root.appending(path: ".build/debug/LedgeAgentHook")
}

/// Runs the helper with `input` on stdin and `home` as $HOME.
private func runHelper(input: Data, home: URL) throws -> (status: Int32, seconds: TimeInterval) {
    let process = Process()
    process.executableURL = helperURL()
    var env = ProcessInfo.processInfo.environment
    env["HOME"] = home.path
    process.environment = env
    let stdin = Pipe()
    process.standardInput = stdin
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let start = Date()
    try process.run()
    stdin.fileHandleForWriting.write(input)
    try? stdin.fileHandleForWriting.close()
    process.waitUntilExit()
    return (process.terminationStatus, Date().timeIntervalSince(start))
}

@Test func sendDeliversTheBytes() {
    let home = makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let socketURL = AgentSocket.socketURL(home: home)
    let listener = Listener(path: socketURL.path)
    defer { listener.stop() }
    #expect(AgentSocket.send(Data("hi\n".utf8), to: socketURL, timeout: 0.5))
    #expect(listener.wait() == [Data("hi\n".utf8)])
}

@Test func sendToNothingFailsFast() {
    let home = makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let start = Date()
    #expect(AgentSocket.send(Data("hi\n".utf8), to: AgentSocket.socketURL(home: home), timeout: 0.5) == false)
    #expect(Date().timeIntervalSince(start) < 0.6)
}

@Test func ourOwnStartTimeAndParentsAreReadable() {
    let started = AgentProcess.startTime(of: getpid())
    let now = Int64(Date().timeIntervalSince1970 * 1_000_000)
    #expect(started != nil)
    if let started { #expect(abs(now - started) < 3_600 * 1_000_000) }
    #expect(AgentProcess.parentChain(from: getpid()).first == getppid())
}

@Test func argumentsAreReadable() {
    #expect(AgentProcess.arguments(of: getpid())?.first == CommandLine.arguments.first)
}

private let writeHook = #"{"session_id":"s1","hook_event_name":"PreToolUse","cwd":"/p/x","tool_name":"Write","tool_input":{"file_path":"/a/x.swift","content":"CONTENT"}}"#

@Test func theHelperForwardsAHook() throws {
    let home = makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let listener = Listener(path: AgentSocket.socketURL(home: home).path)
    defer { listener.stop() }
    let result = try runHelper(input: Data(writeHook.replacingOccurrences(of: "CONTENT", with: "hi").utf8), home: home)
    #expect(result.status == 0)
    let got = listener.wait()
    #expect(got.count == 1)
    let line = try #require(got.first)
    #expect(line.last == 0x0A)
    let message = try JSONDecoder().decode(AgentMessage.self, from: line)
    #expect(message.event == "PreToolUse")
    #expect(message.session == "s1")
    #expect(message.tool == "Write")
    #expect(message.pids.first == getpid())
}

@Test func withNoListenerTheHelperExitsZeroQuickly() throws {
    let home = makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let result = try runHelper(input: Data(writeHook.replacingOccurrences(of: "CONTENT", with: "hi").utf8), home: home)
    #expect(result.status == 0)
    #expect(result.seconds < 1)
}

@Test func aHugeToolInputIsDrainedAndTrimmed() throws {
    let home = makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let listener = Listener(path: AgentSocket.socketURL(home: home).path)
    defer { listener.stop() }
    let big = String(repeating: "x", count: 1_000_000)
    let result = try runHelper(input: Data(writeHook.replacingOccurrences(of: "CONTENT", with: big).utf8), home: home)
    #expect(result.status == 0)
    let got = listener.wait()
    #expect(got.count == 1)
    let line = try #require(got.first)
    #expect(line.count <= 4096)
    let message = try JSONDecoder().decode(AgentMessage.self, from: line)
    #expect(message.summary == "x.swift")
}

@Test func garbageOnStdinExitsZeroAndSendsNothing() throws {
    let home = makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let listener = Listener(path: AgentSocket.socketURL(home: home).path)
    defer { listener.stop() }
    let result = try runHelper(input: Data("not json".utf8), home: home)
    #expect(result.status == 0)
    #expect(listener.wait(seconds: 0.4).isEmpty)
}
