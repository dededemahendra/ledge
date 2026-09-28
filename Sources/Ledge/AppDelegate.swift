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
        item.setStatus(key: "systemhud", text: "System HUD — \(model.systemHUDStatus)")
        item.setStatus(key: "media", text: "Media — \(model.mediaStatus)")
        item.addItem(title: "Toggle Panel") { [weak presenter] in
            presenter?.toggle()
        }
        item.addItem(title: "Toggle System HUD Replacement") { [weak model, weak item] in
            model?.toggleStockOSDSuppression()
            if let model { item?.setStatus(key: "systemhud", text: "System HUD — \(model.systemHUDStatus)") }
        }
        // The Accessibility grant usually lands AFTER launch (the user
        // flips the switch in System Settings); keep the row honest.
        model.onSystemHUDStatusChange = { [weak model, weak item] in
            guard let model else { return }
            item?.setStatus(key: "systemhud", text: "System HUD — \(model.systemHUDStatus)")
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
