import AppKit

/// The app's only chrome: a menu bar item carrying status rows and Quit.
@MainActor
final class StatusItemController {
    private let item: NSStatusItem
    private let menu = NSMenu()

    init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "Ledge"
        )
        item.menu = menu
        addSeparator()
        addItem(title: "Quit Ledge") { NSApp.terminate(nil) }
    }

    func addSeparator() {
        menu.addItem(.separator())
    }

    /// Inserts an item above the trailing separator + Quit pair.
    func addItem(title: String, action: @escaping () -> Void) {
        let entry = NSMenuItem(title: title, action: #selector(Trampoline.fire), keyEquivalent: "")
        let trampoline = Trampoline(action)
        entry.target = trampoline
        // `target` is weak in AppKit's target-action pattern, so this strong
        // `representedObject` reference is what keeps the trampoline alive for
        // as long as the item is in the menu. Without it the closure would be
        // deallocated the moment this method returns.
        entry.representedObject = trampoline
        menu.addItem(entry)
    }

    /// Updates (or creates) a status row identified by `key`, e.g. "power".
    func setStatus(key: String, text: String) {
        if let existing = menu.items.first(where: { $0.identifier?.rawValue == key }) {
            existing.title = text
            return
        }
        let entry = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        entry.identifier = NSUserInterfaceItemIdentifier(key)
        entry.isEnabled = false
        menu.insertItem(entry, at: 0)
    }

    private final class Trampoline: NSObject {
        private let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }
}
