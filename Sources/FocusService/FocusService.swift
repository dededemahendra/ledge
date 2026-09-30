import Foundation
import OSLog
import ActivityKit

/// Focus on/off as a blip (2026-09-30): polls the size of the Focus
/// database's assertions file once a second — metadata only, readable
/// without Full Disk Access — and streams the transitions
/// (`FocusSizeDeriver`). If the file cannot be stat'ed the menu says so.
@MainActor
public final class FocusService {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "focus")

    public static let assertionsFile = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/DoNotDisturb/DB/Assertions.json")

    public private(set) var availability: ServiceAvailability = .available

    private var deriver = FocusSizeDeriver()
    private var timer: Timer?
    private var continuation: AsyncStream<FocusEvent>.Continuation?

    public init() {}

    public func start() -> AsyncStream<FocusEvent> {
        let (stream, continuation) = AsyncStream<FocusEvent>.makeStream()
        self.continuation = continuation
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
        return stream
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        continuation?.finish()
        continuation = nil
    }

    private func poll() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: Self.assertionsFile.path),
              let size = (attributes[.size] as? NSNumber)?.intValue
        else {
            availability = .unavailable(reason: "Focus state not readable")
            return
        }
        availability = .available
        if let event = deriver.sample(size: size) {
            Self.log.notice("focus \(event == .on ? "on" : "off", privacy: .public) (assertions file \(size, privacy: .public) bytes)")
            continuation?.yield(event)
        }
    }
}
