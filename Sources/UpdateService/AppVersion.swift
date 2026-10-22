import Foundation

/// A release's version, `0.1.2` or `v0.1.2` (2026-10-22): compared number
/// by number, so 0.1.10 is newer than 0.1.9 and 1.0 equals 1.0.0. A tag that
/// is not a version reads as `nil` and is never announced.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        var text = text.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty, pieces.count <= 4 else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.allSatisfy(\.isNumber), let number = Int(piece) else { return nil }
            parts.append(number)
        }
        self.parts = parts
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    private func padded(to count: Int) -> [Int] {
        parts + Array(repeating: 0, count: max(0, count - parts.count))
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool {
        let count = max(a.parts.count, b.parts.count)
        return a.padded(to: count) == b.padded(to: count)
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        let count = max(a.parts.count, b.parts.count)
        return a.padded(to: count).lexicographicallyPrecedes(b.padded(to: count))
    }
}
