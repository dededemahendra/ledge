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

private func temporaryHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "ledge-zshrc-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func mode(_ url: URL) -> Int? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
}
