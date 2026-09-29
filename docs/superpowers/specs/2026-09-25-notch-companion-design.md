# Ledge — Design Spec

**Date:** 2026-09-25
**Status:** Approved for planning
**App:** `Ledge.app` · bundle id `com.dedemahendra.ledge`

---

## 1. Purpose

A macOS menu-bar-less agent app that turns the MacBook notch into an interactive
Dynamic-Island-style surface: media controls, replacement volume and brightness
HUDs, battery and device activities, mirrored system notifications, and a
lock-screen presence.

**Stated intent (from the user):** build a free equivalent of the paid app Alcove
(currently $14.99), for personal daily use on their own machine.

**Success criteria:** the author uses it every day in place of Alcove, and the
motion quality is good enough that they do not miss the paid app.

**Assumptions made, not stated:**

- Runs only on the author's machine. No public release, so no notarization, no
  installer, no auto-update, no localization, no support for macOS older than
  the machine's own version.
- "Free" means zero cost to the author, not a commitment to open-source it.
- Alcove's feature set is the target, not its code or assets.

### Originality boundary

Features and interaction patterns are reimplemented from observation. No code,
icon, artwork, or naming from Alcove is copied, and the app does not ship under
Alcove's name. Boring Notch (GPL-3.0) may be read for technique but **no code is
copied from it**, which keeps Ledge free of GPL obligations. The only third-party
code vendored is `mediaremote-adapter` (BSD-3-Clause), whose licence permits this.

---

## 2. Non-goals

Explicitly out of scope, and not to be added without a new design round:

- File shelf, drag-and-drop tray, AirDrop shortcut
- Clipboard history, timers, Pomodoro, quick notes, calendar, weather
- Window snapping, app launcher, OCR, text expansion
- Camera mirror, camera guard, mic mute
- Support for external or notch-less displays as the island's host
- Distribution of any kind

Alcove itself has none of the first group; adding them is scope creep dressed as
parity.

---

## 3. Measured constraints

Taken from the target machine on 2026-09-25, not assumed:

| Property | Value |
| --- | --- |
| Machine | MacBook Air 13″, `Mac17,3`, Apple M5, arm64 |
| OS | macOS 27.0 (build 26A428) |
| Toolchain | Xcode 27.0 (27A266a), Swift 6.4, SDK MacOSX27.0 |
| Logical screen | 1470 × 956 pt @2x |
| **Notch** | **179 × 32 pt**, origin x = 645.5 (exactly centered) |
| Menu bar height | 33 pt (notch is 1 pt shorter) |
| `safeAreaInsets.top` | 32 pt |
| Refresh rate | 60 Hz — from the model, not probed; no ProMotion |

Derived from `NSScreen.safeAreaInsets` and the gap between
`auxiliaryTopLeftArea.maxX` and `auxiliaryTopRightArea.minX`.

**These numbers change with display scaling and must never be hardcoded.**
`NotchGeometry` recomputes them on
`NSApplication.didChangeScreenParametersNotification`.

### The dead-zone constraint

The notch is a physical cutout. **There are no pixels in the 179 × 32 pt notch
region.** The island may surround it but can never draw inside it. All content
lives either in the two "ears" beside the notch or in the region below it. Every
layout in §6 obeys this.

### Environment setup note

`xcode-select` currently points at `/Library/Developer/CommandLineTools`. The
Makefile must either set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
itself or the author runs `sudo xcode-select -s /Applications/Xcode.app` once.
Prefer the former — no sudo, no global state change.

---

## 4. Architecture

### Chosen approach

Own the shell and the feel; vendor the private-API plumbing. The animation layer
is the product and cannot be inherited from another codebase. The private-API
access (MediaRemote, OSD suppression, notification ingest) is solved-problem
territory where reinvention costs reliability and gains nothing.

### Data flow

Strictly one-directional. This single rule is what makes the fragile modules
survivable and the logic testable.

```
services ──emit domain events──▶ ActivityQueue ──▶ NotchController ──▶ NotchRootView
  (media, HUD, power,             (priority,        (state machine)       (SwiftUI)
   device, notification,           coalescing,
   lockscreen)                     TTL)                     ▲
                                                            │
  user intents (play, seek, skip, switch output) ────────────┘
       leave through a Command protocol
```

Services never touch UI. The view never touches services. Everything the UI
knows arrives as an `Activity`; everything it wants done leaves as a command.

### Concurrency model

