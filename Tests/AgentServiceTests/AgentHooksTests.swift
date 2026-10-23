import Testing
import Foundation
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
        == "[ -x \"/H/L/ledge-agent-hook\" ] && \"/H/L/ledge-agent-hook\" || true")
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
