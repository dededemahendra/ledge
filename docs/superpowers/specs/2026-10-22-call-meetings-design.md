# Calls that know the meeting — design

2026-10-22. A follow-up to calls on the island
(`2026-10-22-call-island-design.md`). The user asked to "enhance the call
features, like optimise for Google Meet, Zoom etc." They chose three of four
proposed pieces, and approved the behaviour as played back in chat. Calls marked
*(my call)* are mine, not the user's.

## Goal

When a call is a calendar meeting, the island knows which meeting it is:

- the meeting service's icon instead of the browser's;
- the meeting's title on the card;
- how long is left, and when it has run over;
- whether the next meeting is close;
- whether the camera is on.

None of this needs a new permission. Ledge already reads the calendar for
meeting reminders, and the camera's state is open to any app.

## Decisions (user's, 2026-10-22)

| Question | Decision |
| --- | --- |
| Which pieces | (1) Know the meeting; (2) the next meeting on the card; (3) a camera indicator. Not (4), pressing the meeting app's own mute (fragile: Accessibility, and a Meet tab would have to be brought forward) |
| Not now | FaceTime and WhatsApp extras: who you're talking to, hang-up and the app's own mute, discussed and set aside |
| Matching window | An event with a meeting link, from 10 minutes before its start until its end, when the call starts |
| Icon on the island | The service's own Mac app icon when it is installed (Zoom, Teams, Webex, FaceTime); for Meet, which has no Mac app, a video glyph on a green tile. No third-party logo is bundled |
| Card, top line | The event's title instead of the app name |
| Card, line under it | "12m left", then "+3m" in red once over; "Muted · 12m left" while muted |
| Card, bottom row | "Next: 1:1 at 15:00" in place of the mic's name when another event starts within 10 minutes; a small camera glyph at its left while the camera is on; "Not a call" stays at the right |
| Hidden apps | A call that matches a meeting shows even if its app is hidden ("Not a call"), so hiding a browser for a forgotten tab no longer hides real meetings in it |
| No matching event | Everything exactly as today |

## Matching a call to a meeting

**Services and their apps.** These are read from the event's join link, which
`MeetingLinkDetector` already finds:

| Service | Link host | Apps that can hold its call |
| --- | --- | --- |
| Google Meet | `meet.google.com` | a browser |
| Zoom | `zoom.us` (and subdomains) | `us.zoom.xos`, or a browser |
| Microsoft Teams | `teams.microsoft.com`, `teams.live.com` | `com.microsoft.teams2`, `com.microsoft.teams`, or a browser |
| Webex | `webex.com` | the Webex app, or a browser |
| FaceTime | `facetime.apple.com` | `com.apple.FaceTime` (including its `avconferenced` daemon, which already resolves to FaceTime), or a browser |

The other hosts the detector knows (Whereby, Jitsi, Discord and so on) don't
match *(my call)*. They keep today's look.

**Browsers** *(my call; checked on this Mac where installed)*:

| Browser | Bundle id |
| --- | --- |
| Safari | `com.apple.Safari` |
| Chrome | `com.google.Chrome` |
| Arc | `company.thebrowser.Browser` |
| Dia | `company.thebrowser.dia` |
| Edge | `com.microsoft.edgemac` |
| Firefox | `org.mozilla.firefox` |
| Brave | `com.brave.Browser` |
| Opera | `com.operasoftware.Opera` |
| Vivaldi | `com.vivaldi.Vivaldi` |
| Orion | `com.kagi.kagimacOS` |

The Webex app's bundle id is for the builder to confirm (the app isn't
installed here).

**The rule.** A live call's shown app is matched against the calendar's events
of kind `.event` that:

- have a join link of a service in the table above;
- whose service accepts that app;
- satisfy `start - 10 min ≤ now < end`.

With several candidates, the one whose start is closest to now wins. Near a
boundary (the last minutes of A, two before B) that is B *(my call)*.

When the match is looked for, and how long it lasts *(my call)*:

- **No match yet.** The call is checked again on every refresh against the
  cached events, so joining 15 minutes early picks the meeting up when its
  window opens. The card's title can then change mid-call from the app's name
  to the meeting's.
