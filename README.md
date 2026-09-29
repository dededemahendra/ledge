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
| Music playing (Apple Music, Spotify, TIDAL, Deezer, YouTube Music) | artwork left, equalizer right; hover opens the card |
| Volume or brightness key | glyph left, percentage right, 1.5 s |
| Charger in/out, low or full battery | bolt/plug/battery glyph left, percentage right, 3 s |
| Audio output changes | the device's render or glyph, battery when known, 3 s |

Browsers and everything else that MediaRemote reports are ignored on purpose
(`MediaSourcePolicy`). One blip owns the island at a time; the rest queue.

**The card** (hover with music playing): artwork and titles — click them to
bring the app forward — a scrubber with times, then shuffle · previous ·
play/pause · next · output. The output button opens a row of every audio
output; pick one to switch. Click the island to pin the card open; click
elsewhere, or Escape, to unpin.

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
is just Quit (plus a row when something is broken).

## The one permission

**Accessibility**, asked for at launch, for one thing: intercepting the five
volume/brightness keys so the system never draws its own overlay. On macOS 27
that overlay belongs to `MenuBarAgent` — the process that draws the whole menu
bar — and consuming the key is the only way to keep it off screen
(`docs/private-api-notes.md` has the measurements). Without the grant the keys
work through the system as before, overlay included, and the menu shows a row
that opens the right Settings pane. Nothing else asks for anything: volume,
brightness, battery, output routes and media are all observed by value.

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
