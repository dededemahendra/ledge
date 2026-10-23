import Foundation
import Darwin
import AgentWire

/// The socket server (2026-10-23): one line per connection, at most 8 KB,
/// delivered on newline or EOF. Everything runs on the main queue.
@MainActor
public final class AgentListener {
    public enum Failure: Error, Equatable {
        case pathTooLong
        /// Another process (another Ledge) answers on the path (2026-10-23).
        case inUse
        case system(String)
    }

    static let maxLine = 8192
    static let patience: TimeInterval = 2
    static let maxConnections = 64

    private final class Connection {
        let fd: Int32
        var buffer = Data()
        var source: DispatchSourceRead?
        var timer: DispatchSourceTimer?
        init(fd: Int32) { self.fd = fd }
        /// The source's cancel handler closes the fd, once libdispatch is done with it.
        func cancel() {
            timer?.cancel()
            timer = nil
            if let source {
                source.cancel()
                self.source = nil
            } else {
                close(fd)
            }
        }
    }

    private let url: URL
    private let onLine: (Data) -> Void
    private var listenFD: Int32 = -1
    /// The socket file this listener bound, so stopping never removes another's.
    private var bound: (device: dev_t, inode: ino_t)?
    private var acceptSource: DispatchSourceRead?
    private var connections: [Int32: Connection] = [:]

    public init(url: URL, onLine: @escaping (Data) -> Void) {
        self.url = url
        self.onLine = onLine
    }

    public var isListening: Bool { listenFD >= 0 }

    /// Whether `url`'s path fits a socket address (`sun_path`, NUL included).
    public nonisolated static func fits(_ url: URL) -> Bool {
        Array(url.path.utf8CString).count <= MemoryLayout.size(ofValue: sockaddr_un().sun_path)
    }

    public func start() throws(Failure) {
        stop()
        let path = Array(url.path.utf8CString)
        var addr = sockaddr_un()
        guard Self.fits(url) else { throw .pathTooLong }
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: path.map { UInt8(bitPattern: $0) })
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)

        // Someone answering on the path is another Ledge: leave its socket be.
        if Self.answers(addr) { throw .inUse }
        unlink(url.path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .system(String(cString: strerror(errno))) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let didBind = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard didBind == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw .system(reason)
        }
        var info = stat()
        if lstat(url.path, &info) == 0 { bound = (info.st_dev, info.st_ino) }
        chmod(url.path, 0o600)
        guard listen(fd, SOMAXCONN) == 0, makeNonBlocking(fd) else {
            let reason = String(cString: strerror(errno))
            close(fd)
            unlinkIfOurs()
            throw .system(reason)
        }

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.accept() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        acceptSource = source
    }

    public func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        for connection in connections.values { drop(connection) }
        connections.removeAll()
        if listenFD >= 0 {
            listenFD = -1
            unlinkIfOurs()
        }
    }

    /// Removes the socket file only while it is still the one this listener bound (2026-10-23).
    private func unlinkIfOurs() {
        defer { bound = nil }
        guard let bound else { return }
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_dev == bound.device, info.st_ino == bound.inode else { return }
        unlink(url.path)
    }

    /// Whether a connection to `addr` is taken, or would be but for a full backlog.
    private static func answers(_ addr: sockaddr_un) -> Bool {
        var addr = addr
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else { return false }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        return rc == 0 || errno == EAGAIN || errno == EINPROGRESS
    }

    private func makeNonBlocking(_ fd: Int32) -> Bool {
        let flags = fcntl(fd, F_GETFL)
        return flags >= 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0
    }

    private func accept() {
        while listenFD >= 0 {
            let fd = Darwin.accept(listenFD, nil, nil)
            guard fd >= 0 else {
                if errno == EMFILE || errno == ENFILE { pauseAccepting() }
                return
            }
            guard connections.count < Self.maxConnections else { close(fd); continue }
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            guard makeNonBlocking(fd) else { close(fd); continue }

            let connection = Connection(fd: fd)
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self, weak connection] in
                MainActor.assumeIsolated {
                    guard let self, let connection else { return }
                    self.read(connection)
                }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + Self.patience)
            timer.setEventHandler { [weak self, weak connection] in
                MainActor.assumeIsolated {
                    guard let self, let connection else { return }
                    self.finish(connection, deliver: false)
                }
            }
            timer.resume()
            connection.source = source
            connection.timer = timer
            connections[fd] = connection
        }
    }

    /// Out of descriptors: a level-triggered accept source would spin, so rest it for a second.
    private func pauseAccepting() {
        guard let source = acceptSource else { return }
        source.suspend()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.acceptSource === source else { source.resume(); return }
                source.resume()
            }
        }
    }

    private func read(_ connection: Connection) {
        var chunk = [UInt8](repeating: 0, count: 2048)
        while connections[connection.fd] === connection {
            let n = Darwin.read(connection.fd, &chunk, chunk.count)
            if n > 0 {
                connection.buffer.append(contentsOf: chunk[0..<n])
                if let newline = connection.buffer.firstIndex(of: 0x0A) {
                    connection.buffer = connection.buffer.prefix(upTo: newline)
                    finish(connection, deliver: true)
                    return
                }
                if connection.buffer.count > Self.maxLine {
                    finish(connection, deliver: false)
                    return
                }
            } else if n == 0 {
                finish(connection, deliver: true)
                return
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            } else if errno != EINTR {
                finish(connection, deliver: false)
                return
            }
        }
    }

    private func finish(_ connection: Connection, deliver: Bool) {
        guard connections[connection.fd] === connection else { return }
        connections[connection.fd] = nil
        let line = connection.buffer
        drop(connection)
        if deliver, !line.isEmpty, line.count <= Self.maxLine { onLine(line) }
    }

    private func drop(_ connection: Connection) {
        connection.cancel()
    }
}
