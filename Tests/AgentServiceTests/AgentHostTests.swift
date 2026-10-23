import Testing
import Foundation
import CallService
@testable import AgentService

private let vscode = CallAppInfo(bundleID: "com.microsoft.VSCode", name: "Code", pid: 100)
private let ghostty = CallAppInfo(bundleID: "com.mitchellh.ghostty", name: "Ghostty", pid: 300)
private let ledgePID: Int32 = 500
private let ledge = CallAppInfo(bundleID: "com.dedemahendra.ledge", name: "Ledge", pid: ledgePID)

/// A made-up process table. Nothing in it is bundled: claude's binaries are bare executables.
@MainActor private func table(_ rows: [Int32: (app: CallAppInfo?, responsible: Int32?, parent: Int32?)]) -> ProcessLookup {
    ProcessLookup(regularApp: { rows[$0]?.app }, responsiblePID: { rows[$0]?.responsible },
                  parentPID: { rows[$0]?.parent }, isBundled: { _ in false })
}

@MainActor @Test func aBareClaudeTakesTheAppResponsibleForIt() {
    // The native CLI in VS Code's terminal: claude ← zsh ← the pty host, all VS Code's responsibility.
    let lookup = table([
        42: (nil, 100, 41), 41: (nil, 100, 40), 40: (nil, 100, 1), 100: (vscode, 100, 1),
    ])
    #expect(AgentHostLookup.resolve(42, ownPID: ledgePID, lookup: lookup) == vscode)
    // CallApp turns the same bare executable away.
    #expect(CallApp.resolve(42, ownPID: ledgePID, lookup: lookup) == nil)
}

@MainActor @Test func withNoResponsibleAppTheGrandparentCounts() {
    // claude is its own responsible process; its parent is a shell, the shell's is Ghostty.
    let lookup = table([42: (nil, 42, 41), 41: (nil, nil, 300), 300: (ghostty, 300, 1)])
    #expect(AgentHostLookup.resolve(42, ownPID: ledgePID, lookup: lookup) == ghostty)
}

@MainActor @Test func ledgeIsNeverTheHost() {
    // Ledge responsible and the parent: passed over, and nothing above it is an app.
    let alone = table([42: (nil, ledgePID, ledgePID), ledgePID: (ledge, ledgePID, 1)])
    #expect(AgentHostLookup.resolve(42, ownPID: ledgePID, lookup: alone) == nil)
    // Above Ledge, the next app counts.
    let above = table([42: (nil, ledgePID, ledgePID), ledgePID: (ledge, ledgePID, 300), 300: (ghostty, 300, 1)])
    #expect(AgentHostLookup.resolve(42, ownPID: ledgePID, lookup: above) == ghostty)
    #expect(AgentHostLookup.resolve(ledgePID, ownPID: ledgePID, lookup: above) == nil)
}

@MainActor @Test func theWalkGoesTenParentsUp() {
    // 1000's parent is 999, and so on; the app sits ten, then eleven, parents up.
    func chain(appAt: Int32) -> ProcessLookup {
        var rows: [Int32: (app: CallAppInfo?, responsible: Int32?, parent: Int32?)] = [:]
        for pid in Int32(985)...1000 { rows[pid] = (nil, nil, pid - 1) }
        rows[appAt] = (CallAppInfo(bundleID: "x.term", name: "Term", pid: appAt), nil, 1)
        return table(rows)
    }
    #expect(AgentHostLookup.resolve(1000, ownPID: ledgePID, lookup: chain(appAt: 990))?.pid == 990)
    #expect(AgentHostLookup.resolve(1000, ownPID: ledgePID, lookup: chain(appAt: 989)) == nil)
}

@MainActor @Test func theNativeClaudeIsFoundByItsArgvZero() {
    // The native CLI's process name is its version; argv[0] is still "claude".
    func lookup(argv0: String) -> AgentHostLookup {
        AgentHostLookup(name: { $0 == 42 ? "2.1.306" : "zsh" },
                        arguments: { $0 == 42 ? [argv0, "--resume"] : ["-zsh"] },
                        app: { $0 == 42 ? vscode : nil })
    }
    for argv0 in ["claude", "/Users/x/.local/bin/claude"] {
        let facts = lookup(argv0: argv0).facts(for: [10, 11, 42, 7])
        #expect(facts.claudePID == 42)
        #expect(facts.host == vscode)
        #expect(!facts.isHeadless)
    }
    // Neither name nor argv[0]: the second pid, as before.
    #expect(lookup(argv0: "node").facts(for: [10, 11, 42, 7]).claudePID == 11)
}

@Test func theFolderToOpenMustExist() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "ledge-folder-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appending(path: "notes.txt")
    try Data("x".utf8).write(to: file)

    let url = try #require(AgentWindows.folderURL(for: dir.path))
    #expect(url.path == dir.path)
    #expect(url.hasDirectoryPath)
    #expect(AgentWindows.folderURL(for: dir.appending(path: "missing").path) == nil)
    #expect(AgentWindows.folderURL(for: file.path) == nil)
    #expect(AgentWindows.folderURL(for: "") == nil)
}

@Test func focusOpensTheFullPathNotTheFolderName() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "ledge-focus-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let session = AgentSession(id: "s", name: "x", project: dir.lastPathComponent, projectPath: dir.path, state: .idle)
    #expect(AgentWindows.folderURL(for: session.projectPath)?.path == dir.path)
    #expect(AgentWindows.folderURL(for: session.project) == nil)
}
