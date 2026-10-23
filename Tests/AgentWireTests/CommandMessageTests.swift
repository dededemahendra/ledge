import Foundation
import Testing
@testable import AgentWire

@Test func theLabelIsTheProgramAndTwoPlainWords() {
    #expect(CommandTrim.label("make test") == "make test")
    #expect(CommandTrim.label("npm run build -- --watch") == "npm run build")
    #expect(CommandTrim.label("/usr/bin/swift test --parallel") == "swift test")
}

/// Only plain words that follow the program directly survive, so a header,
/// token, path or URL never leaves the shell (2026-10-23).
@Test func secretsNeverReachTheLabel() {
    #expect(CommandTrim.label("curl -H \"Authorization: Bearer abc123\" https://x") == "curl")
    #expect(CommandTrim.label("TOKEN=abc make") == nil, "an assignment first is no program")
    #expect(CommandTrim.label("gh auth login --with-token ghp_0123456789abcdefghijklmnopqrstuv") == "gh auth login")
    #expect(CommandTrim.label("echo ghp_0123456789abcdefghijklmn") == "echo")
}

@Test func aLongLabelIsCutAtAWord() {
    #expect(CommandTrim.label("xcodebuild archive-and-export something") == "xcodebuild")
}

@Test func longLivedProgramsAreSkipped() {
    #expect(CommandTrim.isSkipped("vim notes.md"))
    #expect(CommandTrim.isSkipped("ssh host"))
    #expect(CommandTrim.isSkipped("claude"))
    #expect(CommandTrim.isSkipped("tail -f server.log"))
    #expect(!CommandTrim.isSkipped("tail server.log"))
    #expect(!CommandTrim.isSkipped("make"))
    #expect(CommandTrim.label("vim notes.md") == nil)
}

@Test func theHelperBuildsTheMessage() {
    let message = CommandHook.message(arguments: ["ledge-agent-hook", "command", "1", "83.4", "npm run build"],
                                      cwd: "/tmp", pids: [10, 9], stamp: 5)
    #expect(message?.label == "npm run build")
    #expect(message?.status == 1)
    #expect(message?.seconds == 83.4)
    #expect(message?.pids == [10, 9])
    #expect(CommandHook.message(arguments: ["ledge-agent-hook", "command", "0", "soon", "make"], cwd: nil, pids: [], stamp: 0) == nil)
    #expect(CommandHook.message(arguments: ["ledge-agent-hook", "command", "0", "20", "vim x"], cwd: nil, pids: [], stamp: 0) == nil)
}

@Test func theMessageRoundTripsAsJSON() throws {
    let message = CommandMessage(label: "make test", status: 0, seconds: 12.5, cwd: "/tmp", pids: [1, 2], stamp: 3)
    let decoded = try JSONDecoder().decode(CommandMessage.self, from: JSONEncoder().encode(message))
    #expect(decoded == message)
    #expect(decoded.event == "command" && decoded.v == 1)
}

/// A password is often a plain word: after a program that prints its
/// arguments, or mixing letters and digits, it stops the label (2026-10-23).
@Test func aPasswordShapedWordNeverReachesTheLabel() {
    #expect(CommandTrim.label("echo hunter2 | sudo -S softwareupdate -ia") == "echo")
    #expect(CommandTrim.label("printf s3cretPass99 | docker login --password-stdin") == "printf")
    #expect(CommandTrim.label("print correcthorse") == "print")
    #expect(CommandTrim.label("bw unlock MyVaultPass1") == "bw unlock")
    #expect(CommandTrim.label("sleep 12") == "sleep 12", "digits alone are a count")
    #expect(CommandTrim.label("make test") == "make test")
}

/// A line typed after a space is kept out of history by choice: it stays
/// off the island too.
@Test func aLineLedByASpaceIsSkipped() {
    #expect(CommandTrim.isSkipped(" make deploy"))
    #expect(CommandTrim.label(" make deploy") == nil)
    #expect(!CommandTrim.isSkipped("make deploy"))
}
