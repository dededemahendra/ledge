import Testing
@testable import MediaService

@Test func theSettingsNarrowTheAllowList() {
    let onlyMusic: Set<String> = ["com.apple.music"]
    #expect(MediaSourcePolicy.isAllowed(bundleIdentifier: "com.apple.Music", enabled: onlyMusic))
    #expect(MediaSourcePolicy.isAllowed(bundleIdentifier: "com.apple.iTunes", enabled: onlyMusic), "old Music rides with Music")
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: "com.spotify.client", enabled: onlyMusic))
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: "com.apple.Safari", enabled: ["com.apple.safari"]), "never outside the allow-list")
    #expect(!MediaSourcePolicy.isAllowed(bundleIdentifier: nil, enabled: onlyMusic))
}
