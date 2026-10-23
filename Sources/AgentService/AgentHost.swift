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
        app: { resolve($0, ownPID: ProcessInfo.processInfo.processIdentifier, lookup: .live) }
    )

    /// How far up the parents `resolve` looks.
    static let maxHops = 10

    /// The app a claude process runs in (2026-10-23). Claude's binaries are
    /// bare executables (`~/.local/share/claude/versions/…`, an editor
    /// extension's `native-binary/claude`), which `CallApp.resolve` turns
    /// away: here the process macOS holds responsible for it counts when that
    /// is a regular app, else the first regular app up its parents. Never Ledge.
    public static func resolve(_ pid: Int32, ownPID: Int32, lookup: ProcessLookup) -> CallAppInfo? {
        func regular(_ pid: Int32) -> CallAppInfo? {
            pid == ownPID ? nil : lookup.regularApp(pid)
        }
        guard pid != ownPID else { return nil }
        if let responsible = lookup.responsiblePID(pid), let app = regular(responsible) { return app }
        var current = pid
        for _ in 0..<maxHops {
            guard let parent = lookup.parentPID(current), parent > 1 else { return nil }
            if let app = regular(parent) { return app }
            current = parent
        }
        return nil
    }

    /// Claude by its process name, or by its argv[0] when the name is a version (the native CLI, "2.1.306").
    private func isClaude(_ pid: Int32) -> Bool {
        if name(pid) == "claude" { return true }
        guard let first = arguments(pid)?.first else { return false }
        return (first as NSString).lastPathComponent == "claude"
    }

    /// The first pid that is claude (else pids[1], else pids[0]); headless when its arguments hold "-p" or "--print".
    public func facts(for pids: [Int32]) -> AgentFacts {
        let claude = pids.first(where: isClaude) ?? (pids.count > 1 ? pids[1] : pids.first)
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

    /// Accessibility asks of a busy app give up after this long, not the default six seconds.
    static let messagingTimeout: Float = 0.25

    private static func folder(of session: AgentSession) -> String {
        URL(fileURLWithPath: session.project).lastPathComponent
    }

    /// The project folder to open (2026-10-23): nil when the path is empty or is not a folder.
    nonisolated static func folderURL(for path: String) -> URL? {
        var isDirectory: ObjCBool = false
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        return app
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
        let app = application(host.pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return false }
        return title(of: window as! AXUIElement)?.contains(name) == true
    }

    /// VS Code opens the project's folder, which brings its window forward; with
    /// no folder to open, or any other app, the app comes forward.
    static func focus(_ session: AgentSession) {
        guard let host = session.host else { return }
        if vscode.contains(host.bundleID), let folder = folderURL(for: session.projectPath),
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: host.bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([folder], withApplicationAt: appURL, configuration: configuration)
            return
        }
        let running = NSRunningApplication(processIdentifier: host.pid)
        running?.activate()
        guard host.bundleID == ghostty, AXIsProcessTrusted() else { return }
        let name = folder(of: session)
        guard !name.isEmpty else { return }
        let app = application(host.pid)
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
