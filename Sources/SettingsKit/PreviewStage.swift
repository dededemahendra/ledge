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
