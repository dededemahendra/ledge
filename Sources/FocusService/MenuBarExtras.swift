import AppKit
import ApplicationServices

/// One system menu bar extra as `MenuBarAgent` exposes it through
/// Accessibility (2026-09-29; layout in `docs/private-api-notes.md`).
public struct MenuBarExtra: Sendable, Equatable {
    public let identifier: String
    public let description: String?
    public let value: String?
    public let title: String?

    public init(identifier: String, description: String? = nil, value: String? = nil, title: String? = nil) {
        self.identifier = identifier
        self.description = description
        self.value = value
        self.title = title
    }
}

/// Reads `MenuBarAgent`'s extras bar. Needs the Accessibility grant the
/// media keys already have; a few dozen IPC round-trips per read, so a
/// once-a-second poll is cheap. Shared by the Focus blip and, next, the
/// iPhone Live Activity mirror.
@MainActor
public enum MenuBarExtrasReader {
    public static let host = "com.apple.MenuBarAgent"

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// `nil` when the host is not running or exposes no extras bar.
    public static func read() -> [MenuBarExtra]? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: host).first else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXExtrasMenuBarAttribute as CFString, &bar) == .success, let bar else { return nil }
        var extras: [MenuBarExtra] = []
        for group in children(of: bar as! AXUIElement) {
            for item in [group] + children(of: group) {
                guard let id = string(kAXIdentifierAttribute, of: item), id.hasPrefix("com.apple.menuextra.") else { continue }
                extras.append(MenuBarExtra(
                    identifier: id,
                    description: string(kAXDescriptionAttribute, of: item),
                    value: string(kAXValueAttribute, of: item),
                    title: string(kAXTitleAttribute, of: item)
                ))
            }
        }
        return extras
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private static func string(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        let text = (value as? String) ?? (value as? NSNumber)?.stringValue
        return (text?.isEmpty == false) ? text : nil
    }
}
