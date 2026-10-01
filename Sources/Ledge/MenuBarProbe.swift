import AppKit
import ApplicationServices

/// Reads the system menu bar's extras through Accessibility (2026-09-29):
/// iPhone Live Activities are drawn there by `MenuBarAgent`/Control Center
/// for `liveactivitiesd`, and nothing about them is persisted anywhere
/// this app could read. On demand (`ledge://probe/menubar`) this dumps
/// every extra's role, identifier, title, description, value and frame,
/// two levels deep, so a live activity's shape can be learned from the log
/// and mirrored into the island. Needs the Accessibility grant the media
/// keys already have.
@MainActor
enum MenuBarProbe {
    static let hosts = ["com.apple.controlcenter", "com.apple.MenuBarAgent"]

    static func dump() -> [String] {
        guard AXIsProcessTrusted() else { return ["not trusted for Accessibility"] }
        var lines: [String] = []
        for bundle in hosts {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
                lines.append("\(bundle): not running")
                continue
            }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var extras: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(element, kAXExtrasMenuBarAttribute as CFString, &extras)
            if status == .success, let bar = extras {
                lines.append("\(bundle) extras:")
                describe(bar as! AXUIElement, depth: 0, into: &lines)
            } else {
                lines.append("\(bundle): no extras menu bar (\(status.rawValue))")
            }
            // The whole top level too: a Focus item or a live activity may
            // be hosted as a window or a child rather than an extra.
            for attribute in [kAXWindowsAttribute, kAXChildrenAttribute, kAXMenuBarAttribute] {
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { continue }
                let items = (value as? [AXUIElement]) ?? [value as! AXUIElement]
                lines.append("\(bundle) \(attribute) (\(items.count)):")
                for item in items.prefix(30) { describe(item, depth: 0, into: &lines) }
            }
        }
        return lines
    }

    private static func describe(_ element: AXUIElement, depth: Int, into lines: inout [String]) {
        guard depth <= 7 else { return }
        var parts: [String] = []
        for (label, attribute) in [("role", kAXRoleAttribute), ("sub", kAXSubroleAttribute), ("id", kAXIdentifierAttribute),
                                   ("title", kAXTitleAttribute), ("desc", kAXDescriptionAttribute), ("value", kAXValueAttribute),
                                   ("help", kAXHelpAttribute)] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value {
                let text = (value as? String) ?? (value as? NSNumber)?.stringValue ?? String(describing: value)
                if !text.isEmpty { parts.append("\(label)=\(text)") }
            }
        }
        var frameValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &frameValue) == .success, let frameValue {
            var rect = CGRect.zero
            if AXValueGetValue(frameValue as! AXValue, .cgRect, &rect) {
                parts.append("frame=\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height))")
            }
        }
        lines.append(String(repeating: "  ", count: depth + 1) + parts.joined(separator: " "))
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let children = children as? [AXUIElement] {
            for child in children.prefix(40) { describe(child, depth: depth + 1, into: &lines) }
        }
    }
}
