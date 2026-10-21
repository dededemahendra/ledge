import AppKit
import OSLog

/// The private window-server space the island's window lives in
/// (2026-10-21, `2026-10-21-lock-screen-island-design.md`): one space at the
/// absolute level the system gives Notification Center at screen lock, which
/// draws over the lock screen and over every other window. macOS 27 covers
/// windows of any level with its lock screen (`docs/private-api-notes.md`);
/// a space at this level is the way past it.
///
/// The five SkyLight calls come in as plain closures (`Calls`), resolved from
/// the framework by `system()`, so the tests can record them.
/// `SLSShowSpaces` and `SLSSpaceAddWindowsAndRemoveFromSpaces` return nothing
/// readable on macOS 27 (the probe read `0xB0000000`, not a `CGError`), so the
/// only test of availability is that every symbol resolved.
@MainActor
public final class SkyLightSpace {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "notch")
    private static let frameworkPath = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"

    /// `kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`: above the
    /// screen lock's own 300.
    static let lockScreenLevel: Int32 = 400

    struct Calls {
        var mainConnection: () -> Int32
        /// `SLSSpaceCreate(cid, 1, 0)`.
        var createSpace: (_ connection: Int32) -> Int32
        var setAbsoluteLevel: (_ connection: Int32, _ space: Int32, _ level: Int32) -> Void
        /// `SLSShowSpaces(cid, [space])`.
        var showSpace: (_ connection: Int32, _ space: Int32) -> Void
        /// `SLSSpaceAddWindowsAndRemoveFromSpaces(cid, space, [window], 7)`.
        var addWindow: (_ connection: Int32, _ space: Int32, _ windowNumber: Int) -> Void

        static let symbolNames = [
            "SLSMainConnectionID", "SLSSpaceCreate", "SLSSpaceSetAbsoluteLevel",
            "SLSShowSpaces", "SLSSpaceAddWindowsAndRemoveFromSpaces",
        ]

        private typealias MainConnection = @convention(c) () -> Int32
        private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
        private typealias SetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
        private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
        private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

        /// The five calls from `lookup` (a symbol's name to its address), or
        /// `nil` when any one is missing.
        static func resolve(_ lookup: (String) -> UnsafeMutableRawPointer?) -> Calls? {
            let found = symbolNames.compactMap(lookup)
            guard found.count == symbolNames.count else { return nil }
            let main = unsafeBitCast(found[0], to: MainConnection.self)
            let create = unsafeBitCast(found[1], to: SpaceCreate.self)
            let setLevel = unsafeBitCast(found[2], to: SetAbsoluteLevel.self)
            let show = unsafeBitCast(found[3], to: ShowSpaces.self)
            let add = unsafeBitCast(found[4], to: AddWindows.self)
            return Calls(
                mainConnection: { main() },
                createSpace: { create($0, 1, 0) },
                setAbsoluteLevel: { _ = setLevel($0, $1, $2) },
                showSpace: { _ = show($0, [$1] as CFArray) },
                addWindow: { _ = add($0, $1, [$2] as CFArray, 7) }
            )
        }
    }

    private let calls: Calls
    private let connection: Int32
    private let space: Int32

    init(calls: Calls) {
        self.calls = calls
        connection = calls.mainConnection()
        space = calls.createSpace(connection)
        calls.setAbsoluteLevel(connection, space, Self.lockScreenLevel)
        calls.showSpace(connection, space)
    }

    /// The real space, or `nil` on a macOS without one of the calls; the
    /// island then stays an ordinary window and hides while locked. The
    /// framework stays open for the app's life, as the space does.
    public static func system() -> SkyLightSpace? {
        guard let handle = dlopen(frameworkPath, RTLD_LAZY) else {
            log.debug("SkyLight did not load; the island hides while locked")
            return nil
        }
        guard let calls = Calls.resolve({ dlsym(handle, $0) }) else {
            dlclose(handle)
            log.debug("a SkyLight space call is missing; the island hides while locked")
            return nil
        }
        return SkyLightSpace(calls: calls)
    }

    /// Moves `window` into the space. Done again on every order-in, since a
    /// window ordered out may come back in the user's own space.
    public func adopt(_ window: NSWindow) {
        adopt(windowNumber: window.windowNumber)
    }

    func adopt(windowNumber: Int) {
        calls.addWindow(connection, space, windowNumber)
    }
}
