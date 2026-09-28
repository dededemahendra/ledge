import Foundation
import CoreGraphics
import ActivityKit
import OSLog

/// Thin wrapper over the private `DisplayServices` framework.
///
/// Verified on macOS 27.0: the framework `dlopen`s and
/// `DisplayServicesGetBrightness(CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32`
/// returns 0 and writes a value in `0...1`.
///
/// The Interfaces section of this task's brief specifies this as a
/// `struct DisplayServicesBridge: ~Copyable` (it owns a `dlopen` handle, a
/// resource with exactly one owner that should be closed exactly once, which
/// is exactly what noncopyable value semantics are for). Tried that first;
/// it does not compile here because `Testing.#require` requires its argument
/// type to conform to `Copyable` in this toolchain ("no exact matches in
/// call to macro 'require'" / "candidate requires that 'DisplayServicesBridge'
/// conform to 'Copyable'") -- and the brief's own required test calls
/// `try #require(DisplayServicesBridge(), ...)`. Falling back to the `final
/// class` this task's Step 3 sample code actually uses, which is compatible
/// with that test. Kept as a `final class` rather than a plain (copyable)
/// struct wrapping the handle, since a copyable value type sharing one
/// `dlopen` handle across copies would reintroduce the double-close hazard
/// noncopyability was meant to prevent. Unlike the brief's sample, this does
/// call `dlclose` in `deinit` -- the sample never did.
public final class DisplayServicesBridge {
    private typealias GetBrightness =
        @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    /// `DisplayServicesSetBrightness(CGDirectDisplayID, float) -> int`, the
    /// same private call MonitorControl and BetterDisplay drive the built-in
    /// panel with. Resolved lazily and optionally: reading must keep working
    /// on a system that drops the setter.
    private typealias SetBrightness =
        @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    private let handle: UnsafeMutableRawPointer
    private let getBrightness: GetBrightness
    private let setBrightnessSymbol: SetBrightness?
    public let canRegisterForNotifications: Bool

    public init?() {
        guard let handle = dlopen(Self.frameworkPath, RTLD_LAZY) else { return nil }
        guard let symbol = dlsym(handle, "DisplayServicesGetBrightness") else {
            dlclose(handle)
            return nil
        }
        self.handle = handle
        self.getBrightness = unsafeBitCast(symbol, to: GetBrightness.self)
        self.setBrightnessSymbol = dlsym(handle, "DisplayServicesSetBrightness")
            .map { unsafeBitCast($0, to: SetBrightness.self) }
        self.canRegisterForNotifications =
            dlsym(handle, "DisplayServicesRegisterForBrightnessChangeNotifications") != nil
    }

    public func brightness(for display: CGDirectDisplayID) -> Double? {
        var value: Float = 0
        guard getBrightness(display, &value) == 0 else { return nil }
        guard value >= 0, value <= 1 else { return nil }
        return Double(value)
    }

    public var canSetBrightness: Bool { setBrightnessSymbol != nil }

    /// `false` when the symbol is missing or the call is refused.
    @discardableResult
    public func setBrightness(_ value: Double, for display: CGDirectDisplayID) -> Bool {
        guard let setBrightnessSymbol else { return false }
        return setBrightnessSymbol(display, Float(min(1, max(0, value)))) == 0
    }

    deinit {
        dlclose(handle)
    }
}

public enum BrightnessBackend: Sendable, Equatable {
    case notifications
    case polling
    case unavailable
}

/// Observes display brightness by value.
///
/// Prefers change notifications. Falls back to a cheap poll if the undocumented
/// callback signature turns out not to fire — a single C call at 10 Hz, which is
/// a deliberate, documented deviation from the spec's no-polling rule.
@MainActor
public final class BrightnessObserver {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "brightness")

    nonisolated public static let pollInterval: TimeInterval = 0.1

    public private(set) var availability: ServiceAvailability = .available
    public private(set) var backend: BrightnessBackend = .unavailable

    private let onChange: (Double) -> Void
    private let bridge: DisplayServicesBridge?
    private var timer: Timer?
    private var lastSeen: Double?

    public init(onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        self.bridge = DisplayServicesBridge()
    }

    // MARK: - pure decisions

    // `nonisolated`: pure functions of their parameters; @MainActor on the
    // class would otherwise make them implicitly async from a synchronous
    // test context (see VolumeObserver.strategy/availability for the same fix).
    nonisolated public static func backend(canRegister: Bool, canRead: Bool) -> BrightnessBackend {
        guard canRead else { return .unavailable }
        return canRegister ? .notifications : .polling
    }

    nonisolated public static func availability(for backend: BrightnessBackend) -> ServiceAvailability {
        backend == .unavailable
            ? .unavailable(reason: "DisplayServices brightness unavailable")
            : .available
    }

    // MARK: - lifecycle

    public func start() {
        let canRead = bridge?.brightness(for: CGMainDisplayID()) != nil
        // Registration is treated as unusable until Step 5 proves the signature.
        backend = Self.backend(canRegister: false, canRead: canRead)
        availability = Self.availability(for: backend)

        guard backend == .polling else {
            Self.log.info("brightness unavailable")
            return
        }
        startPolling()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.pollInterval, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = Self.pollInterval / 2   // let the OS coalesce wakeups
        tick()
    }

    private func tick() {
        guard let level = bridge?.brightness(for: CGMainDisplayID()) else { return }
        guard lastSeen != level else { return }
        lastSeen = level
        onChange(level)
    }
}
