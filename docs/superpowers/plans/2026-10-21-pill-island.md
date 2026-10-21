# Pill Island Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On a screen without a notch, draw the island as a floating, fully rounded pill like the iPhone's Dynamic Island, leaving a MacBook's notch island exactly as it is.

**Architecture:** One island, a few numbers changed per screen type. `NotchShapeParameters` gains a top inset and a top-corner radius (both 0 on a real notch); `NotchMetrics` returns pill sizes when `isVirtual`; the controller reports when the ears show something above an open card so the pill's card can grow its top strip back; the presenter stretches the hidden pill's hover zone to the top edge; the root view pads content by the inset and sizes the card's top band from the metrics.

**Tech Stack:** Swift 6.4, Swift 6 language mode, SwiftUI + AppKit, SwiftPM only (no Xcode project), swift-testing (`import Testing`, `@Test`, `#expect`), macOS 27.

**Spec:** `docs/superpowers/specs/2026-10-21-pill-island-design.md` (read it with this plan).

## Global Constraints

- A real notch (`NotchMetrics.isVirtual == false`) keeps every `NotchShapeParameters` value it has today, in the measured 179 × 32 notch and in a scaled mode's 208 × 37 one; the new `topInset` and `topRadius` are 0 there.
- Pill numbers: float 4 pt below the top edge; middle 44 × 32; small pill 120 × 32 with 16 pt round ends; caption pill 255 to 430 × 58 with 18 pt corners; card 356 × (136 + top band + output rows) with 26 pt corners; top band 12 pt, 32 pt while the ears show something; hidden is a 0 × 0 point; hidden and hover-preview zones reach up to the top edge.
- Run tests with `make test` (it adds the swift-testing plugin path); narrow with `make test FILTER=<name>`. Never call bare `swift test`.
- Two tests fail on a Mac without a built-in panel and are not this plan's concern: `brightnessTargetsTheBuiltInDisplay` and `bridgeLoadsAndReadsARealBrightnessValue`. Every other test must pass.
- Comments follow the files' own style: plain sentences, dated rationale like `(2026-10-21)` where a decision is recorded. Match the surrounding density.
- `@State` cannot be used as a macro on this toolchain; this plan adds no view state, so it does not come up.
- Commit messages follow the repo's history: one lowercase plain-English sentence, no prefix, ending with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Pointer pushed hard against the top edge over a hidden pill: the preview opens, as it does under a MacBook's notch (Task 3, `aHiddenPillIsHoveredFromTheTopEdgeDown`).
2. Display change with a blip up (MacBook lid shut while the island shows): the next read is the pill's size, nothing notch-shaped left over (Task 3, `swappingToAPillMidBlipResizesAtOnce`).
3. Reduce Motion on the pill: it still draws correctly, content inside its outline (Task 4, `pillRendersUnderReduceMotion`).
4. The card's strip growing while the output list is open: 136 + 32 + rows (Task 2, `pillCardGrowsItsStripOnlyWhileTheEarsShowSomething`).
5. A MacBook in a scaled display mode: every size unchanged (Task 2, `realNotchSizesAreExactlyAsBefore`).

## Before Task 1

- [ ] Run `git status`. The tree may still carry earlier uncommitted work (the virtual notch, warnings moved to Settings, dash removal) and this plan's spec. Follow the user's decision on committing it first, so each task's commit holds only that task.

## File structure

| File | Change |
| --- | --- |
| `Sources/NotchKit/NotchShape.swift` | Parameters gain `topInset`, `topRadius`; path draws a floating rounded shape when `topRadius > 0` |
| `Sources/NotchKit/NotchGeometry.swift` | `virtualNotchSize` becomes the pill's 44 × 32 middle |
| `Sources/NotchKit/NotchMetrics.swift` | Pill sizes when `isVirtual`; `cardTopBand(earsShowing:)`; `expanded(outputRows:earsShowing:)` |
| `Sources/NotchKit/NotchController.swift` | `earsShowAboveCard`; `.expanded` passes it to the metrics |
| `Sources/NotchKit/NotchPresenter.swift` | `hoverParameters` stretches over the inset to the top edge |
| `Sources/NotchKit/NotchRootView.swift` | `NotchAnimation.isArrival`; content padded by the inset; card top band from the metrics |
| `Tests/NotchKitTests/*` | Shape, metrics, geometry, controller, presenter, animation tests |
| `Tests/NotchRenderTests/NotchRootViewRenderTests.swift` | Pill render tests |
| `README.md`, `docs/superpowers/specs/2026-09-25-notch-companion-design.md` | Docs |

---

### Task 1: The shape can float and round its top corners

**Files:**
- Modify: `Sources/NotchKit/NotchShape.swift` (the whole `NotchShapeParameters` struct and `NotchShape.path(in:)`)
- Test: `Tests/NotchKitTests/NotchShapeTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `NotchShapeParameters.init(width:height:bottomRadius:outerFillet:topInset:topRadius:)` with `topInset: CGFloat = 0`, `topRadius: CGFloat = 0`; stored `var topInset: CGFloat`, `var topRadius: CGFloat`, both animatable and interpolated by `lerp`. `NotchShape.path(in:)` draws a pill (convex top corners, no fillets, offset by `topInset`) when `topRadius > 0`.

- [ ] **Step 1: Write the failing tests.** Append to `Tests/NotchKitTests/NotchShapeTests.swift`:

```swift
// MARK: - The pill (2026-10-21)

private let pillCapsule = NotchShapeParameters(
    width: 120, height: 32, bottomRadius: 16, outerFillet: 0, topInset: 4, topRadius: 16
)

@Test func newValuesDefaultToZeroSoTheNotchOutlineIsUnchanged() {
    let p = NotchShapeParameters(width: 255, height: 32, bottomRadius: 12, outerFillet: 6)
    #expect(p.topInset == 0)
    #expect(p.topRadius == 0)
}

@Test func pillFloatsAtItsInset() {
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    let bounds = NotchShape(pillCapsule).path(in: canvas).boundingRect
    #expect(abs(bounds.minY - 4) < 0.5, "the pill floats 4 pt below the top edge")
    #expect(abs(bounds.height - 32) < 0.5)
    #expect(abs(bounds.width - 120) < 0.5)
    #expect(abs(bounds.midX - canvas.midX) < 0.5)
}

@Test func pillEndsAreRoundTopAndBottom() {
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    let path = NotchShape(pillCapsule).path(in: canvas)
    let left = canvas.midX - 60, right = canvas.midX + 60
    let top: CGFloat = 4, bottom: CGFloat = 36
    // 2 pt in from each corner: inside a square corner, outside a 16 pt round one.
    for corner in [CGPoint(x: left + 2, y: top + 2), CGPoint(x: right - 2, y: top + 2),
                   CGPoint(x: left + 2, y: bottom - 2), CGPoint(x: right - 2, y: bottom - 2)] {
        #expect(!path.contains(corner), "\(corner) should be cut away by a round end")
    }
    #expect(path.contains(CGPoint(x: left + 1, y: top + 16)), "the end's widest point reaches the edge")
    #expect(path.contains(CGPoint(x: canvas.midX, y: top + 1)), "the top edge is straight between the ends")
}

