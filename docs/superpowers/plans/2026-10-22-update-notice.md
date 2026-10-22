# Update Notice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ledge checks GitHub for a newer release a minute after launch and daily, announces each new version once with an island blip, and shows the state in Settings › About.

**Architecture:** A new `UpdateService` library holds the pure parts (`AppVersion`, `ReleaseInfo`, `UpdateDecision`, `UpdateNotice`) and the thin request (`UpdateChecker`, with an injected fetch). The island gains `ActivityKind.update` and a caption for it; SettingsKit gains `PreviewScene.update`; `AppSettings` gains `checksForUpdates`. `AppModel` schedules the checks, remembers the last announced version, holds the blip until unlock, and exposes `updateStatus` for About.

**Tech Stack:** Swift 6.4, Swift 6 language mode, SwiftPM only, swift-testing, macOS 27, Foundation `URLSession`.

**Spec:** `docs/superpowers/specs/2026-10-22-update-notice-design.md`.

## Global Constraints

- The request: `GET https://api.github.com/repos/dededemahendra/ledge/releases/latest`, headers `Accept: application/vnd.github+json` and `User-Agent: Ledge/<version>`, ephemeral session (no cookies or cache), 15 s timeout. Anything but a readable 200 is "could not check".
- One blip per version: announced only when the release is newer than the running app and not equal to `UserDefaults` key `lastAnnouncedUpdate`.
- `ActivityKind.update`: priority 35, TTL 8 s. Blip symbol `arrow.down.circle.fill`, tint positive (green), compact text the version, caption `"Ledge <v> is available · Download"`, click opens the release page.
- Checks: 60 s after launch, then every 24 h, plus About's Check now. `checksForUpdates` (default `true`) off means no request at all.
- Run tests with `make test` / `make test FILTER=<name>`; never bare `swift test`. Only `brightnessTargetsTheBuiltInDisplay` and `bridgeLoadsAndReadsARealBrightnessValue` may fail.
- `@State` cannot be used as a macro: spelled-out `State` as elsewhere.
- Text people read: Australian English, no em or en dashes, no exclamation marks, sentence case.
- Comments: plain sentences, dated `(2026-10-22)`. Commits: one lowercase sentence, blank line, `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; `git add` only the task's files, never `.superpowers`.
- Implementers do not launch, install or stop the app.

## Review Focus

1. A tag that is not a version (`latest`, `nightly`) or a release with no DMG: no crash, no blip (Task 1, `aTagThatIsNotAVersionIsNotARelease`, `aReleaseWithoutADiskImageStillCounts`).
2. GitHub's rate limit (403) or no network: silent, "could not check" (Task 1, `anythingButAReadable200IsCouldNotCheck`).
3. The same version found again on the next day's check: no second blip (Task 1, `aVersionIsAnnouncedOnce`).
4. Found while the Mac is locked: the blip waits for unlock (Task 3; checked live).
5. Switched off: no request at all (Task 3; `checkForUpdates` returns before any request when off; checked live with the probe disabled path).

## File structure

| File | Change |
| --- | --- |
| `Package.swift` | `UpdateService` target and tests; `Ledge` and `SettingsKit` depend on it |
| `Sources/UpdateService/AppVersion.swift`, `ReleaseInfo.swift`, `UpdateDecision.swift`, `UpdateChecker.swift`, `UpdateNotice.swift` | New |
| `Sources/ActivityKit/ActivityKind.swift` | `case update` |
| `Sources/NotchKit/NotchController.swift` | `updateActivityID`, caption for an update leading |
| `Sources/LedgeSettings/AppSettings.swift` | `checksForUpdates` |
| `Sources/SettingsKit/PreviewScene.swift`, `PreviewContent.swift`, `PreviewStage.swift` | `.update` |
| `Sources/Ledge/AppModel.swift` | Scheduling, announcing, status, probe |
| `Sources/Ledge/SettingsPanes.swift`, `SettingsWindow.swift` | General row, About › Updates, sidebar badge |
| `Tests/UpdateServiceTests/UpdateServiceTests.swift` | New |
| `Tests/ActivityKitTests`, `Tests/NotchKitTests/NotchControllerTests.swift`, `Tests/LedgeSettingsTests/AppSettingsTests.swift`, `Tests/SettingsKitTests/PreviewStageTests.swift` | New expectations |
| `README.md`, `docs/superpowers/specs/2026-09-25-notch-companion-design.md` | Docs |

---

### Task 1: The UpdateService library

**Files:** Modify `Package.swift`; create the five `Sources/UpdateService/*.swift` files and `Tests/UpdateServiceTests/UpdateServiceTests.swift`.

**Interfaces — Produces:** `public struct AppVersion: Comparable, Sendable, CustomStringConvertible` (`init?(_ text: String)`, `parts: [Int]`); `public struct ReleaseInfo: Sendable, Equatable` (`version`, `pageURL`, `downloadURL`, `init(version:pageURL:downloadURL:)`, `static func decode(_ data: Data) -> ReleaseInfo?`); `public enum UpdateFinding: Sendable, Equatable { case upToDate; case available(ReleaseInfo, announce: Bool) }`; `public enum UpdateDecision { static func evaluate(current:latest:lastAnnounced:) -> UpdateFinding }`; `public struct UpdateChecker: Sendable` (`typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)`, `static let latestReleaseURL`, `static let session: Fetch`, `init(currentVersion: AppVersion, fetch: @escaping Fetch = UpdateChecker.session)`, `func latestRelease() async -> ReleaseInfo?`, `func check(lastAnnounced: AppVersion?) async -> UpdateFinding?`); `public enum UpdateNotice` (`symbolName`, `title(_:)`, `caption(_:)`).

- [ ] **Step 1: Targets.** In `Package.swift` add `"UpdateService"` to the `Ledge` target's dependencies, and to `SettingsKit`'s; after `.target(name: "LedgeSettings"),` add `.target(name: "UpdateService"),`; after the SettingsKitTests test target add `.testTarget(name: "UpdateServiceTests", dependencies: ["UpdateService"]),`.

- [ ] **Step 2: Failing tests.** Create `Tests/UpdateServiceTests/UpdateServiceTests.swift`:

```swift
import Testing
import Foundation
@testable import UpdateService

private let reply = #"""
{"tag_name":"v0.1.2","html_url":"https://github.com/dededemahendra/ledge/releases/tag/v0.1.2","draft":false,"prerelease":false,
 "assets":[{"name":"Ledge-0.1.2.dmg","browser_download_url":"https://github.com/dededemahendra/ledge/releases/download/v0.1.2/Ledge-0.1.2.dmg"}]}
"""#

@Test func versionsCompareNumberByNumber() {
    #expect(AppVersion("v0.1.2")! == AppVersion("0.1.2")!)
    #expect(AppVersion("0.1.10")! > AppVersion("0.1.9")!)
    #expect(AppVersion("1.0")! == AppVersion("1.0.0")!)
    #expect(AppVersion("0.2")! > AppVersion("0.1.9")!)
    #expect(AppVersion("0.1.2")!.description == "0.1.2")
    for junk in ["latest", "nightly", "", "1..2", "v", "1.2.x"] {
        #expect(AppVersion(junk) == nil, "\(junk) is not a version")
    }
}

@Test func aReleaseIsReadFromGitHubsReply() {
    let release = ReleaseInfo.decode(Data(reply.utf8))
    #expect(release?.version == AppVersion("0.1.2"))
    #expect(release?.pageURL.absoluteString == "https://github.com/dededemahendra/ledge/releases/tag/v0.1.2")
    #expect(release?.downloadURL?.lastPathComponent == "Ledge-0.1.2.dmg")
}

/// Review Focus 1.
@Test func aTagThatIsNotAVersionIsNotARelease() {
    let nightly = reply.replacingOccurrences(of: "v0.1.2\",\"html", with: "nightly\",\"html")
    #expect(ReleaseInfo.decode(Data(nightly.utf8)) == nil)
    #expect(ReleaseInfo.decode(Data("not json".utf8)) == nil)
    #expect(ReleaseInfo.decode(Data(#"{"message":"Not Found"}"#.utf8)) == nil)
    let pre = reply.replacingOccurrences(of: "\"prerelease\":false", with: "\"prerelease\":true")
    #expect(ReleaseInfo.decode(Data(pre.utf8)) == nil, "a pre-release never shows")
}

/// Review Focus 1.
@Test func aReleaseWithoutADiskImageStillCounts() {
    let bare = #"{"tag_name":"v0.1.2","html_url":"https://github.com/dededemahendra/ledge/releases/tag/v0.1.2","assets":[]}"#
    let release = ReleaseInfo.decode(Data(bare.utf8))
    #expect(release?.version == AppVersion("0.1.2") && release?.downloadURL == nil)
}

/// Review Focus 3.
@Test func aVersionIsAnnouncedOnce() {
    let latest = ReleaseInfo.decode(Data(reply.utf8))!
    #expect(UpdateDecision.evaluate(current: AppVersion("0.1.1")!, latest: latest, lastAnnounced: nil)
            == .available(latest, announce: true))
    #expect(UpdateDecision.evaluate(current: AppVersion("0.1.1")!, latest: latest, lastAnnounced: AppVersion("0.1.2"))
            == .available(latest, announce: false), "found again: still available, not announced")
    #expect(UpdateDecision.evaluate(current: AppVersion("0.1.2")!, latest: latest, lastAnnounced: nil) == .upToDate)
    #expect(UpdateDecision.evaluate(current: AppVersion("0.2")!, latest: latest, lastAnnounced: nil) == .upToDate)
}

private final class Seen: @unchecked Sendable { var request: URLRequest? }

private func answering(_ status: Int, _ body: String, seen: Seen? = nil) -> UpdateChecker.Fetch {
    { request in
        seen?.request = request
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

@Test func theCheckAsksGitHubPolitely() async {
    let seen = Seen()
    let checker = UpdateChecker(currentVersion: AppVersion("0.1.1")!, fetch: answering(200, reply, seen: seen))
    #expect(await checker.check(lastAnnounced: nil) == .available(ReleaseInfo.decode(Data(reply.utf8))!, announce: true))
    #expect(seen.request?.url == UpdateChecker.latestReleaseURL)
    #expect(seen.request?.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    #expect(seen.request?.value(forHTTPHeaderField: "User-Agent") == "Ledge/0.1.1")
    #expect(seen.request?.timeoutInterval == 15)
}

/// Review Focus 2.
@Test func anythingButAReadable200IsCouldNotCheck() async {
    let current = AppVersion("0.1.1")!
    #expect(await UpdateChecker(currentVersion: current, fetch: answering(403, #"{"message":"rate limit"}"#)).check(lastAnnounced: nil) == nil)
    #expect(await UpdateChecker(currentVersion: current, fetch: answering(500, "")).check(lastAnnounced: nil) == nil)
    #expect(await UpdateChecker(currentVersion: current, fetch: answering(200, "garbage")).check(lastAnnounced: nil) == nil)
    let offline: UpdateChecker.Fetch = { _ in throw URLError(.notConnectedToInternet) }
    #expect(await UpdateChecker(currentVersion: current, fetch: offline).check(lastAnnounced: nil) == nil)
}

@Test func theNoticeReadsTheSameEverywhere() {
    #expect(UpdateNotice.symbolName == "arrow.down.circle.fill")
    #expect(UpdateNotice.title("0.1.2") == "Ledge 0.1.2 is available")
    #expect(UpdateNotice.caption("0.1.2") == "Ledge 0.1.2 is available · Download")
}
```

- [ ] **Step 3: Run and watch them fail.** `make test FILTER=UpdateServiceTests` → compile errors (no `AppVersion` etc.).

- [ ] **Step 4: Implement.** `Sources/UpdateService/AppVersion.swift`:

```swift
import Foundation

/// A release's version, `0.1.2` or `v0.1.2` (2026-10-22): compared number
/// by number, so 0.1.10 is newer than 0.1.9 and 1.0 equals 1.0.0. A tag that
/// is not a version reads as `nil` and is never announced.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        var text = text.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty, pieces.count <= 4 else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.allSatisfy(\.isNumber), let number = Int(piece) else { return nil }
            parts.append(number)
        }
        self.parts = parts
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    private func padded(to count: Int) -> [Int] {
        parts + Array(repeating: 0, count: max(0, count - parts.count))
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool {
        let count = max(a.parts.count, b.parts.count)
        return a.padded(to: count) == b.padded(to: count)
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        let count = max(a.parts.count, b.parts.count)
        return a.padded(to: count).lexicographicallyPrecedes(b.padded(to: count))
    }
}
```

`Sources/UpdateService/ReleaseInfo.swift`:

```swift
import Foundation

/// The latest full release on GitHub (2026-10-22), read from
/// `GET /repos/{owner}/{repo}/releases/latest`: its version, its page, and
/// its disk image when it has one.
public struct ReleaseInfo: Sendable, Equatable {
    public let version: AppVersion
    public let pageURL: URL
    public let downloadURL: URL?

    public init(version: AppVersion, pageURL: URL, downloadURL: URL?) {
        self.version = version
        self.pageURL = pageURL
        self.downloadURL = downloadURL
    }

    /// GitHub's reply, or `nil` for anything that is not a full release
    /// with a version tag and a page.
    public static func decode(_ data: Data) -> ReleaseInfo? {
        struct Reply: Decodable {
            struct Asset: Decodable {
                let name: String
                let url: URL
                enum CodingKeys: String, CodingKey { case name, url = "browser_download_url" }
            }
            let tag: String
            let page: URL
            let draft: Bool?
            let prerelease: Bool?
            let assets: [Asset]?
            enum CodingKeys: String, CodingKey {
                case tag = "tag_name", page = "html_url", draft, prerelease, assets
            }
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              reply.draft != true, reply.prerelease != true,
              let version = AppVersion(reply.tag) else { return nil }
        let disk = reply.assets?.first { $0.name.lowercased().hasSuffix(".dmg") }?.url
        return ReleaseInfo(version: version, pageURL: reply.page, downloadURL: disk)
    }
}
```

`Sources/UpdateService/UpdateDecision.swift`:

```swift
import Foundation

/// What a check found (2026-10-22).
public enum UpdateFinding: Sendable, Equatable {
    /// The running version is the latest, or newer.
    case upToDate
    /// A newer release; `announce` only the first time this version is found.
    case available(ReleaseInfo, announce: Bool)
}

/// One island blip per version (2026-10-22, user's call).
public enum UpdateDecision {
    public static func evaluate(current: AppVersion, latest: ReleaseInfo, lastAnnounced: AppVersion?) -> UpdateFinding {
        guard latest.version > current else { return .upToDate }
        let announce = lastAnnounced.map { $0 != latest.version } ?? true
        return .available(latest, announce: announce)
    }
}
```

`Sources/UpdateService/UpdateChecker.swift`:

```swift
import Foundation

/// Asks GitHub for the latest release (2026-10-22): the app's only network
/// request. No cookies or cache, a `Ledge/<version>` User-Agent, a 15 s
/// timeout; anything but a readable 200 is "could not check". `fetch` is
/// injected so the tests can answer it.
public struct UpdateChecker: Sendable {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/dededemahendra/ledge/releases/latest")!

    private static let ephemeral = URLSession(configuration: .ephemeral)
    public static let session: Fetch = { request in try await ephemeral.data(for: request) }

    let currentVersion: AppVersion
    let fetch: Fetch

    public init(currentVersion: AppVersion, fetch: @escaping Fetch = UpdateChecker.session) {
        self.currentVersion = currentVersion
        self.fetch = fetch
    }

    public func latestRelease() async -> ReleaseInfo? {
        var request = URLRequest(url: Self.latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Ledge/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await fetch(request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return ReleaseInfo.decode(data)
    }

    /// One check, decided; `nil` when it could not be made or read.
    public func check(lastAnnounced: AppVersion?) async -> UpdateFinding? {
        guard let latest = await latestRelease() else { return nil }
        return UpdateDecision.evaluate(current: currentVersion, latest: latest, lastAnnounced: lastAnnounced)
    }
}
```

`Sources/UpdateService/UpdateNotice.swift`:

```swift
import Foundation

/// How the island announces an update (2026-10-22), shared by the app and
/// the Settings preview so both draw the same blip.
public enum UpdateNotice {
    public static let symbolName = "arrow.down.circle.fill"
    public static func title(_ version: String) -> String { "Ledge \(version) is available" }
    public static func caption(_ version: String) -> String { "Ledge \(version) is available · Download" }
}
```

If Swift 6 rejects something (for example the static `session` closure), make the smallest change that keeps the interface and behaviour, and report it.

- [ ] **Step 5: Pass.** `make test FILTER=UpdateServiceTests` → 8 tests pass; then `make test` once.

- [ ] **Step 6: Commit.** `git add Package.swift Sources/UpdateService Tests/UpdateServiceTests`, message: `a small update service: ask github once for the latest release, compare versions, and announce each one once`.

---

### Task 2: The blip, the switch and the preview scene

**Files:** Modify `Sources/ActivityKit/ActivityKind.swift`, `Sources/NotchKit/NotchController.swift`, `Sources/LedgeSettings/AppSettings.swift`, `Sources/SettingsKit/PreviewScene.swift`, `PreviewContent.swift`, `PreviewStage.swift`; tests in `Tests/ActivityKitTests/` (the file holding `prioritiesAndTTLsMatchTheSpec`), `Tests/NotchKitTests/NotchControllerTests.swift`, `Tests/LedgeSettingsTests/AppSettingsTests.swift`, `Tests/SettingsKitTests/PreviewStageTests.swift`.

**Interfaces — Consumes:** `UpdateNotice` (Task 1). **Produces:** `ActivityKind.update`; `NotchController.updateActivityID = "update"`, `isUpdateLeading`; `AppSettings.checksForUpdates` (key `"checksForUpdates"`, default `true`); `PreviewScene.update` (title `"Check for updates"`, on when `checksForUpdates`); `PreviewContent.availableUpdate: String?` (memberwise init argument after `timer`, default `nil`); `PreviewSample.updateVersion = "0.1.2"`.

- [ ] **Step 1: Failing tests.** Append to `prioritiesAndTTLsMatchTheSpec`'s file a new test:

```swift
/// An update (2026-10-22): below every other blip, above a Clock timer,
/// eight seconds to read like a meeting.
@Test func anUpdateIsTheQuietestBlip() {
    #expect(ActivityKind.update.priority == 35)
    #expect(ActivityKind.update.defaultTTL == 8)
    #expect(ActivityKind.update < .notification && ActivityKind.update > .timer)
}
```

Append to `NotchControllerTests.swift`:

```swift
/// An update blip (2026-10-22) carries its caption line and its link.
@MainActor
@Test func anUpdateBlipLeadsWithItsCaptionAndLink() {
    let c = makeController()
    let page = URL(string: "https://github.com/dededemahendra/ledge/releases/tag/v0.1.2")!
    c.setActivities([.init(id: NotchController.updateActivityID, title: "Ledge 0.1.2 is available", compactText: "0.1.2",
                           symbolName: "arrow.down.circle.fill", tint: .positive, url: page)], overflow: 0)
    c.setCaption("Ledge 0.1.2 is available · Download")
    #expect(c.isUpdateLeading && c.hasCaption)
    #expect(c.captionText == "Ledge 0.1.2 is available · Download")
    #expect(c.linkURL == page)
}
```

Append to `AppSettingsTests.swift`:

```swift
/// Checking for updates (2026-10-22): on by default, remembered off.
@MainActor
@Test func checkingForUpdatesIsOnByDefaultAndRemembered() {
    let (s, defaults) = fresh()
    #expect(s.checksForUpdates)
    s.checksForUpdates = false
    #expect(!AppSettings(defaults: defaults).checksForUpdates)
}
```

Append to `PreviewStageTests.swift`:

```swift
/// The update scene: the real available version, or a labelled sample.
@MainActor
@Test func theUpdateSceneShowsTheVersionAndItsCaption() {
    let c = island()
    let sample = PreviewStage.apply(.update, content: PreviewContent(), to: c)
    #expect(sample.text == "Check for updates · Sample: no update out")
    #expect(c.activities.first?.compactText == "0.1.2")
    #expect(c.captionText == "Ledge 0.1.2 is available · Download")
    let real = PreviewStage.apply(.update, content: PreviewContent(availableUpdate: "0.2.0"), to: c)
    #expect(real.sampleReason == nil && c.activities.first?.compactText == "0.2.0")
}
```

`make test FILTER="ActivityKitTests"` etc. → compile errors.

- [ ] **Step 2: Implement.**
  - `ActivityKind.swift`: after `case notification` add
    ```swift
    /// A newer Ledge on GitHub (2026-10-22): once per version, under every
    /// other blip (it waits for nothing) and over a Clock timer.
    case update
    ```
    `priority`: `case .update: return 35`; `defaultTTL`: `case .update: return 8       // a version and a line to read`.
  - `NotchController.swift`: next to `calendarActivityID` add `/// \`AppModel\` inserts the update notice with this id (2026-10-22).` `public static let updateActivityID = "update"` and `public var isUpdateLeading: Bool { activities.first?.id == Self.updateActivityID }`; in `hasCaption` change `(isMediaLeading || isCalendarLeading)` to `(isMediaLeading || isCalendarLeading || isUpdateLeading)` and add to its doc comment `An update notice (2026-10-22) carries its own too.`. Fix any exhaustive `switch` over `ActivityKind` the compiler reports (add `.update` with the closest existing behaviour, and report each).
  - `AppSettings.swift`: `Key.checksForUpdates = "checksForUpdates"`; `/// Asks GitHub once a day for a newer Ledge (2026-10-22).` `public var checksForUpdates: Bool { didSet { save(checksForUpdates, Key.checksForUpdates) } }`; in `init`: `checksForUpdates = defaults.object(forKey: Key.checksForUpdates) as? Bool ?? true`.
  - `PreviewScene.swift`: add `update` to the second `case` line; `title`: `case .update: return "Check for updates"`; `isOn`: `case .update: return settings.checksForUpdates`.
  - `PreviewContent.swift`: add `/// A newer version that is really out, for the update scene.` `public var availableUpdate: String?` after `timer`, the matching `init` argument `availableUpdate: String? = nil` after `timer`, and in `PreviewSample` `public static let updateVersion = "0.1.2"`.
  - `PreviewStage.swift`: `import UpdateService`; a case:
    ```swift
        case .update:
            let version = content.availableUpdate ?? PreviewSample.updateVersion
            c.setActivities([NotchController.ActivityDisplay(
                id: NotchController.updateActivityID, title: UpdateNotice.title(version), compactText: version,
                symbolName: UpdateNotice.symbolName, tint: .positive
            )], overflow: 0)
            c.setCaption(UpdateNotice.caption(version))
            return caption(scene, sample: content.availableUpdate == nil ? "no update out" : nil)
    ```

- [ ] **Step 3: Pass.** The four new tests pass; `make test` once (only the two known failures).

- [ ] **Step 4: Commit.** Message: `an update blip for the island, a switch for checking, and an update scene for the settings preview`.

---

### Task 3: The app checks, announces once, and shows it in Settings

**Files:** Modify `Sources/Ledge/AppModel.swift`, `Sources/Ledge/SettingsPanes.swift`, `Sources/Ledge/SettingsWindow.swift`.

**Interfaces — Consumes:** Tasks 1 and 2. **Produces:** `AppModel.UpdateStatus` (`notChecked`, `off`, `checking`, `upToDate(Date)`, `available(ReleaseInfo, Date)`, `failed(Date)`), `AppModel.updateStatus`, `AppModel.hasUpdate`, `AppModel.checkForUpdates(pretending:)`; `AboutSettings(model:)`; `UpdateRow(model:)`.

- [ ] **Step 1: AppModel.** `import UpdateService`. Add a `// MARK: - Updates (2026-10-22)` block with:

```swift
    /// What the last update check found, for Settings › About.
    enum UpdateStatus: Equatable {
        case notChecked, off, checking
        case upToDate(Date)
        case available(ReleaseInfo, Date)
        case failed(Date)
    }

    private(set) var updateStatus: UpdateStatus = .notChecked
    var hasUpdate: Bool { if case .available = updateStatus { true } else { false } }
    private var updateTimers: [Timer] = []
    /// Found while locked: shown at the first tick after unlock.
    private var pendingUpdate: ReleaseInfo?
    private static let lastAnnouncedKey = "lastAnnouncedUpdate"
    private static let runningVersion = AppVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") ?? AppVersion("0")!

    /// One check now: the timers, About's Check now, and the debug probe,
    /// which pretends to be `version`, announces regardless and remembers
    /// nothing. Off, it makes no request.
    func checkForUpdates(pretending version: AppVersion? = nil) {
        guard settings.checksForUpdates || version != nil else {
            updateStatus = .off
            return
        }
        updateStatus = .checking
        let checker = UpdateChecker(currentVersion: version ?? Self.runningVersion)
        let lastAnnounced = version == nil
            ? UserDefaults.standard.string(forKey: Self.lastAnnouncedKey).flatMap(AppVersion.init) : nil
        Task { @MainActor [weak self] in
            let finding = await checker.check(lastAnnounced: lastAnnounced)
            self?.apply(finding, remember: version == nil)
        }
    }

    private func apply(_ finding: UpdateFinding?, remember: Bool) {
        let now = Date()
        switch finding {
        case nil:
            updateStatus = .failed(now)
        case .upToDate?:
            updateStatus = .upToDate(now)
        case .available(let release, let announce)?:
            updateStatus = .available(release, now)
            guard announce else { return }
            if remember { UserDefaults.standard.set(release.version.description, forKey: Self.lastAnnouncedKey) }
            pendingUpdate = release
            showPendingUpdate()
        }
    }

    /// The update blip, once, on an unlocked screen.
    private func showPendingUpdate() {
        guard let release = pendingUpdate, !presenter.isLocked else { return }
        pendingUpdate = nil
        let version = release.version.description
        queue.insert(ActivityRecord(
            id: NotchController.updateActivityID, kind: .update, insertedAt: Date(),
            ttl: ActivityKind.update.defaultTTL, title: UpdateNotice.title(version),
            compactText: version, symbolName: UpdateNotice.symbolName, tint: .positive, url: release.pageURL
        ))
        showCaption(UpdateNotice.caption(version), for: ActivityKind.update.defaultTTL ?? NotchController.captionDuration)
        publish()
    }
```

In `start()`, after `pruneTimer = timer`:

```swift
        // Updates (2026-10-22): a minute after launch, then once a day.
        let firstCheck = Timer(timeInterval: 60, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForUpdates() }
        }
        let daily = Timer(timeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForUpdates() }
        }
        RunLoop.main.add(firstCheck, forMode: .common)
        RunLoop.main.add(daily, forMode: .common)
        updateTimers = [firstCheck, daily]
```

In the 0.25 s timer's closure add `self?.showPendingUpdate()`. In `stop()` add `updateTimers.forEach { $0.invalidate() }; updateTimers.removeAll()`. In `applySettings()` add:

```swift
        if !settings.checksForUpdates {
            updateStatus = .off
        } else if updateStatus == .off {
            checkForUpdates()
        }
```

In `openURL(_:)`'s `#if DEBUG` probes add:

```swift
        if url.scheme == "ledge", url.host() == "probe", url.path() == "/update" {
            checkForUpdates(pretending: AppVersion("0.0.0"))
            return
        }
```

In `previewContent()` pass `availableUpdate: { if case .available(let release, _) = updateStatus { return release.version.description }; return nil }()` as the last argument.

- [ ] **Step 2: General.** In `GeneralSettings`, change the director's scenes to `[.hoverCard, .songCaption, .update]` and add, after the hover section (as the `Form`'s last section):

```swift
            Section {
                SettingsRow("Check for updates", detail: "Once a day, Ledge asks GitHub whether a newer version is out.",
                            symbol: "arrow.down.circle.fill", color: Color(nsColor: .systemGreen), scene: .update, director: director) {
                    Toggle("Check for updates", isOn: playing(\.checksForUpdates, .update, settings: settings, director: director))
                        .labelsHidden()
                }
            }
```

- [ ] **Step 3: About.** `AboutSettings` gains `let model: AppModel`; between the header section and the links section add:

```swift
            Section {
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    UpdateRow(model: model)
                }
            } header: {
                Text("Updates")
            }
```

and add to `SettingsPanes.swift`:

```swift
/// Settings › About › Updates (2026-10-22): what the last check found,
/// when, and a way to act on it.
struct UpdateRow: View {
    let model: AppModel

    var body: some View {
        let status = model.updateStatus
        SettingsRow(Self.title(status), detail: Self.detail(status),
                    symbol: "arrow.down.circle.fill", color: Color(nsColor: .systemGreen)) {
            switch status {
            case .available(let release, _):
                Button("Download") { NSWorkspace.shared.open(release.pageURL) }
            case .off, .checking:
                EmptyView()
            default:
                Button("Check now") { model.checkForUpdates() }
            }
        }
    }

    static func title(_ status: AppModel.UpdateStatus) -> String {
        switch status {
        case .notChecked:             return "Not checked yet"
        case .off:                    return "Checking is off"
        case .checking:               return "Checking…"
        case .upToDate:               return "Ledge is up to date"
        case .available(let r, _):    return "Version \(r.version) is available"
        case .failed:                 return "Could not check just now"
        }
    }

    static func detail(_ status: AppModel.UpdateStatus) -> String? {
        switch status {
        case .off:
            return "Turn it on in General."
        case .upToDate(let at), .available(_, let at), .failed(let at):
            let day: Date.FormatStyle.DateStyle = Calendar.current.isDateInToday(at) ? .omitted : .abbreviated
            return "Last checked at \(at.formatted(date: day, time: .shortened))."
        case .notChecked, .checking:
            return nil
        }
    }
}
```

- [ ] **Step 4: The window.** In `SettingsWindow.swift`: `case .about: AboutSettings(model: model)`, and the sidebar badge becomes `.badge(section == .permissions ? issueCount : (section == .about && model.hasUpdate ? 1 : 0))`.

- [ ] **Step 5: Build and test.** `make test` (only the two known failures).

- [ ] **Step 6: Commit.** Message: `check github for a newer ledge a minute after launch and daily, announce each version once, and show it in about`.

---

### Task 4: Docs

- [ ] **README.** In the Install section, after step 4's paragraph, add: `Once a day Ledge asks GitHub whether a newer version is out, and says so once, on the island; Settings › About shows it too. Settings › General › Check for updates turns it off. It never downloads or installs anything itself.`
- [ ] **Design spec.** Append to `docs/superpowers/specs/2026-09-25-notch-companion-design.md`:

```markdown

## Update notice (2026-10-22)

Lifts "no auto-update" for a notice only (user's call): a minute after launch
and once a day Ledge asks GitHub's API for the latest full release; a newer one
is announced once per version with an island blip (click: the release page) and
shown in Settings › About until updated. Settings › General › Check for updates
turns it off. Nothing is downloaded or installed. Design:
`2026-10-22-update-notice-design.md`.
```

- [ ] **Commit.** `git add README.md docs/superpowers/specs/2026-09-25-notch-companion-design.md`, message: `describe the update notice in the readme and the design spec`.

## After the tasks (controller)

Final review; live check with `make dev` and `open -a dist/Ledge.app "ledge://probe/update"` (blip captured on the island region, About captured through `ledge://probe/settings`); restore the installed copy; push, PR, review; merge when the user says merge.
