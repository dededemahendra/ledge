import Foundation
import Security

/// Where the user's GitHub login came from (2026-10-22).
public enum GitHubTokenSource: String, Sendable, Equatable {
    case gh, keychain
}

public enum GitHubToken {
    /// Where Homebrew puts `gh` on Apple silicon and on Intel.
    public static let ghPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

    /// `gh auth token` prints the token and a newline; anything else
    /// (nothing, a message, several lines) is no token.
    public static func parse(ghOutput: String) -> String? {
        let lines = ghOutput.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count == 1, let token = lines.first, !token.contains(" ") else { return nil }
        return token
    }

    /// Asks `gh` for its token; `nil` when `gh` is not installed or not
    /// logged in.
    public static func fromGH(paths: [String] = ghPaths) async -> String? {
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        return await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: path)
            process.arguments = ["auth", "token", "--hostname", "github.com"]
            let out = Pipe()
            process.standardOutput = out
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? parse(ghOutput: String(decoding: data, as: UTF8.self)) : nil
        }.value
    }
}

/// A token pasted in Settings (2026-10-22), kept in the login keychain.
public struct GitHubKeychain: Sendable {
    public static let account = "github.com"
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func read() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func save(_ token: String) -> Bool {
        delete()
        var query = base
        query[kSecValueData as String] = Data(token.utf8)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    public func delete() {
        SecItemDelete(base as CFDictionary)
    }

    private var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: Self.account]
    }
}
