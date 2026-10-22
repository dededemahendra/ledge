# Rich Settings: the look — design

2026-10-22. The first of two pieces of "rich settings" (user's call: both a
richer look and more options, look first). This piece changes how the Settings
window presents the settings it has today; the new options are the second
piece, with their own design. Approved section by section in chat; the user
waived a written-spec review (2026-10-22).

## Goal

Every option in Settings says what it does and shows it: an icon, a one-line
explanation, and, where the option makes the island do something, a live
preview of the real island at the top of the pane that follows the row the
pointer rests on.

## Decisions (user's calls, 2026-10-22)

| Question | Decision |
| --- | --- |
| Where the preview lives | A strip at the top of each pane that shows the blip of the row the pointer rests on, plays it when a switch turns on, and cycles through the pane's switched-on blips at rest (option C of three mockups) |
| What the preview shows | The user's real content where it exists (current song and artwork, next meeting and reminder, battery, headphones, Focus, volume, a running timer); a labelled sample where it does not |
| How it is drawn | The real island view (`NotchRootView`) on its own private `NotchController`, not a drawing and not a mirror of the live island |
| Panes | General, Island, Media and Calendar get the strip; Permissions gets status rows with no strip; About gets a header and two links |
| Look | Apple's System Settings idiom, per the apple-design skill: icon tiles, grouped forms, the control next to its effect |

## Scope

- In: the strip, scenes, the user's content with samples, the director, a
  shared row, the six panes reworked, a slightly larger window.
- Out (this piece): new options, a search field, help popovers, sounds, an
  update checker (the spec rules out auto-update).

## Where the code lives

A new library target, `SettingsKit` (depends on NotchKit, LedgeSettings and the
service modules whose event types the scenes reuse), with a `SettingsKitTests`
target. The app target `Ledge` is an executable and cannot be tested, so
everything with logic goes in SettingsKit; the panes stay in `Ledge` because
they read `AppModel`.

| Unit | Job |
| --- | --- |
| `PreviewScene` | The fixed list of what a strip can show: volume, brightness, Caps Lock, battery, headphones, Focus, timer, Live Activity, meeting, reminder, now playing, song caption, hover card, lock screen |
| `PreviewContent` | A snapshot of the user's real content, every field optional, with a sample for each that is missing |
| `PreviewStage` | Puts a private `NotchController` into a scene, built from the same event types the app uses (`HUDEvent`, `PowerEvent`, `DeviceEvent`), so a scene matches the real blip; returns the strip's caption, marked when it uses a sample |
| `PreviewDirector` | Decides the current scene from the pointer, switch-ons and an injected clock |
| `PreviewStrip` | The view: the user's wallpaper (a gradient fallback), a menu-bar band, the real island on top, no hit testing, sized per pane |
| `SettingsRow`, `SettingsTile` | The shared row (tile, title, explanation, control) that tells the director where the pointer is |

`AppModel` gains a `previewContent()` that builds the snapshot from what it
holds (the live controller's media, upcoming item and calendar mode,
`PowerService.latest`, a running Clock timer), plus three things it starts
remembering because they only arrive as events: the last volume level, the last
Focus that came on, and the last headphones event with battery levels.

## The director

- Pointing at a row shows that row's scene; leaving the rows returns to
  cycling.
- A switch turned on plays its scene once for `playDuration` (3 s), then the
  director goes back to what it was doing.
- At rest it cycles through the pane's switched-on scenes every
  `cycleInterval` (2.5 s); with none on, it shows nothing.
- Pointing at a row that is off still shows its scene, and the caption says
  "Off".
- The hover scene is two steps: now playing for the hover delay, then the card.
- Reduce Motion: the private controller's `reduceMotion` follows the system, so
  scenes crossfade instead of morphing.

## Panes

- **General** (tall strip): launch at login (no scene), the hover delay
  (hover card at that delay), the song caption (song caption).
- **Island** (short strip): the existing groups with an icon and explanation
  per row: volume and brightness, Caps Lock, battery, headphones, Focus, Clock
  timers, Live Activities, calendar events, reminders, and the lock screen
  switch, each with its scene.
- **Media** (short strip): each music app with its real icon and a status line
  ("Playing now", "Installed", "Not installed"); scene: now playing.
- **Calendar** (short strip): the lead time (a meeting blip at that lead), and
  the calendars (meeting) and reminder lists (reminder) with their colour dots.
- **Permissions**: icon, what it unlocks, an Allowed or Not allowed pill, Open
  Settings… beside anything missing; Needs attention stays on top.
- **About**: a centred header (icon, name, version, line) and rows for the
  latest release and the source code.

The window grows from 740 × 520 to 780 × 620 (minimum 720 × 560) so the Island
pane's strip and rows fit without scrolling.

## Edge cases

- A sample is always labelled in the caption ("Sample: no music playing").
- Without Calendars access, the meeting and reminder scenes are samples.
- The strip's controller is made when the pane appears and dropped when it
  goes; nothing runs while Settings is closed.
- Screen type (notch or pill) is read from `NSScreen.islandHost` when the strip
  appears.
- The strip is decorative to VoiceOver; each row reads its title and
  explanation.
- Real titles and artwork appear in the user's own Settings window; accepted.

## Testing

- SettingsKitTests: every scene's stage recipe (controller state and caption,
  real and sample), `PreviewContent` fallbacks, the director on a fake clock
  (pointing, switch-on, cycling only through switched-on scenes, off rows, the
  two-step hover), and a headless render of the strip showing the island inside
  it on a notch and on the pill.
- Live: every pane captured with the app's debug snapshot hook
  (`ledge://probe/settings`), and pointed at by hand.

## Delivery

A branch and a PR, reviewed, merged when the user says merge.
