# Island on the Lock Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The island shows on macOS 27's lock screen, on a MacBook's notch and on the pill, for looking at only, by living in a private window-server space above the lock screen.

**Architecture:** A new `SkyLightSpace` (NotchKit) makes one private space at absolute level 400 and moves windows into it; its five SkyLight calls come in as closures so tests can record them. `NotchPresenter` puts every island window it builds into that space, and again whenever it orders the window back in, and no longer hides the island on lock when it has a space and the switch is on. `NotchController` turns look-only while locked: every click, tap, swipe and intent is dropped. A switch in Settings › Island turns the lock-screen island off.

**Tech Stack:** Swift 6.4, Swift 6 language mode, SwiftUI + AppKit, SwiftPM only (no Xcode project), swift-testing (`import Testing`, `@Test`, `#expect`), macOS 27, the private SkyLight framework through `dlopen`/`dlsym`.

**Spec:** `docs/superpowers/specs/2026-10-21-lock-screen-island-design.md` (read it with this plan).

## Global Constraints

- The window lives in the private space from launch, always (approach B); there is no second window for the lock screen and no moving it out on unlock.
- The space's absolute level is `400` (`kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`); the space is created with `SLSSpaceCreate(cid, 1, 0)`; windows are added with `SLSSpaceAddWindowsAndRemoveFromSpaces(cid, space, [windowNumber], 7)`.
- Availability is "SkyLight loaded and all five symbols resolved", nothing else: `SLSShowSpaces` and `SLSSpaceAddWindowsAndRemoveFromSpaces` return nothing readable.
- No space, or the switch off: the 2026-10-01 behaviour exactly (tuck and hide on lock, come back tucked and pop on unlock).
- While locked: everything shows as unlocked; hover opens the card display-only; no click, tap, swipe or intent does anything.
- Settings › Island › "Show on the lock screen", `AppSettings.showsOnLockScreen`, default `true`.
- No third-party package: the five calls are written in Ledge.
- Run tests with `make test` (it adds the swift-testing plugin path); narrow with `make test FILTER=<name>`. Never call bare `swift test`.
- Two tests fail on a Mac without a built-in panel and are not this plan's concern: `brightnessTargetsTheBuiltInDisplay` and `bridgeLoadsAndReadsARealBrightnessValue`. Every other test must pass.
- Comments follow the files' own style: plain sentences, dated rationale like `(2026-10-21)` where a decision is recorded. Match the surrounding density.
- Text the user sees: Australian English, no em or en dashes, no exclamation marks, sentence case.
- Commit messages follow the repo's history: one lowercase plain-English sentence, no prefix, ending with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- The lock screen cannot be captured (`screencapture` fails while locked); every lock-screen check is by the user's eye. Do not lock the user's Mac yourself.

## Review Focus

1. The island hidden at rest (window ordered out), then shown while locked (hovering the empty spot, a timer, a blip): it must come back over the lock screen, not under it (Task 3 re-adopts on every order-in; Task 5 live check step 3).
2. Hover on the lock screen: the pointer may not reach Ledge while locked; resting on the island should open the card to look at (Task 5 live check step 4; a failure is recorded, not fixed here).
3. Unlocking with the card open under the pointer: the card stays open and its controls come back, with no collapse and no pop (Task 3, `unlockingWithTheCardOpenKeepsItOpenAndUntucked`).
4. A swipe over the locked island with music playing: no track skip and no skip glyph (Task 3, `aSwipeOnTheLockedIslandSkipsNothing`).
5. Day to day, the island above Spotlight, a full-screen video and the screen saver: nothing it covers becomes unusable (Task 5 live check step 7).

## Before Task 1

- [ ] Run `git status`. The tree should be clean apart from this plan and the spec's last corrections; commit those first if they are not yet committed (`git add docs/superpowers && git commit`), so each task's commit holds only that task.

## File structure

| File | Change |
| --- | --- |
| `Sources/NotchKit/SkyLightSpace.swift` | New: the private space and its five calls |
| `Sources/NotchKit/NotchController.swift` | Look only while `isLocked`: `tap`, `click`, `swipe`, `linkURL`, `emit` |
| `Sources/NotchKit/NotchRootView.swift` | The detail row takes no hits while locked |
| `Sources/NotchKit/NotchPresenter.swift` | The space, adopt on build and order-in, `showsOnLockScreen`, lock path, `setShowsOnLockScreen`, swipe guard |
| `Sources/NotchKit/NotchWindow.swift` | `setLocked` and the shield level removed |
| `Sources/LedgeSettings/AppSettings.swift` | `showsOnLockScreen` |
| `Sources/Ledge/SettingsWindow.swift` | The switch in Settings › Island |
| `Sources/Ledge/AppModel.swift` | Applies the switch |
| `Tests/NotchKitTests/SkyLightSpaceTests.swift` | New |
| `Tests/NotchKitTests/NotchControllerTests.swift`, `NotchPresenterTests.swift` | Look-only and lock-path tests |
| `Tests/NotchWindowTests/NotchWindowTests.swift` | The shield-level test removed |
| `Tests/LedgeSettingsTests/AppSettingsTests.swift` | The switch's default and round trip |
| `docs/private-api-notes.md`, `docs/superpowers/specs/2026-09-25-notch-companion-design.md`, `README.md`, `docs/manual-checks.md` | Docs |

