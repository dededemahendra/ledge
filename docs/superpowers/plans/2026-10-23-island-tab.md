# Two at once: the island's tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The island shows two live things at once: its lead in the island and the next live item in a small black tab beside it, shaped for the MacBook's notch (a second notch-height tab welded to the top edge) and a circle beside the pill on other screens; hovering the tab opens its item's card, clicking it does its item's click.

**Architecture:** `ActivityQueue` picks the tab's record (`tab`) and a pip count beyond what's shown (`overflowBeyondTab`). `AppModel.publish()` hands the tab's display to the presenter with the lead's. `NotchController` owns the tab's display, whether it shows, its animatable geometry (`tabParameters`, from `NotchMetrics.tab(beside:)` and `tabTucked(beside:)`), which part is hovered, and the tab's card and click. `NotchTabShape` draws it; `TabGlyph` draws each kind's short form; `NotchPresenter` claims hover and clicks over island ∪ tab.

**Tech Stack:** Swift 6, SwiftUI, AppKit, swift-testing. macOS 27.

**Spec:** `docs/superpowers/specs/2026-10-23-island-tab-design.md`

## Global Constraints

- Two at most: the island and one tab. Never a third shape.
- `ActivityKind.canSitInTab`: sticky (`defaultTTL == nil`) and not `.charging` — so `call`, `agentWaiting`, `timer`, `githubRun`, `liveActivity`, `media`, `agentRun`.
- The tab's record: the highest-priority record other than the lead whose kind `canSitInTab`; none → no tab.
- The pip ("+N") counts records that are neither the lead, nor the tab, nor charging.
- The tab shows only while `state == .activity` and not tucked: hidden, peek, expanded and tucked hide it.
- Notch geometry: width 40 pt, height = the notch's height (32 pt on the target Mac), gap 6 pt from the island's live right edge, welded to the top edge (topInset 0), outer fillets 6 pt, bottom radius 12 pt.
- Pill geometry (no notch): a circle whose diameter is the pill's height, at the pill's top inset (`NotchMetrics.pillTopInset`), 6 pt right of the pill.
- Bud: from width 0 and gap 0 at the island's right edge to 40 and 6, the island's springs; merge is the reverse; Reduce Motion fades in place.
- Hover on the tab opens its item's card: call → `.call`, the three agent ids → `.agents`, `githubActivityID`/`githubRunActivityID` → `.github`, `liveActivityID` → `.liveActivity`, `mediaActivityID` → `.media`; a timer has no card (hover only keeps it lit, never expands, even with music playing).
- Click on the tab: `mediaActivityID` → pin the music card (`click()`); anything else with a `url` → `emit(.open(url))`. Locked: nothing.
- Short forms (≈20 pt, no text) as the spec's table; the same drawings the leading ear uses.
- Run tests with `make test` / `make test FILTER=<name>`; exactly two pre-existing `HUDServiceTests` brightness failures on this Mac (no built-in display). No new warnings.
- Commits: the repo's lowercase sentence style, then `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **The island widens while a tab shows** (a song caption, a wider ear): the tab rides along at the island's live right edge and never overlaps it. Pinned by `theTabFollowsAWiderIsland` (Task 2) and `theTabParametersFollowTheIslandsLiveShape` (Task 3).
2. **Clicks on the menu bar around the island and tab** (in the 6 pt gap, right of the tab, below it) pass through to the menu bar. Pinned by `pointsInTheGapAndBesideTheTabPassThrough` (Task 4).
3. **The lead ends and the tab's item takes over** (a timer finishing during a call): the same item is never in both places, and the next live item buds into the tab. Pinned by `theTabIsNeverTheLead` and `whenTheLeadGoesTheTabMovesUp` (Task 1).
4. **Hovering a timer tab while music plays** must not open the music card. Pinned by `hoveringATimerTabOpensNothing` (Task 3).
5. **Lock screen:** the tab is look only — hover may open its card (look only, as the island's), a click does nothing. Pinned by `whileLockedTheTabsClickDoesNothing` (Task 3).

---

### Task 1: Which record gets the tab

**Files:**
- Modify: `Sources/ActivityKit/ActivityKind.swift`, `Sources/ActivityKit/ActivityQueue.swift`
- Test: `Tests/ActivityKitTests/ActivityQueueTests.swift`

**Interfaces:**
- Produces: `extension ActivityKind { public var canSitInTab: Bool }`; on `ActivityQueue`: `public var tab: ActivityRecord? { get }` and `public var overflowBeyondTab: Int { get }`. `visible` and `overflowCount` are unchanged.

- [ ] **Step 1: Write the failing tests:**

```swift
@Test func onlyStickyKindsButChargingCanSitInTheTab()
    // every case of ActivityKind.allCases: canSitInTab == (defaultTTL == nil && self != .charging)
    // so .call, .agentWaiting, .timer, .githubRun, .liveActivity, .media, .agentRun are true; .charging and every blip false
@Test func oneLiveItemHasNoTab()                 // only .media → tab nil
@Test func theSecondLiveItemTakesTheTab()        // .media + .agentRun → lead media (ordered.first), tab agentRun
@Test func chargingNeverTakesTheTab()            // .media + .charging → tab nil; overflowBeyondTab 0
@Test func aBlipLeadsAndTheTopStickyTakesTheTab()// .hud + .timer + .media → lead hud, tab timer, overflowBeyondTab 1 (media)
@Test func theTabIsNeverTheLead()                // .call alone → lead call, tab nil; .call + .timer → tab timer, not call
@Test func whenTheLeadGoesTheTabMovesUp()        // .call + .timer + .agentRun → tab timer; remove(.call) → lead timer, tab agentRun
@Test func thePipCountsBeyondTheTwoShownAndNotCharging()
    // .call + .timer + .media + .agentRun + .charging → lead call, tab timer, overflowBeyondTab 2
```

- [ ] **Step 2: Run them to make sure they fail.** `make test FILTER=ActivityQueueTests`. Expected: compile failure.
- [ ] **Step 3: Implement.** `canSitInTab`: `defaultTTL == nil && self != .charging`, with a dated doc comment. `tab`: `ordered.dropFirst().first { $0.kind.canSitInTab }`. `overflowBeyondTab`: `ordered.dropFirst()` filtered to drop the tab's record and `.charging`, counted.
- [ ] **Step 4: Run the tests to see them pass.** Expected: all pass, the existing ones included.
- [ ] **Step 5: Commit**: "pick the island's tab: the next live item after the lead, never charging, and a pip only beyond the two shown".

### Task 2: The tab's geometry and shape

**Files:**
- Create: `Sources/NotchKit/NotchTabShape.swift`
- Modify: `Sources/NotchKit/NotchMetrics.swift`
- Test: `Tests/NotchKitTests/NotchTabGeometryTests.swift`

**Interfaces:**
- Produces:

```swift
/// The tab beside the island (2026-10-23), relative to the island's own
/// live parameters: the shape is drawn from the island's right edge out.
public struct NotchTabParameters: Sendable, Equatable, Animatable {
    public var gap: CGFloat          // 6 shown, 0 tucked
    public var width: CGFloat        // 40 shown (pill: the pill's height), 0 tucked
    public var height: CGFloat       // the notch's height (pill: the pill's height)
    public var bottomRadius: CGFloat // 12 (pill: height / 2)
    public var outerFillet: CGFloat  // 6 on a notch, 0 on a pill
    public var topInset: CGFloat     // 0 on a notch, NotchMetrics.pillTopInset on a pill
    public var topRadius: CGFloat    // 0 on a notch, height / 2 on a pill
    public var animatableData: … // gap, width, height
}
extension NotchMetrics {
    public static let tabWidth: CGFloat = 40
    public static let tabGap: CGFloat = 6
    public func tab(beside island: NotchShapeParameters) -> NotchTabParameters
    public func tabTucked(beside island: NotchShapeParameters) -> NotchTabParameters   // gap 0, width 0, else as `tab`
}
/// The tab's path in the island's canvas: x from `rect.midX + island.width / 2 + tab.gap`.
public struct NotchTabShape: Shape, Animatable {
    public var island: NotchShapeParameters
    public var tab: NotchTabParameters
    public init(island: NotchShapeParameters, tab: NotchTabParameters)
    public var animatableData: AnimatablePair<NotchShapeParameters.AnimatableData, NotchTabParameters.AnimatableData>
    public func path(in rect: CGRect) -> Path
}
```

  The path mirrors `NotchShape`'s construction (read `Sources/NotchKit/NotchShape.swift`): on a notch, a flat top welded to `rect.minY` with concave outer fillets of `outerFillet` at both top corners and convex bottom corners of `bottomRadius`; on a pill (`topRadius > 0`), a capsule/circle at `topInset`. Width 0 draws an empty path.

- [ ] **Step 1: Write the failing tests:**

```swift
@Test func onANotchTheTabIsAFortyPointTabBesideTheIsland()
    // metrics = NotchMetrics(notchRect: CGRect(x: 0, y: 0, width: 179, height: 32)); island = metrics.oneActivity
    // tab(beside:) → gap 6, width 40, height 32, bottomRadius 12, outerFillet 6, topInset 0, topRadius 0
    // NotchTabShape(island: island, tab: t).path(in: canvas).boundingRect: minX == canvas.midX + island.width/2 + 6 (± the fillet's reach, documented), maxX == minX + 40 (+ fillet), minY == 0, height == 32
@Test func onAPillTheTabIsACircleBesideThePill()
    // isVirtual: true → width == height == the pill's height, topInset == pillTopInset, topRadius == height/2, outerFillet 0
@Test func theTabFollowsAWiderIsland()
    // island = metrics.captioned(fitting: 400) → the path's minX moves right by (400 - oneActivity.width)/2, never below the island's maxX + 6
@Test func aTuckedTabHasNoWidthAtTheIslandsEdge()
    // tabTucked(beside:) → gap 0, width 0; its path is empty
```

- [ ] **Step 2: Run them to make sure they fail.** `make test FILTER=NotchTabGeometryTests`. Expected: compile failure.
- [ ] **Step 3: Implement** the interface above.
- [ ] **Step 4: Run the tests to see them pass.**
- [ ] **Step 5: Commit**: "shape the tab: a forty point notch tab welded beside the island, a circle beside the pill, tucked to nothing at its edge".

### Task 3: The controller's tab: showing, hover, card and click

**Files:**
- Modify: `Sources/NotchKit/NotchController.swift`, `Sources/NotchKit/NotchPresenter.swift` (forwarding only), `Sources/NotchKit/NotchRootView.swift` (only where the Live Activity card reads its activity — see Step 3)
- Test: `Tests/NotchKitTests/NotchControllerTests.swift`

**Interfaces:**
- Consumes: Task 2's `NotchTabParameters`, `metrics.tab(beside:)`, `metrics.tabTucked(beside:)`.
- Produces, on `NotchController`:
  - `public func setActivities(_ activities: [ActivityDisplay], overflow: Int, tab: ActivityDisplay? = nil)` (existing callers keep working);
  - `public private(set) var tab: ActivityDisplay?`;
  - `public var isTabShowing: Bool` — `tab != nil && state == .activity && !isTucked`;
  - `public var tabParameters: NotchTabParameters` — `isTabShowing ? metrics.tab(beside: parameters) : metrics.tabTucked(beside: parameters)`;
  - `public enum HoverPart: Sendable, Equatable { case island, tab }` and `public func setHovered(_ hovered: Bool, part: HoverPart)` (the existing `setHovered(_:)` means `.island`);
  - `public private(set) var hoveredPart: HoverPart?`;
  - `public func tapTab()`;
  - `public private(set) var tabArtworkImage: NSImage?` and `tabCrestImage: NSImage?`, decoded once per change (as `callIconImage`);
  - `public var liveActivityDisplay: ActivityDisplay?` — the lead if it is the Live Activity, else the tab if it is.
- On `NotchPresenter`: `setActivities(_:overflow:tab:)` forwarding and resyncing.

- [ ] **Step 1: Write the failing tests** (in the style of `hoveringAnAgentItemOpensTheAgentsCard`):

```swift
@MainActor @Test func theTabShowsOnlyAtActivitySize()
    // lead media + tab agentRun: .activity → isTabShowing; setHovered(true) over the island with media → .expanded → false;
    // hidden (no activities) → false; setTucked(true) → false
@MainActor @Test func theTabParametersFollowTheIslandsLiveShape()
    // showing → tabParameters == metrics.tab(beside: parameters); setCaption so the island is captioned → still equal to tab(beside: the new parameters)
@MainActor @Test func hoveringTheTabOpensItsItemsCard()
    // lead media, tab call + setCallPanel(sample) → setHovered(true, part: .tab) → panel .call, .expanded
    // tab agent-run + setAgentPanel(sample) → .agents; tab github-run + setGitHubPanel → .github
@MainActor @Test func hoveringATimerTabOpensNothing()
    // lead media (setMedia(sample)) + tab timer → setHovered(true, part: .tab) → state stays .activity, panel stays .media, hoveredPart .tab
@MainActor @Test func hoveringTheIslandStillOpensTheLeadsCard()
    // lead call (callPanel set) + tab agent-run → setHovered(true, part: .island) → .call
@MainActor @Test func clickingTheTabDoesItsItemsClick()
    // tab with url ledge://agent/s1 → tapTab() emits .open(that url); tab media → tapTab() pins the music card (isPinnedOpen, .expanded)
@MainActor @Test func whileLockedTheTabsClickDoesNothing()
    // setLocked(true); tapTab() → no intent, not pinned
@MainActor @Test func theTabsImagesAreDecodedOnce()
    // the same artwork twice → tabArtworkImage identical instance (===)
@MainActor @Test func aLiveActivityInTheTabOpensItsCard()
    // lead media + tab liveActivity with lines ["A", "B"] → hover tab → panel .liveActivity, .expanded; liveActivityDisplay == the tab
```

- [ ] **Step 2: Run them to make sure they fail.** `make test FILTER=NotchControllerTests`. Expected: compile failure.
- [ ] **Step 3: Implement.**
  - `setHovered(_:part:)` records `hoveredPart` (nil when not hovered). Over the tab it picks the tab item's panel per Global Constraints (only when that panel's data exists, and not when pinned). `recomputeState` keeps a hovered tab whose item has no card (or no card data) at `.activity` — it must not fall into the "hovered with media → expanded" branch.
  - `hasCard`, `hasPanelContent` and the Live Activity card read `liveActivityDisplay` instead of `activities.first` when `panel == .liveActivity`; the ears' `score` stays the lead's. In `NotchRootView`'s `detailRow`, the `.liveActivity` branches (~line 1306-1315) read the card's score and lines from `liveActivityDisplay`; the crests decode from it too.
  - `tapTab()`: guard not locked and `isTabShowing`; `mediaActivityID` → `click()`; else `tab.url` → `emit(.open(url))`.
  - Decode `tabArtworkImage` from `tab.artwork` and `tabCrestImage` from `tab.score?.home.crest` once per change.
