import AppKit
import Foundation
import OSLog

public enum OSDAction: Sendable, Equatable {
    case stop(pid_t)
    case resume(pid_t)
    case nothing
}

/// Pure decisions about which signals to send. Tested exhaustively; the shell
/// below does nothing but enumerate pids and call `kill`.
public struct OSDSuppressionPolicy: Sendable {
    /// The helper is launched on demand, lingers briefly, then exits — so the
    /// sweep has to be frequent enough to catch it mid-burst.
    public static let sweepInterval: TimeInterval = 0.75

    public static func actions(pids: [pid_t], suppressing: Bool) -> [OSDAction] {
        pids.map { suppressing ? .stop($0) : .resume($0) }
    }

    /// At launch, always resume first. A previous crash may have left the helper
    /// `SIGSTOP`ped, and the user's system HUD would be dead until reboot.
    ///
    /// Takes no `willSuppress` parameter: an earlier revision carried one that
    /// its body never read (dead by design, the whole point of launch recovery
    /// being that it must not depend on what this run is about to do), which
    /// only advertised a choice that did not exist. Dropped instead of kept —
    /// a run that wants to suppress does so on its own next sweep via
    /// `setSuppressing(true)`, same as any other run.
    public static func launchRecoveryActions(pids: [pid_t]) -> [OSDAction] {
        pids.map { .resume($0) }
    }
}

/// Suppresses the stock volume/brightness overlay by pausing `OSDUIHelper`.
///
/// The least clean thing in the app, so restoration is belt-and-braces:
/// on disable, on terminate, via `atexit`, and unconditionally at next launch.
@MainActor
public final class OSDSuppressor {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "osd")

    // `nonisolated`: a plain constant read synchronously by tests (and
    // meaningful cross-module, per Task 5's composition). @MainActor on the
    // class would otherwise make it implicitly async to read from outside.
    nonisolated public static let helperBundleIdentifier = "com.apple.OSDUIHelper"

    /// Set so the `atexit` handler — which cannot touch the actor — can still
    /// hand the helper back.
    private nonisolated(unsafe) static var atexitInstalled = false

    public private(set) var isSuppressing = false
    private var sweepTimer: Timer?

    public init() {}

    private static func helperPIDs() -> [pid_t] {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: helperBundleIdentifier)
            .map(\.processIdentifier)
            .filter { $0 > 0 }
    }

    private static func apply(_ actions: [OSDAction]) {
        for action in actions {
            switch action {
            case .stop(let pid):
                if kill(pid, SIGSTOP) != 0 { log.debug("SIGSTOP \(pid) failed") }
            case .resume(let pid):
                if kill(pid, SIGCONT) != 0 { log.debug("SIGCONT \(pid) failed") }
            case .nothing:
                break
            }
        }
    }

    /// Review Focus 3, part one: undo a previous run's suppression regardless
    /// of how that run ended, before deciding what this run wants. Always
    /// resumes unconditionally — the brief's original `willSuppress: Bool`
    /// parameter was dead: `launchRecoveryActions` ignores it by design, and
    /// nothing here read it either. Deleted; a run that wants to suppress
    /// does so on its own next sweep via `setSuppressing(true)`, same as any
    /// other run.
    public func recoverAtLaunch() {
        let pids = Self.helperPIDs()
        Self.apply(OSDSuppressionPolicy.launchRecoveryActions(pids: pids))
        if !pids.isEmpty {
            Self.log.info("launch recovery resumed \(pids.count) helper process(es)")
        }
    }

    public func setSuppressing(_ suppressing: Bool) {
        guard suppressing != isSuppressing else { return }
        isSuppressing = suppressing

        if suppressing {
            installAtexitHandler()
            sweepTimer = Timer.scheduledTimer(
                withTimeInterval: OSDSuppressionPolicy.sweepInterval, repeats: true
            ) { _ in
                MainActor.assumeIsolated {
                    Self.apply(OSDSuppressionPolicy.actions(pids: Self.helperPIDs(), suppressing: true))
                }
            }
            sweepTimer?.tolerance = OSDSuppressionPolicy.sweepInterval / 2
            Self.apply(OSDSuppressionPolicy.actions(pids: Self.helperPIDs(), suppressing: true))
        } else {
            sweepTimer?.invalidate()
            sweepTimer = nil
            Self.apply(OSDSuppressionPolicy.actions(pids: Self.helperPIDs(), suppressing: false))
        }
    }

    /// Called from `applicationWillTerminate`.
    public func shutdown() {
        setSuppressing(false)
    }

    /// Review Focus 3, part two: a signal-kill skips `applicationWillTerminate`,
    /// but `atexit` still runs for most terminations.
    private func installAtexitHandler() {
        guard !Self.atexitInstalled else { return }
        Self.atexitInstalled = true
        atexit {
            // No actor access here; re-enumerate and resume directly.
            for app in NSRunningApplication.runningApplications(
                withBundleIdentifier: OSDSuppressor.helperBundleIdentifier
            ) {
                kill(app.processIdentifier, SIGCONT)
            }
        }
    }
}
