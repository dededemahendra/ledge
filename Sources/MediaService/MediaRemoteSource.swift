import Foundation
import OSLog
import Synchronization

/// Splits a byte stream into newline-delimited lines behind a real lock.
///
/// `FileHandle.readabilityHandler` is `@Sendable` and Foundation invokes it
/// from a background dispatch-source thread; a plain captured `var buffer`
/// is correctly rejected by strict concurrency checking as a potential data
/// race even though a single dispatch source never re-enters its own handler
/// concurrently with itself — the compiler cannot see that guarantee, so
/// this gives the buffer a real `Mutex` instead of relying on it.
private final class LineAccumulator: Sendable {
    private let buffer = Mutex(Data())

    /// Appends `chunk` and returns every complete line it just completed, in order.
    func appendAndExtractLines(_ chunk: Data) -> [String] {
        buffer.withLock { data in
            data.append(chunk)
            var lines: [String] = []
            while let newline = data.firstIndex(of: 0x0A) {
                let lineData = data[data.startIndex..<newline]
                data.removeSubrange(data.startIndex...newline)
                if let line = String(data: lineData, encoding: .utf8) {
                    lines.append(line)
                }
            }
            return lines
        }
    }
}

/// Runs the adapter process and turns its stdout into lines.
/// Knows nothing about merging state or deciding whether to restart —
/// that judgement lives in `MediaStateMerger` and `RestartPolicy`.
final class MediaRemoteSource {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "media.proc")

    private let locator: AdapterLocator
    private var process: Process?

    init(locator: AdapterLocator) {
        self.locator = locator
    }

    /// Emits each stdout line, then exactly one terminal `ExitReason`.
    func run(
        onLine: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (ExitReason) -> Void
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = locator.streamArguments()

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        // Every stderr line is an error message, non-fatal unless the exit code
        // is also non-zero -- per the adapter README. Never logged above
        // `.debug`: stderr occasionally echoes fragments of now-playing state.
        err.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Self.log.debug("adapter stderr: \(text, privacy: .private)")
        }

        let lineAccumulator = LineAccumulator()
        out.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            for line in lineAccumulator.appendAndExtractLines(chunk) {
                onLine(line)
            }
        }

        process.terminationHandler = { finished in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            let reason: ExitReason
            if finished.terminationReason == .uncaughtSignal {
                reason = .signalled(finished.terminationStatus)
            } else if finished.terminationStatus == 0 {
                reason = .clean
            } else {
                reason = .nonZero(finished.terminationStatus)
            }
            onExit(reason)
        }

        do {
            try process.run()
            self.process = process
        } catch {
            Self.log.error("could not launch adapter: \(error.localizedDescription, privacy: .public)")
            onExit(.nonZero(-1))
        }
    }

    /// The adapter streams until it receives SIGTERM, per its README.
    /// Escalates to SIGKILL if it is still running two seconds later —
    /// two adapters were found orphaned (parent pid 1) after app relaunches
    /// on 2026-09-28, so "SIGTERM is enough" is not something to rely on.
    func terminate() {
        guard let process else { return }
        process.terminationHandler = nil
        process.terminate()
        self.process = nil
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    /// Kills any adapter stream left behind by a previous instance of THIS
    /// bundle — matched on the script's absolute path, so another app's
    /// copy of the same adapter is never touched. A previous Ledge that was
    /// SIGKILLed, crashed, or whose SIGTERM the adapter ignored leaves a
    /// perl process streaming to nobody; each one holds a MediaRemote
    /// subscription and they accumulate across relaunches.
    static func reapOrphans(locator: AdapterLocator) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-f", "^/usr/bin/perl \(locator.scriptPath.path) .* stream$"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()   // pkill returns immediately; nothing to await
    }

    /// One-shot invocation for `send` / `seek`. Fire-and-forget: a lost
    /// playback command is not worth blocking on or retrying.
    static func fire(locator: AdapterLocator, command: MediaCommand) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = locator.commandArguments(command)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// Capability probe. Exit 0 means MediaRemote access still works.
    ///
    /// `async`, resumed from the process's termination handler — never
    /// `waitUntilExit()`. This used to block whichever thread called it,
    /// and `MediaService.start()` called it from inside its `AsyncStream`
    /// builder, which Swift runs synchronously at stream creation on the
    /// main actor: a slow perl start-up (cold disk, busy machine) stalled
    /// app launch, menu bar item included.
    static func probe(locator: AdapterLocator) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = locator.testArguments()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                // `run()` throwing means the handler will never fire.
                continuation.resume(returning: false)
            }
        }
    }
}
