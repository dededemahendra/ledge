# Island on the lock screen — design

2026-10-21. Reopens "LockScreenService — fragile, built last" (§7 of
`2026-09-25-notch-companion-design.md`), parked 2026-09-28 and marked closed in
`docs/private-api-notes.md` on 2026-10-01: no window level drew over macOS 27's
lock screen.

## Goal

The island shows on the lock screen as it does on the desktop, on a MacBook's
notch and on the pill alike, for looking at only. Nothing on the locked island
can be operated.

## What the probe found (2026-10-21)

A throwaway probe (not in the repo) moved a borderless panel into a private
window-server space: `SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel` at 400 (the
level the system uses for Notification Center at screen lock), `SLSShowSpaces`,
then `SLSSpaceAddWindowsAndRemoveFromSpaces`. On macOS 27, on the Mac mini:

- SkyLight and all five functions resolve. `SLSSpaceSetAbsoluteLevel` returns
  0; `SLSShowSpaces` and `SLSSpaceAddWindowsAndRemoveFromSpaces` return
  `0xB0000000`, which is not a `CGError` and reads as no return value at all.
- The user saw the panel on the lock screen for as long as it was locked.
- The panel's own tracking area got pointer enter and exit while locked, and
  a click the user made on the lock screen.
- `screencapture` cannot capture the lock screen ("could not create image from
  rect"), so every lock-screen check is by eye.

The same technique is the MIT-licensed `SkyLightWindow` package, which Boring
Notch adopted for its lock screen in October 2025.

## Decisions (user's calls, 2026-10-21)

| Question | Decision |
| --- | --- |
| Where the island's window lives | Always in the private space, from launch (Boring Notch's way): not a second window just for the lock screen, not moved in and out on lock |
| What shows while locked | Everything the island shows unlocked: now playing, volume, brightness, battery and devices, Focus, Clock timers, Live Activities, and calendar and reminder blips with their titles |
| What works by hand while locked | Look only: hover opens the card, display-only; nothing reacts to a click, tap or swipe |
| An off switch | Settings › Island › "Show on the lock screen", on by default; off is today's behaviour |

## Choices made in this design (for the user's review)

- **The private calls are written in Ledge**, five `dlsym` lookups in one
  file, rather than adding the `SkyLightWindow` package. The package's useful
  part is those same five calls; the spec's originality boundary keeps
  third-party code to one vendored adapter; and owning the lookup lets the
  tests fake it.

## Scope

- In: the window's space, lock and unlock without hiding, look-only behaviour
  while locked, a live check of hover on the lock screen, the setting, the
  fallback.
- Not in scope: controls on the lock screen (media or otherwise); a
  different look while locked; hiding titles while locked; fast user
  switching; the login window before anyone has logged in.

## The space

A new `SkyLightSpace` in NotchKit holds the private calls, in the style of the
other private-framework bridges (`docs/private-api-notes.md`):

- `init?(lookup:)` resolves the five symbols through an injected lookup
  (`dlsym` on SkyLight in the app, a fake in tests) and returns `nil` if any is
  missing. On success it takes the main connection, creates one space, sets
  its absolute level to 400 and shows it. The space lives as long as the app.
- `adopt(_ window: NSWindow)` moves a window into the space
  (`SLSSpaceAddWindowsAndRemoveFromSpaces(cid, space, [windowNumber], 7)`).
- The two calls without a readable result are not checked. The only test of
  availability is that every symbol resolved.

`NotchPresenter` makes one `SkyLightSpace` at start and calls `adopt` on every
`NotchWindow` it builds in `rebuildForCurrentScreen()` (launch, a display
change, the lid opening or closing), right after creating it, and again each
time `syncWindowToVisibility()` orders the window back in after it was out:
the island orders its window out whenever it hides, and whether a window
ordered back in keeps its space is not known, so it is put back every time.
With no space (`nil`), the window stays an ordinary window, exactly as today.

`NotchWindow.setLocked` and its `CGShieldingWindowLevel() + 1` level go: they
were the 2026-09-28 attempt and never drew on the lock screen. The window keeps
its normal level inside the space.

### Above everything, always

Inside the space the island sits above full-screen apps, Spotlight, system
alerts and possibly the screen saver, all the time, not only while locked. The
user accepted this for approach B. It already sat above the menu bar; the
visible difference is over other system overlays.

## Lock and unlock

`NotchPresenter.showsOnLockScreen` is true when there is a space and the
setting is on.

- **Lock, showing:** `controller.setLocked(true)` and nothing else. No tuck, no
  hide: the island stays as it is and turns look-only.
- **Unlock, showing:** `controller.setLocked(false)`. No tuck and no pop on the
  way back, since the island never left. A card open at unlock stays open and
  gains its controls.
- **Not showing** (no space, or the switch off): today's code path, unchanged:
  tuck and hide on lock, come back tucked and pop out on unlock.
- The switch turned off while locked hides the island at once (the setter
  resyncs the window); turned on while locked, it shows at once.

