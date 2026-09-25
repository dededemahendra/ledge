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
        item.setStatus(key: "app", text: "Ledge — running")
        item.setStatus(key: "power", text: "Power — \(model.powerStatus)")
        item.setStatus(key: "hud", text: "HUD — \(model.hudStatus)")
        item.setStatus(key: "media", text: "Media — \(model.mediaStatus)")
        item.addItem(title: "Toggle Panel") { [weak presenter] in
            presenter?.toggle()
        }
        item.addItem(title: "Toggle Stock OSD Suppression") { [weak model] in
            model?.toggleStockOSDSuppression()
        }
        statusItem = item

        Self.log.info("launched; notch \(String(describing: presenter.controller.metrics.notchRect))")
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
        presenter?.stop()
        Self.log.info("terminating")
    }
}
