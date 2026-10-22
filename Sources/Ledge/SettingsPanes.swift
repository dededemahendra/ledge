import AppKit
import SwiftUI
import LedgeSettings
import CalendarService
import SettingsKit

// The Settings panes (2026-10-22: moved out of SettingsWindow.swift and
// rebuilt around SettingsKit's rows and preview strips).

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
                Text("A match shows its crests and score around the notch and keeps up by the second; hover for the card. Needs Screen Recording for the crests. While this is on, the system's own card is held open out of sight, so the menu bar's pill shows its collapse arrow; switching it off gives the card back.")
            }
            Section {
                row("Calendar events", "A blip before a meeting, and again as it starts.",
                    "calendar", .systemRed, \.showsCalendarEvents, .meeting)
                row("Reminders with a time", "A reminder's ring before it is due.",
                    "checklist", .systemOrange, \.showsReminders, .reminder)
            } header: {
                Text("Coming up")
            } footer: {
                Text("A blip a few minutes before, and again as it starts. Resting on the island with nothing playing shows the next one.")
            }
            Section {
                row("Show on the lock screen", "The island over the lock screen, to look at.",
                    "lock.fill", .systemGray, \.showsOnLockScreen, .lockScreen)
            } header: {
                Text("Lock screen")
            } footer: {
                Text("While the Mac is locked the island shows what it shows unlocked, meeting and reminder titles included, for anyone at the Mac to see. Resting on it opens the card to look at; nothing on it can be pressed until you unlock.")
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
                Text("The island follows music from these apps only. A browser tab or a video never takes the notch.")
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

struct CalendarSettings: View {
    let settings: AppSettings
    let model: AppModel
    private var _director: State<PreviewDirector>
    private var director: PreviewDirector { _director.wrappedValue }

    init(settings: AppSettings, model: AppModel) {
        self.settings = settings
        self.model = model
        _director = State(initialValue: PreviewDirector(scenes: [.meeting, .reminder], isOn: { $0.isOn(in: settings) }))
    }

    var body: some View {
        let calendars = model.availableCalendars
        let events = CalendarInfo.grouped(calendars.filter { $0.kind == .event })
        let lists = CalendarInfo.grouped(calendars.filter { $0.kind == .reminder })
        Form {
            Section {
                PreviewStrip(director: director, height: PreviewStrip.shortHeight,
                             options: .init(leadMinutes: settings.calendarLeadMinutes)) { model.previewContent() }
                    .asPaneHeader()
            }
            Section {
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
            } footer: {
                Text("And again as it starts. A click on the blip joins the call, or opens the event in Calendar or Reminders.")
            }
            if calendars.isEmpty {
                Section {
                    Text("Grant Calendars and Reminders access to choose which to follow.")
                        .foregroundStyle(.secondary)
                }
            }
            // One card per kind with the accounts as label rows inside it, in
            // one flat loop — not a section per account, and not a label
            // followed by a nested loop: both render unreliably in a grouped
            // Form on macOS (merged cards, the last row drawn under its card).
            if !events.isEmpty {
                Section {
                    ForEach(CalendarRow.rows(events)) { row in
                        switch row {
                        case .account(let title):
                            AccountLabel(title)
                        case .calendar(let calendar):
                            CalendarToggle(calendar: calendar, settings: settings, scene: .meeting, director: director)
                        }
                    }
                } header: {
                    Text("Calendars")
                } footer: {
                    Text("A calendar added later is followed until you switch it off here.")
                }
            }
            if !lists.isEmpty {
                Section {
                    ForEach(CalendarRow.rows(lists)) { row in
                        switch row {
                        case .account(let title):
                            AccountLabel(title)
                        case .calendar(let list):
                            CalendarToggle(calendar: list, settings: settings, scene: .reminder, director: director)
                        }
                    }
                } header: {
                    Text("Reminder lists")
                } footer: {
                    Text("Only reminders with a time of day are shown.")
                }
            }
        }
    }
}

/// An account's name as a quiet label row inside the card.
struct AccountLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }
}

/// One row of a calendars card (2026-10-22): an account's label or one
/// calendar, so the card is one flat loop. A label followed by a nested loop
/// put the last calendar under its card, drawn as footer text.
private enum CalendarRow: Identifiable {
    case account(String)
    case calendar(CalendarInfo)

    var id: String {
        switch self {
        case .account(let title): return "account:\(title)"
        case .calendar(let calendar): return "calendar:\(calendar.id)"
        }
    }

    static func rows(_ groups: [(source: String, calendars: [CalendarInfo])]) -> [CalendarRow] {
        groups.flatMap { [CalendarRow.account($0.source)] + $0.calendars.map { CalendarRow.calendar($0) } }
    }
}

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

struct PermissionsSettings: View {
    let model: AppModel

    var body: some View {
        // Re-read every couple of seconds while the pane is up: a grant
        // made in System Settings shows here without a relaunch.
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            Form {
                // What the menu used to list above Quit (moved here
                // 2026-10-21), and only while something is wrong.
                let issues = model.issues
                if !issues.isEmpty {
                    Section("Needs attention") {
                        ForEach(issues) { issue in
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color(nsColor: .systemOrange))
                                Text(issue.text)
                                Spacer()
                                if let fix = issue.fix {
                                    Button("Open Settings…") { fix() }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                Section {
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
                } footer: {
                    Text("Ledge asks for nothing it does not need. Each grant unlocks one thing and can be turned off again in System Settings.")
                }
            }
        }
    }

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
}

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
