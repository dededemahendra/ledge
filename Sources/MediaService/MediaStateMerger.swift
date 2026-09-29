import Foundation

/// One line of the adapter's `stream` output.
public struct MediaStreamLine: Sendable {
    public let isDiff: Bool
    /// `nil` means the line was literal `null`: no media at all.
    /// A present dictionary may hold `NSNull` values, meaning "this key vanished".
    ///
    /// `nonisolated(unsafe)`: `[String: Any]` is not statically `Sendable`, but
    /// every value in it was just produced by `JSONSerialization` from this
    /// struct's own `parse(_:)` and is one of `NSString`/`NSNumber`/`NSNull` —
    /// immutable, never mutated after parsing, and never shared with anything
    /// that would mutate it. Safe to hand across actors on that basis.
    public nonisolated(unsafe) let payload: [String: Any]?

    public init(isDiff: Bool, payload: [String: Any]?) {
        self.isDiff = isDiff
        self.payload = payload
    }

    /// Returns `nil` for blank or unparseable lines — they are skipped, never
    /// fatal. The adapter is a separate process; a garbled or partial line
    /// (e.g. a torn write) must never bring the stream down.
    public static func parse(_ line: String) -> MediaStreamLine? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "null" { return MediaStreamLine(isDiff: false, payload: nil) }

        guard
            let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any]
        else { return nil }

        // An envelope whose payload is `null` means nothing is playing —
        // same as a bare `null` line (review, 2026-09-29: it used to be
        // read as a full payload made of the envelope's own keys).
        if root["payload"] is NSNull {
            return MediaStreamLine(isDiff: false, payload: nil)
        }
        // A bare `get` payload has no envelope.
        guard let payload = root["payload"] as? [String: Any] else {
            return MediaStreamLine(isDiff: false, payload: root)
        }
        return MediaStreamLine(isDiff: root["diff"] as? Bool ?? false, payload: payload)
    }
}

extension MediaStreamLine: Equatable {
    public static func == (lhs: MediaStreamLine, rhs: MediaStreamLine) -> Bool {
        lhs.isDiff == rhs.isDiff
            && NSDictionary(dictionary: lhs.payload ?? [:])
                .isEqual(to: rhs.payload ?? [:])
    }
}

/// Accumulates the adapter's diff stream into a complete picture.
///
/// The adapter diffs by default. A key present with a `null` value means the key
/// *vanished* and must be removed; a key simply absent from a diff is unchanged.
/// Conflating those two is what produces titles that never clear.
public struct MediaStateMerger: Sendable {
    // Same reasoning as `MediaStreamLine.payload` above: JSON-derived scalars
    // only, never mutated after being merged in.
    private nonisolated(unsafe) var raw: [String: Any] = [:]

    public init() {}

    /// Drops all accumulated state, so a freshly (re)started adapter process
    /// never gets its first diff merged against a previous process's leftovers.
    public mutating func reset() {
        raw = [:]
    }

    public mutating func apply(_ line: MediaStreamLine) -> MediaPayload? {
        guard let payload = line.payload else {
            raw = [:]                       // literal null: nothing is playing
            return MediaPayload.decode(raw)
        }

        if line.isDiff {
            for (key, value) in payload {
                if value is NSNull {
                    raw.removeValue(forKey: key)     // vanished
                } else {
                    raw[key] = value
                }
            }
        } else {
            raw = payload.filter { !($0.value is NSNull) }
        }

        return MediaPayload.decode(raw)
    }
}
