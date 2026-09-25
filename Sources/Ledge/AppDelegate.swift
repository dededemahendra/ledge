import AppKit
import NotchKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "app")

    private var statusItem: StatusItemController?
    private var presenter: NotchPresenter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let presenter = NotchPresenter()
        presenter.start()
        self.presenter = presenter

        let item = StatusItemController()
        item.setStatus(key: "app", text: "Ledge — running")
        item.addItem(title: "Toggle Panel") { [weak presenter] in
            presenter?.toggle()
        }
        statusItem = item

        Self.log.info("launched; notch \(String(describing: presenter.controller.metrics.notchRect))")
    }

    func applicationWillTerminate(_ notification: Notification) {
        presenter?.stop()
        Self.log.info("terminating")
    }
}
