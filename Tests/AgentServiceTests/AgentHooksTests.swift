import Testing
import Foundation
import Darwin
@testable import AgentService

private let helper = "/H/Ledge/ledge-agent-hook"

private func parse(_ s: String) -> OrderedJSON { try! OrderedJSON.parse(Data(s.utf8)) }

private func groups(_ settings: OrderedJSON, _ event: String) -> [OrderedJSON] {
    guard case .array(let a)? = settings["hooks"]?[event] else { return [] }
    return a
}

private let othersFixture = """
{
  "model": "opus",
  "hooks": {
    "PreToolUse": [
      {"matcher":"Bash","hooks":[{"type":"command","command":"/Users/x/.claude/hooks/rtk-rewrite.sh"}]},
      {"matcher":"*","hooks":[{"type":"command","command":"/x/orca-hook","timeout":10}]},
      {"matcher":"Artifact","hooks":[{"type":"command","command":"[ -n \\"$SUPERSET_HOME_DIR\\" ] && x || true"}]}
    ],
    "Stop": [
      {"hooks":[{"type":"command","command":"/x/orca-stop"}]}
    ],
    "SessionStart": [
      {"hooks":[{"type":"command","command":"/x/superset-start"}]}
    ]
  },
  "statusLine": {"type":"command","command":"x"},
  "theme": "dark"
}
"""

@Test func everyHookIsAsyncAndGuarded() {
    #expect(AgentHooks.command(helper: "/H/L/ledge-agent-hook")
        == "[ -x '/H/L/ledge-agent-hook' ] && '/H/L/ledge-agent-hook' || true")
    let odd = "/Users/o'neil/Library/Application Support/Ledge/ledge-agent-hook"
    let quoted = #"'/Users/o'\''neil/Library/Application Support/Ledge/ledge-agent-hook'"#
    #expect(AgentHooks.command(helper: odd) == "[ -x \(quoted) ] && \(quoted) || true")
    #expect(AgentHooks.command(helper: odd).contains(AgentHooks.marker))
    let out = AgentHooks.installing(into: parse("{}"), helper: helper)
    #expect(AgentHooks.events.count == 10)
    #expect(AgentHooks.matcherEvents == ["PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest"])
    guard case .object(let events)? = out["hooks"] else { Issue.record("no hooks"); return }
    #expect(events.map(\.key) == AgentHooks.events)
    for event in AgentHooks.events {
        let g = groups(out, event)
        #expect(g.count == 1)
        let expected: OrderedJSON = .object(
            (AgentHooks.matcherEvents.contains(event) ? [(key: "matcher", value: OrderedJSON.string("*"))] : [])
            + [(key: "hooks", value: .array([.object([
                (key: "type", value: .string("command")),
                (key: "command", value: .string(AgentHooks.command(helper: helper))),
                (key: "async", value: .bool(true)),
                (key: "timeout", value: .number("5")),
            ])]))])
        #expect(g[0] == expected)
    }
}

@Test func othersEntriesAreKept() {
    let before = parse(othersFixture)
    let out = AgentHooks.installing(into: before, helper: helper)
    for event in ["PreToolUse", "Stop", "SessionStart"] {
        let old = groups(before, event)
        let new = groups(out, event)
        #expect(new.count == old.count + 1)
        #expect(Array(new.prefix(old.count)) == old)
    }
    guard case .object(let top) = out else { return }
    #expect(top.map(\.key) == ["model", "hooks", "statusLine", "theme"])
}

@Test func installingTwiceChangesNothing() {
    let once = AgentHooks.installing(into: parse(othersFixture), helper: helper)
    #expect(AgentHooks.installing(into: once, helper: helper) == once)
    #expect(once.written() == AgentHooks.installing(into: once, helper: helper).written())
}

@Test func anOldHelperPathIsReplaced() {
    let old = AgentHooks.installing(into: parse(othersFixture), helper: "/old/Ledge/ledge-agent-hook")
    let new = AgentHooks.installing(into: old, helper: helper)
    for event in AgentHooks.events {
        let text = groups(new, event).map { String(decoding: $0.written(), as: UTF8.self) }
        let ours = text.filter { $0.contains(AgentHooks.marker) }
        #expect(ours.count == 1)
        #expect(ours[0].contains(helper))
        #expect(!ours[0].contains("/old/"))
    }
    #expect(AgentHooks.isInstalled(in: new, helper: helper))
    #expect(!AgentHooks.isInstalled(in: new, helper: "/old/Ledge/ledge-agent-hook"))
}

