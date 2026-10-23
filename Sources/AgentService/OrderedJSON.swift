import Foundation

/// JSON that keeps its keys' order and its numbers' text, written the way
/// Claude Code writes settings.json (`JSON.stringify(value, null, 2)`).
public indirect enum OrderedJSON: Sendable, Equatable {
    case object([(key: String, value: OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    /// The literal as written.
    case number(String)
    case bool(Bool)
    case null

    public struct ParseError: Error, Equatable, CustomStringConvertible {
        public let description: String
    }

    public static func == (lhs: OrderedJSON, rhs: OrderedJSON) -> Bool {
        switch (lhs, rhs) {
        case let (.object(a), .object(b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        case let (.array(a), .array(b)): return a == b
        case let (.string(a), .string(b)): return a == b
        case let (.number(a), .number(b)): return a == b
        case let (.bool(a), .bool(b)): return a == b
        case (.null, .null): return true
        default: return false
        }
    }

    /// The value for `key` in an object (the last one, if a key repeats).
    public subscript(key: String) -> OrderedJSON? {
        guard case .object(let members) = self else { return nil }
        return members.last { $0.key == key }?.value
    }

    // MARK: Parsing

    public static func parse(_ data: Data) throws -> OrderedJSON {
        var parser = Parser(bytes: [UInt8](data))
        parser.skipSpace()
        let value = try parser.value()
        parser.skipSpace()
        guard parser.i == parser.bytes.count else { throw parser.fail("unexpected text after the value") }
        return value
    }

    private struct Parser {
        static let maxDepth = 512
        let bytes: [UInt8]
        var i = 0
        var depth = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        func fail(_ why: String) -> ParseError { ParseError(description: "\(why) at byte \(i)") }

        mutating func skipSpace() {
            while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
        }

        mutating func value() throws -> OrderedJSON {
            guard i < bytes.count else { throw fail("unexpected end") }
            switch bytes[i] {
            case UInt8(ascii: "{"): return try object()
            case UInt8(ascii: "["): return try array()
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default: return try number()
            }
        }

        mutating func literal(_ word: String) throws {
            let w = Array(word.utf8)
            guard i + w.count <= bytes.count, Array(bytes[i..<i + w.count]) == w else { throw fail("bad literal") }
            i += w.count
        }

        mutating func object() throws -> OrderedJSON {
            depth += 1
            defer { depth -= 1 }
            guard depth <= Parser.maxDepth else { throw fail("nested too deeply") }
            i += 1
            var members: [(key: String, value: OrderedJSON)] = []
            skipSpace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object(members) }
            while true {
                skipSpace()
                guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { throw fail("expected a key") }
                let key = try string()
                skipSpace()
                guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { throw fail("expected a colon") }
                i += 1
                skipSpace()
                members.append((key: key, value: try value()))
                skipSpace()
                guard i < bytes.count else { throw fail("unexpected end") }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "}") { i += 1; return .object(members) }
                throw fail("expected a comma or a closing brace")
            }
        }

        mutating func array() throws -> OrderedJSON {
            depth += 1
            defer { depth -= 1 }
            guard depth <= Parser.maxDepth else { throw fail("nested too deeply") }
            i += 1
            var items: [OrderedJSON] = []
            skipSpace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
            while true {
                skipSpace()
                items.append(try value())
                skipSpace()
                guard i < bytes.count else { throw fail("unexpected end") }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
                throw fail("expected a comma or a closing bracket")
            }
        }

        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= bytes.count else { throw fail("short unicode escape") }
            var v: UInt32 = 0
            for _ in 0..<4 {
                let c = bytes[i]
                let d: UInt32
                switch c {
                case 0x30...0x39: d = UInt32(c - 0x30)
                case 0x41...0x46: d = UInt32(c - 0x41 + 10)
                case 0x61...0x66: d = UInt32(c - 0x61 + 10)
                default: throw fail("bad unicode escape")
                }
                v = v * 16 + d
                i += 1
            }
            return v
        }

        mutating func string() throws -> String {
            i += 1
            var out: [UInt8] = []
            while true {
                guard i < bytes.count else { throw fail("unterminated string") }
                let c = bytes[i]
                i += 1
                switch c {
                case UInt8(ascii: "\""):
                    guard let s = String(validatingUTF8: out.map { CChar(bitPattern: $0) } + [0]) , !out.contains(0) else {
                        throw fail("bad text in a string")
                    }
                    return s
                case UInt8(ascii: "\\"):
                    guard i < bytes.count else { throw fail("unterminated string") }
                    let e = bytes[i]
                    i += 1
                    switch e {
                    case UInt8(ascii: "\""): out.append(0x22)
                    case UInt8(ascii: "\\"): out.append(0x5C)
                    case UInt8(ascii: "/"): out.append(0x2F)
                    case UInt8(ascii: "b"): out.append(0x08)
                    case UInt8(ascii: "f"): out.append(0x0C)
                    case UInt8(ascii: "n"): out.append(0x0A)
                    case UInt8(ascii: "r"): out.append(0x0D)
                    case UInt8(ascii: "t"): out.append(0x09)
                    case UInt8(ascii: "u"):
                        var scalar = try hex4()
                        if (0xD800...0xDBFF).contains(scalar) {
                            guard i + 1 < bytes.count, bytes[i] == UInt8(ascii: "\\"), bytes[i + 1] == UInt8(ascii: "u") else {
                                throw fail("lone surrogate")
                            }
                            i += 2
                            let low = try hex4()
                            guard (0xDC00...0xDFFF).contains(low) else { throw fail("lone surrogate") }
                            scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                        } else if (0xDC00...0xDFFF).contains(scalar) {
                            throw fail("lone surrogate")
                        }
                        guard let u = Unicode.Scalar(scalar) else { throw fail("bad unicode escape") }
                        out.append(contentsOf: Array(String(Character(u)).utf8))
                    default: throw fail("bad escape")
                    }
                default:
                    guard c >= 0x20 else { throw fail("raw control character in a string") }
                    out.append(c)
                }
            }
        }

        mutating func digits() -> Int {
            var n = 0
            while i < bytes.count, (0x30...0x39).contains(bytes[i]) { i += 1; n += 1 }
            return n
        }

        mutating func number() throws -> OrderedJSON {
            let start = i
            if i < bytes.count, bytes[i] == UInt8(ascii: "-") { i += 1 }
            guard i < bytes.count, (0x30...0x39).contains(bytes[i]) else { throw fail("unexpected character") }
            if bytes[i] == UInt8(ascii: "0") {
                i += 1
                if i < bytes.count, (0x30...0x39).contains(bytes[i]) { throw fail("leading zero") }
            } else {
                _ = digits()
            }
            if i < bytes.count, bytes[i] == UInt8(ascii: ".") {
                i += 1
                guard digits() > 0 else { throw fail("bad number") }
            }
            if i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
                i += 1
                if i < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") { i += 1 }
                guard digits() > 0 else { throw fail("bad number") }
            }
            return .number(String(decoding: bytes[start..<i], as: UTF8.self))
        }
    }

    // MARK: Writing

    /// Two-space indent, `"key": value`, `[]` and `{}` when empty, a trailing newline.
    public func written() -> Data {
        var out = ""
        write(into: &out, depth: 0)
        out += "\n"
        return Data(out.utf8)
    }

    private func write(into out: inout String, depth: Int) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += n
        case .string(let s): Self.escape(s, into: &out)
        case .array(let items): Self.writeArray(items, into: &out, depth: depth)
        case .object(let members): Self.writeObject(members, into: &out, depth: depth)
        }
    }

    // Kept apart from `write` so each level of nesting uses a small stack frame.
    private static func writeArray(_ items: [OrderedJSON], into out: inout String, depth: Int) {
        if items.isEmpty { out += "[]"; return }
        out += "[\n"
        for (n, item) in items.enumerated() {
            indent(&out, depth + 1)
            item.write(into: &out, depth: depth + 1)
            out += n < items.count - 1 ? ",\n" : "\n"
        }
        indent(&out, depth)
        out += "]"
    }

    private static func writeObject(_ members: [(key: String, value: OrderedJSON)], into out: inout String, depth: Int) {
        if members.isEmpty { out += "{}"; return }
        out += "{\n"
        for (n, member) in members.enumerated() {
            indent(&out, depth + 1)
            escape(member.key, into: &out)
            out += ": "
            member.value.write(into: &out, depth: depth + 1)
            out += n < members.count - 1 ? ",\n" : "\n"
        }
        indent(&out, depth)
        out += "}"
    }

    private static func indent(_ out: inout String, _ depth: Int) {
        for _ in 0..<depth { out += "  " }
    }

    private static func escape(_ s: String, into out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 {
                    let h = String(u.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - h.count) + h
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        out += "\""
    }
}