/// A pill has nothing to blend into: an outer fillet left in its
/// parameters must not flare it wider.
@Test func pillIgnoresOuterFillets() {
    var flared = pillCapsule
    flared.outerFillet = 6
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    #expect(abs(NotchShape(flared).path(in: canvas).boundingRect.width - 120) < 0.5)
}

/// The point a hidden pill shrinks into draws nothing.
@Test func aZeroSizedPillCoversNothing() {
    let point = NotchShapeParameters(width: 0, height: 0, bottomRadius: 16, outerFillet: 0, topInset: 4, topRadius: 16)
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    let path = NotchShape(point).path(in: canvas)
    #expect(path.boundingRect.width < 0.5 && path.boundingRect.height < 0.5)
    #expect(!path.contains(CGPoint(x: canvas.midX, y: 4)))
}

/// Mid-growth the two ends share the height: neither radius may pass half
/// of it, so a short pill is rounded top AND bottom, not square on top.
@Test func pillRadiiShareTheHeight() {
    let small = NotchShapeParameters(width: 40, height: 10, bottomRadius: 16, outerFillet: 0, topInset: 4, topRadius: 16)
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    let path = NotchShape(small).path(in: canvas)
    let left = canvas.midX - 20, top: CGFloat = 4, bottom: CGFloat = 14
    #expect(abs(path.boundingRect.height - 10) < 0.5)
    #expect(!path.contains(CGPoint(x: left + 0.5, y: top + 0.5)), "the top end is rounded too")
    #expect(!path.contains(CGPoint(x: left + 0.5, y: bottom - 0.5)))
}

@Test func pillValuesInterpolateAndRoundTrip() {
    let point = NotchShapeParameters(width: 0, height: 0, bottomRadius: 16, outerFillet: 0, topInset: 4, topRadius: 16)
    let mid = NotchShapeParameters.lerp(point, pillCapsule, 0.5)
    #expect(mid.topInset == 4)
    #expect(mid.topRadius == 16)
    #expect(mid.width == 60)

    var p = pillCapsule
    let captured = p.animatableData
    p.topInset = 0; p.topRadius = 0
    p.animatableData = captured
    #expect(p.topInset == 4)
    #expect(p.topRadius == 16)
}
```

- [ ] **Step 2: Run them and watch them fail.**

Run: `make test FILTER=NotchKitTests`
Expected: build fails with `extra arguments at positions #5, #6 in call` / `value of type 'NotchShapeParameters' has no member 'topInset'`.

- [ ] **Step 3: Implement.** In `Sources/NotchKit/NotchShape.swift`, replace the whole `NotchShapeParameters` struct with:

```swift
/// The six animated dimensions of the island.
public struct NotchShapeParameters: Sendable, Equatable, Animatable {
    public var width: CGFloat
    public var height: CGFloat
    public var bottomRadius: CGFloat
    public var outerFillet: CGFloat
    /// How far below the canvas top the island's top edge sits (2026-10-21):
    /// 0 on a real notch, welded to the bezel; the pill's float on a screen
    /// without one.
    public var topInset: CGFloat
    /// Radius of the two top corners, convex like the bottom ones: 0 on a
    /// real notch, the pill's round ends without one. Above 0 the shape is a
    /// pill and `outerFillet` is ignored.
    public var topRadius: CGFloat

    public init(
        width: CGFloat, height: CGFloat, bottomRadius: CGFloat, outerFillet: CGFloat,
        topInset: CGFloat = 0, topRadius: CGFloat = 0
    ) {
        self.width = width
        self.height = height
        self.bottomRadius = bottomRadius
        self.outerFillet = outerFillet
        self.topInset = topInset
        self.topRadius = topRadius
    }

    public var animatableData: AnimatablePair<
        AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>,
        AnimatablePair<CGFloat, CGFloat>
    > {
        get {
            AnimatablePair(
                AnimatablePair(
                    AnimatablePair(width, height),
                    AnimatablePair(bottomRadius, outerFillet)
                ),
                AnimatablePair(topInset, topRadius)
            )
        }
        set {
            width = newValue.first.first.first
            height = newValue.first.first.second
            bottomRadius = newValue.first.second.first
            outerFillet = newValue.first.second.second
            topInset = newValue.second.first
            topRadius = newValue.second.second
        }
    }

    public static func lerp(
        _ a: NotchShapeParameters,
        _ b: NotchShapeParameters,
        _ t: Double
    ) -> NotchShapeParameters {
        let t = CGFloat(min(max(t, 0), 1))
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
        return NotchShapeParameters(
            width: mix(a.width, b.width),
            height: mix(a.height, b.height),
            bottomRadius: mix(a.bottomRadius, b.bottomRadius),
            outerFillet: mix(a.outerFillet, b.outerFillet),
            topInset: mix(a.topInset, b.topInset),
            topRadius: mix(a.topRadius, b.topRadius)
        )
    }
}
```

Then replace the whole `path(in:)` method of `NotchShape` with:

```swift
    public func path(in rect: CGRect) -> Path {
        let centreX = rect.midX
        let top = rect.minY + max(0, parameters.topInset)
        let height = max(0, parameters.height)
        let halfWidth = max(0, parameters.width) / 2
        let isPill = parameters.topRadius > 0
        // Radii cannot exceed the box they round, or the path self-intersects.
        let bottomRadius: CGFloat
        let topRadius: CGFloat
        if isPill {
            // The pill (2026-10-21): its two ends share the height, so
            // neither radius may pass half of it.
            let limit = min(halfWidth, height / 2)
            bottomRadius = min(parameters.bottomRadius, limit)
            topRadius = min(parameters.topRadius, limit)
        } else {
            bottomRadius = min(parameters.bottomRadius, halfWidth, height)
            topRadius = 0
        }
        let fillet = isPill ? 0 : max(0, min(parameters.outerFillet, height - bottomRadius))

        let left = centreX - halfWidth
        let right = centreX + halfWidth
        let bottom = top + height

        var path = Path()
        if topRadius > 0 {
            // Convex top-left: a floating pill has nothing to weld to.
            path.move(to: CGPoint(x: left + topRadius, y: top))
            path.addArc(
                center: CGPoint(x: left + topRadius, y: top + topRadius),
                radius: topRadius,
                startAngle: .degrees(270),
                endAngle: .degrees(180),
                clockwise: true
            )
        } else {
            path.move(to: CGPoint(x: left - fillet, y: top))
            if fillet > 0 {
                // Concave top-left: curves away from the island, into the menu bar.
                path.addArc(
                    center: CGPoint(x: left - fillet, y: top + fillet),
                    radius: fillet,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(0),
                    clockwise: false
                )
            }
        }

        path.addLine(to: CGPoint(x: left, y: bottom - bottomRadius))

        if bottomRadius > 0 {
            path.addArc(
                center: CGPoint(x: left + bottomRadius, y: bottom - bottomRadius),
                radius: bottomRadius,
                startAngle: .degrees(180),
                endAngle: .degrees(90),
                clockwise: true
            )
        }

        path.addLine(to: CGPoint(x: right - bottomRadius, y: bottom))

        if bottomRadius > 0 {
            path.addArc(
                center: CGPoint(x: right - bottomRadius, y: bottom - bottomRadius),
                radius: bottomRadius,
                startAngle: .degrees(90),
                endAngle: .degrees(0),
                clockwise: true
            )
        }

        if topRadius > 0 {
            path.addLine(to: CGPoint(x: right, y: top + topRadius))
            // Convex top-right.
            path.addArc(
                center: CGPoint(x: right - topRadius, y: top + topRadius),
                radius: topRadius,
                startAngle: .degrees(0),
                endAngle: .degrees(270),
                clockwise: true
            )
        } else {
            path.addLine(to: CGPoint(x: right, y: top + fillet))
            if fillet > 0 {
                // Concave top-right.
                path.addArc(
                    center: CGPoint(x: right + fillet, y: top + fillet),
                    radius: fillet,
                    startAngle: .degrees(180),
                    endAngle: .degrees(270),
                    clockwise: false
                )
            }
        }

        path.closeSubpath()
        return path
    }
```

