import Testing
import Foundation
@testable import MediaService

@Test func decodesTheMandatoryKeys() {
    let p = MediaPayload.decode([
        "bundleIdentifier": "com.apple.Music",
        "playing": true,
        "title": "Song",
        "artist": "Artist",
        "album": "Album",
        "duration": 210.0,
        "elapsedTime": 12.5,
        "playbackRate": 1.0,
    ])
    #expect(p.bundleIdentifier == "com.apple.Music")
    #expect(p.playing == true)
    #expect(p.title == "Song")
    #expect(p.artist == "Artist")
    #expect(p.duration == 210.0)
    #expect(p.elapsedTime == 12.5)
    #expect(p.playbackRate == 1.0)
}

@Test func integerNumbersDecodeAsDoubles() {
    // JSON may deliver these as Int rather than Double.
    let p = MediaPayload.decode(["duration": 210, "elapsedTime": 12])
    #expect(p.duration == 210.0)
    #expect(p.elapsedTime == 12.0)
}

@Test func wrongTypesAreIgnoredRatherThanCrashing() {
    let p = MediaPayload.decode(["duration": "nonsense", "playing": "yes", "title": 42])
    #expect(p.duration == nil)
    #expect(p.playing == nil)
    #expect(p.title == nil)
}

@Test func base64ArtworkDecodes() {
    let raw = Data("hello".utf8)
    let p = MediaPayload.decode([
        "artworkData": raw.base64EncodedString(),
        "artworkMimeType": "image/jpeg",
    ])
    #expect(p.artworkData == raw)
    #expect(p.artworkMimeType == "image/jpeg")
}

@Test func malformedArtworkIsDroppedNotFatal() {
    let p = MediaPayload.decode(["artworkData": "!!!not base64!!!"])
    #expect(p.artworkData == nil)
}

@Test func timestampParsesISO8601() {
    let p = MediaPayload.decode(["timestamp": "2026-09-25T04:00:00Z"])
    #expect(p.timestamp == Date(timeIntervalSince1970: 1_790_308_800))
}

@Test func emptyPayloadMeansNoMediaNotAnError() {
    let p = MediaPayload.decode([:])
    #expect(p.title == nil)
    #expect(p.hasMedia == false)
}

@Test func hasMediaRequiresTheMandatoryTrio() {
    #expect(MediaPayload.decode([
        "bundleIdentifier": "x", "playing": true, "title": "t",
    ]).hasMedia)
    #expect(MediaPayload.decode(["playing": true, "title": "t"]).hasMedia == false)
    #expect(MediaPayload.decode(["bundleIdentifier": "x", "title": "t"]).hasMedia == false)
    #expect(MediaPayload.decode(["bundleIdentifier": "x", "playing": true]).hasMedia == false)
}

// --- line parsing ---

@Test func parsesAStreamLine() throws {
    let line = #"{"type":"data","diff":true,"payload":{"elapsedTime":45.0}}"#
    let parsed = try #require(MediaStreamLine.parse(line))
    #expect(parsed.isDiff)
    #expect(parsed.payload?["elapsedTime"] as? Double == 45.0)
}

@Test func nullLineMeansNoMedia() throws {
    let parsed = try #require(MediaStreamLine.parse("null"))
    #expect(parsed.payload == nil)
    #expect(parsed.isDiff == false)
}

@Test func blankAndGarbageLinesAreSkipped() {
    #expect(MediaStreamLine.parse("") == nil)
    #expect(MediaStreamLine.parse("   ") == nil)
    #expect(MediaStreamLine.parse("not json at all") == nil)
    #expect(MediaStreamLine.parse("{unterminated") == nil)
}

@Test func everyLineOfTheCapturedFixtureParsesOrIsSkipped() throws {
    // `.copy("Fixtures")` in Package.swift preserves "Fixtures" as a
    // subdirectory inside the resource bundle rather than flattening it, so
    // the lookup must name that subdirectory explicitly.
    let url = try #require(Bundle.module.url(
        forResource: "stream-diff", withExtension: "ndjson", subdirectory: "Fixtures"
    ))
    let text = try String(contentsOf: url, encoding: .utf8)
    var parsedCount = 0
    for line in text.split(separator: "\n") {
        if MediaStreamLine.parse(String(line)) != nil { parsedCount += 1 }
    }
    #expect(parsedCount > 0, "the real capture must yield at least one usable line")
}
