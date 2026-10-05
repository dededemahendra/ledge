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
    public nonisolated static let host = "com.apple.MenuBarAgent"
    public nonisolated static let identifierPrefix = "live-activity-pill-"

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

    /// The open card's own Accessibility window, when it is up.
    public static func expandedWindow() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: host).first else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows) == .success,
              let items = windows as? [AXUIElement]
        else { return nil }
        return items.first { string(kAXIdentifierAttribute, of: $0) == "live-activity-expanded" }
    }

    /// Where a window is now, in screen points.
    public static func position(of window: AXUIElement) -> CGRect? { frame(of: window) }

    /// Tries to move a window; `false` when the app will not have it.
    @discardableResult
    public static func move(_ window: AXUIElement, to point: CGPoint) -> Bool {
        var origin = point
        guard let value = AXValueCreate(.cgPoint, &origin) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }

    /// What the open card says: its own size in points and every text and
    /// picture in it, placed relative to its top-left. The card hangs in
    /// a tall window and its content lives in whichever hosting view
    /// actually has children, so that view's frame is the origin.
    public static func cardContent(of window: AXUIElement) -> (size: CGSize, elements: [CardElement])? {
        var best: (frame: CGRect, elements: [(CardElement.Kind, String, CGRect)])?
        func walk(_ item: AXUIElement, depth: Int) {
            guard depth <= 10 else { return }
            var found: [(CardElement.Kind, String, CGRect)] = []
            collect(item, depth: 0, into: &found)
            if !found.isEmpty, let frame = frame(of: item) {
                // The innermost container that still holds everything.
                if best == nil || found.count >= best!.elements.count, frame.width > 0, frame.height > 0 {
                    best = (frame, found)
                }
            }
            for child in children(of: item) { walk(child, depth: depth + 1) }
        }
        func collect(_ item: AXUIElement, depth: Int, into found: inout [(CardElement.Kind, String, CGRect)]) {
            guard depth <= 10 else { return }
            let role = string(kAXRoleAttribute, of: item) ?? ""
            if role == "AXStaticText", let value = string(kAXValueAttribute, of: item), let frame = frame(of: item) {
                found.append((.text, value, frame))
            } else if role == "AXImage", let desc = string(kAXDescriptionAttribute, of: item), let frame = frame(of: item) {
                found.append((.image, desc, frame))
            }
            for child in children(of: item) { collect(child, depth: depth + 1, into: &found) }
        }
        walk(window, depth: 0)
        guard let best, !best.elements.isEmpty else { return nil }
        let origin = best.frame.origin
        let elements = best.elements.map {
            CardElement(kind: $0.0, text: $0.1,
                        frame: CGRect(x: $0.2.minX - origin.x, y: $0.2.minY - origin.y, width: $0.2.width, height: $0.2.height))
        }
        return (best.frame.size, elements)
    }

    #if DEBUG
    /// Debug only: every element of `MenuBarAgent`'s windows, so the open
    /// card's own Accessibility tree can be read once.
    public static func describePopoverTree() -> [String] {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: host).first else { return ["no agent"] }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows) == .success,
              let items = windows as? [AXUIElement]
        else { return ["no windows"] }
        var lines: [String] = []
        for (index, window) in items.enumerated() {
            lines.append("window \(index):")
            describe(window, depth: 1, into: &lines)
        }
        return lines
    }

    private static func describe(_ element: AXUIElement, depth: Int, into lines: inout [String]) {
        guard depth <= 10 else { return }
        var parts: [String] = []
        for (label, attribute) in [("role", kAXRoleAttribute), ("sub", kAXSubroleAttribute), ("id", kAXIdentifierAttribute),
                                   ("title", kAXTitleAttribute), ("desc", kAXDescriptionAttribute), ("value", kAXValueAttribute)] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value {
                let text = (value as? String) ?? (value as? NSNumber)?.stringValue ?? ""
                if !text.isEmpty { parts.append("\(label)=\(text)") }
            }
        }
        if let frame = frame(of: element) {
            parts.append("frame=\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))")
        }
        lines.append(String(repeating: "  ", count: depth) + parts.joined(separator: " "))
        for child in children(of: element) { describe(child, depth: depth + 1, into: &lines) }
    }
    #endif

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