Swift 6 strict concurrency. Each service is an `actor` (or a `@MainActor` class
where it wraps AppKit) exposing `AsyncStream<DomainEvent>`. Domain events are
`Sendable` value types. One `@MainActor @Observable AppModel` consumes every
stream, feeds `ActivityQueue`, and drives `NotchController`. No shared mutable
state crosses an actor boundary.

### Module layout

`★` = written here, defines the product. `▢` = protocol-fronted plumbing,
replaceable, allowed to fail.

```
Sources/
  Ledge/                  @main, AppDelegate, wiring, menu-bar-less lifecycle
  NotchKit/            ★  NotchWindow, NotchGeometry, NotchController,
                          NotchShape, NotchRootView
  ActivityKit/         ★  Activity protocol, ActivityQueue
  MediaService/        ▢  mediaremote-adapter subprocess + ScriptingBridge fallback
  HUDService/          ▢  volume/brightness observation + OSD suppression
  PowerService/        ▢  IOKit power source
  DeviceService/       ▢  CoreAudio route + IOBluetooth + IORegistry battery
  NotificationService/ ▢  fragile — usernoted DB, AX fallback
  LockScreenService/   ▢  fragile — shielding-level presence
  Settings/               preferences UI, persistence, per-service status
Tests/
  <one target per module>
```

### Service availability contract

Every service exposes:

```swift
enum ServiceAvailability: Sendable, Equatable {
    case available
    case needsPermission(Permission)
    case unavailable(reason: String)
}
```

**The app must be correct with any subset of services available.** Settings shows
one live status row per service with the reason and, where applicable, a Grant
button.

---

## 5. NotchKit — the shell

### NotchWindow

A borderless, non-activating `NSPanel`:

| Property | Value |
| --- | --- |
| `styleMask` | `[.borderless, .nonactivatingPanel]` |
| `level` | `NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)` normally; `NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)` when locked |
| `collectionBehavior` | `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]` |
| `backgroundColor` | `.clear`, `isOpaque = false`, `hasShadow = false` |
| `isMovable` | `false` |
| `hidesOnDeactivate` | `false` |
| `isFloatingPanel` | `true` |

Ordered out entirely when state is `.hidden`, so idle compositing cost is zero.

### The window never animates

The window is a **fixed, oversized, transparent canvas** — 640 × 320 pt, anchored
top-centre over the notch. The island animates *inside* it in SwiftUI.

Rationale: `NSWindow` frame animation cannot be spring-driven, drops frames, and
thrashes the backing store. Growing a shape inside a static window is free.

### Hit testing

A 640 × 320 transparent window would swallow every click at the top of the
screen. The content view overrides `hitTest(_:)` to return `nil` unless the point
falls inside the island's **current** path, so clicks pass through to whatever is
below.

- The view holds the live `CGPath`, updated as the shape animates.
- Collapsed, the claimed region is the notch rect plus ~4 pt of forgiveness —
  which is not clickable screen area anyway.
- Menu bar clicks beside the notch keep working.
- This behaviour is integration-tested (§10) because it breaks silently.

**Corrected 2026-09-28.** `hitTest` alone was not enough: the window was
created with `ignoresMouseEvents = false`, and a window that opts into mouse
events receives every click in its frame — a `hitTest` that returns `nil`
discards the click rather than passing it to the window beneath. While the
island was visible, everything under the canvas was dead, and a click there
never reached the click-outside monitor either, so a pinned panel could not be
dismissed from there ("click the notch, then can't click anything"). The
window is now mouse-transparent by default and `NotchPresenter` turns
`ignoresMouseEvents` off only while the cursor is inside the island's
forgiving path (re-evaluated on every mouse move and on the 250 ms tick), and
back on the moment it leaves. `hitTest` remains as the second line of defence
inside the canvas.

### NotchController state machine

One `@Observable` value, so SwiftUI derives every animation from a single source.

```
  hidden ──hover──▶ peek ──hover, media playing──▶ expanded
    ▲                │                                │
    │                └──unhover──────────────────────┤ unhover (hover-opened)
    │                                                │ esc / click-outside (pinned)
    └────── activity(a) ◀────────────────────────────┘
            auto-collapses after a.ttl
```

