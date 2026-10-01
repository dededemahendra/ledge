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
    #expect(s.showsDevices && s.showsCalendarEvents && s.showsReminders && s.showsFocus && s.showsClockTimers && s.showsLiveActivities && s.hidesLiveActivityPill)
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
