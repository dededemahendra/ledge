# GitHub on the island — design

2026-10-22. The first piece of "Developer Island" (the user's list: Git and
working tree, builds and tests, GitHub Actions, package installs, local
servers, errors, coding agents). The user asked for Git and GitHub first and
local Git later, with the shell hook. Approved section by section in chat; the
user waived a written-spec review.

## Goal

The user stops keeping GitHub open in a tab: the island says when checks on
their PRs start, pass or fail, when someone reviews, comments, merges or closes
one, when someone asks for their review, and when a workflow run they started
outside a PR finishes. The open island lists it all.

## Decisions (user's calls, 2026-10-22)

| Question | Decision |
| --- | --- |
| Which repos | All of the user's on GitHub: their open PRs anywhere, PRs waiting for their review, their own runs. No folder list |
| Which moments | Checks finished (passed or failed); checks running, live; reviews, comments, merges and closes (bots included); review requested |
| Runs outside PRs | Yes, the ones the user starts (a push, a merge, a tag, a deploy), in any repo. Runs other people start stay quiet |
| Local Git | Later, with the shell hook piece |
| How Ledge learns | Asks GitHub every minute and compares (approach A), every 20 s while something runs. Not the notifications API, not webhooks |

## The check: a new `GitHubService` library

Built like `UpdateService`: pure parts, and a thin client with an injected
`fetch` so tests can answer it.

| Unit | Job |
| --- | --- |
| `GitHubToken` | The login: a token pasted in Settings and kept in the Keychain, else `gh auth token` when `gh` is installed (`/opt/homebrew/bin/gh`, `/usr/local/bin/gh`). A pasted token wins: pasting one is choosing it |
| `GitHubClient` | All requests go to `api.github.com`. One GraphQL query per round: the viewer's login; their open PRs (up to 50; for each the latest commit's check rollup and its contexts, the last 10 reviews and comments); PRs requesting their review (up to 20); their 10 most recently pushed repos. Then, for repos pushed in the last 24 hours (at most 5), `GET /repos/{repo}/actions/runs?actor={login}&per_page=10` with an ETag, so an unchanged answer costs nothing. PRs that left the open list are looked up by ID to tell merged from closed, and by whom |
| `GitHubSnapshot` | What one round found, a plain value |
| `GitHubEvents` | Compares two snapshots and lists what happened; also what is running now |
| `GitHubNotice` | Each event's glyph, word, colour, caption and link; which event wins a burst |
| `GitHubPanelRows` | The open island's list, from a snapshot |
| `GitHubSchedule` | When to ask next: 60 s, 20 s while anything runs, backing off after failures, waiting out a rate limit |
| `GitHubMonitor` | The loop: asks, compares, hands events and the snapshot to the app; asks at once on wake and on connect |

**First round:** the first snapshot after launch or after connecting sets the
baseline and announces nothing.

**What counts as an event:**

