import Testing
import AppKit
@testable import NotchKit

/// Every call a space makes, in order.
private final class CallLog {
    var calls: [String] = []
}

@MainActor
private func recordingCalls(_ log: CallLog) -> SkyLightSpace.Calls {
    SkyLightSpace.Calls(
        mainConnection: { log.calls.append("main"); return 11 },
        createSpace: { cid in log.calls.append("create \(cid)"); return 22 },
        setAbsoluteLevel: { cid, space, level in log.calls.append("level \(cid) \(space) \(level)") },
        showSpace: { cid, space in log.calls.append("show \(cid) \(space)") },
        addWindow: { cid, space, window in log.calls.append("add \(cid) \(space) \(window)") }
    )
}

/// One space, made at the level the system gives Notification Center at
/// screen lock, and shown (2026-10-21).
@MainActor
@Test func aSpaceIsMadeAtTheLockScreenLevelAndShown() {
    let log = CallLog()
    _ = SkyLightSpace(calls: recordingCalls(log))
    #expect(log.calls == ["main", "create 11", "level 11 22 400", "show 11 22"])
}

/// Adopting moves the window into that space, as often as it is asked:
/// the presenter adopts again on every order-in.
@MainActor
@Test func adoptingAWindowMovesItIntoTheSpace() {
    let log = CallLog()
    let space = SkyLightSpace(calls: recordingCalls(log))
    log.calls.removeAll()
    space.adopt(windowNumber: 409)
    space.adopt(windowNumber: 409)
    #expect(log.calls == ["add 11 22 409", "add 11 22 409"])
}

/// No space unless every one of the five calls is there; a future macOS
/// without one leaves the island an ordinary window.
@MainActor
@Test func theCallsResolveOnlyWhenEverySymbolIsThere() {
    let present = UnsafeMutableRawPointer(bitPattern: 0x1000)!
    #expect(SkyLightSpace.Calls.symbolNames.count == 5)
    #expect(SkyLightSpace.Calls.resolve { _ in present } != nil)
    for missing in SkyLightSpace.Calls.symbolNames {
        #expect(SkyLightSpace.Calls.resolve { $0 == missing ? nil : present } == nil, "\(missing) missing: no space")
    }
}
