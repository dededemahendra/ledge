import AppKit

/// The app's only chrome: a menu bar item. Minimal by design (2026-09-29):
/// Settings… and Quit, nothing else (2026-10-21: the problem rows that sat
/// above them now live in Settings › Permissions).
@MainActor
final class StatusItemController: NSObject {
    private let item: NSStatusItem
    private let menu = NSMenu()

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.image = Self.makeIcon()
        item.button?.toolTip = "Ledge"
        item.menu = menu
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Quit Ledge") { NSApp.terminate(nil) })
    }

    /// Inserts an action item above the trailing separator + Quit pair and
    /// returns it, so the caller can retitle it or set its checkmark as
    /// state changes.
    @discardableResult
    func addItem(title: String, keyEquivalent: String = "", action: @escaping () -> Void) -> NSMenuItem {
        let entry = makeItem(title: title, keyEquivalent: keyEquivalent, action: action)
        // The separator and Quit are always the last two items by
        // construction (`init` above), so "above them" is always here.
        menu.insertItem(entry, at: max(0, menu.items.count - 2))
        return entry
    }

    private func makeItem(title: String, keyEquivalent: String = "", action: @escaping () -> Void) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: #selector(Trampoline.fire), keyEquivalent: keyEquivalent)
        let trampoline = Trampoline(action)
        entry.target = trampoline
        // `target` is weak in AppKit's target-action pattern, so this strong
        // `representedObject` reference is what keeps the trampoline alive for
        // as long as the item is in the menu.
        entry.representedObject = trampoline
        return entry
    }

    /// The menu bar glyph: a display with its notch, drawn at 2x and pixel
    /// aligned, as a template image so it takes the menu bar's own colour
    /// in light and dark. Replaces the stock "rectangle" symbol, which read
    /// as a generic window.
    private static func makeIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            // Display outline: 16 × 11, corner 2.5, 1.5pt stroke, centred.
            let frame = NSRect(x: 1.25, y: 3.75, width: 15.5, height: 10.5)
            let outline = NSBezierPath(roundedRect: frame, xRadius: 2.5, yRadius: 2.5)
            outline.lineWidth = 1.5
            outline.stroke()
            // The notch: hangs from the inside of the top edge, rounded at
            // the bottom like the real one.
            let notch = NSBezierPath()
            let top = frame.maxY - 0.75
            let width: CGFloat = 5, depth: CGFloat = 2.25, radius: CGFloat = 1
            let left = frame.midX - width / 2, right = frame.midX + width / 2
            notch.move(to: NSPoint(x: left, y: top))
            notch.line(to: NSPoint(x: left, y: top - depth + radius))
            notch.appendArc(withCenter: NSPoint(x: left + radius, y: top - depth + radius), radius: radius, startAngle: 180, endAngle: 270)
            notch.line(to: NSPoint(x: right - radius, y: top - depth))
            notch.appendArc(withCenter: NSPoint(x: right - radius, y: top - depth + radius), radius: radius, startAngle: 270, endAngle: 360)
            notch.line(to: NSPoint(x: right, y: top))
            notch.close()
            notch.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private final class Trampoline: NSObject {
        private let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }
}
