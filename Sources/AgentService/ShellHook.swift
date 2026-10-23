import Foundation

/// Ledge's block in `~/.zshrc` for long commands (2026-10-23): times each
/// command and, at 10 s or more, hands it to the helper's `command` mode in
/// the background. Matched only by its exact marker lines.
public enum ShellHookBlock {
    public static let begin = "# >>> Ledge long commands >>>"
    public static let end = "# <<< Ledge long commands <<<"

    public static var text: String {
        """
        \(begin)
        if [[ -o interactive && -x "$HOME/Library/Application Support/Ledge/ledge-agent-hook" ]]; then
          zmodload zsh/datetime
          autoload -Uz add-zsh-hook
          __ledge_cmd_preexec() { __ledge_cmd_start=$EPOCHREALTIME; __ledge_cmd_line=$1 }
          __ledge_cmd_precmd() {
            local s=$?
            [[ -n $__ledge_cmd_start ]] || return
            local d=$(( EPOCHREALTIME - __ledge_cmd_start ))
            unset __ledge_cmd_start
            (( d >= 10 )) && "$HOME/Library/Application Support/Ledge/ledge-agent-hook" command "$s" "$d" "$__ledge_cmd_line" &!
          }
          add-zsh-hook preexec __ledge_cmd_preexec
          add-zsh-hook precmd __ledge_cmd_precmd
        fi
        \(end)

        """
    }

    public enum State: Equatable { case absent, present, broken }

    public static func state(of text: String) -> State {
        let lines = text.components(separatedBy: "\n")
        let begins = lines.indices.filter { lines[$0] == begin }
        let ends = lines.indices.filter { lines[$0] == end }
        if begins.isEmpty, ends.isEmpty { return .absent }
        if begins.count == 1, ends.count == 1, begins[0] < ends[0] { return .present }
        return .broken
    }

    /// Appends the block after a blank line; unchanged if it is there.
    public static func installing(into text: String) -> String {
        guard state(of: text) == .absent else { return text }
        guard !text.isEmpty else { return Self.text }
        let base = text.hasSuffix("\n") ? text : text + "\n"
        return base + "\n" + Self.text
    }

    /// Takes out the block and the blank line installing put before it.
    public static func removing(from text: String) -> String {
        guard state(of: text) == .present,
              let beginRange = text.range(of: begin + "\n"),
              let endRange = text.range(of: end + "\n", range: beginRange.upperBound..<text.endIndex)
                ?? text.range(of: end, range: beginRange.upperBound..<text.endIndex) else { return text }
        var head = String(text[..<beginRange.lowerBound])
        if head.hasSuffix("\n\n") { head.removeLast() }
        return head + String(text[endRange.upperBound...])
    }
}

/// `~/.zshrc`, edited with care (2026-10-23), the way `AgentHooksFile` edits
/// Claude Code's settings: the symlink's target gets the change; the last
/// version before Ledge's first change is kept beside it with its mode; the
/// write is atomic and the mode kept; a broken block is left alone.
public struct ZshrcFile {
    public enum Problem: Error, Equatable {
        case unreadable(String)
        case broken
        case unwritable(String)
    }

    public let url: URL

    public init(url: URL) { self.url = url }

    private var target: URL { url.resolvingSymlinksInPath() }
    private var backupURL: URL { target.appendingPathExtension("ledge-backup") }

    public func install() throws(Problem) {
        let (text, original) = try read()
        guard ShellHookBlock.state(of: text) != .broken else { throw .broken }
        let changed = ShellHookBlock.installing(into: text)
        guard changed != text else { return }
        try write(changed, original: original)
    }

    public func uninstall() throws(Problem) {
        let (text, original) = try read()
        switch ShellHookBlock.state(of: text) {
        case .absent: return
        case .broken: throw .broken
        case .present: try write(ShellHookBlock.removing(from: text), original: original)
        }
    }

    public func isInstalled() -> Bool {
        guard let (text, _) = try? read() else { return false }
        return ShellHookBlock.state(of: text) == .present
    }

    private func read() throws(Problem) -> (String, Data?) {
        guard FileManager.default.fileExists(atPath: target.path) else { return ("", nil) }
        do {
            let data = try Data(contentsOf: target)
            guard let text = String(data: data, encoding: .utf8) else { throw Problem.unreadable("not UTF-8") }
            return (text, data)
        } catch let problem as Problem {
            throw problem
        } catch {
            throw .unreadable(error.localizedDescription)
        }
    }

    private func write(_ text: String, original: Data?) throws(Problem) {
        let fm = FileManager.default
        let mode = (try? fm.attributesOfItem(atPath: target.path))?[.posixPermissions] as? Int
        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let original, !fm.fileExists(atPath: backupURL.path) {
                try writeBackup(original, mode: mode_t(mode ?? 0o644))
            }
            try Data(text.utf8).write(to: target, options: .atomic)
            // An atomic write is a new file with default permissions.
            if let mode { chmod(target.path, mode_t(mode)) }
        } catch {
            throw .unwritable(error.localizedDescription)
        }
    }

    /// Created with the original's permissions, so a private file's copy is
    /// never readable by others, even briefly.
    private func writeBackup(_ data: Data, mode: mode_t) throws {
        let path = backupURL.path
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, mode)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var failure: Int32 = fchmod(fd, mode) == 0 ? 0 : errno
        if failure == 0 {
            failure = data.withUnsafeBytes { raw -> Int32 in
                var offset = 0
                while offset < raw.count {
                    let n = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                    if n > 0 { offset += n } else if n == 0 { return EIO } else if errno != EINTR { return errno }
                }
                return 0
            }
        }
        close(fd)
        guard failure == 0 else {
            unlink(path)
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
    }
}
