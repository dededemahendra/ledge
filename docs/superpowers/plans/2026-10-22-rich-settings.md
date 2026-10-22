# Rich Settings (the look) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every option in Settings gets an icon and a line on what it does, and General, Island, Media and Calendar get a live strip at the top showing the real island in the scene of the row the pointer rests on.

**Architecture:** A new library target, `SettingsKit`, holds everything with logic: `PreviewScene` (what a strip can show), `PreviewContent` (the user's own content, with samples), `PreviewStage` (puts a private `NotchController` into a scene, built from the app's own event types), `PreviewDirector` (picks the scene from the pointer, switch-ons and a clock), and the views `PreviewStrip`, `SettingsRow`, `SettingsTile`, `StatusPill`. The panes move out of `SettingsWindow.swift` into `SettingsPanes.swift` in the app target and are rebuilt from those pieces; `AppModel` gains `previewContent()`.

**Tech Stack:** Swift 6.4, Swift 6 language mode, SwiftUI + AppKit, SwiftPM only (no Xcode project), swift-testing (`import Testing`, `@Test`, `#expect`), macOS 27, Observation (`@Observable`).

**Spec:** `docs/superpowers/specs/2026-10-22-rich-settings-design.md` (read it with this plan).

## Global Constraints

- Run tests with `make test` (it adds the swift-testing plugin path); narrow with `make test FILTER=<name>`. Never call bare `swift test`.
- Two tests fail on this Mac (no built-in display) and are not this plan's concern: `brightnessTargetsTheBuiltInDisplay` and `bridgeLoadsAndReadsARealBrightnessValue`. Every other test must pass.
- `@State` cannot be used as a macro on this toolchain: write state as `private var _name: State<T>` set with `State(initialValue:)` in `init`, read through a computed property, exactly as the code below does. `@Observable` and `@ObservationIgnored` do work.
- The strip's controller is fenced: `onIntent = nil` and `.allowsHitTesting(false)`; nothing in a strip may reach the app or the real island.
- A sample is always labelled in the caption: `"<title> · Sample: <reason>"`.
- Director timings: `cycleInterval` 2.5 s, `playDuration` 3 s.
- Strip heights: `PreviewStrip.shortHeight` 104 (Island, Media, Calendar), `PreviewStrip.tallHeight` 214 (General).
- Window: content 780 × 620, minimum 720 × 560.
- Text people read: Australian English, no em or en dashes, no exclamation marks, sentence case; a row's explanation is one short sentence ending in a full stop.
- Comments follow the files' own style: plain sentences, dated rationale like `(2026-10-22)`.
- Commit messages: one lowercase plain-English sentence, no prefix, then a blank line, then `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Implementers do not launch, install or stop the app and never lock the screen; the live check is the controller's.

## Review Focus

1. The pointer sweeping quickly down a pane: the next row's enter can arrive before the last row's leave; the strip must show the row under the pointer (Task 2, `aLeaveThatArrivesAfterTheNextRowsEnterIsIgnored`).
2. No desktop picture readable (a dynamic or online wallpaper): the strip falls back to the gradient and still draws the island in the right place (Task 3, the render test runs with `wallpaper: nil`).
3. A switch turned on while another row is pointed at: the pointed row keeps the strip (Task 2, `pointingWinsOverAScenePlaying`).
4. Every option switched off in a pane: the strip is empty, not stuck on the last scene (Task 2, `withNothingSwitchedOnTheStripIsEmpty`).
5. Settings closed or another pane chosen: the strip's clock stops (the `.task` loop is cancelled with the view); checked live in the controller's snapshot pass.

## Before Task 1

- [ ] Run `git status` on branch `rich-settings`. The spec and this plan are committed first, on their own.

## File structure

| File | Change |
| --- | --- |
| `Package.swift` | `SettingsKit` target and `SettingsKitTests`; `Ledge` depends on `SettingsKit` |
| `Sources/SettingsKit/PreviewScene.swift` | New: the scenes, their titles, `isOn(in:)` |
| `Sources/SettingsKit/PreviewContent.swift` | New: the user's content and `PreviewSample` |
| `Sources/SettingsKit/PreviewStage.swift` | New: `PreviewCaption`, `PreviewStage` |
| `Sources/SettingsKit/PreviewDirector.swift` | New |
| `Sources/SettingsKit/SettingsRow.swift` | New: `SettingsTile`, `SettingsRow`, `StatusPill` |
| `Sources/SettingsKit/PreviewStrip.swift` | New |
| `Sources/Ledge/SettingsWindow.swift` | Panes moved out; sidebar uses SettingsKit's tile; window size; snapshot width |
| `Sources/Ledge/SettingsPanes.swift` | New: the six panes, rebuilt |
| `Sources/Ledge/AppModel.swift` | `previewContent()` and three last-seen values |
| `Tests/SettingsKitTests/*` | New |
| `README.md`, `docs/superpowers/specs/2026-09-25-notch-companion-design.md` | Docs |

---

### Task 1: Scenes, content and the stage

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SettingsKit/PreviewScene.swift`, `Sources/SettingsKit/PreviewContent.swift`, `Sources/SettingsKit/PreviewStage.swift`
- Test: `Tests/SettingsKitTests/PreviewStageTests.swift`

**Interfaces:**
- Consumes: NotchKit (`NotchController`, `NotchMetrics`, `MediaPresentation`, `UpcomingEvent`, `NotchController.ActivityDisplay`), LedgeSettings (`AppSettings`), HUDService (`HUDEvent`), PowerService (`PowerEvent`), DeviceService (`DeviceEvent`, `PeripheralLevels`), FocusService (`FocusEvent`, `FocusMode`).
- Produces:
  - `public enum PreviewScene: String, CaseIterable, Sendable` with cases `volume, brightness, capsLock, battery, headphones, focus, timer, liveActivity, meeting, reminder, nowPlaying, songCaption, hoverCard, lockScreen`; `public var title: String`; `@MainActor public func isOn(in settings: AppSettings) -> Bool`
  - `public struct PreviewContent: Sendable, Equatable` with nested `Headphones(name:main:left:right:case:)`, `Focus(name:symbolName:tintName:)`; fields `media`, `mediaSource`, `nextEvent`, `nextReminder`, `batteryPercent`, `headphones`, `focus`, `volume`, `timer`; memberwise `public init` with every argument defaulting to `nil`
  - `public enum PreviewSample` (static samples)
  - `public struct PreviewCaption: Sendable, Equatable` (`title`, `sampleReason`, `text`)
  - `@MainActor public enum PreviewStage` with `struct Options(leadMinutes: Int = 5)`, `static func reset(_:)`, `@discardableResult static func apply(_:content:to:options:) -> PreviewCaption`

- [ ] **Step 1: Add the target.** In `Package.swift`, add `"SettingsKit"` to the `Ledge` executable target's `dependencies` (after `"LedgeSettings"`). After `.target(name: "LedgeSettings"),` add:

```swift
        .target(name: "SettingsKit", dependencies: ["NotchKit", "LedgeSettings", "HUDService", "PowerService", "DeviceService", "FocusService"]),
```

After `.testTarget(name: "LedgeSettingsTests", dependencies: ["LedgeSettings"]),` add:

```swift
        .testTarget(name: "SettingsKitTests", dependencies: ["SettingsKit", "NotchKit", "LedgeSettings", "HUDService"]),
```

- [ ] **Step 2: Write the failing tests.** Create `Tests/SettingsKitTests/PreviewStageTests.swift`:

```swift
import Testing
import Foundation
@testable import SettingsKit
import NotchKit
import LedgeSettings
import HUDService

@MainActor
private func island() -> NotchController {
    NotchController(metrics: NotchMetrics(notchRect: CGRect(x: 0, y: 0, width: 179, height: 32)), reduceMotion: true)
}

/// Every scene puts the island into a state that shows, and names itself.
@MainActor
@Test func everySceneShowsSomethingAndIsCaptioned() {
    for scene in PreviewScene.allCases {
        let c = island()
        let caption = PreviewStage.apply(scene, content: PreviewContent(), to: c)
        #expect(c.isVisible, "\(scene) left the island hidden")
        #expect(caption.title == scene.title)
    }
}

/// A sample says so; the user's own content does not.
@MainActor
@Test func aSampleIsLabelledAndTheUsersOwnIsNot() {
    let c = island()
    #expect(PreviewStage.apply(.battery, content: PreviewContent(), to: c).text
            == "Battery and charging · Sample: no battery on this Mac")
    #expect(c.activities.first?.compactText == "87%")
    let mine = PreviewStage.apply(.battery, content: PreviewContent(batteryPercent: 41), to: c)
    #expect(mine.sampleReason == nil && mine.text == "Battery and charging")
    #expect(c.activities.first?.compactText == "41%")
    #expect(PreviewStage.apply(.capsLock, content: PreviewContent(), to: c).sampleReason == nil,
            "Caps Lock has no content of its own to stand in for")
}

/// Blips are built from the app's own event types, so they are the real ones.
@MainActor
@Test func blipsMatchTheAppsOwnEvents() {
    let c = island()
    PreviewStage.apply(.volume, content: PreviewContent(volume: 0.3), to: c)
    #expect(c.activities.first?.symbolName == HUDEvent.volume(level: 0.3, muted: false).symbolName)
    #expect(c.activities.first?.barFill == 0.3)
    PreviewStage.apply(.headphones, content: PreviewContent(), to: c)
    #expect(c.activities.first?.parts?.count == 3, "the sample AirPods: left, right and case")
    PreviewStage.apply(.focus, content: PreviewContent(focus: .init(name: "Work", symbolName: "briefcase.fill", tintName: "blue")), to: c)
    #expect(c.activities.first?.compactText == "Work")
    #expect(c.activities.first?.tint == .system("blue"))
}

/// The meeting and reminder blips use the lead time and the item's caption.
@MainActor
@Test func calendarBlipsUseTheLeadTimeAndTheItemsCaption() {
    let c = island()
    PreviewStage.apply(.meeting, content: PreviewContent(), to: c, options: .init(leadMinutes: 10))
    #expect(c.activities.first?.compactText == "10m")
    #expect(c.captionText == PreviewSample.event.caption)
    PreviewStage.apply(.reminder, content: PreviewContent(), to: c)
    #expect(c.activities.first?.symbolName == "circle")
    #expect(c.activities.first?.tint == .color(red: 1, green: 0.58, blue: 0))
}

/// The media scenes: compact, captioned, opened as on hover, and locked.
@MainActor
@Test func mediaScenesPutTheIslandInTheirStates() {
    let c = island()
    PreviewStage.apply(.nowPlaying, content: PreviewContent(), to: c)
    #expect(c.state == .activity && c.media == PreviewSample.media)
    PreviewStage.apply(.songCaption, content: PreviewContent(), to: c)
    #expect(c.captionText == "Night Drive · The Islands")
    PreviewStage.apply(.hoverCard, content: PreviewContent(), to: c)
    #expect(c.state == .expanded)
    PreviewStage.apply(.lockScreen, content: PreviewContent(), to: c)
    #expect(c.isLocked && c.state == .activity && !c.isHovered)
}

/// Each scene starts from a clear island: nothing of the last one is left.
@MainActor
@Test func eachSceneStartsFromAClearIsland() {
    let c = island()
    PreviewStage.apply(.hoverCard, content: PreviewContent(), to: c)
    PreviewStage.apply(.volume, content: PreviewContent(), to: c)
    #expect(c.state == .activity && c.media == nil && c.captionText == nil && !c.isHovered)
}

/// A scene is on exactly when its option is.
@MainActor
@Test func aScenesSwitchIsItsOption() {
    let suite = "settingskit.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let s = AppSettings(defaults: defaults)
    #expect(PreviewScene.allCases.allSatisfy { $0.isOn(in: s) }, "everything is on by default")
    s.showsBattery = false
    s.showsVolumeBrightness = false
    #expect(!PreviewScene.battery.isOn(in: s))
    #expect(!PreviewScene.volume.isOn(in: s) && !PreviewScene.brightness.isOn(in: s), "one switch for both")
    #expect(PreviewScene.nowPlaying.isOn(in: s) && PreviewScene.hoverCard.isOn(in: s), "no switch of their own")
}
```

- [ ] **Step 3: Run them and watch them fail.**

Run: `make test FILTER=SettingsKitTests`
Expected: a compile error: `cannot find 'PreviewStage' in scope` (and the other new names).

- [ ] **Step 4: Implement.** Create `Sources/SettingsKit/PreviewScene.swift`:

```swift
import Foundation
import LedgeSettings

/// What a Settings pane's preview strip can show (2026-10-22): one scene
/// for each option that makes the island do something. `PreviewStage`
/// puts a private island into a scene; `PreviewDirector` picks which.
public enum PreviewScene: String, CaseIterable, Sendable {
    case volume, brightness, capsLock, battery, headphones, focus, timer, liveActivity
    case meeting, reminder, nowPlaying, songCaption, hoverCard, lockScreen

    /// The caption under the island: the option's own name.
    public var title: String {
        switch self {
        case .volume, .brightness: return "Volume and brightness"
        case .capsLock:            return "Caps Lock"
        case .battery:             return "Battery and charging"
        case .headphones:          return "Headphones and speakers"
        case .focus:               return "Focus"
        case .timer:               return "Clock timers and stopwatch"
        case .liveActivity:        return "Live Activities"
        case .meeting:             return "Calendar events"
        case .reminder:            return "Reminders with a time"
        case .nowPlaying:          return "Now playing"
        case .songCaption:         return "Song title on track change"
        case .hoverCard:           return "Open the island on hover"
        case .lockScreen:          return "Show on the lock screen"
        }
    }

    /// Whether the option behind this scene is switched on. Now playing
    /// and the hover card have no switch of their own.
    @MainActor
    public func isOn(in settings: AppSettings) -> Bool {
        switch self {
        case .volume, .brightness:    return settings.showsVolumeBrightness
        case .capsLock:               return settings.showsCapsLock
        case .battery:                return settings.showsBattery
        case .headphones:             return settings.showsDevices
        case .focus:                  return settings.showsFocus
        case .timer:                  return settings.showsClockTimers
        case .liveActivity:           return settings.showsLiveActivities
        case .meeting:                return settings.showsCalendarEvents
        case .reminder:               return settings.showsReminders
        case .songCaption:            return settings.showsSongCaption
        case .lockScreen:             return settings.showsOnLockScreen
        case .nowPlaying, .hoverCard: return true
        }
    }
}
```

Create `Sources/SettingsKit/PreviewContent.swift`:

```swift
import Foundation
import NotchKit

/// The user's own content for the Settings previews (2026-10-22), every
/// field optional: `AppModel.previewContent()` fills what the island
/// already knows, and a strip shows a labelled sample for the rest.
public struct PreviewContent: Sendable, Equatable {
    /// The headphones in use and the charge they report.
    public struct Headphones: Sendable, Equatable {
        public let name: String
        public let main: Int?
        public let left: Int?
        public let right: Int?
        public let `case`: Int?

        public init(name: String, main: Int? = nil, left: Int? = nil, right: Int? = nil, case: Int? = nil) {
            self.name = name
            self.main = main
            self.left = left
            self.right = right
            self.case = `case`
        }
    }

    /// The last Focus that came on.
    public struct Focus: Sendable, Equatable {
        public let name: String
        public let symbolName: String?
        public let tintName: String?

        public init(name: String, symbolName: String?, tintName: String?) {
            self.name = name
            self.symbolName = symbolName
            self.tintName = tintName
        }
    }

    public var media: MediaPresentation?
    /// The bundle identifier of the app playing `media`.
    public var mediaSource: String?
    public var nextEvent: UpcomingEvent?
    public var nextReminder: UpcomingEvent?
    public var batteryPercent: Int?
    public var headphones: Headphones?
    public var focus: Focus?
    /// The last volume level seen, `0...1`.
    public var volume: Double?
    /// A Clock timer running now, as the island shows it.
    public var timer: NotchController.ActivityDisplay?

    public init(
        media: MediaPresentation? = nil, mediaSource: String? = nil,
        nextEvent: UpcomingEvent? = nil, nextReminder: UpcomingEvent? = nil,
        batteryPercent: Int? = nil, headphones: Headphones? = nil, focus: Focus? = nil,
        volume: Double? = nil, timer: NotchController.ActivityDisplay? = nil
    ) {
        self.media = media
        self.mediaSource = mediaSource
        self.nextEvent = nextEvent
        self.nextReminder = nextReminder
        self.batteryPercent = batteryPercent
        self.headphones = headphones
        self.focus = focus
        self.volume = volume
        self.timer = timer
    }
}

/// What a strip shows where the user has nothing of their own.
public enum PreviewSample {
    public static let media = MediaPresentation(
        title: "Night Drive", artist: "The Islands", artwork: nil,
        isPlaying: true, elapsed: 74, duration: 243, anchor: Date(timeIntervalSinceReferenceDate: 0)
    )
    public static let volume = 0.62
    public static let brightness = 0.7
    public static let batteryPercent = 87
    public static let headphones = PreviewContent.Headphones(name: "AirPods Pro", left: 80, right: 80, case: 60)
    public static let focus = PreviewContent.Focus(name: "Do Not Disturb", symbolName: "moon.fill", tintName: "indigo")
    public static let event = UpcomingEvent(
        title: "Design review", symbolName: "calendar", compactText: "5m",
        caption: "Design review · 14:00", time: "14:00", url: nil, kind: .event
    )
    public static let reminder = UpcomingEvent(
        title: "Call the plumber", symbolName: "circle", compactText: "5m",
        caption: "Call the plumber · 17:30", time: "17:30", url: nil,
        tint: .init(red: 1, green: 0.58, blue: 0), kind: .reminder
    )
    public static let timer = NotchController.ActivityDisplay(
        id: NotchController.timerActivityID, title: "Timer", compactText: "4:32",
        symbolName: "stopwatch", barFill: 0.6, tint: .system("orange")
    )
    public static let liveActivity = NotchController.ActivityDisplay(
        id: NotchController.liveActivityID, title: "Live Activity",
        score: .init(home: .init(name: "HOME", value: "2", crest: nil),
                     away: .init(name: "AWAY", value: "1", crest: nil),
                     status: "2H", clock: "67'")
    )
}
```

Create `Sources/SettingsKit/PreviewStage.swift`:

```swift
import AppKit
import NotchKit
import HUDService
import PowerService
import DeviceService
import FocusService

/// What a strip says under the island (2026-10-22): the option's name,
/// and why a sample stands in where the user has nothing of their own.
public struct PreviewCaption: Sendable, Equatable {
    public let title: String
    public let sampleReason: String?

    public init(title: String, sampleReason: String? = nil) {
        self.title = title
        self.sampleReason = sampleReason
    }

    /// "Battery and charging", or "Battery and charging · Sample: no battery on this Mac".
    public var text: String {
        sampleReason.map { "\(title) · Sample: \($0)" } ?? title
    }
}

/// Puts a private island into a scene (2026-10-22). Blips are built from
/// the same event types the app turns into blips (`HUDEvent`, `PowerEvent`,
/// `DeviceEvent`, `FocusEvent`), so a scene is the real blip, not a copy
/// of it.
@MainActor
public enum PreviewStage {
    public struct Options: Sendable, Equatable {
        /// Calendar › Remind me before an event: the meeting and reminder
        /// blips show this many minutes.
        public var leadMinutes: Int

        public init(leadMinutes: Int = 5) {
            self.leadMinutes = leadMinutes
        }
    }

    /// Clears everything a scene may have set.
    public static func reset(_ c: NotchController) {
        c.setLocked(false)
        c.setHovered(false)
        c.dismiss()
        c.setCaption(nil)
        c.setUpcoming(nil)
        c.setCalendarMode(nil)
        c.setMedia(nil)
        c.setActivities([], overflow: 0)
    }

    @discardableResult
    public static func apply(_ scene: PreviewScene, content: PreviewContent, to c: NotchController,
                             options: Options = Options()) -> PreviewCaption {
        reset(c)
        switch scene {
        case .volume:
            show(c, hud: .volume(level: content.volume ?? PreviewSample.volume, muted: false))
            return caption(scene, sample: content.volume == nil ? "no volume change yet" : nil)
        case .brightness:
            show(c, hud: .brightness(level: PreviewSample.brightness))
            return caption(scene, sample: "no brightness change yet")
        case .capsLock:
            show(c, hud: .capsLock(on: true))
            return caption(scene, sample: nil)
        case .battery:
            let percent = content.batteryPercent ?? PreviewSample.batteryPercent
            let event = PowerEvent.pluggedIn(percent: percent, isCharging: percent < 100, timeToFullMinutes: nil)
            c.setActivities([NotchController.ActivityDisplay(
                id: NotchController.powerActivityID, title: event.activityTitle, compactText: event.compactText,
                symbolName: event.symbolName, tint: event.tint.map { $0 == .positive ? .positive : .warning }
            )], overflow: 0)
            return caption(scene, sample: content.batteryPercent == nil ? "no battery on this Mac" : nil)
        case .headphones:
            let h = content.headphones ?? PreviewSample.headphones
            let event = DeviceEvent.outputChanged(
                name: h.name, transport: .bluetooth,
                battery: PeripheralLevels(main: h.main, left: h.left, right: h.right, case: h.`case`)
            )
            c.setActivities([NotchController.ActivityDisplay(
                id: NotchController.deviceActivityID, title: event.activityTitle, compactText: event.compactText,
                symbolName: event.symbolName,
                parts: event.parts?.map { .init(symbolName: $0.symbolName, text: $0.text) }
            )], overflow: 0)
            return caption(scene, sample: content.headphones == nil ? "no headphones connected" : nil)
        case .focus:
            let f = content.focus ?? PreviewSample.focus
            let event = FocusEvent.on(FocusMode(identifier: "preview", name: f.name, symbolName: f.symbolName, tintColorName: f.tintName))
            // As the app draws it: a symbol this macOS lacks falls back to the moon.
            let symbol = NSImage(systemSymbolName: event.symbolName, accessibilityDescription: nil) == nil ? "moon.fill" : event.symbolName
            c.setActivities([NotchController.ActivityDisplay(
                id: NotchController.focusActivityID, title: f.name, compactText: f.name,
                symbolName: symbol, tint: f.tintName.map { .system($0) }
            )], overflow: 0)
            return caption(scene, sample: content.focus == nil ? "no Focus seen yet" : nil)
        case .timer:
            c.setActivities([content.timer ?? PreviewSample.timer], overflow: 0)
            return caption(scene, sample: content.timer == nil ? "no timer running" : nil)
        case .liveActivity:
            c.setActivities([PreviewSample.liveActivity], overflow: 0)
            return caption(scene, sample: "no Live Activity running")
        case .meeting:
            showBlip(c, content.nextEvent ?? PreviewSample.event, options: options, tint: nil)
            return caption(scene, sample: content.nextEvent == nil ? "no event coming up" : nil)
        case .reminder:
            let r = content.nextReminder ?? PreviewSample.reminder
            let ring: NotchController.ActivityDisplay.Tint = r.tint.map { .color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .system("gray")
            showBlip(c, r, options: options, tint: ring)
            return caption(scene, sample: content.nextReminder == nil ? "no timed reminder coming up" : nil)
        case .nowPlaying:
            showMedia(c, content)
            return mediaCaption(scene, content)
        case .songCaption:
            let media = showMedia(c, content)
            c.setCaption(media.artist.map { "\(media.title) · \($0)" } ?? media.title)
            return mediaCaption(scene, content)
        case .hoverCard:
            showMedia(c, content)
            c.setHovered(true)
            return mediaCaption(scene, content)
        case .lockScreen:
            showMedia(c, content)
            c.setLocked(true)
            return mediaCaption(scene, content)
        }
    }

    private static func show(_ c: NotchController, hud event: HUDEvent) {
        c.setActivities([NotchController.ActivityDisplay(
            id: NotchController.hudActivityID, title: event.activityTitle, compactText: event.compactText,
            symbolName: event.symbolName, barFill: event.barFill
        )], overflow: 0)
    }

    /// A meeting or reminder blip at the lead time, its caption under it.
    private static func showBlip(_ c: NotchController, _ item: UpcomingEvent, options: Options,
                                 tint: NotchController.ActivityDisplay.Tint?) {
        c.setActivities([NotchController.ActivityDisplay(
            id: NotchController.calendarActivityID, title: item.title, compactText: "\(options.leadMinutes)m",
            symbolName: item.symbolName, tint: tint
        )], overflow: 0)
        c.setCaption(item.caption)
    }

    @discardableResult
    private static func showMedia(_ c: NotchController, _ content: PreviewContent) -> MediaPresentation {
        let media = content.media ?? PreviewSample.media
        c.setMedia(media)
        c.setActivities([NotchController.ActivityDisplay(
            id: NotchController.mediaActivityID, title: media.title, detail: media.artist
        )], overflow: 0)
        return media
    }

    private static func mediaCaption(_ scene: PreviewScene, _ content: PreviewContent) -> PreviewCaption {
        caption(scene, sample: content.media == nil ? "nothing playing" : nil)
    }

    private static func caption(_ scene: PreviewScene, sample: String?) -> PreviewCaption {
        PreviewCaption(title: scene.title, sampleReason: sample)
    }
}
```

If a name in these files does not exist with this exact spelling (for example `PowerEvent.Tint`'s cases or `DeviceEvent.Part`), check the source file it comes from, use the real spelling, and say so in your report; do not invent a different behaviour.

- [ ] **Step 5: Run the tests and watch them pass.**

Run: `make test FILTER=SettingsKitTests`
Expected: the 7 tests pass.

- [ ] **Step 6: Commit.**

```bash
git add Package.swift Sources/SettingsKit Tests/SettingsKitTests
git commit -m "scenes for the settings previews, built from the island's own events, with the user's content or a labelled sample

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The director

**Files:**
- Create: `Sources/SettingsKit/PreviewDirector.swift`
- Test: `Tests/SettingsKitTests/PreviewDirectorTests.swift`

**Interfaces:**
- Consumes: `PreviewScene` (Task 1).
- Produces: `@MainActor @Observable public final class PreviewDirector` with `static let cycleInterval: TimeInterval = 2.5`, `static let playDuration: TimeInterval = 3`, `init(scenes: [PreviewScene], isOn: @escaping @MainActor (PreviewScene) -> Bool, now: Date = Date())`, `var hoverDwell: TimeInterval` (default 0.2), `private(set) var scene: PreviewScene?`, `private(set) var staged: PreviewScene?`, `var isShowingOff: Bool`, `func point(at:now:)`, `func leave(_:now:)`, `func switchedOn(_:now:)`, `func tick(at:)`.

- [ ] **Step 1: Write the failing tests.** Create `Tests/SettingsKitTests/PreviewDirectorTests.swift`:

```swift
import Testing
import Foundation
@testable import SettingsKit

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

@MainActor
@Test func atRestItCyclesOnlyThroughTheScenesSwitchedOn() {
    let d = PreviewDirector(scenes: [.volume, .capsLock, .battery], isOn: { $0 != .capsLock }, now: t0)
    #expect(d.scene == .volume)
    d.tick(at: t0)
    d.tick(at: t0 + 2.4)
    #expect(d.scene == .volume, "not yet")
    d.tick(at: t0 + 2.5)
    #expect(d.scene == .battery, "Caps Lock is off, so it is skipped")
    d.tick(at: t0 + 5.0)
    #expect(d.scene == .volume, "and round again")
}

@MainActor
@Test func pointingShowsThatRowEvenWhenOffAndLeavingResumesTheCycle() {
    let d = PreviewDirector(scenes: [.volume, .capsLock], isOn: { $0 != .capsLock }, now: t0)
    d.point(at: .capsLock, now: t0 + 1)
    #expect(d.scene == .capsLock && d.isShowingOff)
    d.tick(at: t0 + 10)
    #expect(d.scene == .capsLock, "pointing holds it, however long")
    d.leave(.capsLock, now: t0 + 11)
    #expect(d.scene == .volume && !d.isShowingOff)
}

/// Review Focus 1: moving down a pane, the next row's enter can come
/// before the last row's leave.
@MainActor
@Test func aLeaveThatArrivesAfterTheNextRowsEnterIsIgnored() {
    let d = PreviewDirector(scenes: [.volume, .battery], isOn: { _ in true }, now: t0)
    d.point(at: .volume, now: t0)
    d.point(at: .battery, now: t0)
    d.leave(.volume, now: t0)
    #expect(d.scene == .battery)
}

@MainActor
@Test func aSwitchTurnedOnPlaysOnceThenTheCycleResumes() {
    let d = PreviewDirector(scenes: [.volume, .battery], isOn: { _ in true }, now: t0)
    d.switchedOn(.battery, now: t0)
    #expect(d.scene == .battery)
    d.tick(at: t0 + PreviewDirector.playDuration - 0.1)
    #expect(d.scene == .battery)
    d.tick(at: t0 + PreviewDirector.playDuration)
    #expect(d.scene == .volume)
}

/// Review Focus 3.
@MainActor
@Test func pointingWinsOverAScenePlaying() {
    let d = PreviewDirector(scenes: [.volume, .battery], isOn: { _ in true }, now: t0)
    d.switchedOn(.battery, now: t0)
    d.point(at: .volume, now: t0 + 0.5)
    #expect(d.scene == .volume)
}

/// Review Focus 4.
@MainActor
@Test func withNothingSwitchedOnTheStripIsEmpty() {
    let d = PreviewDirector(scenes: [.volume, .battery], isOn: { _ in false }, now: t0)
    #expect(d.scene == nil && d.staged == nil)
    d.tick(at: t0 + 10)
    #expect(d.scene == nil && d.staged == nil)
}

/// The hover scene is two steps: now playing for the hover delay, then the card.
@MainActor
@Test func theHoverSceneShowsNowPlayingForTheHoverDelayThenTheCard() {
    let d = PreviewDirector(scenes: [.songCaption, .hoverCard], isOn: { _ in true }, now: t0)
    d.hoverDwell = 0.5
    d.point(at: .hoverCard, now: t0 + 1)
    #expect(d.scene == .hoverCard && d.staged == .nowPlaying)
    d.tick(at: t0 + 1.4)
    #expect(d.staged == .nowPlaying)
    d.tick(at: t0 + 1.5)
    #expect(d.staged == .hoverCard)
}
```

- [ ] **Step 2: Run them and watch them fail.**

Run: `make test FILTER=PreviewDirectorTests`
Expected: a compile error, `cannot find 'PreviewDirector' in scope`.

- [ ] **Step 3: Implement.** Create `Sources/SettingsKit/PreviewDirector.swift`:

```swift
import Foundation
import Observation

/// Decides which scene a Settings pane's strip shows (2026-10-22): the row
/// the pointer rests on; a switch just turned on, once; or, at rest, the
/// pane's switched-on scenes in turn. Clock-fed, so it is testable; the
/// strip calls `tick(at:)` four times a second while it is on screen.
@MainActor
@Observable
public final class PreviewDirector {
    public static let cycleInterval: TimeInterval = 2.5
    public static let playDuration: TimeInterval = 3

    /// The pane's scenes, in row order.
    public let scenes: [PreviewScene]
    @ObservationIgnored private let isOn: @MainActor (PreviewScene) -> Bool

    /// General › Open the island on hover: how long the hover scene shows
    /// now playing before the card opens.
    public var hoverDwell: TimeInterval = 0.2

    /// The row the strip is about.
    public private(set) var scene: PreviewScene?
    /// What the strip puts on the island now: `scene`, except that the
    /// hover scene is now playing until `hoverDwell` has passed.
    public private(set) var staged: PreviewScene?

    @ObservationIgnored private var pointed: PreviewScene?
    @ObservationIgnored private var playing: (scene: PreviewScene, until: Date)?
    @ObservationIgnored private var cycleIndex = 0
    @ObservationIgnored private var nextCycle: Date?
    @ObservationIgnored private var sceneSince: Date
    @ObservationIgnored private var now: Date

    public init(scenes: [PreviewScene], isOn: @escaping @MainActor (PreviewScene) -> Bool, now: Date = Date()) {
        self.scenes = scenes
        self.isOn = isOn
        self.now = now
        sceneSince = now
        resolve()
    }

    /// The scene showing belongs to an option that is switched off.
    public var isShowingOff: Bool {
        scene.map { !isOn($0) } ?? false
    }

    public func point(at scene: PreviewScene, now: Date = Date()) {
        self.now = now
        pointed = scene
        resolve()
    }

    /// The pointer left `scene`'s row. A leave that arrives after the next
    /// row's enter changes nothing.
    public func leave(_ scene: PreviewScene, now: Date = Date()) {
        self.now = now
        guard pointed == scene else { return }
        pointed = nil
        nextCycle = now + Self.cycleInterval
        resolve()
    }

    public func switchedOn(_ scene: PreviewScene, now: Date = Date()) {
        self.now = now
        playing = (scene, now + Self.playDuration)
        resolve()
    }

    public func tick(at now: Date) {
        self.now = now
        if let playing, now >= playing.until {
            self.playing = nil
            nextCycle = now + Self.cycleInterval
        }
        if pointed == nil, playing == nil {
            if let due = nextCycle {
                if now >= due {
                    cycleIndex += 1
                    nextCycle = now + Self.cycleInterval
                }
            } else {
                nextCycle = now + Self.cycleInterval
            }
        }
        resolve()
    }

    private func resolve() {
        let next: PreviewScene?
        if let pointed {
            next = pointed
        } else if let playing {
            next = playing.scene
        } else {
            let on = scenes.filter { isOn($0) }
            next = on.isEmpty ? nil : on[cycleIndex % on.count]
        }
        if next != scene {
            scene = next
            sceneSince = now
        }
        let nextStaged = (scene == .hoverCard && now < sceneSince + hoverDwell) ? .nowPlaying : scene
        if nextStaged != staged { staged = nextStaged }
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass.**

Run: `make test FILTER=PreviewDirectorTests`
Expected: the 7 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/SettingsKit/PreviewDirector.swift Tests/SettingsKitTests/PreviewDirectorTests.swift
git commit -m "a director for the settings previews: the row pointed at, a switch just turned on, or the pane's blips in turn

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The strip and the row

**Files:**
- Create: `Sources/SettingsKit/SettingsRow.swift`, `Sources/SettingsKit/PreviewStrip.swift`
- Test: `Tests/SettingsKitTests/PreviewStripRenderTests.swift`

**Interfaces:**
- Consumes: `PreviewDirector`, `PreviewStage`, `PreviewContent`, `PreviewCaption`, `PreviewScene` (Tasks 1 and 2); NotchKit's `NotchRootView`, `NotchController`, `NotchMetrics`, `NSScreen.islandHost`.
- Produces:
  - `public struct SettingsTile: View` — `init(symbol: String, color: Color, size: CGFloat = 24)`
  - `public struct SettingsRow<Icon: View, Control: View>: View` — `init(_ title: String, detail: String? = nil, scene: PreviewScene? = nil, director: PreviewDirector? = nil, @ViewBuilder icon: () -> Icon, @ViewBuilder control: () -> Control)`, and where `Icon == SettingsTile`: `init(_ title: String, detail: String? = nil, symbol: String, color: Color, scene: PreviewScene? = nil, director: PreviewDirector? = nil, @ViewBuilder control: () -> Control)`
  - `public struct StatusPill: View` — `init(isOn: Bool, on: String = "Allowed", off: String = "Not allowed")`
  - `public struct PreviewStrip: View` — `static let shortHeight: CGFloat = 104`, `static let tallHeight: CGFloat = 214`, `init(director: PreviewDirector, height: CGFloat, options: PreviewStage.Options = .init(), metrics: NotchMetrics? = nil, wallpaper: NSImage? = PreviewStrip.desktopPicture(), content: @escaping () -> PreviewContent)`, `static func desktopPicture() -> NSImage?`

- [ ] **Step 1: Write the failing test.** Create `Tests/SettingsKitTests/PreviewStripRenderTests.swift`:

```swift
import Testing
import SwiftUI
import AppKit
@testable import SettingsKit
@testable import NotchKit

/// The box around every near-black, opaque pixel of a rendered strip, in
/// points: the island (and, on a MacBook, its outer fillets).
@MainActor
private func islandBox(_ strip: PreviewStrip, width: CGFloat) -> CGRect {
    let renderer = ImageRenderer(content: strip.frame(width: width))
    renderer.scale = 2
    guard let image = renderer.cgImage else { return .null }
    let w = image.width, h = image.height, row = w * 4
    var pixels = [UInt8](repeating: 0, count: h * row)
    guard let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: row,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .null }
    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var box = CGRect.null
    for y in 0..<h {
        for x in 0..<w {
            let i = y * row + x * 4
            if pixels[i + 3] > 200, pixels[i] < 12, pixels[i + 1] < 12, pixels[i + 2] < 12 {
                box = box.union(CGRect(x: CGFloat(x) / 2, y: CGFloat(y) / 2, width: 0.5, height: 0.5))
            }
        }
    }
    return box
}

/// The strip draws the real island where the screen has it: at the top,
/// centred, the one-activity shape for a battery blip, on a MacBook's
/// notch and on the pill. Run with no desktop picture (Review Focus 2):
/// the gradient behind it.
@MainActor
@Test func theStripDrawsTheRealIslandAtTheTopCentre() {
    let screens: [(String, NotchMetrics)] = [
        ("notch", NotchMetrics(notchRect: CGRect(x: 0, y: 0, width: 179, height: 32))),
        ("pill", NotchMetrics(notchRect: CGRect(x: 0, y: 0, width: 44, height: 32), isVirtual: true)),
    ]
    let width: CGFloat = 520
    for (name, metrics) in screens {
        let director = PreviewDirector(scenes: [.battery], isOn: { _ in true })
        let strip = PreviewStrip(director: director, height: PreviewStrip.shortHeight, metrics: metrics, wallpaper: nil) {
            PreviewContent()
        }
        let box = islandBox(strip, width: width)
        let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
        let want = NotchShape(metrics.oneActivity).path(in: canvas).boundingRect
            .offsetBy(dx: width / 2 - canvas.midX, dy: 0)
        #expect(abs(box.midX - want.midX) < 2, "\(name): centred at \(box.midX), want \(want.midX)")
        #expect(abs(box.width - want.width) < 3, "\(name): \(box.width) wide, want \(want.width)")
        #expect(abs(box.minY - want.minY) < 1.5 && abs(box.maxY - want.maxY) < 1.5, "\(name): \(box), want \(want)")
    }
}
```

- [ ] **Step 2: Run it and watch it fail.**

Run: `make test FILTER=PreviewStripRenderTests`
Expected: a compile error, `cannot find 'PreviewStrip' in scope`.

- [ ] **Step 3: Implement.** Create `Sources/SettingsKit/SettingsRow.swift`:

```swift
import SwiftUI
import AppKit

/// A white symbol on a rounded, coloured square: System Settings' own
/// icon, for the sidebar and for every row (2026-10-22).
public struct SettingsTile: View {
    let symbol: String
    let color: Color
    let size: CGFloat

    public init(symbol: String, color: Color, size: CGFloat = 24) {
        self.symbol = symbol
        self.color = color
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size / 4, style: .continuous)
                .fill(color.gradient)
            Image(systemName: symbol)
                .font(.system(size: size / 2, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// One option (2026-10-22): its icon, its name, a line on what it does,
/// and its control. Pointing at it shows its scene in the pane's strip.
public struct SettingsRow<Icon: View, Control: View>: View {
    let title: String
    let detail: String?
    let scene: PreviewScene?
    let director: PreviewDirector?
    let icon: Icon
    let control: Control

    public init(_ title: String, detail: String? = nil, scene: PreviewScene? = nil, director: PreviewDirector? = nil,
                @ViewBuilder icon: () -> Icon, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.scene = scene
        self.director = director
        self.icon = icon()
        self.control = control()
    }

    public var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { inside in
            guard let scene, let director else { return }
            if inside { director.point(at: scene) } else { director.leave(scene) }
        }
    }
}

extension SettingsRow where Icon == SettingsTile {
    public init(_ title: String, detail: String? = nil, symbol: String, color: Color,
                scene: PreviewScene? = nil, director: PreviewDirector? = nil,
                @ViewBuilder control: () -> Control) {
        self.init(title, detail: detail, scene: scene, director: director,
                  icon: { SettingsTile(symbol: symbol, color: color, size: 22) }, control: control)
    }
}

/// Allowed or Not allowed, for a permission row (2026-10-22).
public struct StatusPill: View {
    let isOn: Bool
    let onText: String
    let offText: String

    public init(isOn: Bool, on: String = "Allowed", off: String = "Not allowed") {
        self.isOn = isOn
        onText = on
        offText = off
    }

    public var body: some View {
        let color = Color(nsColor: isOn ? .systemGreen : .systemOrange)
        Text(isOn ? onText : offText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
    }
}
```

Create `Sources/SettingsKit/PreviewStrip.swift`:

```swift
import SwiftUI
import AppKit
import NotchKit

/// The live preview at the top of a Settings pane (2026-10-22, user's
/// call): a strip of the user's desktop with the real island on it, run by
/// a private `NotchController` that `PreviewStage` puts into the
/// director's scene. Fenced: nothing in it takes a click and its
/// controller's intents go nowhere. Its clock runs only while it is on
/// screen.
public struct PreviewStrip: View {
    public static let shortHeight: CGFloat = 104
    public static let tallHeight: CGFloat = 214

    let director: PreviewDirector
    let height: CGFloat
    let options: PreviewStage.Options
    let wallpaper: NSImage?
    let content: () -> PreviewContent

    // Spelled-out State: no macro plugin on this toolchain.
    private var _controller: State<NotchController>
    private var controller: NotchController { _controller.wrappedValue }
    private var _caption: State<PreviewCaption?>
    private var caption: PreviewCaption? {
        get { _caption.wrappedValue }
        nonmutating set { _caption.wrappedValue = newValue }
    }

    public init(director: PreviewDirector, height: CGFloat, options: PreviewStage.Options = .init(),
                metrics: NotchMetrics? = nil, wallpaper: NSImage? = PreviewStrip.desktopPicture(),
                content: @escaping () -> PreviewContent) {
        self.director = director
        self.height = height
        self.options = options
        self.wallpaper = wallpaper
        self.content = content
        let controller = Self.makeController(metrics: metrics ?? Self.hostMetrics())
        // The first scene goes on now, so the strip is right on its first
        // frame (and in a headless render, which runs no `onChange`).
        let first = director.staged.map { PreviewStage.apply($0, content: content(), to: controller, options: options) }
        _controller = State(initialValue: controller)
        _caption = State(initialValue: first)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            backdrop
            Rectangle()
                .fill(Color.black.opacity(0.3))
                .frame(height: 18)
            if director.staged == .lockScreen {
                Text(Date.now, format: .dateTime.hour().minute())
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.top, 46)
            }
            // The island's own fixed canvas, centred and cropped by the strip.
            NotchRootView(controller: controller)
                .frame(width: NotchMetrics.canvasSize.width, height: NotchMetrics.canvasSize.height, alignment: .top)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            if let caption {
                Text(caption.text + (director.isShowingOff ? " · Off" : ""))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: director.staged) { _, staged in show(staged) }
        .onChange(of: options) { _, _ in show(director.staged) }
        .task {
            while !Task.isCancelled {
                director.tick(at: Date())
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    @ViewBuilder private var backdrop: some View {
        if let wallpaper {
            Image(nsImage: wallpaper)
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                .overlay(Color.black.opacity(director.staged == .lockScreen ? 0.35 : 0))
        } else {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.43, blue: 0.55), Color(red: 0.24, green: 0.25, blue: 0.62),
                         Color(red: 0.64, green: 0.27, blue: 0.54)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private func show(_ staged: PreviewScene?) {
        guard let staged else {
            PreviewStage.reset(controller)
            caption = nil
            return
        }
        caption = PreviewStage.apply(staged, content: content(), to: controller, options: options)
    }

    /// The island's size on this Mac: the notch, or the pill without one.
    static func hostMetrics() -> NotchMetrics {
        let placement = NSScreen.islandHost?.placement
        let size = placement?.notchRect.size ?? CGSize(width: 179, height: 32)
        return NotchMetrics(notchRect: CGRect(origin: .zero, size: size), isVirtual: placement?.isVirtual ?? false)
    }

    static func makeController(metrics: NotchMetrics) -> NotchController {
        let controller = NotchController(metrics: metrics, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        controller.onIntent = nil
        return controller
    }

    private static var picture: (url: URL, image: NSImage?)?

    /// The desktop picture behind the island's screen, read once per
    /// picture; `nil` when there is none to read (the strip then draws a
    /// gradient).
    public static func desktopPicture() -> NSImage? {
        guard let screen = NSScreen.islandHost?.screen ?? NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        if let picture, picture.url == url { return picture.image }
        let image = NSImage(contentsOf: url)
        picture = (url, image)
        return image
    }
}
```

- [ ] **Step 4: Run the test and watch it pass.**

Run: `make test FILTER=SettingsKitTests`
Expected: every SettingsKitTests test passes (15). If the render test's box is off, report the measured box from the failure message rather than loosening the tolerances.

- [ ] **Step 5: Commit.**

```bash
git add Sources/SettingsKit/SettingsRow.swift Sources/SettingsKit/PreviewStrip.swift Tests/SettingsKitTests/PreviewStripRenderTests.swift
git commit -m "the settings preview strip, the real island on the user's desktop, and a row with an icon and a line on what it does

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The user's content, General and Island

**Files:**
- Modify: `Sources/Ledge/AppModel.swift` (imports; the three last-seen values; `previewContent()`; one line at the top of `handle(_ event: HUDEvent)`, `handle(_ event: FocusEvent)` and `handle(_ event: DeviceEvent)`)
- Modify: `Sources/Ledge/SettingsWindow.swift` (panes and the private `SettingsTile` move out; window size; snapshot width)
- Create: `Sources/Ledge/SettingsPanes.swift`

**Interfaces:**
- Consumes: everything in SettingsKit (Tasks 1 to 3).
- Produces: `AppModel.previewContent() -> PreviewContent`; in `SettingsPanes.swift`: `GeneralSettings(settings:model:)`, `IslandSettings(settings:model:)`, `MediaSettings(settings:model:)`, `CalendarSettings(settings:model:)`, `PermissionsSettings(model:)`, `AboutSettings()`, and the file-private helper `playing(_:_:settings:director:)`. Tasks 5 and 6 rewrite the last four.

- [ ] **Step 1: AppModel.** In `Sources/Ledge/AppModel.swift`:

Add `import SettingsKit` after `import LiveActivityService`.

Directly above the line `    private var chargingShown: (symbol: String, text: String)?`, insert:

```swift
    // MARK: - Settings previews (2026-10-22)

    /// What only arrives as events, kept for the Settings previews: the
    /// last volume level, the last Focus that came on, and the last
    /// headphones that reported a charge.
    private var lastVolume: Double?
    private var lastFocus: PreviewContent.Focus?
    private var lastHeadphones: PreviewContent.Headphones?

    /// The user's own content for the Settings previews: what the island
    /// already shows or has seen. A nil field becomes a labelled sample.
    func previewContent() -> PreviewContent {
        let controller = presenter.controller
        let items = (controller.upcoming.map { [$0] } ?? []) + (controller.calendarMode?.items ?? [])
        let output = controller.outputs.first(where: \.isCurrent)?.name
        return PreviewContent(
            media: controller.media,
            mediaSource: controller.media == nil ? nil : mediaPayload.bundleIdentifier,
            nextEvent: items.first { $0.kind == .event },
            nextReminder: items.first { $0.kind == .reminder },
            batteryPercent: power.availability.isAvailable ? power.latest?.percent : nil,
            headphones: lastHeadphones.flatMap { $0.name == output ? $0 : nil },
            focus: lastFocus,
            volume: lastVolume,
            timer: controller.activities.first { $0.id == NotchController.timerActivityID }
        )
    }

```

At the top of `private func handle(_ event: HUDEvent) {`, before its first line, insert:

```swift
        if case .volume(let level, _) = event { lastVolume = level }
```

At the top of `private func handle(_ event: FocusEvent) {`, before `guard settings.showsFocus else { return }`, insert:

```swift
        if event.isOn, let mode = event.mode {
            lastFocus = PreviewContent.Focus(name: mode.name, symbolName: mode.symbolName, tintName: mode.tintColorName)
        }
```

At the top of `private func handle(_ event: DeviceEvent) {`, before `guard settings.showsDevices else { return }`, insert:

```swift
        if case .outputChanged(let name, _, let levels?) = event, !levels.isEmpty {
            lastHeadphones = PreviewContent.Headphones(name: name, main: levels.main, left: levels.left,
                                                       right: levels.right, case: levels.`case`)
        }
```

- [ ] **Step 2: Move the panes.** Create `Sources/Ledge/SettingsPanes.swift` starting with:

```swift
import AppKit
import SwiftUI
import LedgeSettings
import CalendarService
import SettingsKit

// The Settings panes (2026-10-22: moved out of SettingsWindow.swift and
// rebuilt around SettingsKit's rows and preview strips).
```

Then move, unchanged except for dropping `private` from their declarations, these types out of `Sources/Ledge/SettingsWindow.swift` into it: `GeneralSettings`, `IslandSettings`, `MediaSettings`, `CalendarSettings`, `AccountLabel`, `CalendarToggle`, `PermissionsSettings`, `AboutSettings`. In `SettingsWindow.swift`, delete the private `SettingsTile` struct (SettingsKit's public one, same look, replaces it) and add `import SettingsKit`. Run `make build` (or `swift build`) to confirm it still compiles before going on.

- [ ] **Step 3: The shared switch helper.** At the end of `SettingsPanes.swift` add:

```swift
/// A switch that plays its scene in the strip when it is turned on.
@MainActor
private func playing(_ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>, _ scene: PreviewScene,
                     settings: AppSettings, director: PreviewDirector) -> Binding<Bool> {
    Binding(
        get: { settings[keyPath: keyPath] },
        set: { on in
            settings[keyPath: keyPath] = on
            if on { director.switchedOn(scene) }
        }
    )
}

/// A strip as the first section of a pane, without the section's card.
private extension View {
    func asPaneHeader() -> some View {
        listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
    }
}
```

- [ ] **Step 4: General.** Replace `GeneralSettings` in `SettingsPanes.swift` with:

```swift
struct GeneralSettings: View {
    let settings: AppSettings
    let model: AppModel
    private var _director: State<PreviewDirector>
    private var director: PreviewDirector { _director.wrappedValue }

    init(settings: AppSettings, model: AppModel) {
        self.settings = settings
        self.model = model
        let director = PreviewDirector(scenes: [.hoverCard, .songCaption], isOn: { $0.isOn(in: settings) })
        director.hoverDwell = settings.hoverDwell
        _director = State(initialValue: director)
    }

    var body: some View {
        Form {
            Section {
                PreviewStrip(director: director, height: PreviewStrip.tallHeight) { model.previewContent() }
                    .asPaneHeader()
            }
            Section {
                SettingsRow("Launch at login", detail: "Start Ledge when you log in.",
                            symbol: "power", color: Color(nsColor: .systemGray)) {
                    Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
                        .labelsHidden()
                }
            } footer: {
                Text("macOS keeps its own switch in System Settings › General › Login Items.")
            }
            Section {
                SettingsRow("Open the island on hover", detail: "How long the pointer rests on the island before it opens.",
                            symbol: "cursorarrow.rays", color: Color(nsColor: .systemBlue), scene: .hoverCard, director: director) {
                    Picker("Open the island on hover", selection: Binding(
                        get: { settings.hoverDwell },
                        set: { seconds in
                            settings.hoverDwell = seconds
                            director.hoverDwell = seconds
                            director.switchedOn(.hoverCard)
                        }
                    )) {
                        ForEach(AppSettings.hoverDwellChoices, id: \.seconds) { choice in
                            Text(choice.name).tag(choice.seconds)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow("Song title on track change", detail: "One line under the island for three seconds.",
                            symbol: "music.note", color: Color(nsColor: .systemPink), scene: .songCaption, director: director) {
                    Toggle("Song title on track change",
                           isOn: playing(\.showsSongCaption, .songCaption, settings: settings, director: director))
                        .labelsHidden()
                }
            } footer: {
                Text("A short pause keeps a pointer passing through the notch from opening the island.")
            }
        }
    }
}
```

- [ ] **Step 5: Island.** Replace `IslandSettings` with (keep the three existing footer texts exactly as they are in the moved code):

```swift
struct IslandSettings: View {
    let settings: AppSettings
    let model: AppModel
    private var _director: State<PreviewDirector>
    private var director: PreviewDirector { _director.wrappedValue }

    init(settings: AppSettings, model: AppModel) {
        self.settings = settings
        self.model = model
        _director = State(initialValue: PreviewDirector(
            scenes: [.volume, .brightness, .capsLock, .battery, .headphones, .focus, .timer,
                     .liveActivity, .meeting, .reminder, .lockScreen],
            isOn: { $0.isOn(in: settings) }
        ))
    }

    var body: some View {
        Form {
            Section {
                PreviewStrip(director: director, height: PreviewStrip.shortHeight,
                             options: .init(leadMinutes: settings.calendarLeadMinutes)) { model.previewContent() }
                    .asPaneHeader()
            }
            Section {
                row("Volume and brightness", "The level in the island, in place of the system's overlay.",
                    "speaker.wave.2.fill", .systemBlue, \.showsVolumeBrightness, .volume)
                row("Caps Lock", "A blip when Caps Lock turns on or off.",
                    "capslock.fill", .systemTeal, \.showsCapsLock, .capsLock)
            } header: {
                Text("Keys")
            } footer: {
                Text("Volume and brightness replace the system's own overlay while on. Needs Accessibility.")
            }
            Section {
                row("Battery and charging", "Plugging in, the charge, and a low battery.",
                    "battery.100percent.bolt", .systemGreen, \.showsBattery, .battery)
                row("Headphones and speakers", "An output connecting, with its charge.",
                    "headphones", .systemPurple, \.showsDevices, .headphones)
                row("Focus", "A Focus turning on or off, in its own colour.",
                    "moon.fill", .systemIndigo, \.showsFocus, .focus)
                row("Clock timers and stopwatch", "A timer or stopwatch running in the Clock app.",
                    "timer", .systemOrange, \.showsClockTimers, .timer)
            } header: {
                Text("What happens on the Mac")
            }
            Section {
                row("Live Activities", "Scores and deliveries from your iPhone.",
                    "iphone", .systemGray, \.showsLiveActivities, .liveActivity)
            } header: {
                Text("From the iPhone")
            } footer: {
                // the existing "From the iPhone" footer text, unchanged
            }
            Section {
                row("Calendar events", "A blip before a meeting, and again as it starts.",
                    "calendar", .systemRed, \.showsCalendarEvents, .meeting)
                row("Reminders with a time", "A reminder's ring before it is due.",
                    "checklist", .systemOrange, \.showsReminders, .reminder)
            } header: {
                Text("Coming up")
            } footer: {
                // the existing "Coming up" footer text, unchanged
            }
            Section {
                row("Show on the lock screen", "The island over the lock screen, to look at.",
                    "lock.fill", .systemGray, \.showsOnLockScreen, .lockScreen)
            } header: {
                Text("Lock screen")
            } footer: {
                // the existing "Lock screen" footer text, unchanged
            }
        }
    }

    private func row(_ title: String, _ detail: String, _ symbol: String, _ color: NSColor,
                     _ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>, _ scene: PreviewScene) -> some View {
        SettingsRow(title, detail: detail, symbol: symbol, color: Color(nsColor: color), scene: scene, director: director) {
            Toggle(title, isOn: playing(keyPath, scene, settings: settings, director: director))
                .labelsHidden()
        }
    }
}
```

Each `// the existing … footer text, unchanged` comment stands for the exact `Text("…")` that footer has in the moved code: copy it in, and remove the comment.

- [ ] **Step 6: The window.** In `Sources/Ledge/SettingsWindow.swift`:
  - In `SettingsView.body`'s `switch`, pass the model: `case .general: GeneralSettings(settings: settings, model: model)`, `case .island: IslandSettings(settings: settings, model: model)`, `case .media: MediaSettings(settings: settings, model: model)` (Task 5 adds that parameter; until then, leave `MediaSettings(settings: settings)` as it is).
  - Change `.frame(minWidth: 700, minHeight: 460)` to `.frame(minWidth: 720, minHeight: 560)`.
  - In `show(section:)`, change `window.setContentSize(NSSize(width: 740, height: 520))` to `window.setContentSize(NSSize(width: 780, height: 620))`.
  - In `snapshotAll(to:)`, change `NSSize(width: 740, height: 1100)` to `NSSize(width: 780, height: 1100)`.

- [ ] **Step 7: Build and test.**

Run: `make test`
Expected: the build succeeds and every test passes except the two known brightness tests.

- [ ] **Step 8: Commit.**

```bash
git add Sources/Ledge/AppModel.swift Sources/Ledge/SettingsWindow.swift Sources/Ledge/SettingsPanes.swift
git commit -m "general and island settings with a live preview of the island, and the user's own content for it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Media and Calendar

**Files:**
- Modify: `Sources/Ledge/SettingsPanes.swift` (`MediaSettings`, `CalendarSettings`, `CalendarToggle`; new `AppIcon`)
- Modify: `Sources/Ledge/SettingsWindow.swift` (`MediaSettings(settings: settings, model: model)` in the `switch`)

**Interfaces:**
- Consumes: SettingsKit; `AppModel.previewContent()`, the `playing` helper and `asPaneHeader()` (Task 4).
- Produces: `MediaSettings(settings:model:)`; `CalendarToggle(calendar:settings:scene:director:)`.

- [ ] **Step 1: Media.** Replace `MediaSettings` with (keep its existing footer text exactly):

```swift
struct MediaSettings: View {
    let settings: AppSettings
    let model: AppModel
    private var _director: State<PreviewDirector>
    private var director: PreviewDirector { _director.wrappedValue }

    init(settings: AppSettings, model: AppModel) {
        self.settings = settings
        self.model = model
        _director = State(initialValue: PreviewDirector(scenes: [.nowPlaying], isOn: { $0.isOn(in: settings) }))
    }

    var body: some View {
        let content = model.previewContent()
        return Form {
            Section {
                PreviewStrip(director: director, height: PreviewStrip.shortHeight) { model.previewContent() }
                    .asPaneHeader()
            }
            Section {
                ForEach(AppSettings.knownMediaSources, id: \.id) { source in
                    SettingsRow(source.name, detail: status(of: source.id, content: content),
                                scene: .nowPlaying, director: director) {
                        AppIcon(bundleIdentifier: source.id)
                    } control: {
                        Toggle(source.name, isOn: Binding(
                            get: { settings.isMediaSourceEnabled(source.id) },
                            set: { on in
                                settings.setMediaSource(source.id, enabled: on)
                                if on { director.switchedOn(.nowPlaying) }
                            }
                        ))
                        .labelsHidden()
                    }
                }
            } header: {
                Text("Now playing from")
            } footer: {
                // the existing "Now playing from" footer text, unchanged
            }
        }
    }

    /// "Playing now", "Installed" or "Not installed".
    private func status(of bundleIdentifier: String, content: PreviewContent) -> String {
        if content.mediaSource == bundleIdentifier, content.media?.isPlaying == true { return "Playing now." }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) == nil
            ? "Not installed." : "Installed."
    }
}

/// An app's own icon, or a plain tile when it is not installed (2026-10-22).
struct AppIcon: View {
    let bundleIdentifier: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
        } else {
            SettingsTile(symbol: "music.note", color: Color(nsColor: .systemGray), size: 22)
        }
    }
}
```

Replace the `// the existing … footer text, unchanged` comment with the footer's exact `Text("…")` from the moved code. In `SettingsWindow.swift`, make the `.media` case `MediaSettings(settings: settings, model: model)`.

- [ ] **Step 2: Calendar.** In `CalendarSettings`:
  - Add the director: a stored `private var _director: State<PreviewDirector>` with `private var director: PreviewDirector { _director.wrappedValue }`, and an `init(settings: AppSettings, model: AppModel)` that sets both properties and `_director = State(initialValue: PreviewDirector(scenes: [.meeting, .reminder], isOn: { $0.isOn(in: settings) }))`.
  - As the `Form`'s first section, add:

```swift
            Section {
                PreviewStrip(director: director, height: PreviewStrip.shortHeight,
                             options: .init(leadMinutes: settings.calendarLeadMinutes)) { model.previewContent() }
                    .asPaneHeader()
            }
```

  - Replace the lead-time `Section`'s content (the `Picker`) with, keeping its existing footer:

```swift
                SettingsRow("Remind me before an event", detail: "How long before an event its blip appears.",
                            symbol: "bell.badge.fill", color: Color(nsColor: .systemRed), scene: .meeting, director: director) {
                    Picker("Remind me before an event", selection: Binding(
                        get: { settings.calendarLeadMinutes },
                        set: { minutes in
                            settings.calendarLeadMinutes = minutes
                            director.switchedOn(.meeting)
                        }
                    )) {
                        ForEach(AppSettings.calendarLeadChoices, id: \.self) { minutes in
                            Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
```

  - In the "Calendars" section use `CalendarToggle(calendar: calendar, settings: settings, scene: .meeting, director: director)`, and in "Reminder lists" `CalendarToggle(calendar: list, settings: settings, scene: .reminder, director: director)`.

Replace `CalendarToggle` with:

```swift
/// One calendar or list (2026-10-22): its colour, its name, its switch.
/// Pointing at it shows a meeting or reminder blip; a calendar added later
/// starts on.
struct CalendarToggle: View {
    let calendar: CalendarInfo
    let settings: AppSettings
    let scene: PreviewScene
    let director: PreviewDirector

    var body: some View {
        SettingsRow(calendar.title, scene: scene, director: director) {
            Circle()
                .fill(calendar.color.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? Color.secondary)
                .frame(width: 10, height: 10)
                .frame(width: 22, height: 22)
        } control: {
            Toggle(calendar.title, isOn: Binding(
                get: { settings.isCalendarEnabled(calendar.id) },
                set: { on in
                    settings.setCalendar(calendar.id, enabled: on)
                    if on { director.switchedOn(scene) }
                }
            ))
            .labelsHidden()
        }
    }
}
```

`SettingsView`'s `.calendar` case already passes `settings` and `model`.

- [ ] **Step 3: Build and test.**

Run: `make test`
Expected: the build succeeds and every test passes except the two known brightness tests.

- [ ] **Step 4: Commit.**

```bash
git add Sources/Ledge/SettingsPanes.swift Sources/Ledge/SettingsWindow.swift
git commit -m "media and calendar settings with the preview, each music app's own icon and status, and each calendar pointing at its blip

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Permissions, About, and docs

**Files:**
- Modify: `Sources/Ledge/SettingsPanes.swift` (`PermissionsSettings`, `AboutSettings`)
- Modify: `README.md` (the Settings paragraph)
- Modify: `docs/superpowers/specs/2026-09-25-notch-companion-design.md` (a dated section at the end)

**Interfaces:**
- Consumes: `SettingsRow`, `StatusPill` (Task 3); `AppModel.permissionRows` (ids `ax`, `cal`, `fda`, `screen`).
- Produces: nothing for code.

- [ ] **Step 1: Permissions.** In `PermissionsSettings`, keep the `TimelineView`, the "Needs attention" section and the footer exactly as they are; replace the `ForEach(model.permissionRows) { row in … }` block with:

```swift
                    ForEach(model.permissionRows) { row in
                        let look = Self.look(row.id)
                        SettingsRow(row.name, detail: row.detail, symbol: look.symbol, color: Color(nsColor: look.color)) {
                            HStack(spacing: 8) {
                                StatusPill(isOn: row.isGranted)
                                if !row.isGranted, let url = row.settingsURL {
                                    Button("Open Settings…") { NSWorkspace.shared.open(url) }
                                }
                            }
                        }
                    }
```

and add to `PermissionsSettings`:

```swift
    /// Each permission's tile (2026-10-22).
    static func look(_ id: String) -> (symbol: String, color: NSColor) {
        switch id {
        case "ax":     return ("accessibility", .systemBlue)
        case "cal":    return ("calendar", .systemRed)
        case "fda":    return ("externaldrive.fill", .systemGray)
        case "screen": return ("rectangle.dashed.badge.record", .systemPurple)
        default:       return ("lock.fill", .systemGray)
        }
    }
```

- [ ] **Step 2: About.** Replace `AboutSettings` with:

```swift
/// About (2026-10-22): a header, and the way to the releases and the
/// source. No update checker: the spec rules out auto-update.
struct AboutSettings: View {
    var body: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        return Form {
            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 88, height: 88)
                    Text("Ledge").font(.title2.weight(.semibold))
                    Text("Version \(version)").foregroundStyle(.secondary)
                    Text("A companion for the notch.").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            Section {
                SettingsRow("Latest release", detail: "The downloads page on GitHub.",
                            symbol: "arrow.down.circle.fill", color: Color(nsColor: .systemGreen)) {
                    Button("Open") { open("https://github.com/dededemahendra/ledge/releases/latest") }
                }
                SettingsRow("Source code", detail: "github.com/dededemahendra/ledge",
                            symbol: "chevron.left.forwardslash.chevron.right", color: Color(nsColor: .systemGray)) {
                    Button("Open") { open("https://github.com/dededemahendra/ledge") }
                }
            }
        }
    }

    private func open(_ address: String) {
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }
}
```

- [ ] **Step 3: README.** In the `## Settings` paragraph, after the sentence that ends `…a sidebar of sections, grouped forms.`, insert: `Every option has an icon and a line on what it does, and the General, Island, Media and Calendar panes open with a live preview of the island that shows the option the pointer rests on, with your own song, meeting and battery where there are any.`

- [ ] **Step 4: Design spec.** Append to `docs/superpowers/specs/2026-09-25-notch-companion-design.md`:

```markdown

## Settings, the look (2026-10-22)

Every option in Settings has an icon and a line on what it does, and four
panes open with a live strip of the real island, run on a private controller,
that shows the option the pointer rests on, with the user's own content or a
labelled sample (user's call). The logic lives in a new `SettingsKit` library.
New options are a separate, later piece. Design:
`2026-10-22-rich-settings-design.md`.
```

- [ ] **Step 5: Build and test.**

Run: `make test`
Expected: everything passes except the two known brightness tests.

- [ ] **Step 6: Commit.**

```bash
git add Sources/Ledge/SettingsPanes.swift README.md docs/superpowers/specs/2026-09-25-notch-companion-design.md
git commit -m "permissions with their status at a glance, an about pane with a header and the way to the releases, and the docs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## After the tasks (controller)

1. Final whole-branch review.
2. Live check: `make dev` (stops the running copy and launches the debug build), then `open "ledge://probe/settings"`; read the six `~/Library/Logs/Ledge/settings-*.png` captures; point at rows by hand where the captures cannot show it (Review Focus 5: switch panes and close Settings, and confirm nothing keeps running). Then `make install` and relaunch the installed copy.
3. Push the branch, open the PR, run the reviewer on it, fix, and merge when the user says merge.
