import AppKit

/// The app's only chrome: a menu bar item carrying status rows and Quit.
@MainActor
final class StatusItemController {
    private let item: NSStatusItem
    private let menu = NSMenu()
    /// Status rows occupy the top of the menu in the order they were first
    /// added — each new one goes AFTER the existing ones, not at index 0,
    /// which listed them in reverse (review, 2026-09-29).
    private var statusRowCount = 0

    init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "Ledge"
        )
        item.menu = menu
        addSeparator()
        // Appended directly, NOT via `addItem(title:action:)` below: this
        // call is what ESTABLISHES the trailing separator + Quit pair that
        // method's own doc comment promises to stay above of. Routing it
        // through `addItem` too was the bug — `addItem` unconditionally
        // appended, so the shipped menu read
        // `power, app, ─, Quit Ledge, Toggle Panel`, with Quit stuck in the
        // middle and whatever action item was added last ending up below it.
        menu.addItem(makeItem(title: "Quit Ledge") { NSApp.terminate(nil) })
    }

    func addSeparator() {
        menu.addItem(.separator())
    }

    /// Inserts an item above the trailing separator + Quit pair.
    func addItem(title: String, action: @escaping () -> Void) {
        // `- 2`: the separator and Quit Ledge are always the last two items
        // by construction (`init` above), so this is where "above them"
        // always is, regardless of how many status rows or action items
        // have been added in between.
        menu.insertItem(makeItem(title: title, action: action), at: max(0, menu.items.count - 2))
    }

    private func makeItem(title: String, action: @escaping () -> Void) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: #selector(Trampoline.fire), keyEquivalent: "")
        let trampoline = Trampoline(action)
        entry.target = trampoline
        // `target` is weak in AppKit's target-action pattern, so this strong
        // `representedObject` reference is what keeps the trampoline alive for
        // as long as the item is in the menu. Without it the closure would be
        // deallocated the moment this method returns.
        entry.representedObject = trampoline
        return entry
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
        menu.insertItem(entry, at: statusRowCount)
        statusRowCount += 1
    }

    private final class Trampoline: NSObject {
        private let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }
}
