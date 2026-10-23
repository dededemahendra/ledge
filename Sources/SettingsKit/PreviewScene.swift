import Foundation
import LedgeSettings

/// What a Settings pane's preview strip can show (2026-10-22): one scene
/// for each option that makes the island do something. `PreviewStage`
/// puts a private island into a scene; `PreviewDirector` picks which.
public enum PreviewScene: String, CaseIterable, Sendable {
    case volume, brightness, capsLock, battery, headphones, focus, timer, call, liveActivity
    case meeting, reminder, nowPlaying, songCaption, hoverCard, lockScreen, update
    case githubRunning, githubChecks, githubReviews, githubMerges, githubRequests, githubRuns
    case agentWaiting, agentWorking, agentFinished, agentFailed

    /// The caption under the island: the option's own name.
    public var title: String {
        switch self {
        case .volume, .brightness: return "Volume and brightness"
        case .capsLock:            return "Caps Lock"
        case .battery:             return "Battery and charging"
        case .headphones:          return "Headphones and speakers"
        case .focus:               return "Focus"
        case .timer:               return "Clock timers and stopwatch"
        case .call:                return "Calls"
        case .liveActivity:        return "Live Activities"
        case .meeting:             return "Calendar events"
        case .reminder:            return "Reminders with a time"
        case .nowPlaying:          return "Now playing"
        case .songCaption:         return "Song title on track change"
        case .hoverCard:           return "Open the island on hover"
        case .lockScreen:          return "Show on the lock screen"
        case .update:              return "Check for updates"
        case .githubRunning:       return "Checks running"
        case .githubChecks:        return "Checks finished"
        case .githubReviews:       return "Reviews and comments"
        case .githubMerges:        return "Merges and closes"
        case .githubRequests:      return "Review requests"
        case .githubRuns:          return "Your runs outside PRs"
        case .agentWaiting:        return "Waiting for you"
        case .agentWorking:        return "Working"
        case .agentFinished:       return "Finished its turn"
        case .agentFailed:         return "Failed"
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
        case .call:                   return settings.showsCalls
        case .liveActivity:           return settings.showsLiveActivities
        case .meeting:                return settings.showsCalendarEvents
        case .reminder:               return settings.showsReminders
        case .songCaption:            return settings.showsSongCaption
        case .lockScreen:             return settings.showsOnLockScreen
        case .update:                 return settings.checksForUpdates
        case .githubRunning:          return settings.githubChecksRunning
        case .githubChecks:           return settings.githubChecksFinished
        case .githubReviews:          return settings.githubReviews
        case .githubMerges:           return settings.githubMerges
        case .githubRequests:         return settings.githubReviewRequests
        case .githubRuns:             return settings.githubMyRuns
        case .agentWaiting:           return settings.agentWaiting
        case .agentWorking:           return settings.agentWorking
        case .agentFinished:          return settings.agentFinished
        case .agentFailed:            return settings.agentFailed
        case .nowPlaying, .hoverCard: return true
        }
    }
}
