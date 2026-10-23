#if DEBUG
import AppKit
import ApplicationServices

/// Learns the call apps' controls (2026-10-22, debug builds only):
/// `ledge://probe/call-ax` arms a ten-minute watch, and while a call is on
/// it writes the call app's Accessibility tree — windows, buttons, menu
/// items, and for apps other than browsers their text — to
/// `~/Library/Logs/Ledge/call-ax-<app>.txt`, at most every 20 s per app.
/// A browser's page text is left out; only its controls are written.
@MainActor
enum CallAppProbe {
    private static let browsers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.microsoft.edgemac", "org.mozilla.firefox", "com.brave.Browser",
    ]
    private static let kept: Set<String> = [
        kAXWindowRole, kAXButtonRole, kAXMenuItemRole, kAXMenuBarItemRole, kAXCheckBoxRole, kAXMenuButtonRole,
        kAXStaticTextRole, kAXImageRole, kAXGroupRole,
    ]

    static var armedUntil = Date.distantPast
    private static var lastDump: [String: Date] = [:]

    static func arm(now: Date = Date()) {
        armedUntil = now.addingTimeInterval(600)
        lastDump = [:]
    }

    private static let callApps: [String] = ["com.apple.FaceTime", "net.whatsapp.WhatsApp", "us.zoom.xos",
                                             "com.microsoft.teams2"] + browsers.sorted()

    /// Called each tick; while armed, dumps every running call app (and
    /// browser) every 20 s, call or not, each dump stamped with the time.
    static func tick(now: Date = Date()) -> [String] {
        guard now < armedUntil else { return [] }
        var written: [String] = []
        let dir = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Ledge")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for bundleID in callApps {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { continue }
            if let last = lastDump[bundleID], now.timeIntervalSince(last) < 20 { continue }
            lastDump[bundleID] = now
            let lines = ["dumped \(now)"] + dump(pid: app.processIdentifier, isBrowser: browsers.contains(bundleID))
            let stamp = Int(now.timeIntervalSince1970)
            let file = dir.appending(path: "call-ax-\(bundleID)-\(stamp).txt")
            if (try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)) != nil {
                written.append(file.lastPathComponent)
            }
        }
        return written
    }

    static func dump(pid: pid_t, isBrowser: Bool) -> [String] {
        guard AXIsProcessTrusted() else { return ["not trusted for Accessibility"] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        // Chromium builds its web content's tree only when asked.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var lines: [String] = []
        var budget = 4000
        for attribute in [kAXWindowsAttribute, kAXMenuBarAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success, let value else {
                lines.append("\(attribute): none")
                continue
            }
            let items = (value as? [AXUIElement]) ?? [value as! AXUIElement]
            lines.append("\(attribute) (\(items.count)):")
            for item in items { describe(item, depth: 0, isBrowser: isBrowser, budget: &budget, into: &lines) }
        }
        return lines
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        let text = (value as? String) ?? (value as? NSNumber)?.stringValue
        return text?.isEmpty == false ? text : nil
    }

    private static func describe(_ element: AXUIElement, depth: Int, isBrowser: Bool, budget: inout Int,
                                 into lines: inout [String]) {
        guard depth <= 40, budget > 0 else { return }
        let role = string(element, kAXRoleAttribute) ?? "?"
        if kept.contains(role), !(isBrowser && role == kAXStaticTextRole) {
            var parts = ["role=\(role)"]
            for (label, attribute) in [("sub", kAXSubroleAttribute), ("id", kAXIdentifierAttribute), ("title", kAXTitleAttribute),
                                       ("desc", kAXDescriptionAttribute), ("help", kAXHelpAttribute), ("value", kAXValueAttribute)] {
                if let text = string(element, attribute) { parts.append("\(label)=\(text.prefix(80))") }
            }
            if role != kAXGroupRole || parts.count > 1 {
                lines.append(String(repeating: " ", count: min(depth, 20)) + parts.joined(separator: " "))
                budget -= 1
            }
        }
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let children = children as? [AXUIElement] {
            for child in children.prefix(200) {
                describe(child, depth: depth + 1, isBrowser: isBrowser, budget: &budget, into: &lines)
            }
        }
    }
}
#endif