- [ ] **Step 4: Run the tests to see them pass**, then `make test FILTER=NotchControllerTests` for all of them.
- [ ] **Step 5: Commit**: "give the controller its tab: shown at activity size only, its card on hover, its click, and a live activity's card from wherever it sits".

### Task 4: Hover and clicks over island and tab

**Files:**
- Modify: `Sources/NotchKit/NotchPresenter.swift`
- Test: `Tests/NotchKitTests/NotchPresenterRegionTests.swift` (new; static functions only, no window)

**Interfaces:**
- Consumes: `NotchTabShape`, `controller.tabParameters`, `controller.isTabShowing`, `setHovered(_:part:)`.
- Produces: `nonisolated static func hoverPart(at point: CGPoint, island: NotchShapeParameters, tab: NotchTabParameters?, metrics: NotchMetrics) -> NotchController.HoverPart?` (nil = outside both) and the interactive region as the union of the island's forgiving path and, when the tab shows, the tab's path.

- [ ] **Step 1: Write the failing tests:**

```swift
@Test func aPointOnTheIslandIsTheIsland()
@Test func aPointOnTheTabIsTheTab()
@Test func pointsInTheGapAndBesideTheTabPassThrough()
    // the gap's centre (island maxX + 3, y 10), 4 pt right of the tab's maxX, 4 pt below the tab's bottom → nil
@Test func withNoTabOnlyTheIslandCounts()          // tab nil → a point where the tab would be → nil
```

