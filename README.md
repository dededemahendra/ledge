# Ledge

A notch companion for the MacBook, in the Dynamic Island style: now-playing
with controls, volume and brightness in place of the stock overlay, battery
and audio-output blips. Personal build for one machine; not distributed.

Built and measured against a MacBook Air 13" (M5) on macOS 27.0 with a
179 × 32 pt notch. Nothing about the notch is hardcoded, but nothing has been
run anywhere else either.

## What it shows

| Trigger | Island |
| --- | --- |
| Music playing (Apple Music, Spotify, TIDAL, Deezer, YouTube Music) | spinning cover left, current output's glyph right; resting the cursor on it opens the card |
| Song changes | the island drops one line for 3 s: "Title · Artist" |
| Nothing playing, cursor resting on the island | the next event: calendar glyph left, countdown right ("42m", "2h 10m", "Now"), "Title · 14:00" under the hole; click to join or open Calendar |
| A meeting 5 min away, and again as it starts | calendar glyph left, "5m" then "Now" right, "Title · 10:00" under the hole for 8 s; click the blip to join the call (Zoom, Meet, Teams, Webex, FaceTime…) or, with no link, to open Calendar |
| Volume or brightness key | glyph left, percentage right, 1.5 s |
| Caps Lock | caps lock glyph, "On"/"Off", 1.5 s |
| Charger in/out, low or full battery | battery glyph left (bolt while charging, plug when held on AC; green charging, red low), percentage right, 3 s |
| Audio output changes | the device's render or glyph, battery when known, 3 s |

Browsers and everything else that MediaRemote reports are ignored on purpose
(`MediaSourcePolicy`). One blip owns the island at a time; the rest queue.

**The card** (rest the cursor on the island for a beat with music playing — passing through to the menu bar does nothing): artwork and titles — click them to
bring the app forward — with a favourite star and the output button beside
them — a scrubber with times, then Apple Music's transport row: shuffle ·
previous · play/pause · next · repeat. The star works for Apple Music only
(Spotify has no local way to like a track); the first tap makes macOS ask once
to let Ledge control Music, and until that tap Ledge never talks to Music. The output button opens a list of every audio
output below the controls (the card grows to fit); pick one to switch. Click the island to pin the card open; click
elsewhere, or Escape, to unpin. A click on a blip with nothing playing does nothing. Two-finger swipe left or right over the island
to skip tracks.

## Build and run

Swift 6.4 toolchain (Xcode 27 or the matching Command Line Tools), SwiftPM
only — no Xcode project.

```sh
make cert          # once: a self-signed "Ledge Dev" identity, so TCC grants survive rebuilds
make cert-allow    # once, if codesign keeps prompting: lets it use the key silently
make dev           # debug build, sign, relaunch
make test          # 237 tests, headless (some render the real SwiftUI tree)
make install       # release build into /Applications
```

The app is a menu-bar-less agent; its only chrome is a status item whose menu
is just Quit (plus a row when something is broken). It registers itself as a
login item on first launch — macOS says so once, and the switch lives in
System Settings › General › Login Items.

## Permissions

**Accessibility**, asked for at launch, for one thing: intercepting the five
volume/brightness keys so the system never draws its own overlay. On macOS 27
that overlay belongs to `MenuBarAgent` — the process that draws the whole menu
bar — and consuming the key is the only way to keep it off screen
(`docs/private-api-notes.md` has the measurements). Without the grant the keys
work through the system as before, overlay included, and the menu shows a row
that opens the right Settings pane. Nothing else asks for anything: volume,
brightness, battery, output routes and media are all observed by value. Two
other prompts: **Automation for Music** appears only when you first tap the
card's favourite star, and **Calendars** is asked once at launch for the meeting
blip — declining just turns that blip off, and the menu says so.

## What it deliberately doesn't do

- **Lock screen.** Wired and parked: on this macOS the lock screen is composited
  over every user window regardless of level. Findings in the spec, §7.
- **Notifications, file shelf, timers, weather** and the rest of the notch-app
  feature zoo. See the spec's non-goals.
- **External or notch-less displays** as the island's host.

## Where things are

- `docs/superpowers/specs/…-design.md` — the design, with dated amendments
  for every decision that changed since (most of them did).
- `docs/manual-checks.md` — what was verified on the real machine, and what
  wasn't, per task.
- `docs/private-api-notes.md` — the private-framework findings: brightness,
  the overlay's owner, the AirPods renders.
- `Sources/` — `NotchKit` (window, shape, controller, views), `ActivityKit`
  (queue), and one service module per source: `HUDService`, `PowerService`,
  `MediaService`, `DeviceService`. `Ledge/` is the app shell that wires them.

## Third-party and system assets

`Resources/mediaremote-adapter` is vendored from
[ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
(BSD-3-Clause, licence alongside). The AirPods renders in the device blip are
Apple's own, read at runtime from the running system — nothing is copied into
the bundle, and a macOS update that moves them falls back to a glyph.
