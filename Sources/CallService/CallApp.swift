import AppKit
import Darwin

/// The app a call is in (2026-10-22): what the island shows and what a
/// click brings forward.
public struct CallAppInfo: Sendable, Equatable, Hashable {
    public let bundleID: String
    public let name: String
    public let pid: pid_t

    public init(bundleID: String, name: String, pid: pid_t) {
        self.bundleID = bundleID
        self.name = name
        self.pid = pid
    }
}

/// The three questions `CallApp` asks about a process, injected so the walk
/// can be tested against a made-up process table.
@MainActor
public struct ProcessLookup {
    /// The app this PID is, when it is a regular one (a Dock icon).
    public var regularApp: (pid_t) -> CallAppInfo?
    /// The process macOS holds responsible for this one, if any.
    public var responsiblePID: (pid_t) -> pid_t?
    public var parentPID: (pid_t) -> pid_t?

    public init(regularApp: @escaping (pid_t) -> CallAppInfo?, responsiblePID: @escaping (pid_t) -> pid_t?,
                parentPID: @escaping (pid_t) -> pid_t?) {
        self.regularApp = regularApp
        self.responsiblePID = responsiblePID
        self.parentPID = parentPID
    }

    public static let live = ProcessLookup(
        regularApp: { pid in
            guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier, let name = app.localizedName else { return nil }
            return CallAppInfo(bundleID: bundleID, name: name, pid: pid)
        },
        responsiblePID: { pid in
            let responsible = responsibility_get_pid_responsible_for_pid(pid)
            return responsible > 0 ? responsible : nil
        },
        parentPID: { pid in
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            return pid_t(info.pbi_ppid)
        }
    )
}

/// The private call Activity Monitor relies on to group a helper under its
/// app; Safari's WebKit processes are launchd's children, not Safari's.
@_silgen_name("responsibility_get_pid_responsible_for_pid")
private func responsibility_get_pid_responsible_for_pid(_ pid: pid_t) -> pid_t

/// Which app a process holding the mic belongs to (2026-10-22). Only a
/// regular app counts: system daemons (Siri, dictation), menu-bar apps and
/// command-line tools resolve to nil, and so does Ledge itself.
@MainActor
public enum CallApp {
    /// How far up the parents to look; a cycle or a deep tree gives up.
    static let maxHops = 10

    public static func resolve(_ pid: pid_t, ownPID: pid_t, lookup: ProcessLookup) -> CallAppInfo? {
        func regular(_ pid: pid_t) -> CallAppInfo? {
            pid == ownPID ? nil : lookup.regularApp(pid)
        }
        guard pid != ownPID else { return nil }
        if let app = regular(pid) { return app }
        if let responsible = lookup.responsiblePID(pid), responsible != pid, let app = regular(responsible) {
            return app
        }
        var current = pid
        for _ in 0..<maxHops {
            guard let parent = lookup.parentPID(current), parent > 1 else { return nil }
            if let app = regular(parent) { return app }
            current = parent
        }
        return nil
    }
}
