import Testing
import Foundation
@testable import MediaService

private func line(_ json: String) -> MediaStreamLine {
    MediaStreamLine.parse(json)!
}

@Test func aFullPayloadBecomesTheBaseline() {
    var m = MediaStateMerger()
    let state = m.apply(line(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.Music","playing":true,"title":"First","artist":"A"}}"#))
    #expect(state?.title == "First")
    #expect(state?.artist == "A")
}

@Test func aDiffUpdatesOnlyTheKeysItCarries() {
    var m = MediaStateMerger()
    _ = m.apply(line(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"b","playing":true,"title":"First","artist":"A","elapsedTime":12.0}}"#))
    let state = m.apply(line(#"{"type":"data","diff":true,"payload":{"elapsedTime":45.0}}"#))
    #expect(state?.elapsedTime == 45.0)
    #expect(state?.title == "First", "untouched keys must survive")
    #expect(state?.artist == "A")
}

// Review Focus 4: the whole point.
@Test func aNullInADiffRemovesTheKeyRatherThanKeepingTheOldValue() {
    var m = MediaStateMerger()
    _ = m.apply(line(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"b","playing":true,"title":"First","artist":"A"}}"#))
    let state = m.apply(line(#"{"type":"data","diff":true,"payload":{"artist":null}}"#))
    #expect(state?.artist == nil, "a stale artist that never clears is the bug this prevents")
    #expect(state?.title == "First")
}

@Test func aNullLineClearsEverything() {
    var m = MediaStateMerger()
    _ = m.apply(line(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"b","playing":true,"title":"First"}}"#))
    let state = m.apply(line("null"))
    #expect(state?.hasMedia == false)
    #expect(state?.title == nil)
}

@Test func anEmptyFullPayloadMeansNoMediaPlayerAtAll() {
    var m = MediaStateMerger()
    _ = m.apply(line(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"b","playing":true,"title":"First"}}"#))
    let state = m.apply(line(#"{"type":"data","diff":false,"payload":{}}"#))
    #expect(state?.hasMedia == false)
}

@Test func aDiffArrivingBeforeAnyBaselineIsStillUsable() {
    var m = MediaStateMerger()
    let state = m.apply(line(#"{"type":"data","diff":true,"payload":{"title":"Orphan"}}"#))
    #expect(state?.title == "Orphan", "never drop data waiting for a baseline that may not come")
}

@Test func aTrackChangeReplacesTheFieldsItCarries() {
    var m = MediaStateMerger()
    _ = m.apply(line(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"b","playing":true,"title":"First","artist":"A","elapsedTime":180.0}}"#))
    let state = m.apply(line(#"{"type":"data","diff":true,"payload":{"title":"Second","artist":"B","elapsedTime":0.0}}"#))
    #expect(state?.title == "Second")
    #expect(state?.artist == "B")
    #expect(state?.elapsedTime == 0.0)
}

@Test func artworkIsRetainedAcrossDiffsThatOmitIt() {
    var m = MediaStateMerger()
    let art = Data("art".utf8).base64EncodedString()
    _ = m.apply(line(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"b","playing":true,"title":"First","artworkData":"\#(art)"}}"#))
    let state = m.apply(line(#"{"type":"data","diff":true,"payload":{"elapsedTime":5.0}}"#))
    #expect(state?.artworkData == Data("art".utf8), "omitted is not the same as null")
}

@Test func resetDropsTheAccumulatedState() {
    var m = MediaStateMerger()
    _ = m.apply(line(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"b","playing":true,"title":"First"}}"#))
    m.reset()
    let state = m.apply(line(#"{"type":"data","diff":true,"payload":{"elapsedTime":1.0}}"#))
    #expect(state?.title == nil, "after a restart nothing from the old process may leak through")
}

@Test func theHandAuthoredEdgeCaseFixtureReplaysWithoutLosingState() throws {
    // Same subdirectory note as MediaPayloadTests' fixture lookup: `.copy("Fixtures")`
    // keeps "Fixtures" as a real subdirectory inside the resource bundle.
    let url = try #require(Bundle.module.url(
        forResource: "edge-cases", withExtension: "ndjson", subdirectory: "Fixtures"
    ))
    let text = try String(contentsOf: url, encoding: .utf8)
    var m = MediaStateMerger()
    var lastGoodTitle: String?
    for raw in text.split(separator: "\n") {
        guard let parsed = MediaStreamLine.parse(String(raw)) else { continue }
        if let state = m.apply(parsed), let title = state.title { lastGoodTitle = title }
    }
    // The fixture ends with an empty full payload and garbage, so the last real
    // title seen must have been "Second".
    #expect(lastGoodTitle == "Second")
}

/// An enveloped `null` payload is "nothing playing", not a payload made of
/// the envelope's own keys (review, 2026-09-29).
@Test func anEnvelopedNullPayloadClearsStateLikeABareNull() throws {
    let line = try #require(MediaStreamLine.parse(#"{"type":"data","diff":true,"payload":null}"#))
    #expect(line.payload == nil)
    var merger = MediaStateMerger()
    _ = merger.apply(MediaStreamLine(isDiff: false, payload: ["bundleIdentifier": "com.apple.Music", "playing": true, "title": "Song"]))
    let cleared = merger.apply(line)
    #expect(cleared?.hasMedia == false)
    #expect(cleared?.title == nil)
}
