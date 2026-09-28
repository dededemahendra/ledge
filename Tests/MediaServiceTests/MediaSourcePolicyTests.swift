import Testing
@testable import MediaService

@Test func musicPlayersAreAllowedAndEverythingElseIsNot() {
    #expect(MediaSourcePolicy.isAllowed(bundleIdentifier: "com.apple.Music"))
    #expect(MediaSourcePolicy.isAllowed(bundleIdentifier: "com.spotify.client"))
    #expect(MediaSourcePolicy.isAllowed(bundleIdentifier: "COM.SPOTIFY.CLIENT"), "case-insensitive")
    #expect(MediaSourcePolicy.isAllowed(bundleIdentifier: "com.tidal.desktop"))
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: "net.imput.helium"), "a browser")
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: "com.apple.Safari"))
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: "company.thebrowser.Browser"), "Arc")
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: "com.apple.QuickTimePlayerX"))
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: "us.zoom.xos"))
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: nil), "no source at all is not a source")
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: ""))
}