- **A match sticks** past the event's end; that is when "+3m" shows.
- **Back to back.** Once the matched event has ended, if another candidate is
  in its window and fits the app, the call switches to it. Leaving an
  overrunning A for B in the same app then shows B, not A "+5m". While the
  matched event is still under way it never switches.
- **A hand-over** to another app looks again from scratch.
- **Edits.** The matched event is re-read from the cached events on each
  refresh, by its join link and title (an event's id includes its start, so a
  moved event gets a new id). An extended or moved meeting then updates its
  end time. If it can no longer be found (deleted), the last copy stays.

**Where the logic lives** *(my call)*. The rule is a pure function in
`CallService`, `CallMeetingMatcher`. It takes the shown app's bundle id, the
time, and plain candidate values:

```swift
struct MeetingCandidate {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let joinURL: URL
}
```

It returns the matched meeting with its service. `CallService` stays free of
EventKit; `AppModel` maps `MeetingEvent` to `MeetingCandidate` from
`calendar.upcoming(at:limit:allowing: [.event])`, which already includes events
under way.

**Hidden apps.** A holder whose app is hidden still counts when it matches a
meeting. `CallService.refresh` passes the tracker the hidden set minus the
bundle ids that match *(my call)*. Two details:

- **Under way, not early.** For a hidden app the meeting must be under way
  (`start ≤ now`), not 10 minutes early. A forgotten tab is then shown as a
  meeting only during the meeting itself.
- **Kept for the call.** Once a hidden app's call is showing as a meeting, the
  exemption lasts as long as that match does. The call doesn't vanish
  mid-call when the event ends.

**What a browser can't tell.** Ledge can't see which site a tab is on. A
browser call (Discord on the web, a Slack huddle in a tab) during a scheduled
Meet's window is labelled as that Meet. That is accepted as the cost of
needing no permission *(my call)*: a browser call while a meeting you're
invited to is under way is that meeting far more often than not.

## What the user sees

**Ears.**

- The leading ear shows the service's icon instead of the app's, when matched:
  - the installed service app's icon (Zoom, Teams, Webex, FaceTime) via
    `NSWorkspace`;
  - for Meet, or a service whose app isn't installed, an SF Symbol `video.fill`
    in white on a rounded tile in the service's colour. Meet is green
    (`#00A67E`); the other tile colours are the builder's call.
- Muted and ended glyphs are unchanged (red), and so is the clock.

**Card, top row.**

- The icon is the service's, as in the ear.
- The name line is the event title, one line, truncated at the tail.
- The status line:
  - Under way: "12m left", or "1h 5m left" from an hour up *(my call)*. Under
    a minute it reads "Ending now".
  - Over: "+3m", then "+1h 2m", in red.
  - Muted: "Muted · 12m left", with "Muted" in red and the rest as above. If
    the meeting has run over, "Muted · +3m".
  - Not matched: today's "On a call" / "Muted".
- A click still brings the app forward.

**Card, bottom row**, left to right:

- A camera glyph, `video.fill` at 9 pt, while any camera is running somewhere.
- Then the first of these that applies:
  1. the unmutable note, since it explains a disabled button *(my call)*;
  2. "Next: 1:1 at 15:00", when another event (kind `.event`, not the matched
     one) starts within the next 10 minutes. The title is truncated, and the
     time uses the same clock format as the island's meeting reminders;
  3. the mic's name, as today.
- "Not a call" at the right.

**Updating.**

- The time left and the next-meeting line follow the clock. The card already
  ticks once a second; the time left counts down in whole minutes, rounded
  down *(my call)*.
- The event list for matching and for "Next" is the calendar's cached day
  (`upcoming(at:limit:allowing:)` with a limit of 50).
- The camera glyph appears within a second of the camera turning on or off.

**Lock screen.** Event titles show on the card over the lock screen, as meeting
reminders already do; the Island pane's lock-screen footer already says so.

## The camera

A small CoreMediaIO watcher in `CallService` (`CameraWatcher`):

