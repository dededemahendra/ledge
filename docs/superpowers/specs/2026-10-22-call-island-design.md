# Calls on the island — design

2026-10-22. The user picked "call in progress" from a list of next features.
They approved the behaviour as played back in chat. Calls marked *(my call)*
are mine, not the user's.

## Goal

While the user is on a call in any app, the island says so: which app, how long,
and whether the mic is muted. A mute button is one hover away. This works the
same for Zoom, FaceTime, Teams, Discord, Slack huddles and Meet in a browser.
It needs no permission and no per-app support.

## Decisions (user's, 2026-10-22)

| Question | Decision |
| --- | --- |
| What counts as a call | Any app using the microphone for more than a moment. The short wait skips Siri and dictation |
| The island during a call | The calling app's own icon left, the call's running time right in green ("12:04"), counting up like the iPhone's call pill. Stays while the mic is on |
| Order | Above music and Clock timers; volume, battery and the other short blips still pass over it for their few seconds |
| Muted | The left glyph turns into a red crossed-out mic |
| Hover | A card: the app's icon and name, the clock, one big mute button. The button mutes the mic for every app, not the call app's own mute |
| Click | Brings the call app to the front |
| End | A 3 s "ended" moment with the call's length, then the island goes |
| Settings | A "Calls" switch in Settings › Island, on by default |
| An app that holds the mic but isn't a call (Voice Memos, OBS, a forgotten browser tab) | A "Not a call" button on the card hides the pill for that app from then on; hidden apps are listed under Settings › Island, where they can be brought back |
| Not in scope | Incoming calls, caller names, answer or decline (no public API; it would mean watching the system's call banner) |

## How Ledge knows

A new `CallService` library, built like the other services: a thin CoreAudio
shell on the main actor, with the judgement in pure, testable parts.

**Who holds the mic.** CoreAudio's process objects list every process using
audio (`kAudioHardwarePropertyProcessObjectList` on the system object). For
each one it reports `kAudioProcessPropertyPID`, `kAudioProcessPropertyBundleID`
and `kAudioProcessPropertyIsRunningInput`. Ledge listens for changes to the
list and to each process's `IsRunningInput`, and reads the set of PIDs that
hold the mic. It does not poll.

**Which app that is** *(my call)*. A holder counts only when it resolves to a
regular app (`NSRunningApplication.activationPolicy == .regular`):

- If the holder is a regular app itself, that's the app.
- Otherwise, ask macOS which process is responsible for it
  (`responsibility_get_pid_responsible_for_pid`, the private call Activity
  Monitor relies on; the app already uses private SkyLight and MediaRemote).
  Safari's WebKit processes are launchd's children, not Safari's, so walking
  parents alone would miss them.
- Failing that, walk up its parent processes until a regular app is found
  (Chrome's and Electron's helpers are their app's children). That makes Meet
  in Safari or Chrome show the browser, and a Slack huddle show Slack.
- Anything that never reaches a regular app is ignored. That covers system
  daemons (Siri, dictation, `corespeechd`), menu-bar apps (dictation tools,
  noise filters that hold the mic all day) and command-line tools.
- Ledge itself is always ignored.
- So is any app the user has marked "Not a call", matched by the resolved
  app's bundle id. Because a browser is matched as a whole, hiding Chrome for a
  forgotten tab also hides Meet in Chrome. The Settings list is where to bring
  it back *(my call; there is no per-tab identity to match on)*.

**No guessing without the process list** *(my call)*. A device-level "running
somewhere" check can't tell a call from Siri or dictation. So if the process
list can't be read, the service is unavailable rather than guessing. It
reports why, and Settings › Permissions lists it like any other service that
can't run.

**Timing** *(my call)*. A call starts once a counted app has held the mic for
2 s. It ends once no counted app has held it for 2 s, so a device switch
mid-call (AirPods connecting) doesn't end the call or restart the clock. The
clock counts from the moment the mic was first taken, not from the end of the
2 s wait.

**Several apps at once** *(my call)*. The call lasts while any counted app holds
the mic. The app shown is the earliest one still holding it. If it lets go and
another still holds, the island switches to that app and the clock keeps
running.

**Mute.** "Muted" means the system's input mute. Ledge mutes every input device
that is running at that moment, and any that starts running while muted (so a
call app that uses a non-default mic is still muted).

- Each device gets `kAudioDevicePropertyMute` on the input scope where it can be
  set.
- Where it can't, the input volume scalar goes to 0, and the earlier value is
  kept to restore later.
- If a device supports neither, the card's button is disabled with "This mic
  can't be muted from here".

The muted state shown on the island is read back from the devices, so a mute
made elsewhere (System Settings, a keyboard's mute key) shows too.

**The button and other people's mutes** *(my call)*. The button follows what it
shows:

- Pressed while unmuted, it mutes, and Ledge records what it changed.
- Pressed while muted, it unmutes every running input device, whoever muted it:
  someone pressing unmute on a call wants to be heard.

Ending the call restores only what Ledge changed and leaves a mute the user set
elsewhere alone.

**Unmute on the way out** *(my call)*. When the call ends, or Ledge quits, every
device Ledge muted is restored. Otherwise a system-wide mute left behind would
silently break the user's next call.

A crash, a force quit or a relaunch skips that. So the record of what Ledge
changed is saved as it changes: each device's UID, and whether Ledge set mute
or set volume to 0 (with the volume to put back). On the next launch, each
device still in exactly the state Ledge left it is restored, and the record is
cleared. A device the user has changed since is left as it is.

## What the user sees

New `ActivityKind.call`: sticky (`ttl: nil`) while the call runs, at priority 30
*(my call)*. That sits under the update notice (35) and over a Clock timer (20),
so every blip passes over it and it outranks timers, GitHub runs, Live
Activities, music and charging. The record id is `"call"`.

| Moment | Leading ear | Trailing ear | Click |
| --- | --- | --- | --- |
| Call running | the app's icon at the ear's glyph size, decoded once | running time in green (`.positive`), `TimerText.format`: "m:ss", then "h:mm" from an hour; ticks without the value bump, like the Clock timer | brings the app forward |
| Call running, muted | red `mic.slash.fill` in place of the icon | running time, still green | brings the app forward |
| Ended, 3 s | red `phone.down.fill` | the call's final length in white, still | nothing |

- **The ended moment** re-inserts the same kind with `ttl: 3`, replacing the
  sticky record. Because the id is the same, it stays in the same ear slot: the
  glyph swaps in place and the island pulses once, with no pop-in *(my call)*.
  The chat wording was "Ended · 12:04". The red hang-up glyph with the frozen
  length says the same in the island's wordless idiom, without adding a caption
  line *(my call)*. If a higher blip covers those 3 s, the ended moment is
  simply missed, like any other blip. Switching Calls off mid-call removes the
  pill at once, with no ended moment *(my call)*.
- **Ticking** follows the GitHub running item: a stable start date, a record
  republished only when the displayed text changes, and the call's id added to
  the trailing ear's `isTicking` check.
- **Click** uses an internal stand-in URL (`ledge://call`) routed in
  `AppModel.open(_:)`. It activates the app by bundle id through
  LaunchServices, falling back to the PID, the way `openSourceApp()` does for
  music. That code is generalised to take either.

**The card.** A new `Panel.call`, opened by hovering while the call leads, like
the GitHub panel. It contains:

- the app's icon and name (a click brings the app forward);
- the running time, large;
- one round mute button: a mic, or a red crossed-out mic when muted;
- the input device's name in small type ("MacBook Pro Microphone"), or "2
  mics" when several are running;
- a quiet text button, "Not a call", at the foot (user's decision).

"Not a call" adds the app to the hidden list. The pill goes at once, with no
ended moment, and any mute Ledge applied is restored. If another counted app
still holds the mic, the call carries on with that app and the clock keeps
running *(my call)*. It sends a new `NotchIntent.hideCallApp`, which, like
every intent, does nothing while locked.

The data goes in as a pure value (`CallPanelData` in NotchKit), and the mute
button sends a new `NotchIntent.toggleMute`. The card uses the standard expanded width.
A shorter card than the others is the builder's call if `NotchMetrics` can take
a per-panel height without disturbing the rest; otherwise it uses the standard
size.

**Lock screen** *(my call)*. The call pill shows over the lock screen like music
does. It shows only an app icon and a time. The card opens look-only, and the
mute button does nothing while locked, which the controller already enforces
for every intent.

## Settings

- `AppSettings.showsCalls`, on by default.
- A row in Settings › Island under "What happens on the Mac": "Calls", detail
  "The app and how long, while the mic is on".
- A preview scene, `PreviewScene.call`: FaceTime's icon if it can be found,
  else the green mic, at "12:04".
- Turning the switch off removes the kind at once (in `applySettings`) and
  restores any mute Ledge applied.
- `AppSettings.hiddenCallApps`, a list of bundle ids, empty by default.
- Under the Calls row, a "Not calls" list: each hidden app's icon and name,
  with a remove button that brings it back. The list shows only when it has
  something in it. Removing an app that holds the mic right now lets its call
  show at once, with the clock counting from when it took the mic *(my call)*.

## Building blocks

| Unit | Job |
| --- | --- |
| `MicHolders` (CoreAudio shell) | Listens to the process list and each process's `IsRunningInput`; reports the PIDs holding the mic, or that the list can't be read |
| `CallApp` | Resolves a PID to the app to show: the regular app itself, else its responsible process, else its nearest regular ancestor; else nil. The process lookups are injected so it can be tested |
| `CallTracker` (pure) | Fed `(now, [holder], hidden bundle ids)`, returns the call state: idle / starting / live(app, since) / ending / ended(app, length). It owns the 2 s grace in both directions, the several-apps rule, and hiding (no ended moment). The clock is injected |
| `InputMute` (CoreAudio shell, pure planner) | Mutes and unmutes the running input devices: mute where settable, else volume 0, remembering (and saving) what to restore; restores a saved record on launch; reports the muted state and whether muting is possible |
| `CallService` | Ties these together; `start() -> AsyncStream<CallEvent>`, `setMuted(_:)`, `availability` |

The app is wired the same way as the other services:

- a `refreshCall()` call in the 0.25 s tick for the clock;
- a line in `evictUnavailableServices`;
- the card data published like `publishGitHubPanel`.

There are no logs of app names or call times, in keeping with how the media
handler treats listening history.

## Tests

- `CallTracker`:
  - a hold under 2 s is no call;
  - the 2 s start, with the clock counting from the first take;
  - a 1 s drop mid-call keeps the call and the clock;
  - a 2 s drop ends it with the right length;
  - two apps, where the first leaving hands over without a restart;
  - hiding the shown app ends the call with no ended moment, or hands over
    to another holder;
  - unhiding an app mid-hold shows its call counting from its first take.
- `CallApp`: a regular app; a WebKit-style helper resolved through its
  responsible process; a helper whose parent is a regular app; a daemon with no
  regular ancestor (nil); Ledge's own PID (nil).
- The `InputMute` planner:
  - mutable, volume-only and neither devices;
  - restore puts back exactly what was changed;
  - a device that starts while muted gets muted;
  - unmute clears an outside mute, but ending the call doesn't;
  - a saved record restores only devices still in Ledge's state.
- `ActivityQueue`: the call's priority sits between update and timer, and every
  priority stays distinct.
- `NotchController`: hovering while the call leads opens `.call`; the panel
  goes with its data; `toggleMute` and `hideCallApp` are dropped while locked.
- Settings: the new switch defaults on; the hidden list starts empty and
  saves; the new scene shows something and is captioned.

## Docs

- A README row: "On a call in any app (the mic in use) | the app's icon left,
  the time right in green, the red crossed-out mic when muted; rest the cursor
  for a card with a mute button and "Not a call"; a red hang-up and the length
  for 3 s when it ends".
- The priority table in the notch companion spec.
- A pending list in `docs/manual-checks.md`: a Zoom or FaceTime call; Meet in
  Chrome; muting from the card and from System Settings; AirPods connecting
  mid-call; locking during a call; the switch off mid-call; "Not a call" on
  Voice Memos, and bringing it back from Settings.

## Not in scope, and what would make this a failure

- **Not in scope:** incoming calls; caller names; answering, declining or ending
  a call; a mute keyboard shortcut; a camera indicator (a separate item on the
  user's list).
- **Failures even if it technically works:**
  - the pill sitting on the island permanently because some app holds the mic
    all day;
  - a mute Ledge applied surviving the call;
  - Siri or dictation flashing a call;
  - any permission prompt.

## Verify first

Before building on it, check on this Mac that reading the process objects and
setting input mute need no permission prompt and don't light the system's
orange mic dot themselves. Also check that Meet in Safari and in Chrome, and a
FaceTime call, resolve to their apps. If any of these fails, stop and report to
the user before building further. The design rests on them.

## Left to the builder

- Exact sizes and layout inside the card.
- Animation details, within the existing ear transitions and pulse.
- The names of internal types and files, beyond those above.
- How parent processes are walked (`proc_pidinfo` or `sysctl`).
