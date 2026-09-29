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
        let presenter = NotchPresenter()
        presenter.start()
        self.presenter = presenter

        let model = AppModel(presenter: presenter)
        model.start()
        self.model = model

        let item = StatusItemController()
        // Minimal (2026-09-29): no status rows while everything works;
        // problem rows only, an on/off checkmark instead of a "Toggle…"
        // verb, and the panel item named for what it will do. All of it
        // re-read from live state whenever the menu opens or a service
        // reports a change.
        let panelItem = item.addItem(title: "Show Panel") { [weak presenter] in
            presenter?.toggle()
        }
        let hudItem = item.addItem(title: "Replace System HUD") { [weak model] in
            model?.toggleStockOSDSuppression()
        }
        let refreshMenu: () -> Void = { [weak model, weak item, weak panelItem, weak hudItem] in
            guard let model, let item else { return }
            item.setIssues(model.issues.map { StatusItemController.Issue(text: $0.text, fix: $0.fix) })
            panelItem?.title = model.isPanelOpen ? "Hide Panel" : "Show Panel"
            hudItem?.state = model.isSuppressingStockOSD ? .on : .off
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
