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

    /// Every `com.apple.menuextra.*` item on the strip. The agent's window
    /// holds the whole menu bar — system extras and third-party buttons —
    /// so it is walked three levels deep, with the extras bar as a second
    /// source; duplicates collapse. `nil` when the host is not running.
    public static func read() -> [MenuBarExtra]? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: host).first else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var roots: [AXUIElement] = []
        var bar: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXExtrasMenuBarAttribute as CFString, &bar) == .success, let bar {
            roots.append(bar as! AXUIElement)
        }
        var windows: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows) == .success,
           let windows = windows as? [AXUIElement] {
            roots += windows
        }
        var extras: [MenuBarExtra] = []
        var seen: Set<String> = []
        func visit(_ item: AXUIElement, depth: Int) {
            if let id = string(kAXIdentifierAttribute, of: item), id.hasPrefix("com.apple.menuextra."), seen.insert(id).inserted {
                extras.append(MenuBarExtra(
                    identifier: id,
                    description: string(kAXDescriptionAttribute, of: item),
                    value: string(kAXValueAttribute, of: item),
                    title: string(kAXTitleAttribute, of: item)
                ))
            }
            guard depth < 4 else { return }
            for child in children(of: item) { visit(child, depth: depth + 1) }
        }
        for root in roots { visit(root, depth: 0) }
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
