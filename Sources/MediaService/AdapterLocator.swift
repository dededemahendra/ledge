import Foundation
import ActivityKit

/// Resolves the bundled adapter's absolute paths. The README requires absolute
/// paths and forbids linking the framework — it is only ever passed as a
/// script argument to `/usr/bin/perl`.
public struct AdapterLocator: Sendable {
    public let resourceRoot: URL

    public init(resourceRoot: URL) {
        self.resourceRoot = resourceRoot
    }

    /// The adapter as bundled by the Makefile's `bundle` target, under
    /// `Contents/Resources/mediaremote-adapter`.
    public static func inMainBundle() -> AdapterLocator? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        return AdapterLocator(
            resourceRoot: resources.appendingPathComponent("mediaremote-adapter", isDirectory: true)
        )
    }

    public var scriptPath: URL {
        resourceRoot.appendingPathComponent("mediaremote-adapter.pl")
    }
    public var frameworkPath: URL {
        resourceRoot.appendingPathComponent("MediaRemoteAdapter.framework")
    }
    public var testClientPath: URL {
        resourceRoot.appendingPathComponent("MediaRemoteAdapterTestClient")
    }

    /// A missing adapter is a clean `unavailable`, not a crash — the app must
    /// launch and work normally with media dead.
    public func validate() -> ServiceAvailability {
        let fm = FileManager.default
        guard fm.fileExists(atPath: scriptPath.path) else {
            return .unavailable(reason: "adapter script missing from bundle")
        }
        guard fm.fileExists(atPath: frameworkPath.path) else {
            return .unavailable(reason: "adapter framework missing from bundle")
        }
        guard fm.isExecutableFile(atPath: "/usr/bin/perl") else {
            return .unavailable(reason: "/usr/bin/perl unavailable")
        }
        return .available
    }

    /// `--no-diff` is deliberately NOT passed: diffs are cheaper on the wire,
    /// and `MediaStateMerger` already handles them.
    public func streamArguments() -> [String] {
        [scriptPath.path, frameworkPath.path, "stream"]
    }

    public func commandArguments(_ command: MediaCommand) -> [String] {
        [scriptPath.path, frameworkPath.path] + command.adapterArguments
    }

    /// The `test` command requires the test client's absolute path as an
    /// additional argument, ordered before the command itself.
    public func testArguments() -> [String] {
        [scriptPath.path, frameworkPath.path, testClientPath.path, "test"]
    }
}
