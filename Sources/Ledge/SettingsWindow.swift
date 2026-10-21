import AppKit
import SwiftUI
import LedgeSettings
import CalendarService

/// The Settings window (2026-09-30), in System Settings' idiom: a sidebar
/// of sections with coloured icon tiles, grouped forms on the right. One
/// window, kept around once made; the menu's "Settings…" shows it.
/// Which pane is showing; shared by the window and the sidebar so the
/// pane can be chosen from outside (a deep link, the debug snapshot).
@MainActor
@Observable
final class SettingsSelection {
    var section: SettingsSection = .general
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let model: AppModel
    private let selection = SettingsSelection()
    private var window: NSWindow?

    init(settings: AppSettings, model: AppModel) {
        self.settings = settings
        self.model = model
    }

    #if DEBUG
    /// Development only: renders every pane of the live window to
    /// `directory/settings-<section>.png` through the view's own display
    /// cache — no screen recording involved.
    func snapshotAll(to directory: URL) async {
        show()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Tall enough that no pane scrolls: a lazy list renders only what
        // shows, and a half-laid-out section reads as a bug in a capture.
        let usual = window?.contentView?.bounds.size
        window?.setContentSize(NSSize(width: 740, height: 1100))
        defer { if let usual { window?.setContentSize(usual) } }
        try? await Task.sleep(for: .seconds(1.5))
        for section in SettingsSection.allCases {
            selection.section = section
            try? await Task.sleep(for: .seconds(2.5))
            window?.contentView?.layoutSubtreeIfNeeded()
            window?.contentView?.displayIfNeeded()
            // The view's own display cache: the forms come out exactly; the
            // sidebar's translucent material does not (it needs the screen
            // to composite), and the window-image API is gone from this SDK.
            guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "settings-\(section.rawValue).png"))
        }
    }
    #endif

    func show(section: SettingsSection? = nil) {
        if let section { selection.section = section }
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings, model: model, selection: selection))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Ledge"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 740, height: 520))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        // An accessory app has no Dock tile: activate, or the window lands
        // behind whatever is frontmost.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The sections, as the sidebar lists them.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, island, media, calendar, permissions, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:     return "General"
        case .island:      return "Island"
        case .media:       return "Media"
        case .calendar:    return "Calendar"
        case .permissions: return "Permissions"
        case .about:       return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general:     return "gearshape.fill"
        case .island:      return "rectangle.topthird.inset.filled"
        case .media:       return "music.note"
        case .calendar:    return "calendar"
        case .permissions: return "hand.raised.fill"
        case .about:       return "info.circle.fill"
        }
    }

    var tile: Color {
        switch self {
        case .general:     return Color(nsColor: .systemGray)
        case .island:      return Color(nsColor: .systemBlue)
        case .media:       return Color(nsColor: .systemPink)
        case .calendar:    return Color(nsColor: .systemRed)
        case .permissions: return Color(nsColor: .systemGreen)
        case .about:       return Color(nsColor: .systemGray)
        }
    }
}

struct SettingsView: View {
    let settings: AppSettings
    let model: AppModel
    let selection: SettingsSelection

    init(settings: AppSettings, model: AppModel, selection: SettingsSelection) {
        self.settings = settings
        self.model = model
        self.selection = selection
    }

    var body: some View {
        NavigationSplitView {
            // Re-read every couple of seconds, like the Permissions pane:
            // the badge is how a problem shows from any pane, now that the
            // menu no longer lists them (2026-10-21).
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                let issueCount = model.issues.count
                List(SettingsSection.allCases, selection: Binding<SettingsSection?>(
                    get: { selection.section }, set: { if let section = $0 { selection.section = section } }
                )) { section in
                    Label {
                        Text(section.title)
                    } icon: {
                        SettingsTile(symbol: section.symbol, color: section.tile)
                    }
                    .badge(section == .permissions ? issueCount : 0)
                    .tag(section)
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selection.section {
                case .general:     GeneralSettings(settings: settings)
                case .island:      IslandSettings(settings: settings)
                case .media:       MediaSettings(settings: settings)
                case .calendar:    CalendarSettings(settings: settings, model: model)
                case .permissions: PermissionsSettings(model: model)
                case .about:       AboutSettings()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(selection.section.title)
        }
        .frame(minWidth: 700, minHeight: 460)
    }
}

/// The sidebar's icon: a white symbol on a rounded, coloured square,
/// System Settings' own idiom.
private struct SettingsTile: View {
    let symbol: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.gradient)
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Sections

private struct GeneralSettings: View {
    let settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: bind(\.launchAtLogin))
            } footer: {
                Text("macOS keeps its own switch in System Settings › General › Login Items.")
            }
            Section {
                Picker("Open the island on hover", selection: bind(\.hoverDwell)) {
                    ForEach(AppSettings.hoverDwellChoices, id: \.seconds) { choice in
                        Text(choice.name).tag(choice.seconds)
                    }
                }
            } footer: {
                Text("A short pause keeps a cursor passing through the notch from opening the island.")
            }
            Section {
                Toggle("Show the song title when the track changes", isOn: bind(\.showsSongCaption))
            }
        }
    }

    private func bind<V>(_ keyPath: ReferenceWritableKeyPath<AppSettings, V>) -> Binding<V> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }
}

