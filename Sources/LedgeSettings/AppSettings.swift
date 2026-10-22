import Foundation
import Observation

/// Everything the Settings window can change (2026-09-30), persisted in
/// `UserDefaults` and observable, so the island and the window agree
/// without either polling. Every setting has a default that matches how
/// the app behaved before there were settings: everything on.
@MainActor
@Observable
public final class AppSettings {
    public enum Key {
        public static let launchAtLogin = "launchAtLogin"
        public static let hoverDwell = "hoverDwell"
        public static let showsSongCaption = "showsSongCaption"
        public static let showsVolumeBrightness = "showsVolumeBrightness"
        public static let showsCapsLock = "showsCapsLock"
        public static let showsBattery = "showsBattery"
        public static let showsDevices = "showsDevices"
        public static let showsCalendarEvents = "showsCalendarEvents"
        public static let showsReminders = "showsReminders"
        public static let showsFocus = "showsFocus"
        public static let showsClockTimers = "showsClockTimers"
        public static let showsLiveActivities = "showsLiveActivities"
        public static let showsOnLockScreen = "showsOnLockScreen"
        public static let checksForUpdates = "checksForUpdates"
        public static let mediaSources = "mediaSources"
        public static let calendarLeadMinutes = "calendarLeadMinutes"
        public static let disabledCalendarIDs = "disabledCalendarIDs"
    }

    /// The music apps the island follows, by bundle identifier, with the
    /// names the window shows. The order is the window's order.
    public static let knownMediaSources: [(id: String, name: String)] = [
        ("com.apple.music", "Music"),
        ("com.spotify.client", "Spotify"),
        ("com.tidal.desktop", "TIDAL"),
        ("com.deezer.deezer-desktop", "Deezer"),
        ("com.github.th-ch.youtube-music", "YouTube Music"),
    ]

    /// Hover dwell choices, in seconds: the island opens as soon as the
    /// cursor rests this long.
    public static let hoverDwellChoices: [(seconds: Double, name: String)] = [
        (0.0, "Immediately"), (0.2, "After a moment"), (0.5, "After half a second"),
    ]

    public static let calendarLeadChoices: [Int] = [1, 2, 5, 10, 15]

    @ObservationIgnored private let defaults: UserDefaults
    /// Fired after any change, once persisted — the app re-applies what
    /// cannot be checked at event time (the system HUD, the dwell, the
    /// lead time, the login item).
    @ObservationIgnored public var onChange: (() -> Void)?

    public var launchAtLogin: Bool { didSet { save(launchAtLogin, Key.launchAtLogin) } }
    public var hoverDwell: Double { didSet { save(hoverDwell, Key.hoverDwell) } }
    public var showsSongCaption: Bool { didSet { save(showsSongCaption, Key.showsSongCaption) } }
    public var showsVolumeBrightness: Bool { didSet { save(showsVolumeBrightness, Key.showsVolumeBrightness) } }
    public var showsCapsLock: Bool { didSet { save(showsCapsLock, Key.showsCapsLock) } }
    public var showsBattery: Bool { didSet { save(showsBattery, Key.showsBattery) } }
    public var showsDevices: Bool { didSet { save(showsDevices, Key.showsDevices) } }
    public var showsCalendarEvents: Bool { didSet { save(showsCalendarEvents, Key.showsCalendarEvents) } }
    public var showsReminders: Bool { didSet { save(showsReminders, Key.showsReminders) } }
    public var showsFocus: Bool { didSet { save(showsFocus, Key.showsFocus) } }
    public var showsClockTimers: Bool { didSet { save(showsClockTimers, Key.showsClockTimers) } }
    public var showsLiveActivities: Bool { didSet { save(showsLiveActivities, Key.showsLiveActivities) } }
    /// The island over the lock screen, look only (2026-10-21).
    public var showsOnLockScreen: Bool { didSet { save(showsOnLockScreen, Key.showsOnLockScreen) } }
    /// Asks GitHub once a day for a newer Ledge (2026-10-22).
    public var checksForUpdates: Bool { didSet { save(checksForUpdates, Key.checksForUpdates) } }
    /// Enabled music apps' bundle identifiers.
    public var mediaSources: Set<String> { didSet { save(Array(mediaSources).sorted(), Key.mediaSources) } }
    public var calendarLeadMinutes: Int { didSet { save(calendarLeadMinutes, Key.calendarLeadMinutes) } }
    /// Calendars and reminder lists switched off, by identifier — so a
    /// calendar added later is on until the user says otherwise.
    public var disabledCalendarIDs: Set<String> { didSet { save(Array(disabledCalendarIDs).sorted(), Key.disabledCalendarIDs) } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? true
        hoverDwell = defaults.object(forKey: Key.hoverDwell) as? Double ?? 0.2
        showsSongCaption = defaults.object(forKey: Key.showsSongCaption) as? Bool ?? true
        showsVolumeBrightness = defaults.object(forKey: Key.showsVolumeBrightness) as? Bool ?? true
        showsCapsLock = defaults.object(forKey: Key.showsCapsLock) as? Bool ?? true
        showsBattery = defaults.object(forKey: Key.showsBattery) as? Bool ?? true
        showsDevices = defaults.object(forKey: Key.showsDevices) as? Bool ?? true
        showsCalendarEvents = defaults.object(forKey: Key.showsCalendarEvents) as? Bool ?? true
        showsReminders = defaults.object(forKey: Key.showsReminders) as? Bool ?? true
        showsFocus = defaults.object(forKey: Key.showsFocus) as? Bool ?? true
        showsClockTimers = defaults.object(forKey: Key.showsClockTimers) as? Bool ?? true
        showsLiveActivities = defaults.object(forKey: Key.showsLiveActivities) as? Bool ?? true
        showsOnLockScreen = defaults.object(forKey: Key.showsOnLockScreen) as? Bool ?? true
        checksForUpdates = defaults.object(forKey: Key.checksForUpdates) as? Bool ?? true
        mediaSources = (defaults.object(forKey: Key.mediaSources) as? [String]).map(Set.init)
            ?? Set(Self.knownMediaSources.map(\.id))
        calendarLeadMinutes = defaults.object(forKey: Key.calendarLeadMinutes) as? Int ?? 5
        disabledCalendarIDs = Set((defaults.object(forKey: Key.disabledCalendarIDs) as? [String]) ?? [])
    }

    public func isCalendarEnabled(_ id: String) -> Bool { !disabledCalendarIDs.contains(id) }

    public func setCalendar(_ id: String, enabled: Bool) {
        if enabled { disabledCalendarIDs.remove(id) } else { disabledCalendarIDs.insert(id) }
    }

    public func isMediaSourceEnabled(_ id: String) -> Bool { mediaSources.contains(id) }

    public func setMediaSource(_ id: String, enabled: Bool) {
        if enabled { mediaSources.insert(id) } else { mediaSources.remove(id) }
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }
}
