import Foundation
import Darwin

/// Where Ledge listens for hook lines, and how the helper reaches it
/// (2026-10-23). Foundation and Darwin only: the helper links this library.
public enum AgentSocket {
    /// `$HOME` when set (Claude Code runs hooks with the user's), else `NSHomeDirectory()`.
    public static var home: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory())
    }

    /// ~/Library/Application Support/Ledge
    public static func supportDirectory(home: URL = AgentSocket.home) -> URL {
        home.appending(path: "Library/Application Support/Ledge")
    }

    public static func socketURL(home: URL = AgentSocket.home) -> URL {
        supportDirectory(home: home).appending(path: "agents.sock")
    }

    /// Finished terminal commands (2026-10-23), beside the agents' socket.
    public static func commandsSocketURL(home: URL = AgentSocket.home) -> URL {
        supportDirectory(home: home).appending(path: "commands.sock")
    }

    public static func helperURL(home: URL = AgentSocket.home) -> URL {
        supportDirectory(home: home).appending(path: "ledge-agent-hook")
    }

    /// Connects, writes all of `data`, closes. False on any failure. Never blocks past `timeout`.
    public static func send(_ data: Data, to socket: URL, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let path = Array(socket.path.utf8CString)   // includes the NUL

        var addr = sockaddr_un()
        guard path.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: path.map { UInt8(bitPattern: $0) })
        }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else { return false }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
        }
        if rc != 0 {
            guard errno == EINPROGRESS, wait(fd, events: Int16(POLLOUT), until: deadline) else { return false }
            var err: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) == 0, err == 0 else { return false }
        }

        var offset = 0
        while offset < data.count {
            let n = data.withUnsafeBytes { raw in
                write(fd, raw.baseAddress! + offset, raw.count - offset)
            }
            if n > 0 {
                offset += n
            } else if n < 0, errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
                guard wait(fd, events: Int16(POLLOUT), until: deadline) else { return false }
            } else {
                return false
            }
        }
        return true
    }

    /// Polls `fd` for `events` until `deadline`; false on timeout or error.
    private static func wait(_ fd: Int32, events: Int16, until deadline: Date) -> Bool {
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return false }
            var p = pollfd(fd: fd, events: events, revents: 0)
            let rc = poll(&p, 1, Int32(max(1, (remaining * 1000).rounded(.up))))
            if rc > 0 { return p.revents & (events | Int16(POLLERR) | Int16(POLLHUP)) != 0 }
            if rc == 0 { return false }
            if errno != EINTR { return false }
        }
    }
}