private struct IslandSettings: View {
    let settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Volume and brightness", isOn: bind(\.showsVolumeBrightness))
                Toggle("Caps Lock", isOn: bind(\.showsCapsLock))
            } header: {
                Text("Keys")
            } footer: {
                Text("Volume and brightness replace the system's own overlay while on. Needs Accessibility.")
            }
            Section {
                Toggle("Battery and charging", isOn: bind(\.showsBattery))
                Toggle("Headphones and speakers", isOn: bind(\.showsDevices))
                Toggle("Focus", isOn: bind(\.showsFocus))
                Toggle("Clock timers and stopwatch", isOn: bind(\.showsClockTimers))
            } header: {
                Text("What happens on the Mac")
            }
            Section {
                Toggle("Live Activities", isOn: bind(\.showsLiveActivities))
            } header: {
                Text("From the iPhone")
            } footer: {
                Text("A match shows its crests and score around the notch and keeps up by the second; hover for the card. Needs Screen Recording for the crests. While this is on, the system's own card is held open out of sight, so the menu bar's pill shows its collapse arrow; switching it off gives the card back.")
            }
            Section {
                Toggle("Calendar events", isOn: bind(\.showsCalendarEvents))
                Toggle("Reminders with a time", isOn: bind(\.showsReminders))
            } header: {
                Text("Coming up")
            } footer: {
                Text("A blip a few minutes before, and again as it starts. Resting on the island with nothing playing shows the next one.")
            }
        }
    }

    private func bind<V>(_ keyPath: ReferenceWritableKeyPath<AppSettings, V>) -> Binding<V> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }
}

private struct MediaSettings: View {
    let settings: AppSettings

    var body: some View {
        Form {
            Section {
                ForEach(AppSettings.knownMediaSources, id: \.id) { source in
                    Toggle(source.name, isOn: Binding(
                        get: { settings.isMediaSourceEnabled(source.id) },
                        set: { settings.setMediaSource(source.id, enabled: $0) }
                    ))
                }
            } header: {
                Text("Now playing from")
            } footer: {
                Text("The island follows music from these apps only. A browser tab or a video never takes the notch.")
            }
        }
    }
}

private struct CalendarSettings: View {
    let settings: AppSettings
    let model: AppModel

    var body: some View {
        let calendars = model.availableCalendars
        let events = CalendarInfo.grouped(calendars.filter { $0.kind == .event })
        let lists = CalendarInfo.grouped(calendars.filter { $0.kind == .reminder })
        Form {
            Section {
                Picker("Remind me before an event", selection: Binding(
                    get: { settings.calendarLeadMinutes },
                    set: { settings.calendarLeadMinutes = $0 }
                )) {
                    ForEach(AppSettings.calendarLeadChoices, id: \.self) { minutes in
                        Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes)
                    }
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
            // One card per kind with the accounts as labels inside it —
            // not a section per account: sections made in a loop render
            // unreliably in a grouped Form on macOS (merged cards, rows
            // drawn twice), and a fixed structure does not.
            if !events.isEmpty {
                Section {
                    ForEach(events, id: \.source) { group in
                        AccountLabel(group.source)
                        ForEach(group.calendars) { calendar in
                            CalendarToggle(calendar: calendar, settings: settings)
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
                    ForEach(lists, id: \.source) { group in
                        AccountLabel(group.source)
                        ForEach(group.calendars) { list in
                            CalendarToggle(calendar: list, settings: settings)
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
private struct AccountLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }
}

/// One calendar row: its colour dot, its name, its switch. A calendar
/// added later starts on.
private struct CalendarToggle: View {
    let calendar: CalendarInfo
    let settings: AppSettings

    var body: some View {
        Toggle(isOn: Binding(
            get: { settings.isCalendarEnabled(calendar.id) },
            set: { settings.setCalendar(calendar.id, enabled: $0) }
        )) {
            HStack(spacing: 8) {
                Circle()
                    .fill(calendar.color.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? Color.secondary)
                    .frame(width: 9, height: 9)
                Text(calendar.title)
            }
        }
    }
}

private struct PermissionsSettings: View {
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
                        HStack {
                            Image(systemName: row.isGranted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(row.isGranted ? Color(nsColor: .systemGreen) : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                Text(row.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !row.isGranted, let url = row.settingsURL {
                                Button("Open Settings…") { NSWorkspace.shared.open(url) }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } footer: {
                    Text("Ledge asks for nothing it does not need. Each grant unlocks one thing and can be turned off again in System Settings.")
                }
            }
        }
    }
}

private struct AboutSettings: View {
    var body: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ledge").font(.title3.weight(.semibold))
                        Text("Version \(version)").foregroundStyle(.secondary)
                        Text("A companion for the notch.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
            Section {
                Button("View on GitHub") {
                    if let url = URL(string: "https://github.com/dededemahendra/ledge") { NSWorkspace.shared.open(url) }
                }
            }
        }
    }
}
