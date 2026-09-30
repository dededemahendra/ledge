import Foundation
import OSLog
import ActivityKit

/// Focus on/off as a blip (2026-09-30): watches the Focus database's
/// assertions file once a second. With Full Disk Access the file is read
/// and the blip carries the Focus's symbol, colour and name; without it,
/// only the file's size is read — metadata is free — and the blip is the
/// moon and On/Off. Either way only transitions are announced.
@MainActor
public final class FocusService {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "focus")

    public private(set) var availability: ServiceAvailability = .available
    /// `.needsPermission("Full Disk Access")` until the database is
    /// readable — the menu offers the Settings pane; the blip works anyway.
    public private(set) var detail: ServiceAvailability = .needsPermission("Full Disk Access")

    private let database = FocusDatabaseReader()
    private var sizeDeriver = FocusSizeDeriver()
    private var lastModified: Date?
    private var lastMode: FocusMode?
    private var hasBaseline = false
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
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: FocusDatabaseReader.assertionsFile.path),
              let size = (attributes[.size] as? NSNumber)?.intValue
        else {
            availability = .unavailable(reason: "Focus state not readable")
            return
        }
        availability = .available
        let modified = attributes[.modificationDate] as? Date

        // The database, when readable: exact state and the Focus itself.
        if let current = database.activeMode() {
            if detail != .available {
                detail = .available
                Self.log.notice("focus: database readable — symbol, colour and name available")
            }
            defer { lastMode = current; lastModified = modified; hasBaseline = true }
            _ = sizeDeriver.sample(size: size)   // keep the fallback's baseline honest
            guard hasBaseline, modified != lastModified else { return }
            if let event = FocusEvent.transition(from: lastMode, to: current) {
                Self.log.notice("focus \(event.isOn ? "on" : "off", privacy: .public): \(event.mode?.name ?? "?", privacy: .private)")
                continuation?.yield(event)
            }
            return
        }

        // Otherwise the size alone.
        if detail == .available {
            detail = .needsPermission("Full Disk Access")
        }
        lastModified = modified
        hasBaseline = true
        if let event = sizeDeriver.sample(size: size) {
            Self.log.notice("focus \(event.isOn ? "on" : "off", privacy: .public) (assertions file \(size, privacy: .public) bytes)")
            continuation?.yield(event)
        }
    }
}
