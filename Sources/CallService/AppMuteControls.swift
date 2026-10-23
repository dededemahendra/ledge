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
    /// Whether the control can be pressed, or only read (Meet).
    var canPress: Bool { get }
    /// Brings the app's own mute to `target`, pressing its control only if
    /// it isn't already; whether there was a control.
    func setMuted(_ target: Bool) -> Bool
}

/// An Accessibility element carried between threads. AXUIElement is a
/// CoreFoundation reference that is safe to use from any thread.
struct AXElementRef: @unchecked Sendable {
    let element: AXUIElement
}

/// A live element seen through `AXNode`, its children fetched as asked.
/// Each element it hands out gives up after 0.25 s, so a hung app can't
/// hold a read up; the limit stays on these elements, not the whole app.
struct LiveAXNode: AXNode {
    static let timeout: Float = 0.25
    let element: AXUIElement

    init(element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, Self.timeout)
        self.element = element
    }

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
/// is found by walking the app's tree on a background queue, then kept, and
/// only its title is read — once a second, one read at a time; a search
/// that finds nothing backs off to every 10 s (`ReadPacer`). A press is
/// decided on the queue by target, against a fresh read, and reads that
/// began before it or disagree just after it aren't believed
/// (`MuteReadGate`). Nothing is brought to the front and no keys are sent.
@MainActor
public final class AXAppMuteControls: AppMuteSource {
    /// Logs a control's own wording and press results only — never a
    /// window title or a meeting's name.
    nonisolated static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "call")

    private struct State: Sendable {
        var bundleID: String?
        var element: AXElementRef?
        var muted: Bool?
        var gate = MuteReadGate()
        var pacer = ReadPacer()
    }

    private let queue = DispatchQueue(label: "com.dedemahendra.ledge.call-mute")
    private let state = OSAllocatedUnfairLock(initialState: State())
    private var current: CallAppInfo?

    public init() {}

    public var canPress: Bool {
        current.flatMap { MeetingMute.kind(for: $0.bundleID) }?.canPress ?? false
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
        if current != app {
            current = app
            state.withLock { $0 = State(bundleID: app.bundleID) }
        }
        let now = Date()
        let generation = state.withLock { state -> Int? in
            state.pacer.shouldStart(at: now) ? state.gate.generation : nil
        }
        guard let generation else { return }
        let state = self.state
        let bundleID = app.bundleID
        let pid = app.pid
        queue.async {
            Self.read(kind: kind, bundleID: bundleID, pid: pid, generation: generation, state: state)
        }
    }

    public func setMuted(_ target: Bool) -> Bool {
        guard canPress else { return false }
        let bundleID = current?.bundleID
        let now = Date()
        let found = state.withLock { state -> (element: AXElementRef?, known: Bool) in
            guard state.bundleID == bundleID, bundleID != nil, let muted = state.muted else { return (nil, false) }
            guard muted != target, let element = state.element else { return (nil, true) }
            state.gate.pressed(target, at: now)
            state.muted = target
            return (element, true)
        }
        guard found.known else { return false }
        guard let element = found.element, let kind = bundleID.flatMap(MeetingMute.kind(for:)) else { return true }
        queue.async {
            // Decided against a fresh read: never pressed the wrong way.
            let title = LiveAXNode(element: element.element).title
            if MeetingMute.isMuted(kind, title: title) != target {
                let result = AXUIElementPerformAction(element.element, kAXPressAction as CFString)
                Self.log.notice("mute press \(String(describing: kind), privacy: .public): before=\(title ?? "nil", privacy: .public) target=\(target, privacy: .public) result=\(result.rawValue, privacy: .public)")
            } else {
                Self.log.notice("mute press skipped: already \(title ?? "nil", privacy: .public)")
            }
        }
        return true
    }

    private nonisolated static func read(kind: MeetingMute, bundleID: String, pid: pid_t, generation: Int,
                                         state: OSAllocatedUnfairLock<State>) {
        guard let cached = state.withLock({ $0.bundleID == bundleID ? Optional($0.element) : nil }) else {
            return   // the call moved on: this read is no longer anyone's
        }
        let (element, muted): (AXElementRef?, Bool?)
        if let cached, let title = LiveAXNode(element: cached.element).title {
            (element, muted) = (cached, MeetingMute.isMuted(kind, title: title))
        } else {
            let found = find(kind: kind, pid: pid)
            (element, muted) = (found.map { AXElementRef(element: $0.element) },
                                found.flatMap { MeetingMute.isMuted(kind, title: $0.title) })
            log.notice("mute search \(String(describing: kind), privacy: .public): cached=\(cached != nil, privacy: .public) found=\(found?.title ?? "nil", privacy: .public)")
        }
        let now = Date()
        state.withLock { state in
            guard state.bundleID == bundleID else { return }
            state.pacer.finished(found: element != nil, at: now)
            guard state.gate.accepts(muted, startedAt: generation, at: now) else { return }
            state.element = element
            state.muted = muted
        }
    }

    private nonisolated static func find(kind: MeetingMute, pid: pid_t) -> LiveAXNode? {
        let app = AXUIElementCreateApplication(pid)
        let root = LiveAXNode(element: app)
        switch kind {
        case .zoom:
            return MeetingMute.find(kind, menuBar: root.menuBar, windows: [])
        case .meet:
            // Chromium builds its pages' trees only when asked, for every tab
            // from then on: ask only with a Meet window open.
            guard MeetingMute.needsPageTree(windowTitles: root.windows.compactMap(\.title)) else { return nil }
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            return MeetingMute.find(kind, menuBar: nil, windows: root.windows)
        }
    }
}