`syncWindowToVisibility()` shows the window when
`controller.isVisible && (!isLocked || showsOnLockScreen)`.

## Look only

While `controller.isLocked`:

- `tap()` and `click()` do nothing: no link opened, no card pinned.
- `linkURL` is `nil`, so the island never shows the link pointer or the press
  dip.
- `swipe(_:)` returns `false` without changing the mode, and
  `NotchPresenter.handleSwipe` returns before its track-skip branch, so
  neither a mode change nor a skip happens.
- `emit(_:)` drops every intent. This is the one gate for the card's buttons:
  play/pause, skip, the scrubber, the favourite star, the output picker, a
  calendar row, the Live Activity's press.
- The card's content does not take hits (`allowsHitTesting(false)` on the
  detail row), so a row or button gives no press feedback either.
- The now-playing card is the display-only one (`MediaPanelView(displayOnly:)`,
  built 2026-09-28): artwork, title, artist, progress and times, no control
  row, no scrubbing.
- Hover opens the card by the usual rules (music to show, or a Live Activity
  with a card); everything else (blips, captions, the next-item preview) is as
  unlocked.

## Hover on the lock screen

The island finds the pointer two ways, both in `NotchPresenter`: a global
`.mouseMoved` monitor (`updateHover()`), and polling, since
`reevaluateHover()` reads `NSEvent.mouseLocation` on every 250 ms tick and
when a dwell timer fires. Whether macOS feeds the monitor, or updates the
pointer's location, while the lock screen is up is unknown.

A tracking area on the window would not help: the window ignores mouse events
until the pointer is already on the island (`NotchWindow.setAcceptsMouse`), so
it would never see the pointer arrive. (The probe's panel took mouse events
all the time, which is why its tracking area fired.)

So nothing is added for hover. The live check in the plan's last task finds
out whether hover opens the card on the lock screen. If it does not, the
island still shows everything while locked and its card cannot be opened
there, which is still look-only; another source for the pointer would be a
later change.

## Edge cases

| Case | Behaviour |
| --- | --- |
| Display change while locked | `rebuildForCurrentScreen()` builds a new window and adopts it; it shows, look-only |
| A card pinned open at lock | Stays open, display-only; unlock restores its controls |
| Media starts or stops while locked | The island follows as unlocked, look-only |
| SkyLight or a symbol missing (a future macOS) | No space: today's hide-on-lock path, a `.debug` log line, nothing else |
| The switch off | Today's hide-on-lock path; the window stays in the space, so "above everything" still holds |
| Screen saver | The island may draw over it; checked live, accepted either way |

## Settings

`AppSettings.showsOnLockScreen` (default `true`), a toggle "Show on the lock
screen" in Settings › Island under the blip switches, applied by
`AppModel.applySettings()` through `NotchPresenter.setShowsOnLockScreen(_:)`.

## Testing

Written first, as everywhere in this repo.

- **`SkyLightSpace`:** with a fake lookup, all five symbols present gives a
  space and records create, set-level 400, show; one missing gives `nil`; adopt
  passes the window number and 7.
- **`NotchController`:** locked, `tap()`, `click()` and `swipe(_:)` change
  nothing and `linkURL` is `nil`; `emit(_:)` reaches `onIntent` only unlocked;
  hover still expands with music; unlocking restores each.
- **`NotchPresenter`:** with a space and the switch on, locking keeps the
  window ordered in and does not tuck; with no space or the switch off,
  locking tucks and hides as today; flipping the switch while locked shows or
  hides at once.
- **Render:** `lockedMediaPanelRendersInsideTheIslandWithoutItsControlRow`
  still holds.
- **Settings:** the new key's default and round trip in `AppSettingsTests`.
- **Live, by the user** (`docs/manual-checks.md`; the lock screen cannot be
  captured): lock with music playing and see the island; hover for the card;
  click it and a row and see nothing happen; unlock and see the controls back;
  turn the switch off and lock again (nothing shows); look over Spotlight and a
  full-screen video, and at the screen saver.

## Docs

- `docs/private-api-notes.md`: the "Lock screen: closed" entry reopened with
  the probe's findings and the five calls.
- `2026-09-25-notch-companion-design.md`: a dated section lifting the park, and
  §7's LockScreenService pointing here.
- `README.md`: the lock screen leaves "What it deliberately doesn't do"; the
  Settings paragraph names the new switch.
- `docs/manual-checks.md`: the live checks above, with what was seen.

## Risks

| Risk | Mitigation |
| --- | --- |
| A macOS update removes or changes the SkyLight calls | Symbols resolved at launch; missing means today's behaviour. A changed signature cannot be detected and would show as the island missing from the lock screen, found by the live check after an update |
| The island above every system overlay, all the time | The user's call (approach B); the live check looks at Spotlight, full-screen video and the screen saver |
| Meeting and reminder titles readable at a locked Mac | The user's call; the switch turns the whole lock-screen island off |
| Hover not reaching Ledge while locked | Checked live; at worst the card does not open while locked |
