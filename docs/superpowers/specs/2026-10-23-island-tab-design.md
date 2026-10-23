# Two at once: the island's tab — design

2026-10-23. The user asked how many live activities the island can show for
the features built so far (one, today, plus a "+N"), shared an iPhone with a
timer in the island and a boarding pass in a bubble beside it, and asked for
the same, made for the MacBook's notch. They picked the "notch tab" from
three layouts and approved the design section by section in chat. Calls
marked *(my call)* are mine.

## Goal

Two live things at once, the iPhone's rule: the most important live item in
the island, the next one in a small tab beside it. Nothing important hides
behind music or a timer any more, and the island never grows a third shape.

## Decisions (user's, 2026-10-23)

| Question | Decision |
| --- | --- |
| Layout | A notch tab: a second, small black shape hanging from the top edge beside the island, not a wider island with an item per ear (retired 2026-09-29 as cramped) and not dots |
| How many | Two at most: the island and one tab. A third waits; "+N" counts what is beyond the two shown |
| What can take the tab | Every sticky kind but charging *(my call, approved)*: call, agent waiting, Clock timer, GitHub running, iPhone Live Activity, music, agents working |
| Blips | Take the island for their few seconds as today; the tab stays put |
| Hover | The tab's own item's card |
| Click | The tab's own item's action |
| Branch | Its own branch off `agent-island`, its own PR after that one |

## What goes where

- **The island** shows the queue's lead, as today: the highest-priority
  record, blip or sticky.
- **The tab** shows the highest-priority record other than the lead whose
  kind `canSitInTab` (sticky and not charging). None: no tab.
- With music and agents working, music fills the island and the turning
  asterisk takes the tab. A Clock timer during a call: the call in the
  island, the ring in the tab.
- "+N" (the island's overflow pip) counts records beyond the lead and the
  tab, so it appears only from three live things.
- The tab shows only while the island is at its activity size: not while
  hidden, peeking, tucked or expanded. Opening a card tucks it into the
  island; closing it buds it out again.
- Lock screen: the tab follows the island. Kinds that are never there
  (GitHub, agents) are never in the tab there either; look only, clicks do
  nothing.

## Shape

**Round, since 2026-10-23 (user's call).** On a notch the tab is now a circle
as tall as the notch (32 pt on the measured notch), 6 pt right of the island,
its top against the screen's edge like the island's, with no fillets: a
round bubble beside the island, as the iPhone's second island is. The
welded 40 pt tab below is how it first shipped. The pill keeps its circle.

**On a notch** (as first shipped) (designed against the measured 179 × 32 pt notch, MacBook Air
13″):

| Property | Value |
| --- | --- |
| Width | 40 pt |
| Height | the notch's height (32 pt), the island's own at activity size |
| Gap | 6 pt from the island's right edge |
| Top | welded to the top edge, with the island's outer fillets (6 pt) |
| Bottom corners | the island's activity radius (12 pt) |
| Fill | flat black, the island's hairline and shadow |

The tab is placed from the island's **live** right edge (the animated
parameters), so it rides along when the island widens for a caption or a
wider ear, and never overlaps it. Island and tab together take about 84 pt
of menu bar right of the notch (the 38 pt ear plus 46); status items under
them are hidden while they show, as under the ears today.

**On a screen without a notch** (the pill): a circle the pill's height,
floating at the pill's inset, 6 pt to its right.

## Motion

All with the island's springs (`NotchAnimation`).

- **Bud:** a tab appears as a sliver at the island's right edge (width 0,
  gap 0) and springs to 40 pt while the gap opens to 6, like a drop
  separating; the island's blip pulse plays on it once as it lands.
- **Merge:** a tab leaves by the same path backwards, into the island's
  edge.
- **Swap:** when the island's item ends and the tab's takes over (a timer
  finishing during a call), the tab merges while the island's content
  cross-fades to the new lead; if another item is left for the tab, a new
  tab buds.
- **Change in place:** another item taking the tab (GitHub starting while
  the asterisk sits there) swaps only the glyph, with the island's
  blur-replace; the shape stays.
- **Reduce Motion:** the tab fades in and out where it stands.

## Short forms

About 20 pt, centred, no text; the same drawings the island's leading ear
already uses, so an item reads the same when it moves.

| Kind | In the tab |
| --- | --- |
| Call | the app's icon (or the meeting service's tile), a small green dot at its corner; muted: the red crossed-out mic |
| Agent waiting | the asterisk in amber, a count from 2 |
| Clock timer | the draining ring; the stopwatch glyph; the pause glyph when paused |
| GitHub running | the check ring with its segments (`CheckRing`), else `GitHubRunRing`, a count from 2 |
| iPhone Live Activity | a match's home crest; otherwise the phone glyph |
| Music | the artwork as a small spinning disc (`SpinningArtwork`), still when paused |
| Agents working | the turning orange asterisk (`AgentGlyph`), a count from 2 |

## Interaction

- **Hover on the tab** (after the usual dwell) opens the card of the tab's
  item: call → call card, agents → Agents card, GitHub → GitHub card,
  Live Activity → its card, music → the music card. A Clock timer has no
  card: hovering only keeps it lit. Leaving closes the card as today.
- **Click on the tab** does the item's own click: the call's app forward, the
  agent's session, the Clock on its tab, the PR or run, the iPhone's card,
  and for music the music card pinned open.
- Swipes stay the island's alone. On the lock screen the tab is look only.

## Building blocks

| Unit | Where | Job |
| --- | --- | --- |
| `ActivityKind.canSitInTab` | ActivityKit | sticky and not charging |
| `ActivityQueue.tab` | ActivityKit | the highest record other than the lead that can sit in the tab; `overflowCount` counts beyond lead and tab |
| `AppModel.publish()` | Ledge | hands the tab's display to the presenter with the lead's |
| `NotchController.tab` | NotchKit | the tab's display; `isTabShowing` (activity size only); its images decoded once; which part is hovered (island or tab) and the tab's card on hover; its click |
| `NotchMetrics.tab(beside:)` | NotchKit | the tab's geometry from the island's live parameters, notch and pill |
| `NotchTabShape` | NotchKit | the tab's path, animatable in width and gap |
| `NotchRootView` | NotchKit | draws the tab and its glyph; bud, merge, swap |
| `NotchPresenter` | NotchKit | hover and clicks over island ∪ tab; which part the pointer is in; everything else still passes through to the menu bar |

## Tests

- `ActivityQueue.tab`: never charging, never a blip, none with one live
  item, the second-highest sticky otherwise; overflow counts beyond two.
- `NotchController`: the tab shows at activity size only; hidden, peek,
  tucked and expanded hide it; hovering the tab opens its item's card (and
  the timer none); its click opens the item's link or runs its intent;
  locked, nothing.
- `NotchMetrics.tab(beside:)`: on a notch, x = island right + 6, 40 × 32,
  welded; on a pill, a circle the pill's height at its inset; follows a
  wider island.
- `NotchPresenter`'s hover and click region: island ∪ tab; a point in the
  gap and a point right of the tab pass through.
- Headless renders: a timer and a call on a notch; music and agents on a
  pill; a frame halfway through the bud.

## Verify on the MacBook's own screen

With the lid open: the tab sits on the notch's bezel line with the island,
its fillets meet the top edge cleanly, status items around it stay
clickable, hover and click reach the tab's item, and a timer ending during
a call merges and swaps as described.

## Not in scope

A third item; a tab on the left; letting the user choose which kinds may
use the tab; charging in the tab; dragging items between island and tab.
