import AppKit
import SwiftUI
import LedgeSettings
import CalendarService
import SettingsKit

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

    /// Closing drops the window (2026-10-22): an ordered-out window keeps its
    /// SwiftUI views, and with them each preview strip's clock, four times a
    /// second. The next `show` builds it again on the same pane, which
    /// `selection` keeps.
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.window = nil }
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
        window?.setContentSize(NSSize(width: 780, height: 1100))
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
            window.setContentSize(NSSize(width: 780, height: 620))
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
    case general, island, media, calendar, github, permissions, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:     return "General"
        case .island:      return "Island"
        case .media:       return "Media"
        case .calendar:    return "Calendar"
        case .github:      return "GitHub"
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
        case .github:      return "arrow.triangle.branch"
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
        case .github:      return Color(white: 0.2)
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
                    .badge(badge(for: section, issues: issueCount))
                    .tag(section)
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selection.section {
                case .general:     GeneralSettings(settings: settings, model: model)
                case .island:      IslandSettings(settings: settings, model: model)
                case .media:       MediaSettings(settings: settings, model: model)
                case .calendar:    CalendarSettings(settings: settings, model: model)
                case .github:      GitHubSettings(settings: settings, model: model)
                case .permissions: PermissionsSettings(model: model)
                case .about:       AboutSettings(model: model)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(selection.section.title)
        }
        .frame(minWidth: 720, minHeight: 560)
    }

    /// Permissions count what is missing; About an update; GitHub a
    /// login it no longer takes (2026-10-22).
    private func badge(for section: SettingsSection, issues: Int) -> Int {
        switch section {
        case .permissions: return issues
        case .about:       return model.hasUpdate ? 1 : 0
        case .github:      return model.githubNeedsAttention ? 1 : 0
        default:           return 0
        }
    }
}