---

### Task 1: The private space

**Files:**
- Create: `Sources/NotchKit/SkyLightSpace.swift`
- Test: `Tests/NotchKitTests/SkyLightSpaceTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `@MainActor public final class SkyLightSpace`
  - `struct SkyLightSpace.Calls` (internal) with closure properties `mainConnection: () -> Int32`, `createSpace: (Int32) -> Int32`, `setAbsoluteLevel: (Int32, Int32, Int32) -> Void`, `showSpace: (Int32, Int32) -> Void`, `addWindow: (Int32, Int32, Int) -> Void`, its memberwise `init`, `static let symbolNames: [String]`, `static func resolve(_ lookup: (String) -> UnsafeMutableRawPointer?) -> Calls?`
  - `static let lockScreenLevel: Int32 = 400`
  - `init(calls: Calls)` (internal): creates, levels and shows the space
  - `public static func system() -> SkyLightSpace?`
  - `public func adopt(_ window: NSWindow)` and `func adopt(windowNumber: Int)` (internal)

- [ ] **Step 1: Write the failing tests.** Create `Tests/NotchKitTests/SkyLightSpaceTests.swift`:

```swift
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
```

- [ ] **Step 2: Run them and watch them fail.**

Run: `make test FILTER=SkyLightSpaceTests`
Expected: a compile error, `cannot find 'SkyLightSpace' in scope`.

- [ ] **Step 3: Implement.** Create `Sources/NotchKit/SkyLightSpace.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests and watch them pass.**

Run: `make test FILTER=SkyLightSpaceTests`
Expected: 3 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/NotchKit/SkyLightSpace.swift Tests/NotchKitTests/SkyLightSpaceTests.swift
git commit -m "a private window-server space above the lock screen, for the island's window to live in

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Look only while locked

