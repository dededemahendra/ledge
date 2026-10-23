import Foundation
import Darwin

/// Process-exit and transcript watchers (2026-10-23). All callbacks arrive
/// on the main queue.
@MainActor
final class AgentWatchers {
    private final class TranscriptWatch {
        let path: String
        let fd: Int32
        var offset: UInt64
        var tail = Data()
        var source: DispatchSourceFileSystemObject?
        init(path: String, fd: Int32, offset: UInt64) {
            self.path = path
            self.fd = fd
            self.offset = offset
        }
    }

    private var processes: [Int32: DispatchSourceProcess] = [:]
    private var transcripts: [String: TranscriptWatch] = [:]

    private let onExit: (Int32) -> Void
    private let onLine: (_ session: String, _ line: Data) -> Void

    init(onExit: @escaping (Int32) -> Void, onLine: @escaping (_ session: String, _ line: Data) -> Void) {
        self.onExit = onExit
        self.onLine = onLine
    }

    var watchedProcessCount: Int { processes.count }
    var watchedTranscriptCount: Int { transcripts.count }

    func sync(pids: Set<Int32>, transcripts wanted: [String: String]) {
        for (pid, source) in processes where !pids.contains(pid) {
            source.cancel()
            processes[pid] = nil
        }
        for pid in pids where processes[pid] == nil { watch(pid: pid) }

        for (session, watch) in transcripts where wanted[session] != watch.path {
            stop(watch)
            transcripts[session] = nil
        }
        for (session, path) in wanted where transcripts[session] == nil { watch(session: session, path: path) }
    }

    func stopAll() {
        sync(pids: [], transcripts: [:])
    }

    // MARK: - Processes

    private func watch(pid: Int32) {
        if kill(pid, 0) != 0, errno == ESRCH {
            // Already gone: say so once the caller has finished its pass.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.onExit(pid) }
            }
            return
        }
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.processes[pid]?.cancel()
                self.processes[pid] = nil
                self.onExit(pid)
            }
        }
        source.resume()
        processes[pid] = source
    }

    // MARK: - Transcripts

    private func watch(session: String, path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        var info = stat()
        let size = fstat(fd, &info) == 0 ? UInt64(max(0, info.st_size)) : 0
        let watch = TranscriptWatch(path: path, fd: fd, offset: size)
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.extend, .write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self, weak watch, weak source] in
            MainActor.assumeIsolated {
                guard let self, let watch, let source else { return }
                let events = source.data
                if events.contains(.extend) || events.contains(.write) { self.read(watch, session: session) }
                if events.contains(.delete) || events.contains(.rename) {
                    self.stop(watch)
                    if self.transcripts[session] === watch { self.transcripts[session] = nil }
                }
            }
        }
        source.resume()
        watch.source = source
        transcripts[session] = watch
    }

    private func stop(_ watch: TranscriptWatch) {
        guard let source = watch.source else { return }
        watch.source = nil
        source.cancel()
        close(watch.fd)
    }

    private func read(_ watch: TranscriptWatch, session: String) {
        guard let handle = FileHandle(forReadingAtPath: watch.path) else { return }
        defer { try? handle.close() }
        var size = stat()
        if stat(watch.path, &size) == 0, UInt64(max(0, size.st_size)) < watch.offset {
            watch.offset = 0       // truncated: start over
            watch.tail = Data()
        }
        guard (try? handle.seek(toOffset: watch.offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty else { return }
        watch.offset += UInt64(data.count)
        var buffer = watch.tail + data
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(Data(buffer[buffer.startIndex..<newline]))
            buffer = Data(buffer[buffer.index(after: newline)...])
        }
        watch.tail = buffer
        for line in lines where !line.isEmpty { onLine(session, line) }
    }
}
