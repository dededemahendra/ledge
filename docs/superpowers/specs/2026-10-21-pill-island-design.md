# Pill island for screens without a notch — design

2026-10-21. Builds on "Screens without a notch (2026-10-21)" in
`2026-09-25-notch-companion-design.md`, which gave a Mac without a notch a
virtual 179 × 32 notch and an island drawn exactly as on the MacBook.

## Goal

On a screen without a notch (a Mac mini, a MacBook with its lid shut), the
island looks like the iPhone's Dynamic Island: a floating pill with all its
corners round, not a tab welded to the top edge. A MacBook drawing on its real
notch is unchanged, value for value.

## Decisions (user's calls, 2026-10-21)

| Question | Decision |
| --- | --- |
| Where the pill sits | Over the menu bar, 4 pt below the top edge, centred: where a notch would be |
| Width of the small pill | Narrow, iPhone-like: the empty middle shrinks from 179 to 44 pt, about 120 pt in all |
| What shows when idle | Nothing, as before; hovering the spot still opens the preview |
| The card's empty top strip | Removed: content starts 12 pt below the card's top edge |
| A blip while the card is open | The card grows the strip back (12 to 32 pt) while the ears have something to show, and shrinks again when they are empty |
| Approach | One island, a few numbers changed per screen type (not a second view, not a mask) |

## Scope

- Applies only when `IslandPlacement.isVirtual` is true. The real notch keeps
  every size, corner, fillet, animation and layout it has today.
- Not in scope: a resting pill while idle; the island following the pointer
  between displays; any change to the MacBook look; a setting to switch
  between pill and tab.

## Geometry

The pill hangs `pillTopInset` = 4 pt below the top edge. At 32 pt tall it
covers the middle of a 24 pt menu bar and reaches 12 pt below it, only while it
shows. All values below are for the pill; the MacBook's are in
`NotchMetrics` today and do not change.

| State | Size (w × h) | Corners | Notes |
| --- | --- | --- | --- |
| Hidden or tucked (`retracted`) | 0 × 0 at the top centre | n/a | A point: the pill grows out of it and shrinks back into it |
| Resting footprint (`collapsed`) | 120 × 32 | 16 all round | Never drawn while hidden; it is where hover finds the island |
| Hover, nothing coming up (`peek`) | 120 × 32 | 16 all round | An empty pill, so the hover is acknowledged |
| One activity (`oneActivity`) | 44 + 2 × ear, 120 at the default 38 pt ears | 16 all round | Ears stretch for a long Focus name, up to the existing 130 pt maximum |
| Caption or next-event line (`captioned`) | 255 to 430 × 58 | 18 all round | Same widths and height as today |
| Open card (`expanded`) | 356 × (148 + output rows), 168 + rows while a blip shows above it | 26 all round | Content area unchanged at 136 pt; output list grows it as today |

The middle gap is the virtual notch: `NotchGeometry.virtualNotchSize` becomes
44 × 32 (from 179 × 32), still centred at the top of the main display. Content
stays clear of it exactly as it stays clear of a real notch, so the existing
"nothing drawn in the hole" assertion keeps holding.

## Shape

`NotchShapeParameters` gains two animatable values, both 0 on a real notch:

- `topInset`: how far below the canvas top the island's top edge sits. 4 on
  the pill.
- `topRadius`: the radius of the two top corners, convex like the bottom ones.
  On the pill it equals `bottomRadius` in every state, and `outerFillet` is 0.

`NotchShape.path(in:)` draws a rounded rectangle when `topRadius > 0`, offset
by `topInset`, with the existing clamping of every radius to half the width
and to the height (so the 0 × 0 point draws nothing). With both values 0 the
path is the one drawn today, point for point.

Hover and click regions already come from `NotchShape` (`NotchPresenter.
islandPath(for:)`, `NotchWindow.setInteractiveShape`), so they follow the pill
with no further change. The content overlay is padded down by `topInset` so it
sits inside the pill.

## Layout

- The ears row (leading ear, middle gap, trailing ear) is 32 pt tall in every
  compact state, as today.
