import Foundation
import Testing
@testable import AgentService

@Test func installingIntoEmptyAndExistingText() {
    #expect(ShellHookBlock.installing(into: "") == ShellHookBlock.text)
    let installed = ShellHookBlock.installing(into: "export A=1\n")
    #expect(installed.hasPrefix("export A=1\n\n" + ShellHookBlock.begin))
    #expect(ShellHookBlock.state(of: installed) == .present)
    #expect(ShellHookBlock.state(of: "export A=1\n") == .absent)
}

/// A second switch-on, or a block copied in by hand: still one block.
@Test func installingTwiceLeavesOneBlock() {
    let once = ShellHookBlock.installing(into: "export A=1\n")
    #expect(ShellHookBlock.installing(into: once) == once)
}

@Test func removingTakesExactlyWhatInstallingAdded() {
    #expect(ShellHookBlock.removing(from: ShellHookBlock.installing(into: "export A=1\n")) == "export A=1\n")
    #expect(ShellHookBlock.removing(from: ShellHookBlock.installing(into: "")) == "")
}

/// A begin marker without its end, from a hand edit: never "fixed" by
/// deleting lines.
@Test func aBrokenBlockIsLeftAloneAndReported() throws {
    let broken = "export A=1\n" + ShellHookBlock.begin + "\necho hi\n"
    #expect(ShellHookBlock.state(of: broken) == .broken)
    let home = try temporaryHome()
    let url = home.appending(path: ".zshrc")
    try broken.write(to: url, atomically: true, encoding: .utf8)
    let file = ZshrcFile(url: url)
    #expect(throws: ZshrcFile.Problem.broken) { try file.install() }
    #expect(throws: ZshrcFile.Problem.broken) { try file.uninstall() }
    #expect(try String(contentsOf: url, encoding: .utf8) == broken)
}

@Test func theFileIsCreatedBackedUpAndKeepsItsMode() throws {
    let home = try temporaryHome()
    let fresh = home.appending(path: ".zshrc")
    try ZshrcFile(url: fresh).install()
    #expect(try String(contentsOf: fresh, encoding: .utf8) == ShellHookBlock.text)

    let other = try temporaryHome().appending(path: ".zshrc")
    try "export A=1\n".write(to: other, atomically: true, encoding: .utf8)
    chmod(other.path, 0o600)
    let file = ZshrcFile(url: other)
    try file.install()
    #expect(file.isInstalled())
    #expect(mode(other) == 0o600)
    let backup = other.appendingPathExtension("ledge-backup")
    #expect(try String(contentsOf: backup, encoding: .utf8) == "export A=1\n")
    #expect(mode(backup) == 0o600)
    try file.uninstall()
    #expect(try String(contentsOf: other, encoding: .utf8) == "export A=1\n")
    #expect(!file.isInstalled())
}

@Test func aSymlinkedZshrcStaysALink() throws {
    let home = try temporaryHome()
    let target = home.appending(path: "dotfiles/zshrc")
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "export A=1\n".write(to: target, atomically: true, encoding: .utf8)
    let link = home.appending(path: ".zshrc")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    try ZshrcFile(url: link).install()
    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)
    #expect(ShellHookBlock.state(of: try String(contentsOf: target, encoding: .utf8)) == .present)
}

/// A commented or indented copy of the markers is the user's own text: only
/// the exact-line block Ledge added comes out (2026-10-23).
@Test func aCopyOfTheMarkersInTheUsersLinesIsNeverTakenOut() {
    let original = "if true; then\n  \(ShellHookBlock.begin)\nfi\n# \(ShellHookBlock.begin)\n# \(ShellHookBlock.end)\n"
    #expect(ShellHookBlock.state(of: original) == .absent)
    let installed = ShellHookBlock.installing(into: original)
    #expect(ShellHookBlock.state(of: installed) == .present)
    #expect(ShellHookBlock.removing(from: installed) == original)
    #expect(ShellHookBlock.removing(from: "a\n\n" + ShellHookBlock.text + "b\n") == "a\nb\n")
}

/// `nounset` and `warn_create_global` in the user's shell, and the helper
/// gone after the shell started: the block says nothing. The helper still
/// gets its arguments, with stdin closed so it never waits on the terminal.
@Test func theBlockIsQuietUnderStrictOptions() throws {
    let home = try temporaryHome()
    let folder = home.appending(path: "Library/Application Support/Ledge")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let helper = folder.appending(path: "ledge-agent-hook")
    try "#!/bin/sh\nread -r x\nprintf '%s\\n' \"$@\" \"stdin:$x\" > \"$HOME/args\"\n"
        .write(to: helper, atomically: true, encoding: .utf8)
    chmod(helper.path, 0o755)
    try ShellHookBlock.text.write(to: home.appending(path: "block.zsh"), atomically: true, encoding: .utf8)
    let errors = try runZsh("""
        setopt nounset warn_create_global
        source "$HOME/block.zsh"
        __ledge_cmd_precmd
        __ledge_cmd_preexec 'make test'
        __ledge_cmd_start=$(( EPOCHREALTIME - 20 ))
        false
        __ledge_cmd_precmd
        sleep 0.5
        rm "$HOME/Library/Application Support/Ledge/ledge-agent-hook"
        __ledge_cmd_preexec 'make test'
        __ledge_cmd_start=$(( EPOCHREALTIME - 20 ))
        __ledge_cmd_precmd
        """, home: home)
    #expect(errors == "")
    let args = home.appending(path: "args")
    for _ in 0..<30 where !FileManager.default.fileExists(atPath: args.path) { usleep(100_000) }
    let lines = (try? String(contentsOf: args, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
    #expect(lines.count == 5)
    #expect(lines.first == "command" && lines.dropFirst().first == "1")
    #expect(lines.dropFirst(2).first?.hasPrefix("20.") == true)
    #expect(Array(lines.suffix(2)) == ["make test", "stdin:"])
}

/// An interactive zsh without the user's files. Its stdin is a pipe left
/// open, as a terminal would be; stderr goes to a file, so a helper that
/// keeps it open can't hang the test.
private func runZsh(_ script: String, home: URL) throws -> String {
    let errors = home.appending(path: "stderr")
    FileManager.default.createFile(atPath: errors.path, contents: nil)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-f", "-i", "-c", script]
    process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
    process.currentDirectoryURL = home
    let input = Pipe()
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    process.standardError = try FileHandle(forWritingTo: errors)
    try process.run()
    process.waitUntilExit()
    withExtendedLifetime(input) {}
    return try String(contentsOf: errors, encoding: .utf8)
}

private func temporaryHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "ledge-zshrc-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func mode(_ url: URL) -> Int? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
}