**Files:**
- Modify: `Sources/NotchKit/NotchController.swift` (`isLocked`'s comment, `click()`, `tap()`, `swipe(_:)`, `linkURL`, `emit(_:)`)
- Modify: `Sources/NotchKit/NotchRootView.swift` (the `detailRow` call in `islandContent`, about line 589)
- Test: `Tests/NotchKitTests/NotchControllerTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: while `NotchController.isLocked`, `tap()` and `click()` do nothing, `swipe(_:)` returns `false` without changing `panel`, `linkURL` is `nil`, and `emit(_:)` does not call `onIntent`. Task 3 relies on `swipe(_:)` returning `false` while locked.

- [ ] **Step 1: Write the failing tests.** Append to `Tests/NotchKitTests/NotchControllerTests.swift`:

```swift
// MARK: - Look only on the lock screen (2026-10-21)

/// Nothing on the locked island can be operated: no link, no pin, no
/// intent from the card's buttons. Unlocking gives it all back.
@MainActor
@Test func whileLockedNothingOnTheIslandCanBeOperated() {
    let c = makeController()
    var intents: [NotchIntent] = []
    c.onIntent = { intents.append($0) }
    let join = URL(string: "https://example.com/join")!
    c.setMedia(someMedia())
    c.setActivities([.init(id: NotchController.calendarActivityID, title: "Standup", compactText: "Now",
                           symbolName: "calendar", url: join)], overflow: 0)
    c.setLocked(true)

    #expect(c.linkURL == nil, "no link pointer and no press dip")
    c.tap()
    c.click()
    #expect(!c.isPinnedOpen && c.state != .expanded, "a click never pins the card")
    c.emit(.togglePlayPause)
    c.emit(.open(URL(string: "https://example.com")!))
    #expect(intents.isEmpty, "nothing reaches the app, not even the blip's link")

    c.setLocked(false)
    #expect(c.linkURL == join)
    c.emit(.togglePlayPause)
    #expect(intents == [.togglePlayPause])
}

/// Hover still opens the card to look at; a swipe changes nothing.
@MainActor
@Test func whileLockedHoverStillOpensTheCardAndASwipeTakesNothing() {
    let c = makeController()
    c.setMedia(someMedia())
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    c.setCalendarMode(CalendarModeData(monthTitle: "October 2026", weekdaySymbols: ["S", "M", "T", "W", "T", "F", "S"],
                                       weeks: [[nil, nil, nil, 1, 2, 3, 4]], today: 1, markedDays: [], items: []))
    c.setLocked(true)
    c.setHovered(true)
    #expect(c.state == .expanded, "hover opens the card to look at")
    #expect(!c.swipe(.next) && c.panel == .media, "no mode change while locked")

    c.setLocked(false)
    #expect(c.swipe(.next) && c.panel == .calendar)
}
```

- [ ] **Step 2: Run them and watch them fail.**

Run: `make test FILTER=whileLocked`
Expected: both fail: `linkURL` is the join URL, `intents` holds `.open(...)` and `.togglePlayPause`, and `swipe(.next)` returns `true`.

- [ ] **Step 3: Implement.** In `Sources/NotchKit/NotchController.swift`:

Replace the comment above `isLocked`

```swift
    /// The screen is locked (`loginwindow` owns it). Spec §7: lock-screen
    /// mode is display-only — with media playing the panel shows the
    /// now-playing card without its controls (`NotchRootView` reads this
    /// flag to strip them), since a panel above the lock shield can render
    /// but cannot reliably take clicks. Charging/HUD/device activities keep
    /// appearing in the ears exactly as when unlocked.
    public private(set) var isLocked = false
```

with

```swift
    /// The screen is locked (`loginwindow` owns it). Look only (2026-10-21,
    /// user's call): everything shows as unlocked and hover opens the card,
    /// the now-playing one without its controls (`NotchRootView` reads this
    /// flag to strip them), but nothing can be operated: `tap()`, `click()`
    /// and `swipe(_:)` do nothing, `linkURL` is `nil` and `emit(_:)` drops
    /// every intent.
    public private(set) var isLocked = false
```

In `click()`, replace

```swift
        guard metrics.notchRect.width > 0, media != nil else { return }
```

with

```swift
        guard !isLocked, metrics.notchRect.width > 0, media != nil else { return }
```

At the top of `tap()`'s body, before `if state == .expanded {`, insert

```swift
        // Look only on the lock screen (2026-10-21): nothing is a button.
        guard !isLocked else { return }
```

At the top of `swipe(_:)`'s body, before `let panels = availablePanels`, insert

```swift
        // Look only on the lock screen (2026-10-21): taken by nobody, and
        // the presenter skips no track while locked either.
        guard !isLocked else { return false }
```

In `linkURL`, replace

```swift
        guard state != .expanded else { return nil }
```

with

```swift
        guard state != .expanded, !isLocked else { return nil }
```

Replace `emit(_:)`

```swift
    public func emit(_ intent: NotchIntent) {
        onIntent?(intent)
    }
```

with

```swift
    public func emit(_ intent: NotchIntent) {
        // The one gate for the card's buttons on the lock screen
        // (2026-10-21): play/pause, skip, the scrubber, the star, the
        // outputs, a calendar row, the Live Activity's press.
        guard !isLocked else { return }
        onIntent?(intent)
    }
```

In `Sources/NotchKit/NotchRootView.swift`, in `islandContent`, replace

```swift
            } else if parameters.height > row.height + 8 {
                detailRow
                    // Mode changes slide the way the swipe went, on the
```

with

```swift
            } else if parameters.height > row.height + 8 {
                detailRow
                    // Look only on the lock screen (2026-10-21): no row or
                    // button on the card takes a press, so none dips.
                    .allowsHitTesting(!controller.isLocked)
                    // Mode changes slide the way the swipe went, on the
```

- [ ] **Step 4: Run the tests and watch them pass.**

Run: `make test FILTER=NotchKitTests`
Expected: every NotchKitTests test passes, including the two new ones and the existing lock tests (`lockingLeavesTheStateAloneAndUnlockingRestoresIt`, `lockingWithNothingPlayingShowsNothingExtra`, `aPinnedPanelSurvivesLockAndUnlock`).

Run: `make test FILTER=lockedMediaPanelRendersInsideTheIslandWithoutItsControlRow`
Expected: passes.

- [ ] **Step 5: Commit.**

```bash
git add Sources/NotchKit/NotchController.swift Sources/NotchKit/NotchRootView.swift Tests/NotchKitTests/NotchControllerTests.swift
git commit -m "make the locked island look only: no click, tap, swipe or button does anything until unlock

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The presenter keeps the island on the lock screen

**Files:**
- Modify: `Sources/NotchKit/NotchPresenter.swift` (properties, `init`, `start()`'s lock comment, `setLocked(_:)`, new `setShowsOnLockScreen(_:)`, `rebuildForCurrentScreen()`, `syncWindowToVisibility()`, new `shouldShowWindow`, `handleSwipe`)
- Modify: `Sources/NotchKit/NotchWindow.swift` (remove `lockedLevel` and `setLocked(_:)`)
- Modify: `Tests/NotchWindowTests/NotchWindowTests.swift` (remove `lockedStateRaisesAboveTheShield`)
- Test: `Tests/NotchKitTests/NotchPresenterTests.swift`

**Interfaces:**
- Consumes: `SkyLightSpace`, its internal `init(calls:)` and `Calls` memberwise init (Task 1); `NotchController.swipe(_:)` returning `false` while locked (Task 2).
- Produces:
  - `public init(space: SkyLightSpace? = SkyLightSpace.system())`
  - `public var showsOnLockScreen: Bool`
  - `public func setShowsOnLockScreen(_ shows: Bool)` (Task 4 calls it)
  - `nonisolated static func shouldShowWindow(visible: Bool, locked: Bool, showsOnLockScreen: Bool) -> Bool`
  - `func handleSwipe(deltaX:phase:invertedFromDevice:)` becomes internal (was private), for its test

- [ ] **Step 1: Write the failing tests.** Append to `Tests/NotchKitTests/NotchPresenterTests.swift`:

```swift
// MARK: - The lock screen (2026-10-21)

@Test func theWindowShowsWhileLockedOnlyWhenTheIslandMayBeThere() {
    #expect(NotchPresenter.shouldShowWindow(visible: true, locked: false, showsOnLockScreen: false))
    #expect(NotchPresenter.shouldShowWindow(visible: true, locked: true, showsOnLockScreen: true))
    #expect(!NotchPresenter.shouldShowWindow(visible: true, locked: true, showsOnLockScreen: false),
            "no space or the switch off: hidden while locked, as from 2026-10-01")
    #expect(!NotchPresenter.shouldShowWindow(visible: false, locked: false, showsOnLockScreen: true), "nothing to show")
    #expect(!NotchPresenter.shouldShowWindow(visible: false, locked: true, showsOnLockScreen: true))
}

/// A space whose calls do nothing: a presenter that may show on the lock
/// screen, without touching the real window server.
@MainActor
private func quietSpace() -> SkyLightSpace {
    SkyLightSpace(calls: .init(mainConnection: { 1 }, createSpace: { _ in 2 }, setAbsoluteLevel: { _, _, _ in },
                               showSpace: { _, _ in }, addWindow: { _, _, _ in }))
}

@MainActor
private func playing(_ p: NotchPresenter) {
    p.controller.setMedia(MediaPresentation(title: "Song", artist: "Artist", artwork: nil, isPlaying: true, elapsed: 10, duration: 200))
    p.controller.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
}

@MainActor
@Test func withASpaceLockingKeepsTheIslandOutAndLookOnly() {
    let p = NotchPresenter(space: quietSpace())
    #expect(p.showsOnLockScreen)
    playing(p)
    p.setLocked(true)
    #expect(p.controller.isLocked)
    #expect(!p.controller.isTucked, "not tucked into the notch: it stays on the lock screen")
    #expect(p.controller.state == .activity)
    p.setLocked(false)
    #expect(!p.controller.isLocked && !p.controller.isTucked)
}

@MainActor
@Test func withoutASpaceLockingTucksAndHidesAsBefore() {
    let p = NotchPresenter(space: nil)
    #expect(!p.showsOnLockScreen)
    playing(p)
    p.setLocked(true)
    #expect(p.controller.isLocked && p.controller.isTucked, "tucked and hidden while locked, the 2026-10-01 behaviour")
}

@MainActor
@Test func theSwitchFlippedWhileLockedHidesOrShowsTheIslandAtOnce() {
    let p = NotchPresenter(space: quietSpace())
    playing(p)
    p.setLocked(true)
    p.setShowsOnLockScreen(false)
    #expect(!p.showsOnLockScreen && p.controller.isTucked)
    p.setShowsOnLockScreen(true)
    #expect(p.showsOnLockScreen && !p.controller.isTucked)
}

/// Review Focus 3: unlocking under a card the pointer opened keeps it open,
/// controls back, with no tuck and so no collapse or pop.
@MainActor
@Test func unlockingWithTheCardOpenKeepsItOpenAndUntucked() {
    let p = NotchPresenter(space: quietSpace())
    playing(p)
    p.controller.setHovered(true)
    #expect(p.controller.state == .expanded)
    p.setLocked(true)
    #expect(p.controller.state == .expanded)
    p.setLocked(false)
    #expect(p.controller.state == .expanded && !p.controller.isTucked && !p.controller.isLocked)
}

/// Review Focus 4: a two-finger swipe over the locked island with music
/// playing skips nothing and shows no skip glyph.
@MainActor
@Test func aSwipeOnTheLockedIslandSkipsNothing() {
    let p = NotchPresenter(space: quietSpace())
    var intents: [NotchIntent] = []
    p.controller.onIntent = { intents.append($0) }
    playing(p)
    p.setLocked(true)
    p.handleSwipe(deltaX: 0, phase: .began, invertedFromDevice: true)
    p.handleSwipe(deltaX: -60, phase: .changed, invertedFromDevice: true)
    #expect(intents.isEmpty)
    #expect(p.controller.skipHint == nil, "no skip glyph while locked")
}
```

The file's existing imports (`Testing`, `CoreGraphics`, `@testable import NotchKit`) cover everything these tests use.

- [ ] **Step 2: Run them and watch them fail.**

Run: `make test FILTER=NotchPresenterTests`
Expected: a compile error: `extra argument 'space' in call`, `type 'NotchPresenter' has no member 'shouldShowWindow'`, and `'handleSwipe' is inaccessible due to 'private' protection level`.

- [ ] **Step 3: Implement.** In `Sources/NotchKit/NotchPresenter.swift`:

After `private var lockObserver: LockScreenObserver?`, insert

```swift
    /// The private space the window lives in (2026-10-21), or `nil` on a
    /// macOS without the calls; see `SkyLightSpace`.
    private let space: SkyLightSpace?
    /// Settings › Island › "Show on the lock screen".
    private var lockScreenEnabled = true

    /// The island stays on the lock screen, look only (2026-10-21): there
    /// is a space to draw it over the lock screen and the switch is on.
    /// Otherwise it hides while locked, as it has since 2026-10-01.
    public var showsOnLockScreen: Bool { space != nil && lockScreenEnabled }
```

Replace

```swift
    public init() {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
```

with

```swift
    public init(space: SkyLightSpace? = SkyLightSpace.system()) {
        self.space = space
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
```

In `start()`, replace

```swift
        // Lock screen, spec §7: raise the window above the lock shield and
        // switch the controller to display-only while `loginwindow` owns
        // the screen. Built last, as the spec sequenced it; nothing else
        // depends on it and it can be removed without touching anything.
```

with

```swift
        // Lock screen, spec §7 and 2026-10-21: from its space the island
        // stays on the lock screen, look only; without one, or with the
        // switch off, it hides while locked.
```

Replace the whole `setLocked(_:)` doc comment and body

```swift
    /// Screen locked/unlocked (`LockScreenObserver`). Nothing is drawn on
    /// the lock screen (2026-10-01): macOS 27 composites the lock screen
    /// over every user window, so raising the island there only ever
    /// bought an unlock that collapsed a card the user never saw — ears
    /// drawn outside a shrinking shape, then a window left out (user's
    /// recording). Now the island is simply hidden while locked, its state
    /// untouched, and shown again exactly as it was.
    public private(set) var isLocked = false

    public func setLocked(_ locked: Bool) {
        isLocked = locked
        controller.setLocked(locked)
        if locked {
```

with

```swift
    /// Screen locked/unlocked (`LockScreenObserver`). With a space and the
    /// switch on (2026-10-21) the island stays where it is and turns look
    /// only (`NotchController.isLocked`): no tuck on the way in and no pop
    /// on the way out, since it never left. Otherwise, as from 2026-10-01:
    /// macOS 27 composites the lock screen over every window level, so the
    /// island is hidden while locked, its state untouched, and shown again
    /// exactly as it was.
    public private(set) var isLocked = false

    public func setLocked(_ locked: Bool) {
        isLocked = locked
        controller.setLocked(locked)
        if showsOnLockScreen {
            controller.setTucked(false)
            syncWindowToVisibility()
            return
        }
        if locked {
```

(the rest of the old body, the `if locked { … return }` block and the unlock path after it, stays exactly as it is).

Directly after `setLocked(_:)`'s closing brace, insert

```swift
    /// Settings › Island › "Show on the lock screen" (2026-10-21). Flipped
    /// while locked, the island goes or comes back at once.
    public func setShowsOnLockScreen(_ shows: Bool) {
        guard shows != lockScreenEnabled else { return }
        lockScreenEnabled = shows
        guard isLocked else { return }
        controller.setTucked(!showsOnLockScreen)
        syncWindowToVisibility()
    }
```

In `rebuildForCurrentScreen()`, replace

```swift
            window = created
        }
        syncWindowToVisibility()
```

with

```swift
            window = created
            space?.adopt(created)
        }
        syncWindowToVisibility()
```

In `syncWindowToVisibility()`, replace

```swift
        // Nothing shows while locked (final, 2026-10-01: the shield level and
        // `canBecomeVisibleWithoutLogin` were both tried live and macOS 27
        // covers them); the window goes after the tuck's retract settles.
        let shouldShow = controller.isVisible && !isLocked
        if shouldShow {
            hideTask?.cancel()
            hideTask = nil
            window.orderFrontRegardless()
        } else if hideTask == nil {
```

with

```swift
        // Locked, the island shows only from its space (2026-10-21); with
        // no space or the switch off, nothing shows while locked (2026-10-01:
        // macOS 27 covers every window level), and the window goes after the
        // tuck's retract settles.
        let shouldShow = Self.shouldShowWindow(visible: controller.isVisible, locked: isLocked,
                                               showsOnLockScreen: showsOnLockScreen)
        if shouldShow {
            hideTask?.cancel()
            hideTask = nil
            let wasOut = !window.isVisible
            window.orderFrontRegardless()
            // Back in after being out: into the space again, which an
            // order-out may have taken it from (2026-10-21).
            if wasOut { space?.adopt(window) }
        } else if hideTask == nil {
```

and, in the same method, replace

```swift
                guard !Task.isCancelled, let self, !(self.controller.isVisible && !self.isLocked) else { return }
```

with

```swift
                guard !Task.isCancelled, let self,
                      !NotchPresenter.shouldShowWindow(visible: self.controller.isVisible, locked: self.isLocked,
                                                       showsOnLockScreen: self.showsOnLockScreen)
                else { return }
```

Directly after `shouldAcceptMouse(visible:hovered:)`, insert

```swift
    /// Pure, pinned by `NotchPresenterTests`: the window is ordered in while
    /// the island has something to show, and while locked only when it may
    /// show on the lock screen (2026-10-21).
    nonisolated static func shouldShowWindow(visible: Bool, locked: Bool, showsOnLockScreen: Bool) -> Bool {
        visible && (!locked || showsOnLockScreen)
    }
```

Replace

```swift
    private func handleSwipe(deltaX: CGFloat, phase: SwipeToSkipTracker.Phase, invertedFromDevice: Bool) {
        guard controller.isVisible else { return }
```

with

```swift
    func handleSwipe(deltaX: CGFloat, phase: SwipeToSkipTracker.Phase, invertedFromDevice: Bool) {
        // Look only on the lock screen (2026-10-21): no mode change, no skip.
        guard controller.isVisible, !controller.isLocked else { return }
```

In `Sources/NotchKit/NotchWindow.swift`, delete

```swift
    private static var lockedLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
    }

```

and

```swift
    public func setLocked(_ locked: Bool) {
        level = locked ? Self.lockedLevel : Self.normalLevel
    }

```

In `Tests/NotchWindowTests/NotchWindowTests.swift`, delete the whole test

```swift
@MainActor
@Test func lockedStateRaisesAboveTheShield() throws {
    let w = try makeWindow()
    w.setLocked(true)
    #expect(w.level.rawValue == Int(CGShieldingWindowLevel()) + 1)
    w.setLocked(false)
    #expect(w.level.rawValue == NSWindow.Level.statusBar.rawValue + 1)
}

```

- [ ] **Step 4: Run the tests and watch them pass.**

Run: `make test FILTER=NotchPresenterTests`
Expected: every test passes, the six new ones included.

Run: `make test FILTER=NotchWindowTests`
Expected: passes, with `lockedStateRaisesAboveTheShield` gone.

- [ ] **Step 5: Commit.**

```bash
git add Sources/NotchKit/NotchPresenter.swift Sources/NotchKit/NotchWindow.swift Tests/NotchKitTests/NotchPresenterTests.swift Tests/NotchWindowTests/NotchWindowTests.swift
git commit -m "keep the island on the lock screen from its private space, look only, and hide it as before without one

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The switch

**Files:**
- Modify: `Sources/LedgeSettings/AppSettings.swift`
- Modify: `Sources/Ledge/SettingsWindow.swift` (`IslandSettings`)
- Modify: `Sources/Ledge/AppModel.swift` (`applySettings()`)
- Test: `Tests/LedgeSettingsTests/AppSettingsTests.swift`

**Interfaces:**
- Consumes: `NotchPresenter.setShowsOnLockScreen(_:)` (Task 3).
- Produces: `AppSettings.Key.showsOnLockScreen = "showsOnLockScreen"`, `AppSettings.showsOnLockScreen: Bool` (default `true`).

- [ ] **Step 1: Write the failing test.** Append to `Tests/LedgeSettingsTests/AppSettingsTests.swift`:

```swift
/// The lock screen switch (2026-10-21): on by default, remembered off.
@MainActor
@Test func theLockScreenSwitchIsOnByDefaultAndRemembered() {
    let (s, defaults) = fresh()
    #expect(s.showsOnLockScreen)
    var changes = 0
    s.onChange = { changes += 1 }
    s.showsOnLockScreen = false
    #expect(changes == 1)
    #expect(!AppSettings(defaults: defaults).showsOnLockScreen)
}
```

- [ ] **Step 2: Run it and watch it fail.**

Run: `make test FILTER=theLockScreenSwitchIsOnByDefaultAndRemembered`
Expected: a compile error, `value of type 'AppSettings' has no member 'showsOnLockScreen'`.

- [ ] **Step 3: Implement.** In `Sources/LedgeSettings/AppSettings.swift`:

In `Key`, after `public static let showsLiveActivities = "showsLiveActivities"`, insert

```swift
        public static let showsOnLockScreen = "showsOnLockScreen"
```

After `public var showsLiveActivities: Bool { didSet { save(showsLiveActivities, Key.showsLiveActivities) } }`, insert

```swift
    /// The island over the lock screen, look only (2026-10-21).
    public var showsOnLockScreen: Bool { didSet { save(showsOnLockScreen, Key.showsOnLockScreen) } }
```

In `init(defaults:)`, after the `showsLiveActivities = …` line, insert

```swift
        showsOnLockScreen = defaults.object(forKey: Key.showsOnLockScreen) as? Bool ?? true
```

In `Sources/Ledge/SettingsWindow.swift`, in `IslandSettings.body`, after the "Coming up" section's closing `}` (the one ending with its `footer`) and before the `Form`'s closing `}`, insert

```swift
            Section {
                Toggle("Show on the lock screen", isOn: bind(\.showsOnLockScreen))
            } header: {
                Text("Lock screen")
            } footer: {
                Text("While the Mac is locked the island shows what it shows unlocked, meeting and reminder titles included, for anyone at the Mac to see. Resting on it opens the card to look at; nothing on it can be pressed until you unlock.")
            }
```

In `Sources/Ledge/AppModel.swift`, in `applySettings()`, after `presenter.setHoverDwell(settings.hoverDwell)`, insert

```swift
        presenter.setShowsOnLockScreen(settings.showsOnLockScreen)
```

- [ ] **Step 4: Run the tests and watch them pass.**

Run: `make test FILTER=LedgeSettingsTests`
Expected: every test passes, the new one included.

Run: `make test`
Expected: everything passes except the two known brightness tests.

- [ ] **Step 5: Commit.**

```bash
git add Sources/LedgeSettings/AppSettings.swift Sources/Ledge/SettingsWindow.swift Sources/Ledge/AppModel.swift Tests/LedgeSettingsTests/AppSettingsTests.swift
git commit -m "a switch in Settings for the island on the lock screen, on by default

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Docs, the full suite, and the live check

**Files:**
- Modify: `docs/private-api-notes.md` (the "Lock screen: closed (2026-10-01, final)" section)
- Modify: `docs/superpowers/specs/2026-09-25-notch-companion-design.md` (§7 LockScreenService, and a dated section at the end)
- Modify: `README.md` (the Settings paragraph and "What it deliberately doesn't do")
- Modify: `docs/manual-checks.md` (a new dated section at the end)

**Interfaces:**
- Consumes: everything above. Produces: nothing for code.

- [ ] **Step 1: Private API notes.** In `docs/private-api-notes.md`, replace the whole section from `## Lock screen: closed (2026-10-01, final)` to the end of its paragraph (`…do not try again without a new API.`) with

```markdown
## Lock screen: a private space (2026-10-21)

Closed on 2026-10-01: window levels 1000 / 2005 / 3000 /
`CGShieldingWindowLevel() + 1`, and `canBecomeVisibleWithoutLogin = true` with
the shield level, were all invisible under macOS 27's lock screen.

Reopened 2026-10-21 with a private window-server space, the technique of the
MIT-licensed `SkyLightWindow` package (Boring Notch uses it). From
`/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight`:

- `SLSMainConnectionID() -> int`
- `SLSSpaceCreate(cid, 1, 0) -> int` (the space id)
- `SLSSpaceSetAbsoluteLevel(cid, space, 400) -> CGError`: 400 is
  `kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`, above the screen
  lock's 300. Returned 0.
- `SLSShowSpaces(cid, [space])` and
  `SLSSpaceAddWindowsAndRemoveFromSpaces(cid, space, [windowNumber], 7)`:
  both returned `0xB0000000`, not a `CGError`; read as no return value.

A probe panel moved into that space showed on the lock screen for as long as it
was locked (seen by the user on the Mac mini), and its own tracking area got
pointer enter, exit and a click there. `screencapture` cannot capture the lock
screen ("could not create image from rect"). In the app: `SkyLightSpace`,
`2026-10-21-lock-screen-island-design.md`.
```

- [ ] **Step 2: Design spec.** In `docs/superpowers/specs/2026-09-25-notch-companion-design.md`, directly under the heading `### LockScreenService — fragile, built last`, insert

```markdown

**Reopened 2026-10-21:** the island now lives in a private window-server space
above the lock screen and shows there, look only. See "The island on the lock
screen (2026-10-21)" at the end and `2026-10-21-lock-screen-island-design.md`.
```

and append at the end of the file

```markdown

## The island on the lock screen (2026-10-21)

Lifts the park of §7 (user's call). The island's window lives in a private
window-server space at absolute level 400, from launch, so it draws over the
lock screen (and, all the time, over every other window). While locked it shows
everything it shows unlocked, meeting and reminder titles included, and is look
only: hover opens the card display-only; no click, tap, swipe or button does
anything. Settings › Island › "Show on the lock screen" turns it off. Without
the SkyLight calls, or with the switch off, it hides while locked as before.
Design: `2026-10-21-lock-screen-island-design.md`.
```

- [ ] **Step 3: README.** In `README.md`, replace

```
caption), Island (which blips show: keys, battery, devices, Focus, Clock timers, Live Activities,
calendar events, reminders), Media (which music apps the island follows),
```

with

```
caption), Island (which blips show: keys, battery, devices, Focus, Clock timers, Live Activities,
calendar events, reminders; and whether the island shows on the lock screen, look
only), Media (which music apps the island follows),
```

and delete

```
- **Lock screen.** Wired and parked: on this macOS the lock screen is composited
  over every user window regardless of level. Findings in the spec, §7.
```

- [ ] **Step 4: Full suite.**

Run: `make test`
Expected: every test run passes except `HUDServiceTests`, with exactly two issues: `brightnessTargetsTheBuiltInDisplay` and `bridgeLoadsAndReadsARealBrightnessValue`. Any other failure stops here.

- [ ] **Step 5: Install.** The user runs Ledge from `/Applications`. Build, install and relaunch that copy:

```bash
make install && make stop; open /Applications/Ledge.app; sleep 3; pgrep -lx Ledge
```

Expected: one `Ledge` process. Signing may ask for the login keychain password unless `make cert-allow` has been run; the user answers that prompt.

- [ ] **Step 6: Live check, by the user.** The lock screen cannot be captured and the user's Mac must not be locked by the agent. Ask the user to do each of these and say what they saw:

1. Play music. Lock (Ctrl+Cmd+Q). The now-playing island is at the top centre of the lock screen.
2. Rest the pointer on it. The card opens, with artwork, title and progress and no control row (Review Focus 2). If it does not open, record that hover does not reach Ledge while locked; the island showing is still the feature.
3. Pause the music from the keyboard or AirPods, so the island hides; then rest the pointer on the empty spot at the top centre while still locked. The island comes back over the lock screen, not under it (Review Focus 1).
4. Click the island and a row of the card while locked. Nothing happens: no music change, no app opens after unlocking.
5. Unlock with the card open under the pointer. It stays open and its controls are back, with no collapse.
6. Turn off Settings › Island › "Show on the lock screen" and lock again. Nothing shows while locked; unlock, and the island pops back as before. Turn it on again.
7. Unlocked: open Spotlight, play a full-screen video, and start the screen saver (or wait for it), with the island showing. Note whether the island draws over each and whether anything it covers stops working (Review Focus 5).

- [ ] **Step 7: Record the check.** Append to `docs/manual-checks.md` a section `## The island on the lock screen (2026-10-21)` that says, for each of the seven steps, what the user saw, in the file's plain past-tense style, and what was not checked (a MacBook's notch and a display change while locked, unless the user did them).

- [ ] **Step 8: Commit.**

```bash
git add README.md docs/private-api-notes.md docs/superpowers/specs/2026-09-25-notch-companion-design.md docs/manual-checks.md
git commit -m "describe the island on the lock screen, and record its live check

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