**Changed 2026-09-28: hover opens the panel, not click.** Hovering the island
while there is media to show expands it; the cursor leaving collapses it. Hover
with nothing playing is still the small peek, and hovering a lone HUD/battery
activity leaves it at activity size — the panel is opened for the now-playing
card, the one expanded surface with controls in it. A click on the island (or
the menu bar's "Toggle Panel") **pins** the panel open so it survives the cursor
leaving; Escape, click-outside and a second click unpin it. Unpinning while the
cursor is still over the island lands straight back on the hover-opened panel.

- Auto-collapse timers are **cancelled while hovered** — never yank the island out
  from under the cursor.
- `peek` is the notch height + 6 pt with glanceable hints.
- Click-outside dismissal (of a *pinned* panel) uses
  `NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown)`, which requires no
  permission for mouse events.
- Escape unpins when expanded.

### NotchShape

A hand-rolled `Path`, not a built-in rounded rectangle —
`UnevenRoundedRectangle` cannot produce the concave outer fillets.

Shape language (chosen from three options): **flush with inverted corners**. Top
edge welded to `y = 0` (the bezel), bottom corners rounded, concave quarter-circle
fillets blending the sides into the menu bar, filled opaque black to match the
bezel.

`animatableData` interpolates four values:

| Parameter | Collapsed | Expanded |
| --- | --- | --- |
| width | 179 pt | up to 390 pt |
| height | 32 pt | 168 pt |
| bottom corner radius | 9 pt | 26 pt |
| outer fillet radius | 0 pt | 13 pt |

The fillet growing with the shape is what stops the seam showing. Path
construction, with `x0 = cx - w/2`, `x1 = cx + w/2`:

```
M (x0 - ro), 0
A ro ro 0 0 1 x0, ro                 ← concave top-left fillet
L x0, (h - rb)
A rb rb 0 0 0 (x0 + rb), h           ← bottom-left
L (x1 - rb), h
A rb rb 0 0 0 x1, (h - rb)           ← bottom-right
L x1, ro
A ro ro 0 0 1 (x1 + ro), 0           ← concave top-right fillet
Z
```

### Motion

| Transition | Spring |
| --- | --- |
| Expand | `response 0.35, dampingFraction 0.72` |
| Collapse | `response 0.30, dampingFraction 0.92` |

Chosen by comparing four candidates against the criterion "which would you still
tolerate on the fiftieth repeat", not "which looks nicest once".

Computed characteristics (`overshoot = e^(-ζπ/√(1-ζ²))`, settle to 2% band
`≈ 4/ζω`, `ω = 2π/response`):

| Transition | Overshoot | Settles |
| --- | --- | --- |
| Expand `0.35 / 0.72` | 3.8% | ~0.31 s |
| Collapse `0.30 / 0.92` | 0.1% | ~0.21 s |

One small, confident overshoot on the way out; effectively none on the way back.
Collapse is deliberately duller — closing should not draw attention.

**Reduce Motion:** when
`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` is true, replace the
entire spring system with a 0.15 s crossfade and an instant size change.

**More motion, 2026-09-29 (user's call: "need more animations").** Ear content
emerges from under the notch (10 pt towards the hole, scaling from 60 %,
sharpening) on the blip spring; the value's digits roll (`numericText`); glyph
swaps morph (`symbolEffect(.replace)`) and each press bounces the glyph; the
cover flips in edge-on on a track change (`FlipOnChange`); the card's header,
scrubber and controls cascade up into place on expand; the caption slides up as
it fades in; the island pulse is 7 %. Reduce Motion: none of it.

**Pop, 2026-09-29 (user's call: "magnification when interactions").** A blip
arriving from the bare notch uses its own spring (`NotchAnimation.pop`,
0.42/0.62, ~8 % overshoot in width; height cannot overshoot at notch height),
its ear content scales in from 60 % on that spring while it sharpens, and
every value change — each volume/brightness step, each percentage tick —
bumps glyph and number to 120 % and back (`ValueBump`, keyframes). The panel's
calm `expand` spring is untouched: opening a card is not a throw. Reduce
Motion gets crossfades only.

**Motion polish, 2026-09-29.** Three things the island's content used to do
badly while the shape sprang: (1) it was laid out for the *target* size from
the first frame, so the ears jumped to their final x and were then revealed by
the moving clip mask — now an `Animatable` modifier publishes the spring's
interpolated parameters through the environment and the ears row lays out from
that, so they travel with the shape; (2) one blip replacing another at the same
size swapped the ears instantly because nothing else animated — the ear
containers are now keyed on the leading activity's identity and crossfade with
`.blurReplace`; (3) the expanded card was sliced by the shrinking mask on
collapse — it now fades and blurs in and out over the spring. The spring
direction is decided by area, not height (peek → activity is growth).

### Content presentation

- `clipShape`'d to the same `NotchShape` so nothing bleeds out mid-morph.
- Opacity ramps over animation progress `0.45 → 0.83`, so text never appears
  before there is room for it.
- `matchedGeometryEffect` for artwork growing compact → expanded.
- `.blurReplace` transition for text swaps.

### Display handling

Always renders on the built-in display. Hides entirely in clamshell mode. No
support for notch-less or external displays as host (§2).

---

## 6. Layout — content around the hole

Chosen from three options: **ears first, grow down only when crowded.** One
activity is minimal and notch-height; a second causes downward growth, so the
growth itself becomes the signal that something happened.

| State | Size | Content placement |
| --- | --- | --- |
| Hidden | — | window ordered out |
| Peek (hover) | 179 × 38 pt | **no content** — see below |
| 1 activity | ~255 × 32 pt | leading ear: artwork 20 pt; trailing ear: waveform |
| Song change (media leading) | ~342 × 58 pt for 3 s | ears: artwork + bars; one "Title · Artist" line under the hole (2026-09-29, from the reference app). A two-finger horizontal swipe over the island skips a track, with the skip glyph in the leading ear for 0.7 s |
| Volume/brightness HUD, power or device blip live (whatever is behind it) | ~255 × 32 pt | leading ear: glyph (or product render); trailing ear: percentage (device over music: artwork left, icon right) |
| 2+ activities | ~255 × 32 pt | **retired 2026-09-29**: the leading activity owns the island alone; the rest wait in the queue (`+N` pip in the trailing ear when more than two are live) |
| Expanded (hover with media, or pinned by click) | ~390 × 168 pt | full panel below the hole; ears keep glyphs |

Ear width at one activity is ~38 pt per side; at two activities ~81 pt per side.
A live volume/brightness HUD takes the island alone for its 1.5 s — even with
the sticky media activity behind it, which with music playing is every volume
press. **Second pass, 2026-09-28 (user's call): glyph + percentage at the
one-activity size, no words, no bar** — the same shape as the power blip. The
first pass below (a 90 pt ear per side with "Sound"/"Display" and a bar) is
kept for the record; it was measured off the reference app and then dropped
as busier than wanted. It got a fixed 90 pt ear per side
(the island width follows from the notch, not the other way round), measured off
the reference app's own HUD on 2026-09-25 — 360 pt around the same 179 pt notch,
glyph then a one-word label leading-aligned on the left, a 5 pt-tall, 68 pt-long
bar ending 10 pt short of the right edge. Whatever the HUD pre-empted (artwork,
battery) comes back when it expires. Any other leading activity keeps the sizes
above.

**Peek carries no content, and cannot.** Peek is the notch's own width, so `earWidth`
is exactly 0 and there is no ear to put a hint in. An earlier draft of the table above
said "glanceable hints in both ears" at peek, which was self-contradictory. Peek is a
6 pt lip whose whole job is to signal "this surface is live" by growing under the
cursor. Anything more means widening peek, which is a separate design decision nobody
has asked for.

**No content may be positioned within the notch rect — and none outside the island.**
Both halves matter, and the second was missing from an earlier draft: a layout that
correctly clears the hole can still render content below the island's bottom edge,
unbacked, over the desktop. Debug builds assert containment inside the island *and*
exclusion from the hole, and a headless `ImageRenderer` test checks the rendered
pixels rather than the intent. Nothing else in this design verifies the view layer,
which is where this project's two worst defects both lived.

Expanded media panel: 60 pt artwork, title, artist, scrub bar with position and
duration, previous / play-pause / next, and an audio-output picker.

---

## 7. Service specifications

### ActivityQueue

```
priority  kind           ttl        notes
   100    hud            1.5 s      always wins; volume, brightness, mute
    60    power          3 s        plug, unplug, 20/10/5% thresholds, full
    50    device         3 s        AirPods/Bluetooth connect, output change
    40    notification   5 s        mirrored system notifications
    10    media          sticky     never expires; the resting state
```

- **Coalescing:** a new event of the same `kind` replaces the existing activity
  rather than queueing. Spinning the volume wheel produces one activity, not
  twenty.
- **Slot cap:** two compact slots (matching §6). A third concurrent activity
  becomes a `+N` pip.
- **Media is the resting state:** whenever playback is active, that is what the
  collapsed island shows.
- Expiry uses an **injected clock** so it is deterministic under test.

`Activity` protocol: `id`, `kind`, `priority`, `ttl`, `isSticky`, and view
builders `compactLeading`, `compactTrailing`, `detailRow`, `expanded`.

### PowerService — no permission, public API

**Presentation (2026-09-28):** a power blip is the plain one-activity island,
alone or over music — glyph (bolt charging, plug held on AC, battery-fill
otherwise) on the left, the percentage on the right, no words (a labelled
"Charging …… 95%" row was tried and dropped at the user's request).
`activityTitle` keeps the long form for the detail row.

`IOPSNotificationCreateRunLoopSource` plus `IOPSCopyPowerSourcesInfo`. Emits
plug/unplug, percentage threshold crossings (20 / 10 / 5%), fully-charged,
low-power-mode changes, and time-to-full estimates. Lowest risk module; built
first after the shell precisely because it proves the whole pipeline end to end.

### HUDService — no permission, by design

**Deviation from how most notch apps do this.** The usual approach taps the
keyboard for volume and brightness keys, which forces an Accessibility prompt and
only catches key presses. Ledge observes the *values* instead:

- **Volume:** CoreAudio property listener on the default output device —
  `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` (the property the
  system's keys and `VolumeControl` write; preferred since the 2026-09-29
  review so observer and interceptor read one number) plus
  `kAudioDevicePropertyMute`, falling back to `kAudioDevicePropertyVolumeScalar`
  for devices with no virtual main.
- **Brightness:** `DisplayServices` brightness-change notifications.

This needs **no permission at all** and fires for the menu-bar slider and Control
Centre too, not just the keys. A `CGEventTap` on `.systemDefined` subtype 8
(requiring Input Monitoring) remains as a fallback **only** if brightness
observation proves unreliable in practice.

Also handles keyboard-backlight changes and the no-audio-device state.

**Changed 2026-09-28 — system HUD replacement needs Accessibility after all.**
On macOS 27 the stock volume/brightness pill is no longer `OSDUIHelper`'s: it is
a popover owned by `MenuBarAgent`, the process that draws the whole menu bar, and
it is triggered by the media-key HID event (a scripted `set volume` never shows
it). Pausing `OSDUIHelper` therefore does nothing, and pausing `MenuBarAgent`
would freeze the menu bar. The only working suppression is the one this section
originally rejected: `MediaKeyInterceptor` takes the five keys with a filtering
`CGEventTap` (Accessibility), applies them itself (CoreAudio virtual main volume /
mute, `DisplayServicesSetBrightness`, sixteenths, sixty-fourths with Shift+Option,
snapped to the grid like the system), and swallows them. The value observers
above stay the source of every HUD event. Without the grant the keys still work
through the system, the menu shows "System HUD — needs Accessibility", and the
tap is retried every 2 s so a grant made in System Settings lands without a
relaunch.

**OSD suppression (legacy).** The stock HUD used to be drawn by the `OSDUIHelper` launchd agent.
Ledge sends it `SIGSTOP` while its own HUD is enabled and `SIGCONT` when
disabled. This is the least clean thing in the app, so restoration is
belt-and-braces:

1. `SIGCONT` in `applicationWillTerminate`
2. `atexit` handler
3. An unconditional `SIGCONT` at next launch whenever the HUD feature is off

A crash can never leave the system HUD dead. One user-facing toggle; off means
both HUDs appear, which is ugly but harmless.

### MediaService — no permission, medium risk

**Source allow-list (2026-09-29, user's call):** only music players are shown
and controlled — Apple Music, Spotify, TIDAL, Deezer, YouTube Music
(`MediaSourcePolicy.allowedBundleIdentifiers`). MediaRemote reports whatever
played most recently, browser tabs included, and those were landing in the
island with their titles; a disallowed source is treated exactly as nothing
playing. Extending the list is one line.

Vendors [`mediaremote-adapter`](https://github.com/ungive/mediaremote-adapter)
(BSD-3-Clause), which restores MediaRemote access broken by Apple in macOS 15.4.
It loads `MediaRemoteAdapter.framework` inside `/usr/bin/perl`, which reports
bundle id `com.apple.perl` and is therefore entitled. Its README lists macOS
27.0+ as supported — the target OS.

- **Transport:** supervised `Process` reading newline-delimited JSON from stdout
  via `AsyncLineSequence`.
- **Supervision:** the upstream README states plainly *"You should not reinvoke
  the script when a fatal error occurs (non-zero exit code)"*, so the policy is
  split by exit reason. A **clean exit or signal termination** is transient:
  restart with exponential backoff 0.5 → 1 → 2 → 4 → … capped at 30 s, five
  rapid failures then `unavailable`. A **non-zero exit is fatal**: do not
  reinvoke, mark `unavailable`, switch to the fallback source.
- **Capability probe:** the adapter ships a `test` command whose exit code 0
  means MediaRemote access still works. Run it once at startup to choose between
  the adapter and the ScriptingBridge fallback, rather than discovering the
  failure through a dead stream.
- **Diffing:** `stream` emits diffs **by default**. Each line is
  `{"type":"data","diff":Bool,"payload":{…}}`; when `diff` is true the payload
  carries only changed keys and a `null` means *that key vanished*. The client
  must merge diffs onto the last non-diff payload. Getting this wrong shows up
  as stale titles that never clear.
- **Position:** extrapolated locally at 1 Hz from `elapsed + rate + timestamp`.
  The adapter is never polled. The tick runs only while playing.
- **Artwork:** cached by `(title, album)`, because the adapter's README admits
  artwork delivery is inconsistent. A cached image beats a flicker; a glyph
  placeholder beats an empty box.
- **Commands out:** short-lived `perl … send play|pause|next|previous`,
  `seek <seconds>`.
- **Stated risk:** depends on Apple not revoking `/usr/bin/perl`'s entitlement.
- **Mitigation:** `MediaSource` is a protocol. A second implementation using
  ScriptingBridge against Music.app and Spotify is narrower in coverage but keeps
  the island working the day Apple closes that door.

### DeviceService — no permission

**Built 2026-09-28, narrower than planned.** `IOBluetooth` turned out to need
the Bluetooth privacy prompt (the app aborts at launch without an
`NSBluetoothAlwaysUsageDescription`), so the "no permission" promise won and
the Bluetooth link observer was dropped:

- CoreAudio default-output-device listener → an activity on every route
  change, titled with the new device's NAME ("Dede's AirPods Pro", "MacBook Air
  Speakers"), product glyph in the leading ear, battery in the trailing ear.
  A move back to the built-in speakers is announced the same way: CoreAudio
  cannot say whether the previous device disconnected or was merely switched
  away from, so "disconnected" would be a guess.
- **Product renders, not just glyphs (2026-09-28, at the user's request):**
  for AirPods the leading ear shows Apple's own photo-real render, read at
  runtime from `HeadphoneAssets.framework` on the running system
  (`DeviceArtwork`) — never copied into the bundle. Missing file → SF Symbol.
  Real-time 3D (SceneKit/USDZ) was considered and rejected: no AirPods models
  ship with macOS, third-party ones carry licences, and a 24pt ear cannot show
  depth a still render does not already give.
- **Never grows the island (2026-09-28, user's call):** a device blip is the
  one-activity island even with music behind it — artwork stays in the
  leading ear, the device's render/glyph takes the trailing ear for 3 s. The
  device NAME is not shown while music plays; the icon is the message.
- Battery from the `IORegistry` (`AppleDeviceManagementHIDEventService`:
  `Product` + `BatteryPercent`), name-matched loosely. No `system_profiler`
  fallback — too slow for a 3 s activity.
- Not covered: non-audio peripherals (keyboard, mouse) connecting or
  disconnecting, and an audio device that connects without becoming the
  default output. Both need `IOBluetooth` and its prompt.
- Output switching in the expanded panel via `AudioObjectSetPropertyData` —
  **built 2026-09-29**: the card's fifth control (where repeat sat) shows the
  current output's glyph; tapping it opens a list of every audio output
  BELOW the controls, and the island grows by one row per output
  (`NotchMetrics.expanded(outputRows:)`; the picker's open state lives in
  `NotchController` because it sizes the island). `OutputDeviceCatalog`
  enumerates every device with an output stream and follows device-list/
  default changes; picking one sets the default output, closes the list, and
  the route blip confirms it. Dimmed with fewer than two outputs. (A first
  cut swapped the control row for chips; replaced the same day at the user's
  request — chips truncated long names.)

### NotificationService — fragile, isolated, opt-in

Two implementations behind one `NotificationSource` protocol.

**Primary:** read `~/Library/Group Containers/group.com.apple.usernoted/db2/db`
(SQLite) with a `DispatchSource` file watch. Requires **Full Disk Access**. Gives
structured data — app id, title, subtitle, body, date — and does not care how
Apple restructures the UI.

**Fallback:** `AXObserver` on Notification Center, scraping banner windows.
Requires **Accessibility**. Breaks whenever Apple changes that UI.

- Dedupe by record id so a banner is never shown twice.
- Hard failure marks the service `unavailable`; nothing else notices.

**Privacy, stated plainly:** this module reads the content of every notification
the user receives. That content stays on-device, is never written to disk by
Ledge, and is never logged above `.debug`. The feature is **off until explicitly
enabled**.

### LockScreenService — fragile, built last

**Does not render on macOS 27.0 — parked 2026-09-28.** The plumbing below is
in and correct (the lock notification fires, the window rises to
`CGShieldingWindowLevel() + 1` and is reported on-screen), but the lock screen
is composited as a separate layer over every user window regardless of level:
test panels at levels 1000, 2005, 3000 and shield+1 were all invisible on the
lock screen, whether created before the lock or after it. `loginwindow`'s own
lock windows sit at levels 2001/2004, and during the lock transition user
windows (ours included) are scaled about the screen centre while those are
not. Reaching the lock layer would need private SkyLight/CGS space APIs. The
code stays because it is harmless (an invisible panel, collapsed again on
unlock) and the observer is reusable; the feature is off the list until a
public way exists. Details in `docs/manual-checks.md`.

**Built 2026-09-28** as `LockScreenObserver` (NotchKit) + `NotchPresenter.setLocked`
+ `NotchController.isLocked`: with media playing, a locked screen shows the
now-playing card in **display-only** form — artwork, title, artist, progress
and times, no control row, no drag on the scrubber. Nothing playing: nothing
extra; charging/HUD/device activities keep appearing in the ears at their
usual size, above the shield. A pinned panel survives lock/unlock.

- Detect lock and unlock via the `com.apple.screenIsLocked` and
  `com.apple.screenIsUnlocked` distributed notifications.
- Raise the panel to `CGShieldingWindowLevel() + 1` while locked.

**Accepted limitation:** a non-activating panel at shielding level can *render*
but cannot reliably receive key or mouse events while `loginwindow` owns the
screen. **Lock-screen mode is display-only** — now-playing metadata and charging
state, no controls. Precedent exists (Boring Notch ships lock-screen widgets), so
this is achievable, but it is sequenced last and may be cut without affecting
anything else.

---

## 8. Permissions and privacy

Nothing is requested at launch. Every permission is requested lazily, from the
Settings row of the feature needing it, with a Grant button that deep-links the
correct System Settings pane (e.g.
`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`).

| Capability | Permission | Requested when |
| --- | --- | --- |
| Notch window, HUD, power, device, media | **none** | never |
| Notification mirroring (primary) | Full Disk Access | user enables the feature |
| Notification mirroring (fallback) | Accessibility | only if the FDA path fails |
| HUD key-tap fallback | Input Monitoring | only if brightness observation fails |

**Logging:** `OSLog` with one subsystem per module. `.debug` stripped in release
builds. Track titles and notification content never logged at `.info` or above.
No telemetry, no network access of any kind.

---

## 9. Failure policy

| Situation | Behaviour |
| --- | --- |
| Service throws at startup | `unavailable(reason)`; red row in Settings; app launches normally |
| Service dies at runtime | its activities evicted from the queue; state flips; no crash |
| Any failure | **no modal alerts, ever** — nothing is worse than a notch app throwing dialogs |
| Media subprocess exits cleanly or is signalled | restart with backoff; five strikes then `unavailable` |
| Media subprocess exits **non-zero** | fatal per upstream guidance: no reinvoke, `unavailable`, fall back |
| App crashes | no persistent system state left broken; `OSDUIHelper` recovery per §7 |
| Screen params change | geometry recomputed; island repositioned |
| Lid closed / clamshell | island hidden entirely |

---

## 10. Testing strategy

The one-directional data flow is what makes this testable: the logic lives in
modules that never touch AppKit.

### Unit tests (Swift Testing) — no private APIs, no UI

- **`NotchGeometry`** — fed a fake screen (frame, `safeAreaInsets`, aux areas) →
  correct notch rect. Table-driven across scaling modes, notch-less displays
  (must yield no island, not a guessed rect), and clamshell (hidden).
- **`ActivityQueue`** — priority ordering, coalescing by kind, TTL expiry, the
  two-slot cap and `+N` pip, sticky media never expiring, hover suppressing
  expiry. Deterministic via injected clock. **This is where bugs will actually
  live.**
- **`NotchController`** — every transition, including: activity arriving while
  expanded, hover leaving mid-collapse, two activities expiring on the same tick,
  escape during a morph.
- **`NotchShape`** — at `p = 0` the path equals the measured notch rect; width and
  height monotonic in `p`; fillet never negative; `animatableData` round-trips.
- **Every parser, separated from its transport** — recorded NDJSON fixtures from
  the media adapter (including malformed lines, missing artwork, rate changes),
  `system_profiler` JSON, notification DB rows. This is how the fragile modules
  get tested without the fragile thing being present.
- **Layout assertion** — no content rect intersects the notch rect.

### Integration tests — real window

Construct the actual `NSPanel` and assert `level`, `collectionBehavior`, frame,
and — the important one — that `hitTest` returns `nil` outside the island path and
non-`nil` inside. Click-through breaks silently and is maddening to notice by
hand.

### Manual checks — `docs/manual-checks.md`

Animation feel; OSD suppression actually suppressing and restoring; lock-screen
rendering; TCC grants surviving a rebuild; behaviour on scaling change.

### TDD scope

TDD applies to `ActivityQueue`, `NotchController`, `NotchGeometry`, and all
parsers. It does not apply to the spring curve, which is tuned by eye via
`make dev`.

---

## 11. Build and run

SwiftPM plus a Makefile. No Xcode project: everything is plain text, module
boundaries are enforced by the compiler, and there is no `pbxproj` to corrupt.
Trade-off accepted: no SwiftUI previews.

```
make cert      one-time: create self-signed code-signing identity in login keychain
make dev       debug build → assemble bundle → sign → relaunch   (the tuning loop)
make           release build
make install   copy to /Applications
make test      swift test
```

Bundle assembly: `Info.plist` with `LSUIElement = true` and a stable bundle id;
`MediaRemoteAdapter.framework` and the perl shim embedded in `Contents/Resources`;
`codesign` with the self-signed identity.

**Why the self-signed certificate matters.** macOS binds TCC grants to the app's
designated code requirement. Ad-hoc signing (`codesign -s -`) derives that from
the binary hash, so every rebuild looks like a new app and Full Disk Access would
need re-granting constantly. A stable self-signed identity makes grants persist
across rebuilds. Five minutes of setup, once.

---

## 12. Build sequence

Ordered so the app is usable early and the fragile work lands last, isolated.

| Phase | Deliverable | Risk |
| --- | --- | --- |
| 0 | Skeleton: SwiftPM, Makefile, cert, bundle, agent app that launches and quits | none |
| 1 | **NotchKit**: window, geometry, hit testing, shape, controller, springs. An island that hovers, clicks and morphs with no data behind it | none |
| 2 | **ActivityKit + PowerService**: charging activity end to end. Proves the whole pipeline with the lowest-risk data source | none |
| 3 | **HUDService**: volume, brightness, OSD suppression. First real daily value | low |
| 4 | **MediaService**: now-playing and controls. The big one | medium |
| 5 | **DeviceService**: AirPods and output switching | low |
| 6 | **Settings** UI, per-service status rows, polish pass | none |
| 7 | **NotificationService** | high |
| 8 | **LockScreenService** | high |

**Usable daily driver at the end of Phase 4.** Phases 7 and 8 are additive and
individually droppable.

### Plan decomposition

This spec is too large for one implementation plan. It drives **one plan covering
Phases 0–4** — the shell plus the three low-risk services that make the app worth
launching. Phases 5–8 each get their own plan written against this same spec, so
the fragile work is scoped, reviewed and abandoned independently if it proves
unworkable.

---

## 13. Open risks

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| Apple revokes `/usr/bin/perl` entitlement | low, high impact | ScriptingBridge fallback (§7) |
| `DisplayServices` brightness notifications unreliable | medium | `CGEventTap` fallback, costs one permission |
| `OSDUIHelper` behaviour changes | low | feature toggle; both HUDs visible is the degraded state |
| Notification DB schema or access changes | medium | AX fallback; service is droppable |
| Lock-screen presence not achievable at shielding level | medium | display-only scope already assumed; droppable |
| Motion feel wrong once on real hardware | medium | `make dev` loop; springs are two numbers in one file |

---

## 14. Decision log

| Decision | Chosen | Rejected |
| --- | --- | --- |
| What to build | Free equivalent of Alcove | Camera mirror, iPhone Mirroring, AirPlay control |
| Audience | Personal daily driver | Public release, learning project, portfolio piece |
| v1 features | All four: media+HUD, battery/device, notifications, lock screen | — |
| Interaction | Dynamic Island: invisible idle, events morph out, **hover to expand** (changed 2026-09-28 from click; click now pins) | Always-on island, event-only, click-to-expand |
| Approach | Own shell, vendor plumbing | Everything from scratch; fork Boring Notch |
| Build | SwiftPM + Makefile | Xcode project; hybrid |
| Shape | Flush with inverted corners | Floating card; notch-hugging capsule |
| Motion | `0.35 / 0.72` expand, `0.30 / 0.92` collapse | Snappy `0.26/1.0`; bouncy `0.48/0.52`; gentle `0.58/0.88` |
| Layout | Ears first, grow down when crowded | Ears only; always-a-row-below |
| Name | Ledge | Alco, Alcova, Perch |
