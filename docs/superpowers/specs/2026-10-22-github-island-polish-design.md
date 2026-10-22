# GitHub on the island: polish — design

2026-10-22. The user found the first cut of GitHub on the island
(`2026-10-22-github-island-design.md`) basic. Chosen with mockups, surface by
surface, and approved section by section in chat; the user waived a
written-spec review. Built on the same branch, so it lands in the same PR.

## Decisions (user's calls, 2026-10-22)

| Surface | Choice |
| --- | --- |
| The GitHub panel | C, hero and rows: the thing most worth watching gets the stage, the rest are rows under it |
| The running item | B, a segment per check: the hero's segmented bar bent into a ring, with the clock |
| The blips | B, the person's avatar when a person did it; a coloured disc for checks and runs |
| Settings › GitHub | An account card and a welcome card, the switches in two groups |

## The panel

The hero is, in order:

1. Something running: a PR of the user's with pending checks, or a run of
   theirs outside a PR; the one that started first.
2. Otherwise a PR of theirs with failed checks.
3. Otherwise a PR waiting for their review.
4. With none, no hero.

| Hero | Tag | Line under the title | Bar |
| --- | --- | --- | --- |
| A PR's checks running | Checks running (amber), a live clock on the right | `ledge #5 · 4 of 6 checks · 1 failed` | a segment per check |
| A run of theirs | Run going (amber), the clock | `web · your run` | none (no per-check detail) |
| Failed | Checks failed (red) | `ledge #4 · test (macos) failed` | the segments, finished |
| Review | Review requested (blue), the asker's avatar | `site #7 · sam asks for your review` | none |

Under a hero, up to two rows; with none, a small "GITHUB" heading and up to five
rows (four and "N more on GitHub" when there are more). Rows keep their order
(runs, the user's PRs failed first, review requests), leave out the hero's
item, and draw real symbols: a green check, a red cross, an amber dotted
circle for running, a grey circle, a blue eye. A click on the hero or a row
opens it.

## The running item

The ring has a segment per check of the leading PR, finished first (passed
green, failed red), then the ones still going in faint amber, breathing (still
under Reduce Motion). Past 12 checks it fills smoothly with the fraction done,
amber, red once any has failed. A run outside a PR has no per-check detail and
keeps the turning arc. The clock stays on the right.

## The blips

- When a person did it (a review, a comment, a merge or close by someone else,
  a review request), the left ear shows their GitHub avatar with a small badge
  for what they did: green check, orange exclamation mark, grey bubble, purple
  merge, grey cross, blue eye.
- Checks and runs show the glyph on a disc in the event's colour.
- The word on the right takes the event's colour (a comment's stays white).
- The caption leads with the PR's title, then who or what, then the repo:
  `Fix the date picker · sam · web`; a run's is `Deploy · web`. The island
  sets a GitHub blip's caption in bold up to its first separator, the rest
  dim; every other caption keeps splitting at its last, so a reminder whose
  title has one stays bold whole.
- A blip waits at most a second for its avatar, then shows the disc.

Avatars come from GitHub's image server (`*.githubusercontent.com`) with no
token and no cookies, only while connected; the last 64 are kept in memory,
none on disk.

## Settings › GitHub

- The preview strip on top, as in the other panes.
- Connected: an account card with the user's avatar, login, how they are
  connected ("through gh" or "with a token") and when Ledge last checked; Check
  now, Disconnect, and Use a token when connected through gh. Under it a line:
  open PRs, failing, running, waiting for your review. Sign in again, could not
  reach GitHub, and the token field take that line's place.
- Not connected: a welcome card, "Your pull requests on the island", a line on
  what it does and that nothing is asked until the user connects, Connect with
  gh and Use a token….
- The switches in two groups: Your pull requests (checks running, checks
  finished, reviews and comments, merges and closes) and Around you (review
  requests, your runs outside PRs); dimmed but usable while not connected.

## Testing

- GitHubServiceTests: segments from each kind of check and their order; avatar
  addresses decoded; the avatar store (GitHub's image server only, no token,
  memory, the 64 cap); the hero's choice and lines; rows under a hero and
  alone; captions and disc glyphs.
- NotchKitTests: the caption split; segments and the avatar reaching the view;
  the hero in the panel data; the debug open.
- SettingsKitTests: the scenes' new captions and the ring's segments.
- Live: `ledge://probe/github` (the story, now with segments) and a new
  debug-only `ledge://probe/github-panel` that pins the panel open on a sample
  with a running hero, captured.
