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
        // Rows are (re)written by `refreshStatusRows` — at launch, after a
        // toggle, and whenever a service reports a change — so a service
        // dying or recovering mid-session never leaves launch-time text
        // behind. `setStatus` updates in place by key.
        func refreshStatusRows() {
            item.setStatus(key: "app", text: "Ledge — running")
            item.setStatus(key: "power", text: "Power — \(model.powerStatus)")
            item.setStatus(key: "hud", text: "HUD — \(model.hudStatus)")
            item.setStatus(key: "systemhud", text: "System HUD — \(model.systemHUDStatus)")
            item.setStatus(key: "media", text: "Media — \(model.mediaStatus)")
            item.setStatus(key: "devices", text: "Devices — \(model.deviceStatus)")
        }
        refreshStatusRows()
        item.addItem(title: "Toggle Panel") { [weak presenter] in
            presenter?.toggle()
        }
        item.addItem(title: "Toggle System HUD Replacement") { [weak model] in
            model?.toggleStockOSDSuppression()
            refreshStatusRows()
        }
        model.onStatusChange = { refreshStatusRows() }
        statusItem = item

        Self.log.info("launched; notch \(String(describing: presenter.controller.metrics.notchRect))")
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
        presenter?.stop()
        Self.log.info("terminating")
    }
}
