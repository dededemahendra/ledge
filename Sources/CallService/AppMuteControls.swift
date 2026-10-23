import AppKit
import ApplicationServices
import os

/// The live call app's own mute (2026-10-23). A protocol so the service can
/// be tested on a made-up control. `muted` is nil while the current app has
/// no control Ledge can read (none found yet, none at all, or no
/// Accessibility trust).
@MainActor
public protocol AppMuteSource: AnyObject {
    func update(for app: CallAppInfo?)
    var muted: Bool? { get }
    /// Presses the control; whether there was one to press.
    func press() -> Bool
}

/// An Accessibility element carried between threads. AXUIElement is a
/// CoreFoundation reference that is safe to use from any thread.
struct AXElementRef: @unchecked Sendable {
    let element: AXUIElement
}

/// A live element seen through `AXNode`, its children fetched as asked.
struct LiveAXNode: AXNode {
    let element: AXUIElement

    var role: String? { string(kAXRoleAttribute) }
    var identifier: String? { string(kAXIdentifierAttribute) }
    var title: String? { string(kAXTitleAttribute) }
    var children: [LiveAXNode] { elements(kAXChildrenAttribute) }
    var windows: [LiveAXNode] { elements(kAXWindowsAttribute) }
    var menuBar: LiveAXNode? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return LiveAXNode(element: value as! AXUIElement)
    }

    private func string(_ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func elements(_ attribute: String) -> [LiveAXNode] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list.map(LiveAXNode.init)
    }
}

/// Zoom's and Meet's own mute through Accessibility (2026-10-23). The control
/// is found once per call by walking the app's tree on a background queue;
/// after that only its title is read, once a second, and a failed read
/// means finding it again. Nothing is brought to the front and no keys are
/// sent. Every Accessibility call in the process gives up after 0.25 s, so a
/// hung app can't hold anything up.
@MainActor
public final class AXAppMuteControls: AppMuteSource {
    private struct State: Sendable {
        var bundleID: String?
        var element: AXElementRef?
        var muted: Bool?
    }

    private let queue = DispatchQueue(label: "com.dedemahendra.ledge.call-mute")
    private let state = OSAllocatedUnfairLock(initialState: State())
    private var current: CallAppInfo?
    private var lastUpdate = Date.distantPast

    public init() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
    }

    public var muted: Bool? {
        let bundleID = current?.bundleID
        return state.withLock { $0.bundleID == bundleID && bundleID != nil ? $0.muted : nil }
    }

    public func update(for app: CallAppInfo?) {
        guard let app, let kind = MeetingMute.kind(for: app.bundleID), AXIsProcessTrusted() else {
            current = nil
            state.withLock { $0 = State() }
            return
        }
        let now = Date()
        let changed = current != app
        guard changed || now.timeIntervalSince(lastUpdate) >= 1 else { return }
        lastUpdate = now
        if changed {
            current = app
            state.withLock { $0 = State(bundleID: app.bundleID) }
        }
        let state = self.state
        let bundleID = app.bundleID
        let pid = app.pid
        queue.async {
            Self.read(kind: kind, bundleID: bundleID, pid: pid, state: state)
        }
    }

    public func press() -> Bool {
        let bundleID = current?.bundleID
        let element = state.withLock { state -> AXElementRef? in
            guard state.bundleID == bundleID, bundleID != nil, state.muted != nil else { return nil }
            // Shown at once; the next read corrects it if the press missed.
            state.muted?.toggle()
            return state.element
        }
        guard let element else { return false }
        queue.async { _ = AXUIElementPerformAction(element.element, kAXPressAction as CFString) }
        return true
    }

    private nonisolated static func read(kind: MeetingMute, bundleID: String, pid: pid_t,
                                         state: OSAllocatedUnfairLock<State>) {
        let cached = state.withLock { $0.bundleID == bundleID ? $0.element : nil }
        if let cached, let title = LiveAXNode(element: cached.element).title {
            let muted = MeetingMute.isMuted(kind, title: title)
            state.withLock { if $0.bundleID == bundleID { $0.muted = muted } }
            return
        }
        let app = AXUIElementCreateApplication(pid)
        if kind == .meet {
            // Chromium builds its pages' tree only when asked.
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        let root = LiveAXNode(element: app)
        let found = MeetingMute.find(kind, menuBar: kind == .zoom ? root.menuBar : nil,
                                     windows: kind == .meet ? root.windows : [])
        let muted = found.flatMap { MeetingMute.isMuted(kind, title: $0.title) }
        let element = found.map { AXElementRef(element: $0.element) }
        state.withLock { state in
            guard state.bundleID == bundleID else { return }
            state.element = element
            state.muted = muted
        }
    }
}
