import Testing
import Foundation
@testable import LedgeSettings

@MainActor
private func fresh() -> (AppSettings, UserDefaults) {
    let suite = "ledge.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (AppSettings(defaults: defaults), defaults)
}

@MainActor
@Test func everythingIsOnByDefaultAsTheAppBehavedBeforeSettings() {
    let (s, _) = fresh()
    #expect(s.launchAtLogin && s.showsSongCaption && s.showsVolumeBrightness && s.showsCapsLock && s.showsBattery)
    #expect(s.showsDevices && s.showsCalendarEvents && s.showsReminders && s.showsFocus && s.showsClockTimers && s.showsLiveActivities)
    #expect(s.showsCalls)
    #expect(s.hoverDwell == 0.2)
    #expect(s.calendarLeadMinutes == 5)
    #expect(s.mediaSources == Set(AppSettings.knownMediaSources.map(\.id)))
}

@MainActor
@Test func changesPersistAndAnnounceThemselves() {
    let (s, defaults) = fresh()
    var changes = 0
    s.onChange = { changes += 1 }
    s.showsBattery = false
    s.hoverDwell = 0.5
    s.setMediaSource("com.spotify.client", enabled: false)
    s.calendarLeadMinutes = 10
    s.setCalendar("holidays", enabled: false)
    #expect(changes == 5)

    let again = AppSettings(defaults: defaults)
    #expect(!again.showsBattery)
    #expect(again.hoverDwell == 0.5)
    #expect(!again.isMediaSourceEnabled("com.spotify.client") && again.isMediaSourceEnabled("com.apple.music"))
    #expect(again.calendarLeadMinutes == 10)
    #expect(!again.isCalendarEnabled("holidays") && again.isCalendarEnabled("anything-new"), "off is remembered; new calendars start on")
}

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

/// Checking for updates (2026-10-22): on by default, remembered off.
@MainActor
@Test func checkingForUpdatesIsOnByDefaultAndRemembered() {
    let (s, defaults) = fresh()
    #expect(s.checksForUpdates)
    s.checksForUpdates = false
    #expect(!AppSettings(defaults: defaults).checksForUpdates)
}

@MainActor
@Test func gitHubStartsDisconnectedWithEveryMomentOn() {
    let (s, defaults) = fresh()
    #expect(!s.githubConnected)
    #expect(s.githubChecksFinished && s.githubChecksRunning && s.githubReviews)
    #expect(s.githubMerges && s.githubReviewRequests && s.githubMyRuns)
    s.githubConnected = true
    s.githubReviews = false
    let again = AppSettings(defaults: defaults)
    #expect(again.githubConnected && !again.githubReviews && again.githubMerges)
}

@MainActor
@Test func callsAreOnAndNothingIsHiddenByDefault() {
    let (s, _) = fresh()
    #expect(s.showsCalls)
    #expect(s.hiddenCallApps == [])
}

/// "Not a call" (2026-10-22): hidden once however often it is pressed,
/// remembered, and brought back from Settings.
@MainActor
@Test func hidingACallAppSavesOnceAndUnhidingRemovesIt() {
    let (s, defaults) = fresh()
    s.hideCallApp("us.zoom.xos")
    s.hideCallApp("us.zoom.xos")
    #expect(s.hiddenCallApps == ["us.zoom.xos"])
    let again = AppSettings(defaults: defaults)
    #expect(again.hiddenCallApps == ["us.zoom.xos"])
    again.unhideCallApp("us.zoom.xos")
    #expect(again.hiddenCallApps == [])
}