- In the open card the row above the content is `cardTopBand` tall. On a
  MacBook it is the notch height, always. On the pill it is 12 pt while the
  ears are empty and 32 pt while they show something
  (`NotchController.earsShowAboveCard`: any leading activity but now-playing,
  whose artwork moves into the card; the "+N" pip; or a match's crests while
  the card shows something else). The card's content frame is
  `height − cardTopBand`, which keeps the 136 pt budget pinned by
  `mediaPanelIdealHeightFitsTheExpandedBudget`, so the strip growing moves the
  content down rather than squeezing it.
- Caption rows keep their position under the 32 pt row.
- `NotchMetrics.oneActivity` on the pill is `notchRect.width + 2 × ear`. On the
  real notch it keeps today's `255 + 2 × (ear − 38)`, unchanged even in a
  scaled display mode with a wider notch.

## Motion

- The springs are unchanged. `NotchAnimation.isExpanding` compares areas, so
  growing out of the 0 × 0 point is growth (the pop spring) and shrinking into
  it is a collapse.
- `NotchRootView`'s `fromHidden` test compares against `retracted` (what a
  hidden island draws) instead of `collapsed`. On a real notch the two are
  equal, so nothing changes there; on the pill only growth out of the point
  counts as an arrival and gets the pop, while hover-pill to card keeps the
  expand spring, as a MacBook's lip-to-card does.
- After the shrink the window orders out after `NotchAnimation.hideSettle`, as
  today. The zero-height slide-up from the virtual-notch change is replaced by
  the shrink into the point.
- Reduce Motion keeps its crossfade path.
- The artwork's matched-geometry flight between the compact pill and the card
  is unaffected.

## Hover

With nothing showing, the hover zone is the resting footprint plus the
existing forgiveness (+8 wide, +4 tall), stretched up over the 4 pt inset to
the very top edge: 128 × 40 from the top of the screen. A pointer pushed hard
against the top edge finds it, as it finds a MacBook's notch. The hover
preview (`peek`) gets the same forgiveness and stretch. The stretch applies in
every state on the pill: the zone and click region of a visible pill or card
also reach up to the top edge (the +8/+4 forgiveness stays with hidden and
preview only). `NotchPresenter.hoverParameters` already uses `collapsed` for
the hidden state; it gains the stretch in every state.

## Edge cases

- Lock (tucked): draws `retracted`, so the pill shrinks into its point.
- Display hot-plug between a real and a virtual notch: `rebuildForCurrentScreen`
  swaps the metrics and with them the style; nothing else holds style state.
- The two-row caption pill at 58 pt tall uses 18 pt corners, a rounded
  rectangle rather than a capsule, as the iPhone's taller island does.
- Ear content beside a round end: a 24 pt glyph centred in a 38 pt ear clears
  a 16 pt end radius by about 1 pt. If the render tests show clipping, the
  pill's ears grow to 40 pt (pill 124 wide); that is the only planned
  fallback.

## Testing

- MacBook unchanged: one test lists every state's parameters on the measured
  real notch (and on the scaled 208 × 37 notch) and compares them with today's
  exact values, including `topInset` and `topRadius` of 0.
- Pill metrics: each row of the geometry table above.
- Shape: the pill path starts at `topInset`; all four corners are outside the
  path (rounded); it has no flare beyond its width; the 0 × 0 point is empty.
  Existing `NotchShapeTests` for the notch outline still pass.
- Hover: the hidden pill's hover zone is 128 × 40 from the top edge, and
  contains a point 0.5 pt below the edge at the centre.
- Card strip: `earsShowAboveCard` for each case above, and the pill card's
  height with and without it, with and without the output list.
- Render (`NotchRenderTests`, the real SwiftUI tree off screen): compact ear
  content is not clipped by the round ends; the card's content fits under the
  12 pt top; the pill silhouette matches its parameters.
- Full suite: `make test`, all passing except the two brightness tests that
  need a MacBook's built-in panel.
- Live, on the Mac mini: a scripted volume change, screenshotted, for the
  pill's width, inset and round ends. Hover, the preview and the open card are
  checked by the user, since driving the pointer is not done from the session.

## Docs

On implementation: a dated section in `2026-09-25-notch-companion-design.md`
superseding the virtual notch's 179 × 32 tab and its slide-up, and the
README's "Build and run" paragraph on Macs without a notch.
