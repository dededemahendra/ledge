# Update notice — design

2026-10-22. Approved section by section in chat; the user waived a written-spec
review. Lifts, for a notice only, the "no auto-update" line in "Downloadable
release (2026-10-22)" of `2026-09-25-notch-companion-design.md`: Ledge tells
the user a newer version is out; it never downloads or installs anything.

## Goal

When a newer Ledge is on GitHub, the user finds out once, from the island, and
can always see it in Settings › About.

## Decisions (user's calls, 2026-10-22)

| Question | Decision |
| --- | --- |
| How it finds out | GitHub's API, `GET https://api.github.com/repos/dededemahendra/ledge/releases/latest` (full releases only; drafts and pre-releases never show) |
| How often | A minute after launch, then every 24 hours, and on demand from About |
| How insistent | One island blip per version; About keeps an "Update available" row until the user updates |
| Off switch | Settings › General › Check for updates, on by default; off means no requests at all |

## The check: a new `UpdateService` library

| Unit | Job |
| --- | --- |
| `AppVersion` | `0.1.2` or `v0.1.2`, compared number by number (0.1.10 > 0.1.9; 1.0 == 1.0.0); a tag that is not a version is `nil` |
| `ReleaseInfo` | Reads GitHub's reply: version, release page, the `.dmg` asset if any; a draft, a pre-release or a broken reply is `nil` |
| `UpdateDecision` | Up to date, or available and whether to announce: only when newer than the running app and not the version announced last |
| `UpdateChecker` | The request: `Accept: application/vnd.github+json`, `User-Agent: Ledge/<version>`, no cookies or cache (ephemeral session), 15 s timeout; anything but a readable 200 is "could not check". `fetch` is injected for tests |
| `UpdateNotice` | The blip's symbol, title and caption, shared by the app and the Settings preview |

The last announced version is kept in `UserDefaults` (`lastAnnouncedUpdate`).
This is the app's only network request.

## What the user sees

- **The blip:** a new `ActivityKind.update`, priority 35 (above Clock timers,
  below notifications, Focus and everything else that is a blip), 8 s like a
  meeting reminder. Green `arrow.down.circle.fill` left, the version right,
  "Ledge 0.1.2 is available · Download" on the caption line (the island's
  caption line now also shows for an update leading). A click opens the release
  page. Found while the screen is locked, it waits for the first tick after
  unlock.
- **General › Check for updates:** the switch, "Once a day, Ledge asks GitHub
  whether a newer version is out.", and the update blip in the preview strip
  (a new `PreviewScene.update`; a sample version unless an update is really
  available).
- **About › Updates:** "Ledge is up to date", "Version 0.1.2 is available"
  (Download), "Could not check just now", "Checking is off", or "Not checked
  yet"; "Last checked at 10:42."; Check now. About gets a sidebar badge while an
  update is available.

## Failures

Offline, rate-limited, a server error, an unreadable reply: no blip, About says
"Could not check just now", and the next scheduled check tries again.

## Testing

- UpdateServiceTests: versions, decoding a saved reply shape (and broken ones),
  the decision (once per version; never for the same or an older one), the
  checker against canned replies (200, 403, 500, a thrown error) and its
  request headers.
- ActivityKitTests: the new kind's priority and lifetime, priorities distinct.
- NotchControllerTests: the update blip leads with its caption and its link.
- LedgeSettingsTests: the switch's default and round trip.
- SettingsKitTests: the update scene.
- Live: a debug-only `ledge://probe/update` runs a check as if the app were
  0.0.0, without remembering the announcement; the blip and the About row are
  captured.

## Out of scope

Downloading or installing an update, pre-releases, release notes in the app.
