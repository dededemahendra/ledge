# Browser video on the island — design (2026-11-18)

Short design for a small change. Approved in conversation on 2026-11-18.

## Intent

Video playing in a web browser (YouTube, Netflix and the like) shows on the
island the way music does: the compact ear, the card, play/pause and seeking.
On 2026-09-29 the user removed browser playback, because tabs and video calls
were landing on the island as "now playing" (`MediaSourcePolicy`, commit
2512835). This change brings browsers back behind rules that keep that noise
out.

## Goals

- Safari, Chrome, Arc, Firefox, Edge and Brave can each take the island.
  Each one gets an on/off switch in Settings → Now Playing, under the music
  apps, with its own icon and status.
- A browser takes the island only when **all** of these hold:
  1. **It is actually playing** (`playing == true`). A browser that was only
     the last thing to make sound, reported paused, never brings the card up.
  2. **What it plays has a length** (`duration` present, finite, > 0). A
     video has a running time; a call or a live stream reports none.
  3. **No call is in progress** (the call kind is on the island). A Meet tab
     stays on the call card.
- Once on the island, a paused browser video keeps its card for **2 minutes**
  (builder's call), then leaves. Playing again brings it straight back. If a
  call starts, the browser card leaves at once.
- Music apps behave exactly as they do today.

## Non-goals

- Filtering by site. MediaRemote reports the browser but never the URL, so
  "YouTube only" cannot be told apart from any other tab.
- A video-shaped card (wide thumbnail, frame preview, picture-in-picture).
- Dedicated video players (IINA, VLC, QuickTime, Infuse). Adding them later
  is one line each.

## Anti-goals

- A muted autoplay preview, a video call, or a paused tab from hours ago
  takes the notch. Any of these means the rules failed.

## Constraints

- **Who the source is.** Safari's media plays in a WebKit helper process, so
  the adapter reports the helper as `bundleIdentifier` and Safari as
  `parentApplicationBundleIdentifier`. `MediaPayload` decodes the parent
  field. The source is then the parent when present, otherwise
  `bundleIdentifier`. That source is used for the policy, the Settings
  "Playing now" status, the favourite star and click-to-open. Click-to-open
  still tries the pid first.
- Bundle ids: `com.apple.safari`, `com.google.chrome`,
  `company.thebrowser.browser` (Arc), `org.mozilla.firefox`,
  `com.microsoft.edgemac`, `com.brave.browser`. They are compared
  case-insensitively, as the music ids are.
- Browsers rarely report shuffle, repeat or skip. The card already disables
  what a source doesn't support.

## Approaches

1. **Behaviour gate per browser (picked).** Allow the browsers, but let one
   in only while it plays something with a length and no call is up. This
   works with what MediaRemote actually reports.
2. **Match sites by title** (" - YouTube" and so on). Rejected: titles are
   whatever the page sets, many sites set nothing recognisable, and the
   check would break silently.
3. **Let any browser playback in.** Rejected: this is the September problem
   again.

## Decided with the user

- Browser video, not dedicated players, is what they want (2026-11-18).
- The three rules and the per-browser switches above (2026-11-18, "yess").

## Builder's calls (marked so the user can check them)

- Paused hold: 2 minutes. Music keeps its card indefinitely while paused.
- Default: browsers arrive **switched on**, including for anyone whose saved
  source list predates them. Settings records which sources it has offered
  (a new `offeredMediaSources` key), and a source never offered before starts
  on. Something the user switched off stays off.
- Card, caption ("title · channel") and favourite star are unchanged. A 16:9
  thumbnail is centre-cropped in the square artwork tile.
- The Settings footer becomes: "The island follows music from these apps,
  and video from these browsers while it plays. Calls and live streams never
  take the notch."
- The rules live in `MediaService` as pure functions (source resolution, the
  entry gate, the pause hold) so they can be tested without the app.
  `AppModel.handle(_ payload:)` calls them and adds the call check.

## Dia (2026-11-18, found live)

Dia is a seventh browser (`company.thebrowser.dia`). It reports a normal
video's length like the others. A live stream reports its length as infinity;
the adapter cannot write infinity as JSON and drops that update, so the app
sees no length and rule 2 keeps live streams out of every browser, Dia
included. (An exemption for Dia was tried and removed the same day: it had
been judged on a live stream, which let live streams in.)
