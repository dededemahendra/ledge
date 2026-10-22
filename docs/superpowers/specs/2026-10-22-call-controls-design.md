# Call controls — design

2026-10-22. The user picked two follow-ups to calls on the island:

- for FaceTime and WhatsApp: the caller's name, a hang-up button and the app's
  own mute;
- for Zoom, Meet and Teams: the meeting's own mute.

They chose to skip the questions ("just start"), so every behaviour below is
*my call* unless stated, and is open to their correction.

## Scope now (2026-10-23)

The user can only test Zoom and Meet for now. This round builds the meeting's
own mute for **Zoom** and **Meet in a browser**. The FaceTime and WhatsApp parts
(caller's name, hang-up, their own mute) wait until those calls can be tested,
and are kept below for then.

**Found live (Task 1 probe, 2026-10-23):**

- **Zoom** (`us.zoom.xos`). The menu bar's "Meeting" menu has an `AXMenuItem`
  with identifier `onMuteAudio:`. Its title is "Unmute audio" while muted and
  "Mute audio" while not. The identifier doesn't depend on the language; only
  the state read from the title does. The meeting window is identified
  `zm.meeting.window.main`.
- **Meet in Dia** (Chromium; the tree is exposed after setting
  `AXManualAccessibility`). The Meet window's title contains "Meet - ". It
  holds an `AXButton` titled "Turn off microphone" while unmuted and "Turn on
  microphone" while muted, next to "Turn off camera" and "Leave call". It is
  found only while the Meet tab is the window's front tab, since background
  tabs expose no page.

**Cost** *(my call)*:

- The control is found once per call by walking the tree, off the main
  thread.
- Its element is then kept, and only its title is read each second (one call).
- A failed read means the control is found again from scratch.

## Goal

The call card controls the call itself, not just the Mac's mic:

- Mute presses the call app's own mute, so the app and the people on the call
  see you muted.
- FaceTime and WhatsApp calls show who you're talking to and can be ended from
  the island.
- Anything Ledge can't reach behaves exactly as today: system-wide mute, the
  app's name, no hang-up.

## How

- **Accessibility.** Ledge already asks for the permission for the volume
  overlay. Through it, Ledge finds the call app's own buttons and menu items,
  reads their state and presses them.
- **No keystrokes.** Ledge sends no keyboard shortcuts, since they land in
  whatever window has focus. Nothing is brought to the front.
- **Without the permission**, everything falls back as above, and Settings ›
  Permissions already lists Accessibility.

**Per app.** The exact element names are found live in Task 1 of the plan and
then pinned in a table. These are the expected shapes:

| App | Mute (state and press) | Hang-up | Who |
| --- | --- | --- | --- |
| FaceTime (`com.apple.FaceTime`, including iPhone calls) | the call window's mute button | its end button | the call window's title or name text |
| WhatsApp (`net.whatsapp.WhatsApp`) | the call window's mute button | its end-call button | the call window's name text |
| Zoom (`us.zoom.xos`) | the Meeting menu's "Mute Audio" / "Unmute Audio" item | none | (calendar title, already) |
| Teams (`com.microsoft.teams2`) | the meeting window's mute button | none | (calendar title) |
| Meet in a browser | the Meet page's microphone button ("Turn off microphone" / "Turn on microphone") in the browser's web content | none | (calendar title) |

**Labels are English only.** If an app is in another language and nothing
matches, that app falls back.

**Not blocking the island.** Each Accessibility call gets a 0.25 s messaging
timeout, so a hung app can't freeze the island. While a call is live, the
app's mute state is read once a second; presses happen on tap.

## What the user sees

- **Mute button.**
  - For these apps, it toggles the app's own mute, and the island's red glyph
    and the card follow the app's own state. So muting from FaceTime's own
    window shows on the island too.
  - If the app's control can't be found at the moment of the tap, the system
    mute is used as today.
  - Ledge never stacks both mutes. While the app's own mute is in use, no
    system mute is applied.
- **Caller's name** (FaceTime, WhatsApp). The card's top line shows the name
  instead of the app's. It stays off the island's ears, and off the card while
  the screen is locked, where the app's name shows instead.
- **Hang-up** (FaceTime, WhatsApp). A red round `phone.down.fill` button sits on
  the card's top row, left of the mute button. One tap ends the call, as on the
  iPhone. It shows only while Ledge can see the app's end button.
- **Zoom, Meet, Teams.** Only the mute changes. The calendar title from the
  meetings work stays the top line.
- **Lock screen.** Look only as today: the buttons do nothing, and names are
  hidden.

## Building blocks

- `CallControls` (in `CallService`) has one adapter per app, behind one
  protocol:

  ```swift
  protocol CallAppControl {
      func isMuted() -> Bool?
      func setMuted(_: Bool) -> Bool
      func hangUp() -> Bool
      func callerName() -> String?
  }
  ```

  Each adapter walks the app's Accessibility tree for elements matching its
  table. The walk is a pure function over a small element tree value, so it can
  be tested against recorded trees; a thin shell reads the live tree.
- **Meet** is found through the browser named by the call's app: its window
  whose web content contains the Meet microphone button.
- `CallService` uses the adapter for the live call's app when one exists and
  answers. Otherwise it uses `InputMutePlan` as today. `CallUpdate` gains:
  - `appMute: Bool?` — the app's own state, when readable;
  - `canHangUp`;
  - `callerName`.
- New intent `NotchIntent.hangUpCall`. `CallPanelData` gains `callerName` and
  `canHangUp`.

## Tests

- Each adapter's matcher runs against recorded Accessibility trees from Task 1,
  with names replaced by placeholders:
  - finds mute (muted and unmuted);
  - finds hang-up;
  - finds the name;
  - returns nil on a tree without a call.
- `CallService`:
  - with a fake control, mute presses the app's mute and applies no system
    mute;
  - with a control that can't answer, it falls back to the system mute;
  - the app's own state drives `isMuted`.
- `NotchController`: `hangUpCall` is dropped while locked. Card renders with and
  without a name and a hang-up button.

## Not in scope, and what would make this a failure

- **Not in scope:**
  - hang-up or leave for Zoom, Meet and Teams;
  - answering incoming calls;
  - other apps (Discord, Slack);
  - non-English labels.
- **Failures:**
  - a tap muting both the app and the mic;
  - the island saying "Muted" while the app isn't (or the reverse);
  - pressing the wrong button (hanging up when muting);
  - the island freezing on a hung app;
  - a caller's name on the lock screen.

## Verify first (Task 1)

This session can't use Accessibility, so a debug probe inside Ledge dumps the
call app's Accessibility tree to `~/Library/Logs/Ledge` while the user is on a
call. The calls are:

- a FaceTime call;
- a WhatsApp call;
- a Zoom meeting;
- a Meet in Dia.

The dumps fix the element names; names in them are replaced before they become
test fixtures. If Ledge isn't trusted for Accessibility, the user grants it
first.
