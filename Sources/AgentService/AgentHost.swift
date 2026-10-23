import AppKit
import ApplicationServices
import Foundation
import AgentWire
import CallService

/// Finds the process and the app a session runs in (2026-10-23).
@MainActor
public struct AgentHostLookup {
    public var name: (Int32) -> String?
    public var arguments: (Int32) -> [String]?
    public var app: (Int32) -> CallAppInfo?

    public init(name: @escaping (Int32) -> String?, arguments: @escaping (Int32) -> [String]?,
                app: @escaping (Int32) -> CallAppInfo?) {
        self.name = name
        self.arguments = arguments
        self.app = app
    }

    public static let live = AgentHostLookup(
        name: { AgentProcess.name(of: $0) },
        arguments: { AgentProcess.arguments(of: $0) },
        app: { CallApp.resolve($0, ownPID: ProcessInfo.processInfo.processIdentifier, lookup: .live) }
    )

    /// The first pid named "claude" (else pids[1], else pids[0]); headless when its arguments hold "-p" or "--print".
    public func facts(for pids: [Int32]) -> AgentFacts {
        let claude = pids.first { name($0) == "claude" } ?? (pids.count > 1 ? pids[1] : pids.first)
        guard let claude else { return AgentFacts(claudePID: nil, isHeadless: false, host: nil) }
        let args = arguments(claude) ?? []
        let headless = args.contains("-p") || args.contains("--print")
        return AgentFacts(claudePID: claude, isHeadless: headless, host: app(claude))
    }
}

/// Bringing a session's window forward, and noticing the user is already in it.
@MainActor
enum AgentWindows {
    static let vscode: Set<String> = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]
    static let ghostty = "com.mitchellh.ghostty"

    private static func folder(of session: AgentSession) -> String {
        URL(fileURLWithPath: session.project).lastPathComponent
    }

    private static func title(of window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func isLooking(at session: AgentSession) -> Bool {
        guard let host = session.host,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == host.pid,
              AXIsProcessTrusted() else { return false }
        let name = folder(of: session)
        guard !name.isEmpty else { return false }
        let app = AXUIElementCreateApplication(host.pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return false }
        return title(of: window as! AXUIElement)?.contains(name) == true
    }

    static func focus(_ session: AgentSession) {
        guard let host = session.host else { return }
        if vscode.contains(host.bundleID),
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: host.bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([URL(fileURLWithPath: session.project)], withApplicationAt: appURL,
                                    configuration: configuration)
            return
        }
        let running = NSRunningApplication(processIdentifier: host.pid)
        running?.activate()
        guard host.bundleID == ghostty, AXIsProcessTrusted() else { return }
        let name = folder(of: session)
        guard !name.isEmpty else { return }
        let app = AXUIElementCreateApplication(host.pid)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
              let list = windows as? [AXUIElement] else { return }
        for window in list where title(of: window)?.contains(name) == true {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            return
        }
    }
}
