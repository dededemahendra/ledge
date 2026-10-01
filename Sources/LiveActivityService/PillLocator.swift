import AppKit
import ApplicationServices

/// Where the menu bar's Live Activity pill is right now (2026-10-01).
/// `MenuBarAgent` hosts an iPhone Live Activity as an `AXMenuBarItem`
/// whose identifier starts with `live-activity-pill-` (46×24 pt on this
/// Mac), with a frame and nothing readable inside — two empty hosting
/// groups and an image — so the frame is all Accessibility gives, and the
/// pixels come from `PillCapture`. See `docs/private-api-notes.md`.
public struct PillLocation: @unchecked Sendable {
    public let identifier: String
    /// Screen points, top-left origin, as Accessibility reports it.
    public let frame: CGRect
    let element: AXUIElement?

    public init(identifier: String, frame: CGRect, element: AXUIElement? = nil) {
        self.identifier = identifier
        self.frame = frame
        self.element = element
    }
}

extension PillLocation: Equatable {
    /// The element is a handle, not state: two readings of the same pill
    /// at the same place are the same location.
    public static func == (lhs: PillLocation, rhs: PillLocation) -> Bool {
        lhs.identifier == rhs.identifier && lhs.frame == rhs.frame
    }
}

@MainActor
public enum PillLocator {
    public static let host = "com.apple.MenuBarAgent"
    public static let identifierPrefix = "live-activity-pill-"

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    public static func isPill(identifier: String?) -> Bool {
        identifier?.hasPrefix(identifierPrefix) ?? false
    }

    /// The pill, or `nil` when no Live Activity is showing (or the host is
    /// not running). The extras bar is walked two levels deep: the pill
    /// has sat directly under it and under a hosting group.
    public static func find() -> PillLocation? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: host).first else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXExtrasMenuBarAttribute as CFString, &bar) == .success, let bar else { return nil }
        return search(bar as! AXUIElement, depth: 0)
    }

    /// Clicks the pill: the system opens its own expanded view under it.
    @discardableResult
    public static func press(_ location: PillLocation) -> Bool {
        guard let element = location.element else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    private static func search(_ item: AXUIElement, depth: Int) -> PillLocation? {
        if let id = string(kAXIdentifierAttribute, of: item), isPill(identifier: id), let frame = frame(of: item) {
            return PillLocation(identifier: id, frame: frame, element: item)
        }
        guard depth < 2 else { return nil }
        for child in children(of: item) {
            if let found = search(child, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private static func string(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        return value as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &value) == .success, let value else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }
}
