import AppKit
import NotchKit
import LedgeSettings
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "app")

    private var statusItem: StatusItemController?
    private var presenter: NotchPresenter?
    private var model: AppModel?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings()
        if settings.launchAtLogin { LoginItem.ensureRegistered() }

        let presenter = NotchPresenter()
        presenter.start()
        self.presenter = presenter

        let model = AppModel(presenter: presenter, settings: settings)
        model.start()
        self.model = model

        let settingsWindow = SettingsWindowController(settings: settings, model: model)
        self.settingsWindow = settingsWindow
        model.onOpenSettings = { [weak settingsWindow] in settingsWindow?.show() }
        #if DEBUG
        model.onSnapshotSettings = { [weak settingsWindow] dir in
            Task { @MainActor in await settingsWindow?.snapshotAll(to: dir) }
        }
        #endif

        let item = StatusItemController()
        // Settings… above Quit (2026-09-30): the one other row the menu has.
        item.addItem(title: "Settings…", keyEquivalent: ",") { [weak settingsWindow] in settingsWindow?.show() }
        // Just Quit (user's call, 2026-09-29). The panel opens on hover and
        // the system HUD replacement is simply on; neither needs a menu
        // item. Problem rows still appear above Quit when — and only when —
        // something is broken, since a revoked Accessibility grant would
        // otherwise be invisible.
        let refreshMenu: () -> Void = { [weak model, weak item] in
            guard let model, let item else { return }
            item.setIssues(model.issues.map { StatusItemController.Issue(text: $0.text, fix: $0.fix) })
        }
        refreshMenu()
        item.onMenuWillOpen = refreshMenu
        model.onStatusChange = refreshMenu
        statusItem = item

        Self.log.info("launched; notch \(String(describing: presenter.controller.metrics.notchRect))")
    }

    /// The `ledge://` scheme (`Info.plist.in`): debug-only probe, see
    /// `AppModel.openURL`.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { model?.openURL(url) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
        presenter?.stop()
        Self.log.info("terminating")
    }
}
