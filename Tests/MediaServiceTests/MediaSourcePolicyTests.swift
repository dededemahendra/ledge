import Testing
@testable import MediaService

@Test func musicPlayersAndBrowsersAreAllowedAndEverythingElseIsNot() {
    #expect(MediaSourcePolicy.isAllowed(bundleIdentifier: "com.apple.Music"))
    #expect(MediaSourcePolicy.isAllowed(bundleIdentifier: "com.spotify.client"))
    #expect(MediaSourcePolicy.isAllowed(bundleIdentifier: "COM.SPOTIFY.CLIENT"), "case-insensitive")
    #expect(MediaSourcePolicy.isAllowed(bundleIdentifier: "com.tidal.desktop"))
    #expect(MediaSourcePolicy.isAllowed(bundleIdentifier: "com.apple.Safari"), "browsers, behind BrowserVideoGate")
    #expect(MediaSourcePolicy.isAllowed(bundleIdentifier: "company.thebrowser.Browser"), "Arc")
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: "net.imput.helium"), "a browser not on the list")
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: "com.apple.QuickTimePlayerX"))
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: "us.zoom.xos"))
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: nil), "no source at all is not a source")
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: ""))
}

@Test func browsersAreKnownAsBrowsers() {
    #expect(MediaSourcePolicy.isBrowser(bundleIdentifier: "com.google.Chrome"))
    #expect(MediaSourcePolicy.isBrowser(bundleIdentifier: "COM.APPLE.SAFARI"))
    #expect(!MediaSourcePolicy.isBrowser(bundleIdentifier: "com.apple.music"))
    #expect(!MediaSourcePolicy.isBrowser(bundleIdentifier: nil))
}
