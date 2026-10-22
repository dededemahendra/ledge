import Foundation
import LedgeSettings

/// What a Settings pane's preview strip can show (2026-10-22): one scene
/// for each option that makes the island do something. `PreviewStage`
/// puts a private island into a scene; `PreviewDirector` picks which.
public enum PreviewScene: String, CaseIterable, Sendable {
    case volume, brightness, capsLock, battery, headphones, focus, timer, liveActivity
    case meeting, reminder, nowPlaying, songCaption, hoverCard, lockScreen, update

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
        case .update:              return "Check for updates"
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
        case .update:                 return settings.checksForUpdates
        case .nowPlaying, .hoverCard: return true
        }
    }
}
