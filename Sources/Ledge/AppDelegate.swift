import AppKit
import NotchKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "app")

    private var statusItem: StatusItemController?
    private var presenter: NotchPresenter?
    private var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.ensureRegistered()

        let presenter = NotchPresenter()
        presenter.start()
        self.presenter = presenter

        let model = AppModel(presenter: presenter)
        model.start()
        self.model = model

        let item = StatusItemController()
        // Just Quit (user's call, 2026-09-29). The panel opens on hover and
        // the system HUD replacement is simply on; neither needs a menu
        // item. Problem rows still appear above Quit when — and only when —
        // something is broken, since a revoked Accessibility grant would
        // otherwise be invisible.
        let refreshMenu: () -> Void = { [weak model, weak item] in
            guard let model, let item else { return }
            item.setIssues(model.issues.map { StatusItemController.Issue(text: $0.text, fix: $0.fix) })
            item.setTimerMenu(
                model.runningTimer.map { .running(paused: $0.isPaused) } ?? .idle,
                onStart: { [weak model] minutes in
                    if let minutes { model?.startTimer(minutes: minutes) } else { model?.startStopwatch() }
                },
                onToggle: { [weak model] in model?.toggleTimerPause() },
                onStop: { [weak model] in model?.stopTimer() }
            )
        }
        refreshMenu()
        item.onMenuWillOpen = refreshMenu
        model.onStatusChange = refreshMenu
        statusItem = item

        Self.log.info("launched; notch \(String(describing: presenter.controller.metrics.notchRect))")
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
        presenter?.stop()
        Self.log.info("terminating")
    }
}
