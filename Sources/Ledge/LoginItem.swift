import Foundation
import ServiceManagement
import OSLog

/// Launch at login, via `SMAppService` (user's call, 2026-09-29): a
/// daily-driver agent that nothing restarts after a reboot is not one.
/// Registers the running bundle on every launch — idempotent, and it
/// keeps the login item pointing at wherever the app currently lives
/// (`dist/` during development, `/Applications` after `make install`).
/// macOS shows its own "added as a login item" notice the first time and
/// keeps the switch in System Settings › General › Login Items.
@MainActor
enum LoginItem {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "login-item")

    static func ensureRegistered() {
        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            return
        case .requiresApproval:
            log.info("login item awaiting approval in System Settings")
            return
        case .notRegistered, .notFound:
            fallthrough
        @unknown default:
            do {
                try service.register()
                log.info("registered as a login item")
            } catch {
                log.error("login item registration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// A problem row for the menu, or `nil` when there is nothing to say.
    static var issue: (text: String, fix: () -> Void)? {
        switch SMAppService.mainApp.status {
        case .requiresApproval:
            return ("Launch at login needs approval…", { SMAppService.openSystemSettingsLoginItems() })
        case .notFound:
            return ("Launch at login points at a moved app — relaunch from its new location", {
                SMAppService.openSystemSettingsLoginItems()
            })
        default:
            return nil
        }
    }
}
