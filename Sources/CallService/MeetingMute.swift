import Foundation

/// An Accessibility element as the mute finder sees it (2026-10-23): the
/// live tree and recorded test trees both conform.
public protocol AXNode {
    var role: String? { get }
    var identifier: String? { get }
    var title: String? { get }
    var children: [Self] { get }
}

/// A recorded element, for tests.
public struct AXSnapshot: AXNode, Sendable, Equatable {
    public var role: String?
    public var identifier: String?
    public var title: String?
    public var children: [AXSnapshot]

    public init(role: String?, identifier: String?, title: String?, children: [AXSnapshot]) {
        self.role = role
        self.identifier = identifier
        self.title = title
        self.children = children
    }
}

/// The meeting's own mute (2026-10-23), found live with the probe:
/// - Zoom: the Meeting menu's item identified `onMuteAudio:`, titled
///   "Unmute audio" while muted and "Mute audio" while not.
/// - Meet in a browser: in a window whose title contains "Meet - ", the
///   button titled "Turn on microphone" while muted and "Turn off
///   microphone" while not. Only the front tab's page is exposed.
/// The state is read from English titles; other languages read as unknown.
public enum MeetingMute: Sendable, Equatable {
    case zoom, meet

    /// Whether pressing the control works. Meet's page ignores presses that
    /// come through Accessibility — the press reports success and nothing
    /// changes (found live, 2026-10-23) — so Meet is read, never pressed.
    public var canPress: Bool { self == .zoom }

    static let maxDepth = 40
    static let maxNodes = 3000

    public static func kind(for bundleID: String) -> MeetingMute? {
        if bundleID == "us.zoom.xos" { return .zoom }
        return CallMeetingMatcher.browsers.contains(bundleID) ? .meet : nil
    }

    public static func find<N: AXNode>(_ kind: MeetingMute, menuBar: N?, windows: [N]) -> N? {
        var budget = maxNodes
        switch kind {
        case .zoom:
            guard let menuBar else { return nil }
            return search(menuBar, depth: 0, budget: &budget) {
                $0.role == "AXMenuItem" && $0.identifier == "onMuteAudio:"
            }
        case .meet:
            for window in windows where window.title?.contains("Meet - ") == true {
                if let found = search(window, depth: 0, budget: &budget, where: {
                    $0.role == "AXButton" && ($0.title == "Turn off microphone" || $0.title == "Turn on microphone")
                }) {
                    return found
                }
            }
            return nil
        }
    }

    /// Whether to ask a browser for its page tree: only with a Meet window
    /// open, since asking makes Chromium build trees for every tab.
    public static func needsPageTree(windowTitles: [String]) -> Bool {
        windowTitles.contains { $0.contains("Meet - ") }
    }

    public static func isMuted(_ kind: MeetingMute, title: String?) -> Bool? {
        guard let title else { return nil }
        switch kind {
        case .zoom:
            if title.hasPrefix("Unmute") { return true }
            if title.hasPrefix("Mute") { return false }
            return nil
        case .meet:
            if title == "Turn on microphone" { return true }
            if title == "Turn off microphone" { return false }
            return nil
        }
    }

    private static func search<N: AXNode>(_ node: N, depth: Int, budget: inout Int, where matches: (N) -> Bool) -> N? {
        guard depth <= maxDepth, budget > 0 else { return nil }
        budget -= 1
        if matches(node) { return node }
        for child in node.children {
            if let found = search(child, depth: depth + 1, budget: &budget, where: matches) { return found }
        }
        return nil
    }
}
