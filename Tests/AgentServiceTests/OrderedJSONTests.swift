import Testing
import Foundation
@testable import AgentService

private func bytes(_ s: String) -> Data { Data(s.utf8) }

@Test func aClaudeWrittenFileRoundTripsByteForByte() throws {
    let text = """
    {
      "model": "opus",
      "hooks": {
        "PreToolUse": [
          {
            "matcher": "Bash",
            "hooks": [
              {
                "type": "command",
                "command": "/Users/x/.claude/hooks/rtk-rewrite.sh"
              }
            ]
          },
          {
            "matcher": "*",
            "hooks": [
              {
                "type": "command",
                "command": "https://example.com/a/b \\"q\\" caf\u{e9}",
                "timeout": 10
              }
            ]
          }
        ],
        "Stop": []
      },
      "statusLine": {
        "type": "command",
        "command": "echo hi"
      },
      "enabledPlugins": {
        "a@b": true,
        "c@d": false
      },
      "empty": {},
      "nothing": null,
      "effortLevel": "high",
      "theme": "dark"
    }

    """
    let parsed = try OrderedJSON.parse(bytes(text))
    #expect(parsed.written() == bytes(text))
}

@Test func keysKeepTheirOrder() throws {
    let v = try OrderedJSON.parse(bytes(#"{"b":1,"a":2}"#))
    guard case .object(let members) = v else { Issue.record("not an object"); return }
    #expect(members.map(\.key) == ["b", "a"])
    #expect(v["a"] == .number("2"))
}

@Test func numbersKeepTheirText() throws {
    let v = try OrderedJSON.parse(bytes("[1.0, 1e3, -0, 12345678901234567890]"))
    #expect(v == .array([.number("1.0"), .number("1e3"), .number("-0"), .number("12345678901234567890")]))
    let out = String(decoding: v.written(), as: UTF8.self)
    #expect(out == "[\n  1.0,\n  1e3,\n  -0,\n  12345678901234567890\n]\n")
}

@Test func stringsAreEscapedAsJavaScriptDoes() throws {
    let v = OrderedJSON.string("q\" b\\ n\n t\t c\u{1} / \u{e9}")
    let out = String(decoding: v.written(), as: UTF8.self)
    #expect(out == "\"q\\\" b\\\\ n\\n t\\t c\\u0001 / \u{e9}\"\n")
    #expect(try OrderedJSON.parse(v.written()) == v)
    #expect(try OrderedJSON.parse(bytes(#""😀""#)) == .string("\u{1F600}"))
}

@Test func badJSONThrows() {
    for bad in ["{", "{'a':1}", "{} x", "", "[1,]", "01", "\"abc", "\"\\u12", "\"\\x\"", "\"a\nb\"", "\"\\ud800x\""] {
        #expect(throws: (any Error).self) { try OrderedJSON.parse(bytes(bad)) }
    }
}

@Test func deepNestingThrowsInsteadOfCrashing() throws {
    #expect(throws: (any Error).self) { try OrderedJSON.parse(bytes(String(repeating: "[", count: 100_000))) }
    let ok = String(repeating: "[", count: 512) + String(repeating: "]", count: 512)
    #expect(try OrderedJSON.parse(bytes(ok)).written().count > 0)
    let tooDeep = String(repeating: "[", count: 513) + String(repeating: "]", count: 513)
    #expect(throws: (any Error).self) { try OrderedJSON.parse(bytes(tooDeep)) }
}