- Checks: GitHub's rollup on a PR's latest commit (Actions and outside
  statuses such as a Pages preview or a review bot's status). A pass is
  announced once per PR head commit, even when the rollup goes back to pending
  in between (a late check joining); a failure each time the checks end failed
  (a re-run that fails again is news), and a pass after a failure is told again.
  Passed is `SUCCESS`, failed is `FAILURE`
  or `ERROR`, naming the first failing check. A result for an older
  commit never shows; a force-push starts the running item again.
- Reviews and comments: a review or comment ID not seen before, not written by
  the user. A review is approved, changes requested, or commented.
- Merged or closed: a PR gone from the open list, merged or closed by someone
  else.
- Review requested: a PR new to the "review requested" list.
- The user's runs outside PRs: a run whose head commit is not the head of one
  of the user's open PRs, created after the baseline: running, then passed
  (`success`) or failed (`failure`, `timed_out`, `startup_failure`). Cancelled
  and skipped runs end quietly.

The user's own comments, reviews, merges and closes are never announced; runs
they start are.

This adds the app's second network destination. The README's line changes from
one request to "one, plus GitHub if you connect it".

## What the user sees

**Two new kinds:**

- `ActivityKind.github`: a blip, priority 38 (under notifications at 40, over
  the update notice at 35), 8 s.
- `ActivityKind.githubRun`: sticky while anything runs, priority 18 (under a
  Clock timer at 20, over an iPhone Live Activity at 15).

| Moment | Leading ear | Trailing ear | Caption line | Click opens |
| --- | --- | --- | --- | --- |
| Running | amber ring turning; a count on it when more than one runs | elapsed "2:14", amber, digits roll without bumping | none (sticky) | the PR or run that started first |
| Checks passed | `checkmark.circle.fill`, green | Passed | `#4 update notice · ledge` | the PR |
| Checks failed | `xmark.circle.fill`, red | Failed | `#4 update notice · test (macos)` | the failed check, else the PR |
| Approved | `checkmark.seal.fill`, green | Approved | `coderabbitai · #4 ledge` | the review |
| Changes requested | `exclamationmark.bubble.fill`, orange | Changes | `login · #4 ledge` | the review |
| Commented (a comment, or a review that only comments) | `bubble.left.fill`, white | Comment | `login · #4 ledge` | the comment |
| Merged | `arrow.triangle.merge`, purple | Merged | `#4 update notice · ledge` | the PR |
| Closed | `xmark.circle`, grey | Closed | `#4 update notice · ledge` | the PR |
| Review requested | `eye.fill`, blue | Review | `login asks for your review · #12 fairwell` | the PR |
| A run of the user's | as running, passed or failed | as above | `Deploy · fairwell` (workflow · repo) | the run |

**A burst is one blip:** of everything one round finds, the most important
shows, its caption ending ` · +N more`. Order: failed, changes requested,
review requested, approved, merged, passed, comment, closed.

**Running item:** the item that started first; the ring carries the count
when more than one is running. It goes when nothing runs.

**The open island's GitHub panel:** a list of up to four rows: the user's runs
going now, then their PRs (failed checks first, then running, then the rest),
then PRs waiting for their review. Each row has a mark (a check dot, amber,
green or red; an eye for a review request), `#4 update notice`, and the repo,
dim, at the end; a click opens it. More than fits: the last row reads
"N more on GitHub" and opens `https://github.com/pulls`. The panel exists only
while connected with something to list. It is one more card in the swipe order
(after media and calendar); hovering while a GitHub item leads opens it
directly, the way an iPhone Live Activity's card opens; a swipe on the empty
peek (no upcoming event) opens it too.

**Lock screen:** GitHub stays off it (PR titles are readable by anyone walking
past): no blips, no running item, no panel. The most important event missed
while locked shows once after unlock.

**Settings › GitHub** (a new pane, `arrow.triangle.branch` on a dark tile, with
the preview strip):

- Connection: "Connected as dededemahendra (from gh)" or "(with a token)";
  Connect, Disconnect, Check now; "Last checked at 10:42." or why not; a token
  field when `gh` is not there (or the user prefers a token).
- One switch per moment, all on: Checks finished, Checks running, Reviews and
  comments, Merges and closes, Review requests, Your runs outside PRs.
- A sidebar badge while the pane needs the user (sign in again).

Not connected is the default: until the user connects, Ledge makes no GitHub
request.

## Failures

| Situation | What happens |
| --- | --- |
| No `gh`, no token | Off; the pane offers Connect and a token field |
| 401 | Polling stops; the pane says "Sign in again", the sidebar badges; no blip |
| Rate limited (403 or 429 with `x-ratelimit-remaining: 0`, or `retry-after`) | Waits until GitHub's reset time; the pane says "GitHub asked Ledge to wait until 14:05" |
| Offline or a server error | Backs off 1, 2, then 5 minutes, keeps the last good snapshot, and compares with it when GitHub answers, so what happened in between shows once, as one blip |
| Sleep and wake | Asks at once on wake; what happened during sleep is one blip |
| An organisation that blocks the token (SSO) | Uses what it can see; the pane says some organisations hide PRs from the token (GitHub's error does not say which) |
| Many PRs | 50 of the user's, 20 review requests; the panel's "N more on GitHub" |

## Testing

- GitHubServiceTests: decoding canned GraphQL and REST replies (and broken
  ones), the request's headers and body, 401 / 403 / 429 / 500 / 304 handling;
  every kind of event from snapshot pairs (the quiet baseline, a head commit
  changing, a PR leaving the list, the user's own actions, runs outside PRs);
  the burst's winner and its "+N"; captions and glyphs; the panel's rows and
  their order and limit; the schedule's delays; reading `gh`'s output.
- ActivityKitTests: the two kinds' priorities and lifetimes, priorities distinct.
- NotchKitTests: the GitHub blip's caption, the panel in the swipe order,
  hover on a GitHub item opening the panel, the peek's swipe, the running
  item's count.
- LedgeSettingsTests: the switches' defaults and round trip.
- SettingsKitTests: the GitHub scenes.
- Live: a debug-only `ledge://probe/github` plays a canned run (running,
  failed, comment, approved, merged, review requested) with no
  network, then leaves the panel to hover; then a live check against the user's account with this
  repo's PRs.

## Out of scope

Local Git (with the shell hook), acting on GitHub from the island (approve,
merge, re-run), GitHub Enterprise, marking notifications read, webhooks.

## Delivery

A branch and a PR, reviewed, merged when the user says merge.