- [ ] **Step 2: Run them to make sure they fail.** Expected: compile failure.
- [ ] **Step 3: Implement.** `reevaluateHover()` uses `hoverPart(at:…)`: inside either part is "inside" for the dwell tracker; on the promoted hover, call `controller.setHovered(true, part:)` with the part under the pointer; moving from island to tab while hovered re-calls it with the new part (no dwell restart). `refreshInteractiveRegion()` sets the union path. Nothing else changes: the hidden/peek forgiveness stays the island's.
- [ ] **Step 4: Run the tests to see them pass.**
- [ ] **Step 5: Commit**: "claim hover and clicks over the island and its tab, and nothing in between".

### Task 5: Draw the tab and its short forms

**Files:**
- Create: `Sources/NotchKit/TabGlyph.swift`
- Modify: `Sources/NotchKit/NotchRootView.swift`

**Interfaces:**
- Consumes: Tasks 2-4.
- Produces: `struct TabGlyph: View { let display: NotchController.ActivityDisplay; let controller: NotchController }` drawing the spec's short-form table at about 20 pt.

- [ ] **Step 1: `TabGlyph`.** By id, reusing the existing drawings (read their call sites in `leadingEar`):
  - `callActivityID`: `controller.tabArtworkImage` at 20 pt (rounded 5) with a 6 pt green dot at its bottom trailing corner; `mic.slash.fill` red when the record's symbol is `mic.slash.fill`;
  - `agentWaitingActivityID`: `AgentGlyph(color: amber, turning: false, count: display.badge)`; `agentRunActivityID`: `AgentGlyph(color: AgentColors.orange, turning: true, count: display.badge)`;
  - `timerActivityID`: the timer ring (the leading ear's ring code, extracted into a small `TimerRing(fill:color:)` view so both use it) or the record's symbol (stopwatch, pause);
  - `githubRunActivityID`: `CheckRing(segments:)` when segments, else `GitHubRunRing(color:count:)`;
  - `liveActivityID`: `controller.tabCrestImage` as a 20 pt circle, else `iphone` symbol;
  - `mediaActivityID`: `SpinningArtwork` with `controller.mediaArtworkImage` at 20 pt (still when paused).
- [ ] **Step 2: Draw the tab** in `NotchRootView`'s top `ZStack`, behind nothing and beside the island: `NotchTabShape(island: parameters, tab: controller.tabParameters)` filled black with the island's hairline and shadow, and `TabGlyph` centred in the tab's frame (x = canvas midX + island.width/2 + gap + width/2, y = topInset + height/2), clipped to the tab shape, keyed `.id(tab.id)` with `.transition(.blurReplace)`. The tab's shape and content animate with the island's `.animation(…, value: parameters)` plus `value: controller.tabParameters`, so bud and merge use the same springs. A new tab id plays the island's blip pulse on the tab once. Reduce Motion: no bud; the tab's opacity fades between 0 and 1 in place.
- [ ] **Step 3: Check the renders headlessly.** A temporary (not committed) test renders `NotchRootView` at `NotchMetrics.canvasSize`, scale 4, PNGs to `/private/tmp/claude-502/-Users-gedemahendra-Developer-Project-ledge/1b720ec9-b36d-48fd-a702-0892efb9025b/scratchpad/renders/t-*.png`: (a) a notch (179 × 32), lead timer ring "4:12", tab call with an app icon; (b) a pill, lead music, tab agents working with a count of 2; (c) a notch, the tab at gap 3 / width 20 (half-way through a bud, set via a test-only override or by building `NotchTabShape` directly into the render). Look at each with the Read tool and describe them. Delete the test.
- [ ] **Step 4: Run the whole suite.** `make test`. Expected: all pass but the two known brightness tests; `NotchRenderTests` pass.
- [ ] **Step 5: Commit**: "draw the tab: a second notch beside the island with each live item's short form, budding out and merging back".

### Task 6: Wire the tab in AppModel, and a probe

**Files:**
- Modify: `Sources/Ledge/AppModel.swift`

- [ ] **Step 1:** In `publish()`, build the tab's display from `queue.tab` with the same mapping as the lead's and call `presenter.setActivities(display, overflow: queue.overflowBeyondTab, tab: tabDisplay)`.
- [ ] **Step 2: Probe (debug).** `ledge://probe/tab`: inserts a sticky `.timer` record (id `NotchController.timerActivityID`, ring at 0.6, "4:12") and a sticky `.agentRun` record (id `agentRunActivityID`, "1:05", orange, badge 2) for 20 s, publishes, then removes both. Logged as "probe: tab". In `openURL`'s `#if DEBUG` block.
- [ ] **Step 3:** `make test`. Expected: all pass but the two known brightness tests; no new warnings.
- [ ] **Step 4: Commit**: "hand the island its tab: the next live item beside the lead, and a probe that shows two at once".

### Task 7: Docs

**Files:**
- Modify: `README.md`: a sentence near the "What it shows" table: two live things at once, the island and a tab beside it (on a MacBook a second notch-height tab, on other screens a circle), hover the tab for its card, click it for its action; the island's "+N" only from three.
- Modify: `docs/superpowers/specs/2026-09-25-notch-companion-design.md`: in §6's table, the retired "2+ activities" row gets a pointer: "2026-10-23: two at once returns as the tab beside the island — see `2026-10-23-island-tab-design.md`".
- Modify: `docs/manual-checks.md`: "## Two at once: the tab (2026-10-23)" with the renders checked and, pending, the spec's "Verify on the MacBook's own screen" list.

- [ ] **Step 1: Make the three edits.**
- [ ] **Step 2: Commit**: "describe the tab in the readme, the companion spec and the manual checks".