@Test func removingTakesOnlyLedgesAndEmptiedGroups() {
    let ledgeHook = AgentHooks.command(helper: helper)
    let text = """
    {"model":"opus",
     "hooks":{
      "Stop":[{"hooks":[{"type":"command","command":"/x/other"},{"type":"command","command":\(String(decoding: OrderedJSON.string(ledgeHook).written().dropLast(), as: UTF8.self))}]}],
      "SessionEnd":[{"hooks":[{"type":"command","command":\(String(decoding: OrderedJSON.string(ledgeHook).written().dropLast(), as: UTF8.self))}]}],
      "Notification":[{"hooks":[]}]
     },
     "theme":"dark"}
    """
    let out = AgentHooks.removing(from: parse(text))
    #expect(groups(out, "Stop").count == 1)
    #expect(groups(out, "Stop")[0] == parse(#"{"hooks":[{"type":"command","command":"/x/other"}]}"#))
    #expect(out["hooks"]?["SessionEnd"] == nil)
    #expect(groups(out, "Notification").count == 1)

    let onlyLedge = AgentHooks.installing(into: parse(#"{"a":1,"b":2}"#), helper: helper)
    let removed = AgentHooks.removing(from: onlyLedge)
    #expect(removed == parse(#"{"a":1,"b":2}"#))
    #expect(removed["hooks"] == nil)
}

@Test func isInstalledNeedsAllTenAtThisPath() {
    let full = AgentHooks.installing(into: parse("{}"), helper: helper)
    #expect(AgentHooks.isInstalled(in: full, helper: helper))
    #expect(!AgentHooks.isInstalled(in: full, helper: "/other/Ledge/ledge-agent-hook"))
    #expect(!AgentHooks.isInstalled(in: parse("{}"), helper: helper))
    // drop one event
    guard case .object(var top) = full, case .object(var events)? = full["hooks"] else { return }
    events.removeAll { $0.key == "Stop" }
    top = top.map { $0.key == "hooks" ? (key: "hooks", value: .object(events)) : $0 }
    #expect(!AgentHooks.isInstalled(in: .object(top), helper: helper))
}

private func tempFile() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ag-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("settings.json")
}

@Test func aMissingFileIsCreatedWithJustTheHooks() throws {
    let url = tempFile()
    let file = AgentSettingsFile(url: url)
    #expect(!file.isInstalled(helper: helper))
    try file.install(helper: helper)
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(file.isInstalled(helper: helper))
    let parsed = try OrderedJSON.parse(Data(contentsOf: url))
    guard case .object(let top) = parsed else { Issue.record("not object"); return }
    #expect(top.map(\.key) == ["hooks"])
    try file.uninstall()
    #expect(!file.isInstalled(helper: helper))
}

@Test func theFirstWriteKeepsABackupOnce() throws {
    let url = tempFile()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let original = Data(othersFixture.utf8)
    try original.write(to: url)
    let file = AgentSettingsFile(url: url)
    try file.install(helper: helper)
    let backup = url.appendingPathExtension("ledge-backup")
    #expect(backup.lastPathComponent == "settings.json.ledge-backup")
    #expect(try Data(contentsOf: backup) == original)
    try file.install(helper: "/new/Ledge/ledge-agent-hook")
    #expect(try Data(contentsOf: backup) == original)
}

@Test func notAnObjectIsLeftAlone() throws {
    let url = tempFile()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("[]".utf8).write(to: url)
    let file = AgentSettingsFile(url: url)
    #expect(throws: AgentSettingsFile.Problem.notAnObject) { try file.install(helper: helper) }
    #expect(try Data(contentsOf: url) == Data("[]".utf8))
}

@Test func anUnchangedFileIsNotRewritten() throws {
    let url = tempFile()
    let file = AgentSettingsFile(url: url)
    try file.install(helper: helper)
    let past = Date(timeIntervalSince1970: 1_000_000)
    try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: url.path)
    try file.install(helper: helper)
    let after = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    #expect(after == past)
}