Also change the doc comment above `public struct NotchShape: Shape` from its first line to: `/// The island: on a real notch, a square top welded to the bezel, rounded bottom corners, and concave outer fillets blending the sides into the menu bar; on a screen without one, a floating pill (2026-10-21).` Keep the rest of that comment.

- [ ] **Step 4: Run the tests and watch them pass.**

Run: `make test FILTER=NotchKitTests`
Expected: `✔ Test run with … tests … passed`. Every pre-existing test in `NotchShapeTests`, `NotchPresenterTests` and `NotchControllerTests` passes unchanged: with both new values 0 the path is the one drawn before.

- [ ] **Step 5: Commit.**

```bash
git add Sources/NotchKit/NotchShape.swift Tests/NotchKitTests/NotchShapeTests.swift
git commit -m "let the island's shape float below the top edge and round its top corners, for the pill

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The pill's sizes

**Files:**
- Modify: `Sources/NotchKit/NotchGeometry.swift` (`virtualNotchSize` and its doc comment)
- Modify: `Sources/NotchKit/NotchMetrics.swift` (`retracted`, `collapsed`, `peek`, `captioned(fitting:)`, `oneActivity(earWidth:)`, `expanded(outputRows:)`; new constants, `cardTopBand(earsShowing:)`, private `pill(width:height:radius:)`)
- Test: `Tests/NotchKitTests/NotchShapeTests.swift`, `Tests/NotchKitTests/NotchGeometryTests.swift`, `Tests/NotchKitTests/NotchAnimationTests.swift`, `Tests/NotchKitTests/NotchPresenterTests.swift`

**Interfaces:**
- Consumes: `NotchShapeParameters(width:height:bottomRadius:outerFillet:topInset:topRadius:)` from Task 1.
- Produces: `NotchMetrics.pillTopInset: CGFloat` (4), `NotchMetrics.pillCardTopBand: CGFloat` (12), `NotchMetrics.cardContentHeight: CGFloat` (136), `NotchMetrics.expandedWidth: CGFloat` (356), `func cardTopBand(earsShowing: Bool) -> CGFloat`, `func expanded(outputRows: Int, earsShowing: Bool = false) -> NotchShapeParameters`. `NotchGeometry.virtualNotchSize == CGSize(width: 44, height: 32)`.

- [ ] **Step 1: Write the failing tests.** Append to `Tests/NotchKitTests/NotchShapeTests.swift`:

```swift
// MARK: - Sizes on a real notch never change (2026-10-21)

/// Every resting size on the measured notch and on a scaled mode's wider,
/// taller one, exactly as before the pill: it must not move a MacBook by a
/// point.
@Test func realNotchSizesAreExactlyAsBefore() {
    func p(_ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ f: CGFloat) -> NotchShapeParameters {
        NotchShapeParameters(width: w, height: h, bottomRadius: r, outerFillet: f)
    }
    let measured = NotchMetrics(notchRect: measuredNotch)
    #expect(measured.collapsed == p(179, 32, 9, 0))
    #expect(measured.retracted == p(179, 32, 9, 0))
    #expect(measured.peek == p(179, 38, 11, 4))
    #expect(measured.captioned(fitting: 300) == p(300, 58, 18, 9))
    #expect(measured.oneActivity == p(255, 32, 12, 6))
    #expect(measured.oneActivity(earWidth: 60) == p(299, 32, 12, 6))
    #expect(measured.expanded == p(356, 168, 26, 13))
    #expect(measured.expanded(outputRows: 2) == p(356, 238, 26, 13))
    #expect(measured.expanded(outputRows: 2, earsShowing: true) == p(356, 238, 26, 13))
    #expect(measured.cardTopBand(earsShowing: false) == 32)
    #expect(measured.cardTopBand(earsShowing: true) == 32)

    let scaled = NotchMetrics(notchRect: CGRect(x: 751, y: 0, width: 208, height: 37))
    #expect(scaled.collapsed == p(208, 37, 9, 0))
    #expect(scaled.peek == p(208, 43, 11, 4))
    #expect(scaled.captioned(fitting: 300) == p(300, 63, 18, 9))
    #expect(scaled.oneActivity == p(255, 37, 12, 6))
    #expect(scaled.expanded == p(356, 168, 26, 13))
    #expect(scaled.cardTopBand(earsShowing: false) == 37)
}

// MARK: - The pill's sizes (2026-10-21)

private let pillHole = CGRect(x: 938, y: 0, width: 44, height: 32)

