# Private API notes

Every private symbol Ledge touches, why, and what breaks if Apple removes it.

## DisplayServices (`/System/Library/PrivateFrameworks/DisplayServices.framework`)

Loaded with `dlopen` + `dlsym`. Never linked. Note: on this OS release the
framework has no standalone file on disk (`nm`/`otool` on the path both fail
with "No such file or directory" — it lives only in the dyld shared cache),
but `dlopen` still resolves it through the shared-cache shim, exactly as the
task brief's verified facts said.

| Symbol | Signature | Verified | Used for |
| --- | --- | --- | --- |
| `DisplayServicesGetBrightness` | `(CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32` | ✅ 2026-09-25, rc=0, value 0…1 (confirmed again via `bridgeLoadsAndReadsARealBrightnessValue`, and repeatedly during the Step 5 spike below) | reading brightness |
| `DisplayServicesRegisterForBrightnessChangeNotifications` | undocumented | ⚠️ 2026-09-25 — registers cleanly (rc=0) and the callback reliably fires, but see **Step 5 spike** below: not adopted | change notifications |
| `DisplayServicesCanChangeBrightness` | undocumented | resolves only, not used |  |
| `DisplayServicesSetBrightness` | `(CGDirectDisplayID, Float) -> Int32` | ✅ resolves and works (used only in the throwaway Step 5 probe, never shipped — Ledge never *sets* brightness) | not used in shipped code |

**If removed:** `DisplayServicesBridge.init?` returns nil, `BrightnessObserver`
reports `.unavailable`, the brightness HUD disappears, and everything else
keeps working. No crash, no alert.

**Backend actually in use: polling**, at `BrightnessObserver.pollInterval`
(0.1s / 10 Hz), one C call per tick.

### Step 5 spike — notification callback signature

The task brief gives this candidate signature to try:

```swift
typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UInt32, CFString?, Double) -> Void
typealias Register = @convention(c) (CGDirectDisplayID, UnsafeMutableRawPointer?, Callback) -> Int32
```

This environment has no physical key-press access (unattended CLI agent, no
Accessibility/Input Monitoring grant, no GUI automation) to drive brightness
keys the way the brief's manual procedure assumes. Substituted: drive
brightness changes programmatically via `DisplayServicesSetBrightness`
(resolves via `dlsym`; confirmed working), oscillating around the original
value and restoring it afterward, while a registered callback listens. This
tests exactly the thing Step 5 needs — does the notification path fire and
with what payload — without needing hardware input.

**Run 1 — brief's literal signature.** `register` returned `rc=0`. The
callback **fired reliably, 1:1 with every `SetBrightness` call** (6/6, plus
one more delivered asynchronously after the run loop's explicit wait window
closed — delivery is not strictly synchronous with the call that triggered
it). But the payload was not usable:
- `value: Double` read as denormalized garbage (`~2.5e-312`), not a
  brightness in `0...1`.
- `display: UInt32` read as `0` — CGMainDisplayID() on this machine is
  actually `1`.

**Run 2 — corrected minimal-assumption signature**, after the garbage/zero
readings suggested a 4-parameter guess was wrong:

```swift
typealias Callback2 = @convention(c) (CGDirectDisplayID, UnsafeMutableRawPointer?) -> Void
```

i.e. no pushed name or value at all — just an identifier and the context
pointer, requiring the caller to re-read brightness itself on any fire. This
run:
- `register` again returned `rc=0`; the callback fired 1:1 with every
  `SetBrightness` call (4/4, plus one more delivered async after the wait
  window, same pattern as run 1).
- The context pointer **round-trips correctly** — a live object reference
  passed in survived through the C trampoline and read back valid on every
  call. This is a real positive signal: it means at least this parameter's
  position/type in the real ABI matches the hypothesis.
- The first parameter still printed `0`, and `CGMainDisplayID()` on this
  machine is `1` — calling `DisplayServicesGetBrightness` with the callback's
  reported "display" value (`0`) failed (no valid value written). So `0` is
  either a different internal display-indexing scheme than `CGDirectDisplayID`
  (plausible — Apple's private display APIs sometimes use a zero-based
  ordinal internally), or this parameter isn't a display identifier in that
  position at all. No way to tell which without disassembly, which is out of
  scope for a spike.