- reads `kCMIOHardwarePropertyDevices` on the system object;
- reads `kCMIODevicePropertyDeviceIsRunningSomewhere` on each device;
- reports `isCameraOn` when any is running.

It is read on each refresh while a call is live and not otherwise *(my call:
cheap, and a call is the only time it shows)*. Listeners are the builder's
choice if they prove reliable. Remember that CoreAudio's per-process ones
didn't, so verify CoreMediaIO's notifications before relying on them. No
permission is involved: CoreMediaIO doesn't gate reading the running state.

## Data flow

- `CallService.refresh(at:hidden:meetings:)` takes the candidate list.
  `CallUpdate` gains:
  - `meeting: CallMeeting?` — id, title, start, end, and service: an enum of
    `.meet`, `.zoom`, `.teams`, `.webex`, `.facetime`;
  - `isCameraOn: Bool`.
- `AppModel.refreshCall()`:
  - builds the candidates;
  - picks the next meeting itself (kind `.event`, start within 10 minutes,
    not the matched one);
  - fills `CallPanelData`.
- `CallPanelData` gains:
  - `meetingTitle: String?`
  - `meetingEnd: Date?`
  - `service: CallService` mirror, as a NotchKit enum `CallPanelData.Service`
  - `isCameraOn: Bool`
  - `nextMeeting: String?` (already formatted, "1:1 at 15:00")
- The ear's icon is the record's `artwork`. When matched, `AppModel` sets it to
  the service icon PNG: the installed app's icon, or the drawn tile for Meet.
  It is cached per service.
- The time-left text is formatted in NotchKit from `meetingEnd` and the clock,
  so it updates with the card's `TimelineView`.

## Tests

`CallMeetingMatcher`:

- Meet in a browser matches; Meet in Zoom's app doesn't.
- Zoom in Zoom's app and in a browser match.
- Teams in either Teams app matches.
- 11 minutes before the start: no match. 10 minutes: a match.
- At the end: no match for a call starting then.
- Two candidates: the nearer start wins.
- An event without a link, or with a Whereby link: no match.

`CallService`:

- The match sticks past the event's end.
- A call joined 15 minutes early matches once the window opens.
- Back to back: after A ends, B in its window takes over. While A is under way,
  B never does.
- A moved or extended event updates the end; a deleted one keeps the last copy.
- A hand-over to another app re-matches.
- A hidden browser holding the mic shows once a Meet is under way, not 10
  minutes early, and stays hidden when none matches. Once shown, it stays
  through the meeting's end.
- The camera's state comes through from a fake watcher.

The time-left formatter (pure, NotchKit):

- "12m left", "1h 5m left", "Ending now", "+3m", "+1h 2m".
- Muted forms.

The next-meeting pick (a pure helper next to the matcher, not in `AppModel`):

- Within 10 minutes it shows; at 11 it doesn't.
- The matched event itself is never "next".

## Docs

- A README note on the call row: "a calendar meeting shows its service, title
  and time left".
- `docs/manual-checks.md` pending items:
  - a scheduled Meet in Dia shows the Meet tile and the title;
  - the time left counts down, and goes red past the end;
  - "Next:" appears 10 minutes before the following meeting;
  - the camera glyph follows the camera;
  - a Zoom meeting in Zoom's app.

## Not in scope, and what would make this a failure

- **Not in scope:**
  - identifying ad-hoc meetings that have no calendar event (no tab titles, no
    Accessibility);
  - the meeting app's own mute;
  - leave or hang-up buttons;
  - participants;
  - screen-sharing indicators;
  - FaceTime and WhatsApp caller names.
- **Failures even if it technically works:**
  - the wrong meeting's title on a call (a match must fit both the time and
    the app);
  - a permission prompt;
  - a third-party logo bundled in the app;
  - the card growing taller. It stays the two-row card: new information
    replaces lines, it doesn't add them.

## Left to the builder

- Tile colours other than Meet's.
- Exact truncation widths.
- How the service icon PNG is drawn.
- Whether `CameraWatcher` listens or reads.
- Internal names beyond the interfaces above.
