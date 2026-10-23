import Foundation

/// A terminal command that ran a while has finished (2026-10-23): one line
/// from the helper's `command` mode to Ledge's `commands.sock`. Carries a
/// trimmed label, never the command line itself.
public struct CommandMessage: Codable, Sendable, Equatable {
    public var v: Int
    public var event: String
    public var label: String
    public var status: Int32
    public var seconds: Double
    public var cwd: String?
    /// The helper's parents, nearest first: the shell, then its terminal.
    public var pids: [Int32]
    /// The helper process's start, in microseconds since 1970.
    public var stamp: Int64

    public init(label: String, status: Int32, seconds: Double, cwd: String?, pids: [Int32], stamp: Int64) {
        self.v = 1
        self.event = "command"
        self.label = label
        self.status = status
        self.seconds = seconds
        self.cwd = cwd
        self.pids = pids
        self.stamp = stamp
    }
}

/// What of a command line may be shown (2026-10-23): the program's base
/// name and up to two plain words straight after it — only letters, digits,
/// `-` and `_`, not a flag, at most 20 characters, and not letters and
/// digits mixed, the shape of most passwords — at most 24 characters in
/// all, cut at a word. Collection stops at the first word that isn't plain,
/// so a header, token, path, URL or assignment never leaves the shell. A
/// program that prints its arguments keeps none of them.
public enum CommandTrim {
    static let maxWord = 20
    static let maxLabel = 24
    /// Long-lived or interactive programs: their end is no news.
    static let skipped: Set<String> = [
        "vi", "vim", "nvim", "nano", "emacs", "hx", "less", "more", "man", "ssh", "mosh", "top", "htop", "btop",
        "watch", "tmux", "screen", "zsh", "bash", "fish", "claude", "codex",
    ]
    /// Their arguments are what they print, often into a pipe: a password.
    static let printers: Set<String> = ["echo", "printf", "print", "yes"]

    public static func label(_ line: String) -> String? {
        guard !isSkipped(line), let program = program(of: line) else { return nil }
        guard !printers.contains(program) else { return String(program.prefix(maxLabel)) }
        let words = line.split(whereSeparator: \.isWhitespace).dropFirst()
        var label = program
        var taken = 0
        for word in words {
            guard taken < 2, isPlain(word) else { break }
            guard label.count + 1 + word.count <= maxLabel else { break }
            label += " " + word
            taken += 1
        }
        return String(label.prefix(maxLabel))
    }

    /// Also a line typed after a space, which zsh users do to keep it out
    /// of history.
    public static func isSkipped(_ line: String) -> Bool {
        if line.first == " " { return true }
        guard let program = program(of: line) else { return false }
        if skipped.contains(program) { return true }
        if program == "tail" {
            return line.split(whereSeparator: \.isWhitespace).dropFirst().contains { $0 == "-f" || $0 == "-F" }
        }
        return false
    }

    /// The first word's base name, unless it is an assignment (`KEY=value`).
    private static func program(of line: String) -> String? {
        guard let first = line.split(whereSeparator: \.isWhitespace).first else { return nil }
        if let equals = first.firstIndex(of: "="), first[..<equals].contains("/") == false { return nil }
        let name = (String(first) as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }

    private static func isPlain(_ word: Substring) -> Bool {
        guard !word.isEmpty, word.count <= maxWord, word.first != "-" else { return false }
        guard word.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return false }
        return !(word.contains(where: \.isLetter) && word.contains(where: \.isNumber))
    }
}

/// The helper's `command` mode (2026-10-23): `ledge-agent-hook command
/// <status> <seconds> <line>` to the message it sends; nil for bad numbers
/// or a line with nothing to show.
public enum CommandHook {
    public static func message(arguments: [String], cwd: String?, pids: [Int32], stamp: Int64) -> CommandMessage? {
        guard arguments.count >= 5, arguments[1] == "command",
              let status = Int32(arguments[2]), let seconds = Double(arguments[3]), seconds.isFinite,
              let label = CommandTrim.label(arguments[4]) else { return nil }
        return CommandMessage(label: label, status: status, seconds: seconds, cwd: cwd, pids: pids, stamp: stamp)
    }
}