**Decision — per the brief's rule, applied by its spirit and not just its
letter:** the rule requires "`CALLBACK FIRED` lines appear with plausible
values" to proceed to Step 6. Run 1, using the brief's own suggested
signature, produced values that were not plausible (garbage double, a display
id that doesn't match the real one under the obvious interpretation). Run 2
firmed up confidence that the dispatch mechanism and context handling are
correct, but left the meaning of the leading identifier genuinely ambiguous —
and, per the task's own instruction ("the polling fallback ... is a correct
and acceptable permanent answer; do not contort the code to avoid it"),
ambiguity here is not worth resolving further by guessing at more candidate
signatures. **Skipped Step 6.** `BrightnessObserver` never attempts
registration (`start()` calls `Self.backend(canRegister: false, canRead:)`
unconditionally) and polls at 10 Hz instead, which is correct, simple, and
costs one C call per 100ms.

If a future task wants to revisit this: the promising thread is the 2-arg
`(identifier, context)` hypothesis, worth confirming by comparing the
"identifier" value across a real multi-display setup rather than guessing
further on a single-display machine, or by disassembling
`DisplayServicesRegisterForBrightnessChangeNotifications`'s call site inside
`OSDUIHelper` or `ControlCenter` to read the real trampoline shape.

## OSDUIHelper

See `Sources/HUDService/OSDSuppressor.swift`. Bundle id `com.apple.OSDUIHelper`,
a `gui/<uid>` LaunchAgent, **not resident** — launches on demand. **On macOS
27.0 it does not draw the volume/brightness pill at all** (see next section);
the suppressor is kept only because it is harmless.

## MenuBarAgent (macOS 27.0) — the real owner of the volume/brightness pill

Measured 2026-09-28 with a `CGWindowListCopyWindowInfo` diff taken while a
volume key was pressed: the only new on-screen window was
`owner=MenuBarAgent pid=678 layer=101 bounds=1128,33 352x152` — the pill under
the Sound menu bar item. `MenuBarAgent` (`/System/Library/CoreServices/
MenuBarAgent.app`, bundle id `com.apple.MenuBarAgent`, `KeepAlive` LaunchAgent,
links `MenuBarClient`/`MenuBarClientCore`/`ControlCenter`) owns exactly one
other window: the 1470×33 menu bar itself, at layer 24. So it cannot be
SIGSTOPped the way `OSDUIHelper` is. Ice (#719) and BetterDisplay (#4726) both
"lose" this pill as side effects — Ice by hiding the Sound status item the
popover anchors to, BetterDisplay by consuming the volume keys with an event
tap. Ledge uses the latter: `Sources/HUDService/MediaKeyInterceptor.swift`.

Media-key event layout (unchanged for decades, still true here): `NSEvent`
type `.systemDefined` (14), subtype 8, `data1 >> 16` = `NX_KEYTYPE_*` (0 sound
up, 1 sound down, 2 brightness up, 3 brightness down, 7 mute), `(data1 & 0xFF00)
>> 8` = `0x0A` down / `0x0B` up, `data1 & 1` = auto-repeat.

`DisplayServicesSetBrightness(CGDirectDisplayID, float) -> int` resolves from the
same private framework `DisplayServicesGetBrightness` does.

## MediaRemote

Not touched directly. Reached only through the vendored `mediaremote-adapter`,
which loads it inside `/usr/bin/perl` (bundle id `com.apple.perl`).

## HeadphoneAssets.framework — AirPods product renders (macOS 27.0)

`/System/Library/PrivateFrameworks/HeadphoneAssets.framework/Versions/A/Resources/`
holds the photo-real renders System Settings' headphone panes use, as plain
996×702 transparent PNGs inside `*.ca` bundles (Core Animation archives):

| Model code | Product | File |
| --- | --- | --- |
| B788 | AirPods Pro 3 | `B788_Translate.ca/assets/AirPodsPro1-3_translate.png` |
| B698 | AirPods Pro 2 | `B698_Translate.ca/assets/AirPodsPro1-2_translator_996x702.png` |
| B768 | AirPods 4 | `B768_Translate.ca/assets/AirPods1-4_translator_996x702.png` |
| B868 | AirPods 3 | `B868_Translate.ca/assets/Airpods3-7_CL-0_Translate.png` |
| B515d | AirPods Max | `B515d-Translate-CL{18..22}.ca/assets/AirPodsMax1-2_CL-{n}_Translate_v14.png` (CL-18 black, CL-20 blue, CL-22 purple) |

Also `IOBluetoothUI.framework/Resources/AirPods.png` (64px, the old menu icon).
No Beats render was found. `DeviceArtwork` reads these by path; the test
`theRendersExistOnThisSystem` fails loudly when an OS update moves them.

## Clock timers and stopwatches: `com.apple.mobiletimerd` (2026-09-29, macOS 27)

macOS runs the same `mobiletimerd` as iOS (`/System/Library/PrivateFrameworks/
MobileTimer.framework/Executables/mobiletimerd`). The Clock app's timers and
stopwatches live in its preference domain, written through cfprefsd on every
change (`MTTimerModifiedDate` moves at once). Read with
`CFPreferencesCopyMultiple(nil, "com.apple.mobiletimerd", CurrentUser, AnyHost)`
after `CFPreferencesAppSynchronize`; no change notification name was found,
so the app polls once a second (`ClockTimerObserver`).

Layout observed:

- `MTTimers.MTTimers[]` → `$MTTimer` with `MTTimerID`, `MTTimerTitle`
  (`""` or `"CURRENT_TIMER"` for the Clock's own placeholders), `MTTimerDuration`
  (seconds), `MTTimerState` (1 idle preset, 3 running; 2 paused is inferred and
  logged if it turns out otherwise), `MTTimerFireTime`: `$MTTimerDate` →
  `MTTimerTimeDate` (absolute fire date) while running, `$MTTimerTimeInterval`
  → `MTTimerTimeInterval` otherwise. `MTTimerFireTimerClass` names which. A
  fired timer stays state 3 with its fire date in the past until dismissed.
- `MTStopwatches.MTStopwatches[]` → `$MTStopwatch` with `MTStopwatchIdentifier`,
  `MTStopwatchState` (0 reset, 1 stopped), `MTStopwatchOffset`, `MTStopwatchCurrentInterval`,
  `MTStopwatchLaps`, `MTStopwatchPreviousLapsTotalInterval`. A RUNNING stopwatch
  has not been observed yet; the parser takes the first `Date` in the record as
  the run's start and logs the keys of any running record it cannot read.
- `MTTimerStorageMigratedToCoreData` is true, but the daemon's group container
  is empty and the plist keeps being updated, so the plist is what there is.
- URL schemes registered by Clock.app: `clock-timer://`, `clock-stopwatch://`.

## iPhone Live Activities on the Mac (2026-09-29, macOS 27)

`liveactivitiesd` (`SessionCore.framework/Support`) receives them; its known
clients are `MenuBarAgent`, Control Center, `chronod` and its
`WidgetRenderer-Activities`. Nothing is persisted: the daemon's group container
is empty and chronod caches no renders. Control Center's `LiveActivityState`
(JSON in `com.apple.controlcenter`) reports `CompanionPaired` — false on this
Mac at the time, so no activity could be observed.

The only readable surface is Accessibility: `MenuBarAgent`'s
`AXExtrasMenuBar` lists every system extra as `AXGroup` (`AXHostingView`) →
`AXMenuBarItem` (`AXMenuExtra`) with `AXIdentifier` (`com.apple.menuextra.*`),
`AXDescription`, `AXValue` and `AXFrame`; Control Center itself exposes no
extras bar (-25212). `ledge://probe/menubar` dumps the tree to the log
(`MenuBarProbe`) so a live activity's shape can be learned once one shows.

**Observed (2026-10-01, phone paired).** The pill is an `AXMenuBarItem`
directly under `MenuBarAgent`'s extras bar, identifier
`live-activity-pill-com.apple.chrono.WidgetRenderer-Activities`, description
"Live Activity", frame 46×24 pt at y=4. Its subtree is two 3×33 `AXGroup`
(`AXHostingView`) children and, at times, an `AXImage` described "Expanded"
(47×27) — no text, no value, seven levels deep. The activity's content is not
readable through Accessibility at all; Control Center's `CompanionPaired` was
still false while the pill showed, so that flag is stale too. Menu bar
extras are not separate windows on macOS 27 (`CGWindowListCopyWindowInfo`
lists one Window Server "Menubar" window, 1470×33), so the pill cannot be
captured as a window either.

**What works: pixels.** `LiveActivityService` finds the pill through
Accessibility once a second (`PillLocator`) and, with the Screen Recording
grant, screenshots exactly its rectangle of the display through
ScreenCaptureKit twice a second (`PillCapture`: `SCScreenshotManager` with
`SCContentFilter(display:excludingApplications:)`, this app excluded,
`sourceRect` = the AX frame relative to the display, width and height at the
screen's scale). Not an `SCStream`: tried live, a stream plants the purple
screen-recording capsule (and a window glyph) in the menu bar for as long as
it runs, which shifts the pill ~85 pt left under the capture; single
screenshots only light the privacy dot in the corner (observed 2026-10-01,
same for `screencapture`). Each changed frame is PNG-encoded and published as the record's
`mirror`; the island draws it at the pill's point size, capsule-clipped so the
menu bar's material around the pill stays out. The two hosting groups are the pill's
compact slots — the leading and trailing views the phone's island splits
around its camera — so when Accessibility reports them, the keyed capture is
sliced at their frames and each slice goes to its own ear, left and right of
the notch (a home team's crest and score left, the away team's right); the
whole pill goes to the trailing ear only when no slots are reported. Observed
2026-10-01 with a third-party activity running: both slots stayed 3 pt wide
and the pill blank — the Mac drew nothing for it, so there was nothing to
mirror; the island shows the phone glyph alone then. A click performs
`AXPress` on the item, and the system opens its own expanded view under the
menu bar. The
first time a pill is seen without the grant, `CGRequestScreenCaptureAccess`
asks once; the grant takes effect for a new process, so relaunch after it.

**The card, and how it is read (2026-10-01, final).** Pressing the pill makes
`MenuBarAgent` a window `live-activity-expanded` (~408×960 pt hanging from the
pill, the card drawn in its top ~122 pt) and the next press destroys it;
nothing exists while it is closed. Its Accessibility tree carries everything
the activity says as text: for a football match, `AXImage` per crest
(description = the team), `AXStaticText` for each figure, and below them the
team names, the period ("HT") and a running clock ("5:56"); for a golf round,
two lines and no sides. The content lives in whichever `AXHostingView` child
actually has children, whose frame is the card's own origin, so every
element's rectangle can be taken relative to it — that is how the crests are
cut exactly instead of guessed at by fractions.

Two things make this live rather than a snapshot. The window's `AXPosition` is
writable, so the card can be moved far off every screen; and it keeps
answering Accessibility there, with its figures and clock updating, for as
long as it is open (checked over twelve seconds). So `LiveActivityService`
presses once, takes a single `SCScreenshotManager` picture for the crests
while the card is still where the system put it, parks the window at
(12000, -8000) and then just reads it once a second. One brief flash when an
activity arrives, nothing after that, and a score that keeps up by itself.
A click on the island moves the card back under the pill for eight seconds.
The window is put back and pressed closed when the activity ends or the app
quits; an already-open card (after a crash or relaunch) is adopted instead of
pressed again. Note the pill shows its collapse chevron the whole time the card is held open.

**The pill itself cannot be moved (2026-10-03).** `AXPosition` on the
`AXMenuBarItem` reports success and the pill does not budge — but writing it
once a second, as an attempt to hide the pill did, dismissed the card over and
over: closes went from one every 20-90 s to one every 1-3 s, and each reopen
shows the card for the blink it takes to park it. Do not write to the pill.
Turning it off at the system level (`RemoteLiveActivitiesEnabled` in
`com.apple.controlcenter`) is not an option either: the pill is what opens the
card, so without it there is nothing to read. The pill stays in the menu bar.

The card's position is read before it is moved, and it is only moved when it
is not already parked: writing a position a thing already has is what made the
pill fight the island. If the card is found on screen when the island did not
put it there, the user pressed the pill, and it is left where it is for eight
seconds — before that, every press of the pill was undone within the second
and the pill looked dead (2026-10-05).

Note also that the pill's own compact view is drawn by the activity's app, and
for an app the Mac cannot render it is simply an empty capsule — brightened
captures show nothing inside it, and it was already empty before this app ever
touched it. That is not something the island can fix, and the pill cannot be
moved or hidden.

**Presses are rationed (2026-10-05, final).** Any click anywhere dismisses the
card, so it is dismissed constantly in normal use, and every reopen shows it
for the blink it takes to park — which is what the pill's "random glitch"
was. Reopening at once, however gently backed off, could not fix that: the
cure is to stop reopening. After a dismissal the island keeps what it last
read and leaves the menu bar alone for ninety seconds; a press that brings
nothing up waits twenty. A rest on the island asks for a fresh reading right
away, once per rest, which is the one moment the user is looking at the
activity rather than the menu bar. The once-a-second poll is the only thing
that ever presses the pill, and it checks that gate first.

So the figures are live while the card happens to be open, and as of the last
reading otherwise, with a rest on the island always bringing them up to date. The window is looked for every 8 ms while it comes up, so it is parked
as soon as it exists.

Pixels are still needed for the crests only, and cannot be taken off-screen:
`SCScreenshotManager` fails for a window that is not on screen, and
`CGWindowListCreateImage` is gone in macOS 27.

## Focus state (2026-09-29)

`~/Library/DoNotDisturb/DB/{Assertions,ModeConfigurations}.json` are behind
Full Disk Access ("Operation not permitted" without it). Read the menu bar
instead: Control Center's Focus extra (`NSStatusItem VisibleCC FocusModes`,
identifier expected `com.apple.menuextra.focusmodes`) appears in
`MenuBarAgent`'s `AXExtrasMenuBar` while a Focus is on; its value/description
carries the mode's name. Exact text not yet observed — `FocusState.name(from:)`
strips a leading "Focus" and trailing ", on".

**Update 2026-09-30.** No Focus item ever appeared in `MenuBarAgent`'s tree on
this Mac while a Focus was on, and no distributed notification fired. What IS
readable without Full Disk Access is the metadata of
`~/Library/DoNotDisturb/DB/Assertions.json` (`stat` succeeds; `open` does not).
The file is rewritten on every toggle: ~1270 bytes with no assertion, ~1900
with one (each record ~630 bytes; a switch between Focuses rewrites at ±2
bytes). `FocusService` polls its size once a second; `FocusSizeDeriver` turns
a jump of ≥300 bytes up into "on", down into "off". The Focus's name is not
available this way.

**With Full Disk Access (2026-09-30).** `Assertions.json`:
`data[].storeAssertionRecords[].assertionDetails.assertionDetailsModeIdentifier`
names the active Focus. `ModeConfigurations.json`:
`data[].modeConfigurations[<id>].mode.{name,symbolImageName,tintColorName}`;
tint names are Apple's ("systemIndigoColor"), mapped in `NotchKit.SystemTint`.
Parsed defensively (`FocusDatabase`); layout not yet observed on this Mac
because the grant was pending when written — the first read logs "database
readable" and any missing field simply yields the moon or white.

## Peripheral battery, per component (2026-09-30)

`AppleDeviceManagementHIDEventService` entries (IO registry, no permission):
`Product`, `BatteryPercent` (or `BatteryPercentMain`), and for AirPods/Beats
buds `BatteryPercentLeft`, `BatteryPercentRight`, `BatteryPercentCase`; values
outside 0…100 mean unknown. Read with `IORegistryEntryCreateCFProperties`.
Other headsets: `system_profiler SPBluetoothDataType -json` →
`SPBluetoothDataType[].device_connected[] / device_not_connected[]`, each a
`{name: props}` with `device_batteryLevelMain/Left/Right/Case` as "85%" strings
and `device_minorType` ("Headphones", "Headset", "Speaker"). Observed on this
Mac with no buds connected; the per-component keys are as documented
elsewhere and parsed defensively. The AirPods renders in
`HeadphoneAssets.framework` are no longer used.

## Lock screen: closed (2026-10-01, final)

Tried live on macOS 27, all invisible under the lock screen: window levels
1000 / 2005 / 3000 / `CGShieldingWindowLevel() + 1`, and
`canBecomeVisibleWithoutLogin = true` with the shield level. loginwindow's
lock UI is composited above every window of the user session. The island is
hidden while locked and restored on unlock; do not try again without a new
API.
