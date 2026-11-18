import Testing
@testable import MediaService

@Test func theSettingsNarrowTheAllowList() {
    let onlyMusic: Set<String> = ["com.apple.music"]
    #expect(MediaSourcePolicy.isAllowed(bundleIdentifier: "com.apple.Music", enabled: onlyMusic))
    #expect(MediaSourcePolicy.isAllowed(bundleIdentifier: "com.apple.iTunes", enabled: onlyMusic), "old Music rides with Music")
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: "com.spotify.client", enabled: onlyMusic))
    #expect(MediaSourcePolicy.isAllowed(bundleIdentifier: "com.apple.Safari", enabled: ["com.apple.safari"]), "a browser switched on")
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: "com.apple.Safari", enabled: onlyMusic), "a browser switched off")
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: "net.imput.helium", enabled: ["net.imput.helium"]), "never outside the allow-list")
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: nil, enabled: onlyMusic))
}
