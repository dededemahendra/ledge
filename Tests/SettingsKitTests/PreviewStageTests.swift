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

/// The update scene: the real available version, or a labelled sample.
@MainActor
@Test func theUpdateSceneShowsTheVersionAndItsCaption() {
    let c = island()
    let sample = PreviewStage.apply(.update, content: PreviewContent(), to: c)
    #expect(sample.text == "Check for updates · Sample: no update out")
    #expect(c.activities.first?.compactText == "0.1.2")
    #expect(c.captionText == "Ledge 0.1.2 is available · Download")
    let real = PreviewStage.apply(.update, content: PreviewContent(availableUpdate: "0.2.0"), to: c)
    #expect(real.sampleReason == nil && c.activities.first?.compactText == "0.2.0")
}