private func otherGroup(_ cmd: String) -> OrderedJSON { parse(#"{"hooks":[{"type":"command","command":"\#(cmd)"}]}"#) }

private func appending(_ group: OrderedJSON, to settings: OrderedJSON, event: String) -> OrderedJSON {
    guard case .object(var top) = settings, let hi = top.firstIndex(where: { $0.key == "hooks" }),
          case .object(var evs) = top[hi].value, let ei = evs.firstIndex(where: { $0.key == event }),
          case .array(var gs) = evs[ei].value else { return settings }
    gs.append(group)
    evs[ei].value = .array(gs)
    top[hi].value = .object(evs)
    return .object(top)
}

@Test func ledgesGroupKeepsItsPlaceWhenAnotherToolAppendsAfterIt() {
    let once = AgentHooks.installing(into: parse("{}"), helper: helper)
    let after = appending(otherGroup("/x/other"), to: once, event: "Stop")
    let again = AgentHooks.installing(into: after, helper: helper)
    #expect(again == after)
    #expect(again.written() == after.written())
    #expect(groups(again, "Stop").count == 2)
    #expect(groups(again, "Stop")[1] == otherGroup("/x/other"))
}

@Test func anOldHelperPathInALedgeOnlyGroupIsUpdatedInPlace() {
    var s = AgentHooks.installing(into: parse("{}"), helper: "/old/Ledge/ledge-agent-hook")
    s = appending(otherGroup("/x/other"), to: s, event: "Stop")
    let out = AgentHooks.installing(into: s, helper: helper)
    let g = groups(out, "Stop")
    #expect(g.count == 2)
    #expect(String(decoding: g[0].written(), as: UTF8.self).contains(helper))
    #expect(g[1] == otherGroup("/x/other"))
}

@Test func aMixedGroupLosesLedgesHookAndLedgesGroupGoesLast() {
    let l = AgentHooks.command(helper: helper)
    let lj = String(decoding: OrderedJSON.string(l).written().dropLast(), as: UTF8.self)
    let mixed = parse(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/x/other"},{"type":"command","command":\#(lj)}]}]}}"#)
    let out = AgentHooks.installing(into: mixed, helper: helper)
    let g = groups(out, "Stop")
    #expect(g.count == 2)
    #expect(g[0] == otherGroup("/x/other"))
    #expect(String(decoding: g[1].written(), as: UTF8.self).contains(AgentHooks.marker))
}

@Test func aSymlinkedSettingsFileStaysALink() throws {
    let dir = tempFile().deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let real = dir.appendingPathComponent("real.json")
    let link = dir.appendingPathComponent("settings.json")
    try Data(#"{"theme":"dark"}"#.utf8).write(to: real)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    try AgentSettingsFile(url: link).install(helper: helper)
    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)
    let parsed = try OrderedJSON.parse(Data(contentsOf: real))
    #expect(AgentHooks.isInstalled(in: parsed, helper: helper))
    #expect(FileManager.default.fileExists(atPath: real.appendingPathExtension("ledge-backup").path))
}

// MARK: - Final fix wave (2026-10-23)

/// Runs `command` with /bin/sh, as Claude Code runs a hook.
private func runShell(_ command: String) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

@Test func theCommandRunsAHelperWhosePathHasQuotesAndSpaces() throws {
    let dir = tempFile().deletingLastPathComponent().appendingPathComponent("it's a \"dir\" $HOME", isDirectory: true)
        .appendingPathComponent("Ledge", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let ran = dir.appendingPathComponent("ran")
    let helper = dir.appendingPathComponent("ledge-agent-hook")
    try Data("#!/bin/sh\ntouch \"$(dirname \"$0\")/ran\"\n".utf8).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
    #expect(try runShell(AgentHooks.command(helper: helper.path)) == 0)
    #expect(FileManager.default.fileExists(atPath: ran.path))
    // A helper that is gone: the guard keeps the hook quiet and successful.
    try FileManager.default.removeItem(at: helper)
    #expect(try runShell(AgentHooks.command(helper: helper.path)) == 0)
}

private func settingsFile(_ text: String) throws -> URL {
    let url = tempFile()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
    return url
}

private let unexpected = AgentSettingsFile.Problem.unexpectedShape("hooks has an unexpected shape")

@Test func hooksOfAnUnexpectedShapeAreLeftAloneOnInstallAndRemoval() throws {
    let shapes = [
        #"{"hooks":{"Stop":{"mine":true}}}"#,
        #"{"hooks":{"Stop":[{"hooks":[]}],"Stop":{"mine":true}}}"#,
        #"{"hooks":{"Stop":{"mine":true},"Stop":[{"hooks":[]}]}}"#,
        #"{"hooks":null}"#,
        #"{"hooks":[]}"#,
        #"{"hooks":{"Stop":[]},"hooks":5}"#,
        #"{"hooks":5,"hooks":{"Stop":[]}}"#,
    ]
    for text in shapes {
        let url = try settingsFile(text)
        let file = AgentSettingsFile(url: url)
        #expect(throws: unexpected) { try file.install(helper: helper) }
        #expect(try Data(contentsOf: url) == Data(text.utf8), "install changed \(text)")
        #expect(throws: unexpected) { try file.uninstall() }
        #expect(try Data(contentsOf: url) == Data(text.utf8), "removal changed \(text)")
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("ledge-backup").path))
        // The pure edits hand such settings back as they were.
        #expect(AgentHooks.installing(into: parse(text), helper: helper) == parse(text))
        #expect(AgentHooks.removing(from: parse(text)) == parse(text))
    }
}

@Test func removalLeavesHooksThatHaveTheirOwnShape() throws {
    // Ledge's hooks in, then someone's Stop made an object: nothing comes out.
    let installed = AgentHooks.installing(into: parse("{}"), helper: helper)
    guard case .object(var top) = installed, case .object(var events)? = installed["hooks"] else { return }
    events = events.map { $0.key == "Stop" ? (key: "Stop", value: parse(#"{"mine":true}"#)) : $0 }
    top = top.map { $0.key == "hooks" ? (key: "hooks", value: .object(events)) : $0 }
    let text = String(decoding: OrderedJSON.object(top).written(), as: UTF8.self)
    let url = try settingsFile(text)
    #expect(throws: unexpected) { try AgentSettingsFile(url: url).uninstall() }
    #expect(try Data(contentsOf: url) == Data(text.utf8))
}

@Test func anEventOutsideTheTenMayHaveAnyShape() throws {
    let url = try settingsFile(#"{"hooks":{"Custom":{"mine":true}}}"#)
    let file = AgentSettingsFile(url: url)
    try file.install(helper: helper)
    #expect(file.isInstalled(helper: helper))
    let parsed = try OrderedJSON.parse(Data(contentsOf: url))
    #expect(parsed["hooks"]?["Custom"] == parse(#"{"mine":true}"#))
    try file.uninstall()
    #expect(try OrderedJSON.parse(Data(contentsOf: url)) == parse(#"{"hooks":{"Custom":{"mine":true}}}"#))
}

@Test func theBackupKeepsTheOriginalsMode() throws {
    for mode in [0o600, 0o640] {
        let url = try settingsFile(othersFixture)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        try AgentSettingsFile(url: url).install(helper: helper)
        let backup = url.appendingPathExtension("ledge-backup")
        let attributes = try FileManager.default.attributesOfItem(atPath: backup.path)
        #expect(attributes[.posixPermissions] as? Int == mode)
        #expect(try Data(contentsOf: backup) == Data(othersFixture.utf8))
    }
}

@Test func aChangeMadeWhileLedgeWorksIsKept() throws {
    let url = try settingsFile(#"{"theme":"dark"}"#)
    var file = AgentSettingsFile(url: url)
    let theirs = Data(#"{"theme":"dark","model":"opus"}"#.utf8)
    file.beforeRecheck = { try? theirs.write(to: url) }
    try file.install(helper: helper)
    let installed = try OrderedJSON.parse(Data(contentsOf: url))
    #expect(installed["model"] == .string("opus"))
    #expect(AgentHooks.isInstalled(in: installed, helper: helper))

    let again = Data(String(decoding: installed.written(), as: UTF8.self).replacingOccurrences(of: "opus", with: "sonnet").utf8)
    file.beforeRecheck = { try? again.write(to: url) }
    try file.uninstall()
    let removed = try OrderedJSON.parse(Data(contentsOf: url))
    #expect(removed == parse(#"{"theme":"dark","model":"sonnet"}"#))
}

@Test func aFailedWriteSaysWrite() throws {
    let url = try settingsFile("{}")
    let folder = url.deletingLastPathComponent()
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
    do {
        try AgentSettingsFile(url: url).install(helper: helper)
        Issue.record("expected the write to fail")
    } catch {
        guard case .unwritable = error else { Issue.record("expected unwritable, got \(error)"); return }
    }
    #expect(try Data(contentsOf: url) == Data("{}".utf8))
}
