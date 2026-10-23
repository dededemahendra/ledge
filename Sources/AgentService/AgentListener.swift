import Foundation
import Darwin
import AgentWire

/// The socket server (2026-10-23): one line per connection, at most 8 KB,
/// delivered on newline or EOF. Everything runs on the main queue.
@MainActor
public final class AgentListener {
    public enum Failure: Error, Equatable {
        case pathTooLong
        case system(String)
    }

    static let maxLine = 8192
    static let patience: TimeInterval = 2

    private final class Connection {
        let fd: Int32
        var buffer = Data()
        var source: DispatchSourceRead?
        var timer: DispatchSourceTimer?
        init(fd: Int32) { self.fd = fd }
        func cancel() {
            source?.cancel()
            timer?.cancel()
            source = nil
            timer = nil
        }
    }

    private let url: URL
    private let onLine: (Data) -> Void
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [Int32: Connection] = [:]

    public init(url: URL, onLine: @escaping (Data) -> Void) {
        self.url = url
        self.onLine = onLine
    }

    public var isListening: Bool { listenFD >= 0 }

    public func start() throws(Failure) {
        stop()
        let path = Array(url.path.utf8CString)
        var addr = sockaddr_un()
        guard path.count <= MemoryLayout.size(ofValue: addr.sun_path) else { throw .pathTooLong }
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: path.map { UInt8(bitPattern: $0) })
        }

        unlink(url.path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .system(String(cString: strerror(errno))) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw .system(reason)
        }
        chmod(url.path, 0o600)
        guard listen(fd, 16) == 0, makeNonBlocking(fd) else {
            let reason = String(cString: strerror(errno))
            close(fd)
            unlink(url.path)
            throw .system(reason)
        }

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.accept() }
        }
        source.resume()
        acceptSource = source
    }

    public func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        for connection in connections.values { drop(connection) }
        connections.removeAll()
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
            unlink(url.path)
        }
    }

    private func makeNonBlocking(_ fd: Int32) -> Bool {
        let flags = fcntl(fd, F_GETFL)
        return flags >= 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0
    }

    private func accept() {
        while listenFD >= 0 {
            let fd = Darwin.accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
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
        close(connection.fd)
    }
}
