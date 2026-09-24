import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "app")

    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController()
        statusItem?.setStatus(key: "app", text: "Ledge — running")
        Self.log.info("launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.log.info("terminating")
    }
}