@Test func pillSizesFollowTheSpec() {
    func pill(_ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NotchShapeParameters {
        NotchShapeParameters(width: w, height: h, bottomRadius: r, outerFillet: 0, topInset: 4, topRadius: r)
    }
    let m = NotchMetrics(notchRect: pillHole, isVirtual: true)
    #expect(m.retracted == pill(0, 0, 16), "hidden: a point at the top centre")
    #expect(m.collapsed == pill(120, 32, 16), "the resting footprint: 44 pt middle, two 38 pt ears")
    #expect(m.peek == m.collapsed, "an empty pill acknowledges the hover")
    #expect(m.oneActivity == pill(120, 32, 16))
    #expect(m.oneActivity(earWidth: 60) == pill(164, 32, 16), "a long Focus name still stretches it")
    #expect(m.captioned(fitting: 300) == pill(300, 58, 18))
    #expect(m.captioned(fitting: 100).width == NotchMetrics.captionedMinimumWidth)
    #expect(m.expanded == pill(356, 148, 26), "the card without its top strip")
    #expect(m.expanded(outputRows: 2) == pill(356, 218, 26))
}

/// The strip comes back while the ears have something to show, output
/// list or not, and the content area stays 136 pt either way.
@Test func pillCardGrowsItsStripOnlyWhileTheEarsShowSomething() {
    let m = NotchMetrics(notchRect: pillHole, isVirtual: true)
    #expect(m.cardTopBand(earsShowing: false) == 12)
    #expect(m.cardTopBand(earsShowing: true) == 32)
    #expect(m.expanded(outputRows: 0, earsShowing: true).height == 168)
    #expect(m.expanded(outputRows: 2, earsShowing: true).height == 238)
    for ears in [false, true] {
        #expect(m.expanded(outputRows: 0, earsShowing: ears).height - m.cardTopBand(earsShowing: ears) == 136)
    }
}
```

In the same file, delete the two tests written for the earlier tab-shaped virtual notch, which these supersede: `aVirtualNotchRetractsToNothingAtTheTopEdge` (with its doc comment) and `retractedVirtualPathCoversNothing` (with its doc comment). Task 1's `aZeroSizedPillCoversNothing` covers the empty path.

In `Tests/NotchKitTests/NotchGeometryTests.swift`, replace the two virtual-notch rect tests with:

```swift
@Test func virtualNotchIsThePillsMiddleCentredAtTheTopEdge() {
    #expect(NotchGeometry.virtualNotchRect(for: external) == CGRect(x: 938, y: 0, width: 44, height: 32))
}

@Test func virtualNotchIsScreenRelativeEvenWhenTheScreenIsNotAtTheOrigin() {
    var screen = external
    screen.frame = screen.frame.offsetBy(dx: 1470, dy: 0)
    #expect(NotchGeometry.virtualNotchRect(for: screen) == CGRect(x: 938, y: 0, width: 44, height: 32))
}
```

(The old ones are `virtualNotchIsTheMeasuredNotchCentredAtTheTopEdge` and `virtualNotchIsScreenRelativeEvenWhenTheScreenIsNotAtTheOrigin`, expecting x 870.5, width 179.)

In `Tests/NotchKitTests/NotchAnimationTests.swift`, inside `springDirectionIsDecidedByArea`, replace

```swift
    // A virtual notch's hidden island has zero height (2026-10-21): coming
    // out of it is growth, going back is a collapse.
    let retracted = CGSize(width: 179, height: 0)
```

with

```swift
    // A pill's hidden island is a point (2026-10-21): coming out of it is
    // growth, going back is a collapse.
    let retracted = CGSize(width: 0, height: 0)
```

In `Tests/NotchKitTests/NotchPresenterTests.swift`, replace the test `aHiddenVirtualNotchIsHoveredAtTheNotchsSize` (and its doc comment) with this interim version; Task 3 extends it to the top edge:

```swift
/// With nothing showing, the cursor finds the pill at its resting
/// footprint plus the margin, though nothing is drawn there.
@Test func aHiddenPillIsHoveredAtItsRestingFootprint() {
    let metrics = NotchMetrics(notchRect: CGRect(x: 938, y: 0, width: 44, height: 32), isVirtual: true)
    let zone = NotchPresenter.hoverParameters(state: .hidden, drawn: metrics.retracted, metrics: metrics)
    #expect(zone.width == 128, "the 120 pt pill plus the 8 pt forgiveness")
    #expect(zone.height == 36, "the 32 pt pill plus the 4 pt forgiveness")
}
```

- [ ] **Step 2: Run them and watch them fail.**

Run: `make test FILTER=NotchKitTests`
Expected: build fails with `value of type 'NotchMetrics' has no member 'cardTopBand'` and `extra argument 'earsShowing' in call`.

- [ ] **Step 3: Implement.** In `Sources/NotchKit/NotchGeometry.swift` replace

```swift
    /// The notch a screen without one gets instead (2026-10-21): the
    /// measured MacBook Air notch, centred at the top edge. Its size, not
    /// the menu bar's, because every island layout was built and pinned
    /// against it. Same island space as `notchRect(for:)`.
    public static let virtualNotchSize = CGSize(width: 179, height: 32)
```

with

```swift
    /// The notch a screen without one gets instead (2026-10-21): the
    /// pill's middle, centred at the top edge. 44 pt wide, not the
    /// measured notch's 179, so the pill's ears sit close as on the
    /// iPhone; 32 pt tall, the measured notch's height, which every layout
    /// was built against. Same island space as `notchRect(for:)`.
    public static let virtualNotchSize = CGSize(width: 44, height: 32)
```

In `Sources/NotchKit/NotchMetrics.swift`:

(a) Replace the `retracted` property and its doc comment with:

```swift
    /// What the island draws while hidden or tucked. On a real notch that
    /// is the notch itself, invisible against the hardware. A pill has
    /// nothing to hide behind, so it shrinks into a point at the top
    /// centre and grows back out of it (2026-10-21). `collapsed` is where
    /// hover finds a hidden island, either way.
    public var retracted: NotchShapeParameters {
        guard isVirtual else { return collapsed }
        return pill(width: 0, height: 0, radius: notchRect.height / 2)
    }
```

(b) In `collapsed`, add as the first line of the getter:

```swift
        // The pill's resting footprint is its one-activity size: never
        // drawn while hidden, it is where hover finds the island.
        if isVirtual { return oneActivity }
```

(c) In `peek`, add as the first line of the getter:

```swift
        // An empty pill, so the hover is acknowledged (2026-10-21).
        if isVirtual { return collapsed }
```

(d) Replace the body of `captioned(fitting:)` with:

```swift
        let width = min(Self.captionedMaximumWidth, max(Self.captionedMinimumWidth, width))
        let height = notchRect.height + Self.captionRowHeight
        if isVirtual { return pill(width: width, height: height, radius: 18) }
        return NotchShapeParameters(width: width, height: height, bottomRadius: 18, outerFillet: 9)
```

(e) In `oneActivity(earWidth:)`, after the `let ear = …` line and before the existing comment that begins `// Height tracks the hardware`, insert:

```swift
        // The pill's middle is a gap, not a camera (2026-10-21): its width
        // follows the 44 pt virtual notch, so the ears sit close, and the
        // ends are round. The 255 below stays the MacBook's own figure.
        if isVirtual {
            return pill(width: notchRect.width + 2 * ear, height: notchRect.height, radius: notchRect.height / 2)
        }
```

(f) Replace the whole `expanded(outputRows:)` method (keep its doc comment above it) with:

```swift
    public func expanded(outputRows: Int, earsShowing: Bool = false) -> NotchShapeParameters {
        let list = outputRows > 0 ? Self.outputListInset + CGFloat(outputRows) * Self.outputRowHeight : 0
        if isVirtual {
            // The pill's card (2026-10-21): the same content room under a
            // 12 pt top, or a 32 pt one while a blip shows above it.
            return pill(
                width: Self.expandedWidth,
                height: Self.cardContentHeight + cardTopBand(earsShowing: earsShowing) + list,
                radius: 26
            )
        }
        return NotchShapeParameters(
            // 390 -> 356 (2026-10-01, user's call: "too wide"). The card's
            // own content measures well under this; the width was simply
            // generous.
            width: Self.expandedWidth,
            // 118 -> 140 during the media-player redesign: the richer card
            // (15pt rounded title, focal 26pt play button, scrub block with
            // live-drag affordance) measures ~97pt of ideal height, and 118's
            // 86pt budget silently clipped its control row. Growing was ruled
            // out for the COMPACT states (layout C, "ears first"), never for
            // expanded — the deliberate full-panel state exists to fit its
            // panel. Pinned by NotchRenderTests'
            // mediaPanelIdealHeightFitsTheExpandedBudget.
            height: atLeastNotchHeight(168 + list),
            bottomRadius: 26,
            outerFillet: 13
        )
    }
```

Add `/// \`earsShowing\`: only the pill reads it — see \`cardTopBand(earsShowing:)\`.` as the last line of that method's existing doc comment.

(g) Directly after `expanded(outputRows:earsShowing:)`, add:

```swift
    /// The row above the open card's content. On a MacBook it is the
    /// notch, always. On a pill it is 12 pt, and the full ear height while
    /// the ears show something above the card (`NotchController.
    /// earsShowAboveCard`), so the card grows a strip for a blip instead of
    /// squeezing it (2026-10-21).
    public func cardTopBand(earsShowing: Bool) -> CGFloat {
        guard isVirtual else { return notchRect.height }
        return earsShowing ? notchRect.height : Self.pillCardTopBand
    }

    // MARK: - The pill (2026-10-21)

    /// How far below the top edge a pill floats: over the menu bar, where a
    /// notch would be.
    public static let pillTopInset: CGFloat = 4
    /// The open card's top on a pill while the ears are empty: the strip a
    /// MacBook's card keeps beside its notch, gone.
    public static let pillCardTopBand: CGFloat = 12
    /// Room for the open card's content below its top: the measured 168 pt
    /// card less the 32 pt notch.
    public static let cardContentHeight: CGFloat = 136
    /// The open card's width, on a notch or a pill.
    public static let expandedWidth: CGFloat = 356

    /// A pill's parameters: every corner `radius`, no fillets, floating at
    /// `pillTopInset`.
    private func pill(width: CGFloat, height: CGFloat, radius: CGFloat) -> NotchShapeParameters {
        NotchShapeParameters(
            width: width, height: height, bottomRadius: radius, outerFillet: 0,
            topInset: Self.pillTopInset, topRadius: radius
        )
    }
```

- [ ] **Step 4: Run the tests and watch them pass.**

Run: `make test FILTER=NotchKitTests`
Expected: all pass, including `realNotchSizesAreExactlyAsBefore`, `pillSizesFollowTheSpec`, `pillCardGrowsItsStripOnlyWhileTheEarsShowSomething`, and the pre-existing `aVirtualNotchDrawsNothingWhenHiddenOrTucked` (hidden and tucked still draw height 0).

- [ ] **Step 5: Commit.**

```bash
git add Sources/NotchKit/NotchGeometry.swift Sources/NotchKit/NotchMetrics.swift Tests/NotchKitTests
git commit -m "size the island as a pill on a screen without a notch, every MacBook size pinned as it was

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The card's strip and the hover zone

**Files:**
- Modify: `Sources/NotchKit/NotchController.swift` (new `earsShowAboveCard` beside `parameters`; the `.expanded` case of `parameters`)
- Modify: `Sources/NotchKit/NotchPresenter.swift` (`hoverParameters(state:drawn:metrics:)`)
- Test: `Tests/NotchKitTests/NotchControllerTests.swift`, `Tests/NotchKitTests/NotchPresenterTests.swift`

**Interfaces:**
- Consumes: `NotchMetrics.expanded(outputRows:earsShowing:)`, `NotchMetrics.cardTopBand(earsShowing:)` from Task 2.
- Produces: `NotchController.earsShowAboveCard: Bool` (public, read-only), used by Task 4's view.

- [ ] **Step 1: Write the failing tests.** Append to `Tests/NotchKitTests/NotchControllerTests.swift`:

```swift
// MARK: - The pill's card strip (2026-10-21)

@MainActor
private func makePillController() -> NotchController {
    NotchController(metrics: NotchMetrics(notchRect: CGRect(x: 938, y: 0, width: 44, height: 32), isVirtual: true))
}

@MainActor
private func openNowPlayingCard(_ c: NotchController) {
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    c.setMedia(MediaPresentation(title: "Song", artist: "Artist", artwork: nil, isPlaying: true, elapsed: 10, duration: 200))
    c.click()
}

/// Now-playing alone: its artwork moves into the card, the ears are
/// empty, and the pill's card has no strip.
@MainActor
@Test func theEarsAreEmptyAboveACardOfNowPlayingAlone() {
    let c = makePillController()
    openNowPlayingCard(c)
    #expect(c.state == .expanded)
    #expect(!c.earsShowAboveCard)
    #expect(c.parameters.height == 148)
}

/// A blip leading while the card is open shows in the ears, and the
/// pill's card grows its strip back for it.
@MainActor
@Test func aBlipOverAnOpenCardGrowsThePillsStrip() {
    let c = makePillController()
    openNowPlayingCard(c)
    c.setActivities([
        .init(id: "hud", title: "Sound", compactText: "62%", symbolName: "speaker.wave.2.fill"),
        .init(id: "media", title: "Song", detail: "Artist"),
    ], overflow: 0)
    #expect(c.state == .expanded)
    #expect(c.earsShowAboveCard)
    #expect(c.parameters.height == 168)
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    #expect(c.parameters.height == 148, "and shrinks again when the blip ends")
}

/// The "+N" pip sits in the trailing ear, so it counts too.
@MainActor
@Test func theOverflowPipCountsAsSomethingAboveTheCard() {
    let c = makePillController()
    openNowPlayingCard(c)
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 2)
    #expect(c.earsShowAboveCard)
}

/// Only an open card has ears above it.
@MainActor
@Test func earsAboveTheCardNeedAnOpenCard() {
    let c = makePillController()
    c.setActivities([.init(id: "hud", title: "Sound", compactText: "62%", symbolName: "speaker.wave.2.fill")], overflow: 0)
    #expect(c.state == .activity)
    #expect(!c.earsShowAboveCard)
}

/// Lid shut with a blip up: the metrics swap to the pill and the very
/// next read is the pill's size, nothing of the notch left over.
@MainActor
@Test func swappingToAPillMidBlipResizesAtOnce() {
    let c = makeController()
    c.setActivities([.init(id: "hud", title: "Sound", compactText: "62%", symbolName: "speaker.wave.2.fill")], overflow: 0)
    #expect(c.parameters.width == 255)
    c.metrics = NotchMetrics(notchRect: CGRect(x: 938, y: 0, width: 44, height: 32), isVirtual: true)
    #expect(c.parameters == c.metrics.oneActivity)
    #expect(c.parameters.width == 120)
    #expect(c.parameters.topRadius == 16)
}
```

In `Tests/NotchKitTests/NotchPresenterTests.swift`, replace Task 2's `aHiddenPillIsHoveredAtItsRestingFootprint` (and its doc comment) with:

```swift
/// The hidden pill is found at its resting footprint plus the margin, and
/// right up to the top edge over its 4 pt float (2026-10-21): a pointer
/// pushed against the top of the screen finds it, as it finds a notch.
@Test func aHiddenPillIsHoveredFromTheTopEdgeDown() {
    let metrics = NotchMetrics(notchRect: CGRect(x: 938, y: 0, width: 44, height: 32), isVirtual: true)
    let zone = NotchPresenter.hoverParameters(state: .hidden, drawn: metrics.retracted, metrics: metrics)
    #expect(zone.width == 128, "the 120 pt pill plus the 8 pt forgiveness")
    #expect(zone.height == 40, "32, the 4 pt forgiveness, and the 4 pt float")
    #expect(zone.topInset == 0)
    let path = NotchPresenter.islandPath(for: zone)
    #expect(path.contains(CGPoint(x: NotchPresenter.canvas.midX, y: 0.5)), "a pointer against the top edge")
}

@Test func thePillsHoverPreviewReachesTheTopEdgeToo() {
    let metrics = NotchMetrics(notchRect: CGRect(x: 938, y: 0, width: 44, height: 32), isVirtual: true)
    let zone = NotchPresenter.hoverParameters(state: .peek, drawn: metrics.peek, metrics: metrics)
    #expect(zone.topInset == 0)
    #expect(zone.height == 40)
}
```

- [ ] **Step 2: Run them and watch them fail.**

Run: `make test FILTER=NotchKitTests`
Expected: build fails with `value of type 'NotchController' has no member 'earsShowAboveCard'`. (After a stub, the hover tests would fail with `zone.height → 36.0`.)

- [ ] **Step 3: Implement.** In `Sources/NotchKit/NotchController.swift`, directly above `public var parameters: NotchShapeParameters {`, add:

```swift
    /// Whether the ears show something above the open card (2026-10-21):
    /// any leading activity but now-playing, whose artwork moves into the
    /// card; the "+N" pip; or a match's crests while the card shows
    /// something else. Mirrors the `.expanded` branches of `NotchRootView`'s
    /// `leadingEar` and `trailingEar`. On a pill the card grows its top
    /// strip back for exactly this (`NotchMetrics.cardTopBand`); on a
    /// MacBook the strip is always there and this changes nothing.
    public var earsShowAboveCard: Bool {
        guard state == .expanded else { return false }
        if let first = activities.first, first.id != Self.mediaActivityID { return true }
        if overflowCount > 0 { return true }
        return score != nil && panel != .liveActivity
    }
```

In the same file, in `parameters`, replace

```swift
            return metrics.expanded(outputRows: panel == .media && isOutputPickerOpen ? outputs.count : 0)
```

with

```swift
            return metrics.expanded(
                outputRows: panel == .media && isOutputPickerOpen ? outputs.count : 0,
                earsShowing: earsShowAboveCard
            )
```

In `Sources/NotchKit/NotchPresenter.swift`, replace the body of `hoverParameters(state:drawn:metrics:)` with:

```swift
        var parameters = state == .hidden ? metrics.collapsed : drawn
        guard state == .hidden || state == .peek else { return parameters }
        parameters.width += 8
        parameters.height += 4
        // A floating pill's zone reaches up over its float to the top edge
        // (2026-10-21): a pointer pushed against the top of the screen must
        // find it, as it finds a notch. Nothing changes on a real notch,
        // whose inset is 0.
        parameters.height += parameters.topInset
        parameters.topInset = 0
        return parameters
```

and add this sentence to the end of that function's doc comment: `A floating pill's zone also reaches up over its inset to the top edge.`

- [ ] **Step 4: Run the tests and watch them pass.**

Run: `make test FILTER=NotchKitTests`
Expected: all pass, including the pre-existing `aHiddenRealNotchIsHoveredAtTheNotchsSize` (187 × 36, unchanged) and `aLiveIslandIsHoveredExactlyAsDrawn`.

- [ ] **Step 5: Commit.**

```bash
git add Sources/NotchKit/NotchController.swift Sources/NotchKit/NotchPresenter.swift Tests/NotchKitTests
git commit -m "grow the pill's card a strip while a blip shows above it, and let its hover reach the top edge

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Draw the pill

**Files:**
- Modify: `Sources/NotchKit/NotchRootView.swift` (`NotchAnimation`, `NotchRootView.body`, `islandContent(parameters:)`)
- Test: `Tests/NotchKitTests/NotchAnimationTests.swift`, `Tests/NotchRenderTests/NotchRootViewRenderTests.swift`

**Interfaces:**
- Consumes: `NotchShapeParameters.topInset` (Task 1), `NotchMetrics.retracted`, `NotchMetrics.cardTopBand(earsShowing:)` (Task 2), `NotchController.earsShowAboveCard` (Task 3).
- Produces: `NotchAnimation.isArrival(from: CGSize, retracted: NotchShapeParameters) -> Bool`.

- [ ] **Step 1: Write the failing tests.** Append to `Tests/NotchKitTests/NotchAnimationTests.swift`:

```swift
/// An arrival is growth out of what a hidden island draws (2026-10-21):
/// the notch on a MacBook, as before; the point on a pill, so the hover
/// pill opening into the card keeps the expand spring, as a MacBook's
/// hover lip does.
@Test func anArrivalIsGrowthOutOfWhatAHiddenIslandDraws() {
    let real = NotchMetrics(notchRect: CGRect(x: 645.5, y: 0, width: 179, height: 32))
    #expect(NotchAnimation.isArrival(from: CGSize(width: 179, height: 32), retracted: real.retracted))
    #expect(!NotchAnimation.isArrival(from: CGSize(width: 179, height: 38), retracted: real.retracted), "the hover lip is not hidden")
    let pill = NotchMetrics(notchRect: CGRect(x: 938, y: 0, width: 44, height: 32), isVirtual: true)
    #expect(NotchAnimation.isArrival(from: .zero, retracted: pill.retracted))
    #expect(!NotchAnimation.isArrival(from: CGSize(width: 120, height: 32), retracted: pill.retracted), "the hover pill is not hidden")
}
```

Append to `Tests/NotchRenderTests/NotchRootViewRenderTests.swift`:

```swift
// MARK: - The pill (2026-10-21)

private let pillHole = CGRect(x: 0, y: 0, width: 44, height: 32)

@MainActor
private func makePillController(reduceMotion: Bool = false) -> NotchController {
    NotchController(metrics: NotchMetrics(notchRect: pillHole, isVirtual: true), reduceMotion: reduceMotion)
}

@MainActor
private func openPillCard(_ c: NotchController) {
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    c.setMedia(MediaPresentation(title: "Song", artist: "Artist", artwork: nil, isPlaying: true, elapsed: 10, duration: 200))
    c.click()
}

private struct PillCheck {
    var hasContent = false
    /// Content within 1.5 pt of the outline: what a glyph cut by a round
    /// end leaves behind.
    var contentAtTheEdgeCount = 0
    var contentOutsideCount = 0
    /// Content in the 44 pt middle of a compact pill.
    var contentInTheMiddleCount = 0
    /// Content in an open card's top band.
    var contentInTopBandCount = 0
}

@MainActor
private func renderPill(_ controller: NotchController) -> PillCheck {
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    let parameters = controller.parameters
    let path = NotchShape(parameters).path(in: canvas)
    let inset = parameters.topInset
    let middle = CGRect(x: canvas.midX - pillHole.width / 2, y: inset, width: pillHole.width, height: pillHole.height)
    let band = controller.state == .expanded
        ? CGRect(x: canvas.midX - parameters.width / 2, y: inset, width: parameters.width,
                 height: controller.metrics.cardTopBand(earsShowing: controller.earsShowAboveCard))
        : CGRect.null
    var check = PillCheck()
    RenderedImage(controller).forEachPixel { point, isContent, _ in
        guard isContent else { return }
        guard path.contains(point) else { check.contentOutsideCount += 1; return }
        check.hasContent = true
        let margin: CGFloat = 1.5
        let neighbours = [CGPoint(x: point.x - margin, y: point.y), CGPoint(x: point.x + margin, y: point.y),
                          CGPoint(x: point.x, y: point.y - margin), CGPoint(x: point.x, y: point.y + margin)]
        if !neighbours.allSatisfy({ path.contains($0) }) { check.contentAtTheEdgeCount += 1 }
        if controller.state != .expanded, middle.contains(point) { check.contentInTheMiddleCount += 1 }
        if band.contains(point) { check.contentInTopBandCount += 1 }
    }
    return check
}

@MainActor
@Test func pillVolumeBlipKeepsClearOfItsRoundEnds() {
    let c = makePillController()
    c.setActivities([.init(id: "hud", title: "Sound", compactText: "62%", symbolName: "speaker.wave.2.fill")], overflow: 0)
    #expect(c.parameters == c.metrics.oneActivity)
    let r = renderPill(c)
    #expect(r.hasContent, "the glyph and the percentage did not render")
    #expect(r.contentAtTheEdgeCount == 0, "\(r.contentAtTheEdgeCount) content pixel(s) cut by the pill's outline")
    #expect(r.contentOutsideCount == 0)
    #expect(r.contentInTheMiddleCount == 0)
}

@MainActor
@Test func pillNowPlayingKeepsClearOfItsRoundEnds() {
    let c = makePillController()
    c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    c.setMedia(MediaPresentation(title: "Song", artist: "Artist", artwork: nil, isPlaying: true, elapsed: 10, duration: 200))
    #expect(c.state == .activity)
    let r = renderPill(c)
    #expect(r.hasContent, "the artwork placeholder did not render")
    #expect(r.contentAtTheEdgeCount == 0, "\(r.contentAtTheEdgeCount) content pixel(s) cut by the pill's outline")
    #expect(r.contentOutsideCount == 0)
    #expect(r.contentInTheMiddleCount == 0)
}

@MainActor
@Test func pillCardContentStartsBelowItsTwelvePointTop() {
    let c = makePillController()
    openPillCard(c)
    #expect(c.parameters.height == 148)
    let r = renderPill(c)
    #expect(r.hasContent)
    #expect(r.contentOutsideCount == 0)
    #expect(r.contentAtTheEdgeCount == 0)
    #expect(r.contentInTopBandCount == 0, "nothing in the 12 pt band above the card's content")
}

@MainActor
@Test func aBlipOverThePillCardShowsInItsGrownStrip() {
    let c = makePillController()
    openPillCard(c)
    c.setActivities([
        .init(id: "hud", title: "Sound", compactText: "62%", symbolName: "speaker.wave.2.fill"),
        .init(id: "media", title: "Song", detail: "Artist"),
    ], overflow: 0)
    #expect(c.parameters.height == 168)
    let r = renderPill(c)
    #expect(r.contentInTopBandCount > 0, "the blip's glyph and value sit in the strip")
    #expect(r.contentOutsideCount == 0)
    #expect(r.contentAtTheEdgeCount == 0)
}

@MainActor
@Test func pillRendersUnderReduceMotion() {
    let c = makePillController(reduceMotion: true)
    c.setActivities([.init(id: "hud", title: "Sound", compactText: "62%", symbolName: "speaker.wave.2.fill")], overflow: 0)
    let r = renderPill(c)
    #expect(r.hasContent)
    #expect(r.contentOutsideCount == 0)
    #expect(r.contentAtTheEdgeCount == 0)
}

/// The harness self-check, for the pill: the black fill lands where the
/// path says, 4 pt below the top.
@MainActor
@Test func renderedPillFillMatchesItsPath() {
    let c = makePillController()
    openPillCard(c)
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    let expected = NotchShape(c.parameters).path(in: canvas).boundingRect
    var minX = CGFloat.infinity, maxX = -CGFloat.infinity
    var minY = CGFloat.infinity, maxY = -CGFloat.infinity
    var sawAny = false
    RenderedImage(c).forEachPixel { point, _, isIslandFill in
        guard isIslandFill else { return }
        sawAny = true
        minX = min(minX, point.x); maxX = max(maxX, point.x)
        minY = min(minY, point.y); maxY = max(maxY, point.y)
    }
    #expect(sawAny, "no black island-fill pixels found at all")
    guard sawAny else { return }
    let tolerance: CGFloat = 3
    #expect(abs(minX - expected.minX) < tolerance, "\(minX) vs \(expected)")
    #expect(abs(maxX - expected.maxX) < tolerance, "\(maxX) vs \(expected)")
    #expect(abs(minY - 4) < tolerance, "the fill floats 4 pt below the top: \(minY)")
    #expect(abs(maxY - expected.maxY) < tolerance, "\(maxY) vs \(expected)")
}
```

- [ ] **Step 2: Run them and watch them fail.**

Run: `make test FILTER=NotchAnimationTests` then `make test FILTER=NotchRenderTests`
Expected: the first fails to build with `type 'NotchAnimation' has no member 'isArrival'`. Once that exists, the render tests fail because content is not yet padded by the inset (content pixels outside the floating path, `contentOutsideCount > 0`) and the card's top band is still 32 pt (`pillCardContentStartsBelowItsTwelvePointTop` sees content in the band or outside).

- [ ] **Step 3: Implement.** In `Sources/NotchKit/NotchRootView.swift`:

(a) In `enum NotchAnimation`, directly after `animation(expanding:fromHidden:reduceMotion:)`, add:

```swift
    /// Whether a change of size is an arrival: growth out of what a hidden
    /// island draws (2026-10-21). On a real notch `retracted` is the notch,
    /// as `collapsed` was before; on a pill it is the point, so the hover
    /// pill opening into the card is not mistaken for an arrival.
    public static func isArrival(from previous: CGSize, retracted: NotchShapeParameters) -> Bool {
        previous.width <= retracted.width && previous.height <= retracted.height
    }
```

(b) In `NotchRootView.body`, replace

```swift
        let collapsed = controller.metrics.collapsed
        let fromHidden = previousWidth <= collapsed.width && previousHeight <= collapsed.height
```

with

```swift
        let fromHidden = NotchAnimation.isArrival(
            from: CGSize(width: previousWidth, height: previousHeight),
            retracted: controller.metrics.retracted
        )
```

(c) In `NotchRootView.body`, inside `.overlay(alignment: .top) {`, replace

```swift
                    islandContent(parameters: parameters)
```

with

```swift
                    islandContent(parameters: parameters)
                        // Down by the pill's float (2026-10-21), so the
                        // content sits inside the shape; 0 on a notch.
                        .padding(.top, parameters.topInset)
```

(d) In `islandContent(parameters:)`, replace

```swift
        let notch = controller.metrics.notchRect
        let ear = controller.metrics.earWidth(forIslandWidth: parameters.width)

        #if DEBUG
        let _ = assertContentStaysInsideIslandAndClearOfNotch(parameters: parameters, notch: notch, ear: ear)
        #endif
```

with

```swift
        let notch = controller.metrics.notchRect
        let ear = controller.metrics.earWidth(forIslandWidth: parameters.width)
        // The row of ears. Above an open card on a pill it is the card's
        // top band, 12 pt while the ears are empty (2026-10-21); everywhere
        // else, and always on a MacBook, it is the notch's height.
        let rowHeight = controller.state == .expanded
            ? controller.metrics.cardTopBand(earsShowing: controller.earsShowAboveCard)
            : notch.height
        let row = CGRect(x: notch.minX, y: notch.minY, width: notch.width, height: rowHeight)

        #if DEBUG
        let _ = assertContentStaysInsideIslandAndClearOfNotch(parameters: parameters, notch: row, ear: ear)
        #endif
```

Then, in the rest of `islandContent(parameters:)`, use `row` where `notch` was: `IslandEarsRow(target: parameters, notch: row, …)`; the caption row's `.frame(width: parameters.width, height: parameters.height - row.height)`; the detail row's condition `} else if parameters.height > row.height + 8 {` and its `.frame(height: parameters.height - row.height, alignment: .top)`. There are exactly four uses of `notch` after the `let row` line; all four become `row`. On a MacBook `row == notch`, so nothing changes there.

- [ ] **Step 4: Run the tests and watch them pass.**

Run: `make test FILTER=NotchAnimationTests` then `make test FILTER=NotchRenderTests`
Expected: all pass, the pre-existing render tests included.

If `pillVolumeBlipKeepsClearOfItsRoundEnds` or `pillNowPlayingKeepsClearOfItsRoundEnds` fails on `contentAtTheEdgeCount` (content cut by a round end), apply the spec's one fallback: in `NotchMetrics.oneActivity(earWidth:)`'s pill branch, use `let pillEar = max(ear, 40)` and `notchRect.width + 2 * pillEar`, update `pillSizesFollowTheSpec` to expect `pill(124, 32, 16)` for `collapsed`, `oneActivity` and `peek`, update the presenter tests' `zone.width` to 132, and re-run Steps 4 of Tasks 2 to 4.

- [ ] **Step 5: Commit.**

```bash
git add Sources/NotchKit/NotchRootView.swift Tests/NotchKitTests/NotchAnimationTests.swift Tests/NotchRenderTests/NotchRootViewRenderTests.swift
git commit -m "draw the island as a floating pill on a screen without a notch

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Docs, the full suite, and the live check

**Files:**
- Modify: `README.md` (the paragraph under "Built and measured against a MacBook Air…")
- Modify: `docs/superpowers/specs/2026-09-25-notch-companion-design.md` (new dated section at the end)

**Interfaces:**
- Consumes: everything above. Produces: nothing for code.

- [ ] **Step 1: README.** Replace

```
179 × 32 pt notch. Nothing about the notch is hardcoded. A Mac without one (a
Mac mini, or a MacBook with its lid shut) gets a virtual notch of that size at
the top centre of the main display: nothing there at rest, the island drops
from the top edge when something happens.
```

with

```
179 × 32 pt notch. Nothing about the notch is hardcoded. A Mac without one (a
Mac mini, or a MacBook with its lid shut) gets a floating pill instead, like the
iPhone's Dynamic Island: 4 pt below the top edge at the centre of the main
display, nothing there at rest, growing out of a point when something happens.
See `docs/superpowers/specs/2026-10-21-pill-island-design.md`.
```

- [ ] **Step 2: Design spec.** Append to `docs/superpowers/specs/2026-09-25-notch-companion-design.md`:

```markdown

## The pill (2026-10-21)

Supersedes the shape of "Screens without a notch" above (user's call): on a
screen without a notch the island is a floating pill like the iPhone's Dynamic
Island, not the measured 179 × 32 tab. It floats 4 pt below the top edge over
the menu bar; its middle is 44 pt, so the small pill is 120 × 32 with round
ends; the open card is 356 × 148 with every corner at 26 pt, its top strip gone
and grown back to 32 pt only while a blip shows above it; hidden, it is a point
it grows out of and shrinks into, replacing the slide-up. Its hover zone reaches
the top edge. The MacBook's notch island is unchanged, value for value
(`realNotchSizesAreExactlyAsBefore`). Design and numbers:
`2026-10-21-pill-island-design.md`.
```

- [ ] **Step 3: Full suite.**

Run: `make test`
Expected: every test run passes except `HUDServiceTests`, with exactly two issues: `brightnessTargetsTheBuiltInDisplay` and `bridgeLoadsAndReadsARealBrightnessValue` (they need a MacBook's built-in panel). Any other failure stops here.

- [ ] **Step 4: Live check on the Mac mini.** The user runs Ledge from `/Applications`. Build and install, then relaunch that copy:

```bash
make install && make stop; open /Applications/Ledge.app; sleep 3; pgrep -lx Ledge
```

Expected: one `Ledge` process. Signing may ask for the login keychain password unless `make cert-allow` has been run; the user answers that prompt.

Then trigger a volume blip, capture the top centre of the 1920-wide display, and restore the volume:

```bash
S=/private/tmp/claude-502/-Users-gedemahendra-Developer-Project-ledge/13a5958b-9c25-4384-b2b4-ea5db8fbb1e1/scratchpad; v=$(osascript -e 'output volume of (get volume settings)'); n=$(( v>=98 ? v-2 : v+2 )); osascript -e "set volume output volume $n"; sleep 0.7; screencapture -x -R 760,0,400,70 $S/pill.png; osascript -e "set volume output volume $v"
```

Read `$S/pill.png`. Expected: a black pill about 120 pt wide centred at x = 960, with a visible gap above it, round ends, the speaker glyph left and the percentage right. With music playing the blip gives way to the now-playing pill (artwork left, output glyph right) of the same shape. Do not drive the pointer; ask the user to check the hover preview, the open card (no strip), and a volume press with the card open (the strip grows, then goes).

- [ ] **Step 5: Commit.**

```bash
git add README.md docs/superpowers/specs/2026-09-25-notch-companion-design.md
git commit -m "describe the pill for screens without a notch

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
