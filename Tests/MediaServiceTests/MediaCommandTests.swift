import Testing
@testable import MediaService

// IDs come verbatim from the adapter README's command table.
@Test func commandIdsMatchTheAdapterTable() {
    #expect(MediaCommand.play.adapterArguments == ["send", "0"])
    #expect(MediaCommand.pause.adapterArguments == ["send", "1"])
    #expect(MediaCommand.togglePlayPause.adapterArguments == ["send", "2"])
    #expect(MediaCommand.nextTrack.adapterArguments == ["send", "4"])
    #expect(MediaCommand.previousTrack.adapterArguments == ["send", "5"])
    #expect(MediaCommand.toggleShuffle.adapterArguments == ["send", "6"])
    #expect(MediaCommand.toggleRepeat.adapterArguments == ["send", "7"])
}

@Test func seekConvertsSecondsToMicroseconds() {
    // The README: "The unit is microseconds", positive integer.
    #expect(MediaCommand.seek(seconds: 1).adapterArguments == ["seek", "1000000"])
    #expect(MediaCommand.seek(seconds: 12.5).adapterArguments == ["seek", "12500000"])
    #expect(MediaCommand.seek(seconds: 0).adapterArguments == ["seek", "0"])
}

@Test func seekClampsNegativesToZero() {
    #expect(MediaCommand.seek(seconds: -5).adapterArguments == ["seek", "0"],
            "a negative position is not a valid positive integer")
}

@Test func seekRoundsRatherThanTruncatingOddly() {
    #expect(MediaCommand.seek(seconds: 0.0000004).adapterArguments == ["seek", "0"])
    #expect(MediaCommand.seek(seconds: 0.0000006).adapterArguments == ["seek", "1"])
}
