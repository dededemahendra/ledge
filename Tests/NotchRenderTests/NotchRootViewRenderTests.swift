import Testing
import SwiftUI
import CoreGraphics
@testable import NotchKit

// MARK: - Headless pixel rendering
//
// `ImageRenderer` rasterises the real view tree synchronously, with no
// window, no screen, and no run loop. This is the only place in the whole
// suite that renders anything — everything else (the shape's path math, the
// controller's state machine, the metrics) is unit tested in isolation, and
// none of that would ever have caught either of the two defects this target
// exists to catch: content pinned at opacity 0 outside `.expanded`, and
// content composited 100+pt below the island because `.overlay` defaults to
// `.center` alignment against a `Shape` fill that occupies the whole canvas.
//
// Pixel attribution: `NotchRenderTestHook.contentColor` (internal to
// `NotchKit`, reachable here only via `@testable import`) repaints every
// content element — both ears and the detail row — a single solid colour
// instead of white. Classification below keys off which channel DOMINATES,
// not brightness: even the leading-ear dot, which is drawn at 28% opacity
// over the fully opaque black island fill and therefore composites down to a
// dim (not bright) pixel, still has red strictly greater than green and
// blue — a signature nothing made of black-on-transparent (the island fill
// and its antialiased edges are always exactly grayscale, R == G == B) can
// ever produce by accident. That's what makes this reliable without hand
// tuning a brightness threshold per element/opacity — and it means the real
// `NotchRootView.body` / `islandContent` / `ContentFade` / `.overlay` /
// `.clipShape` code all still runs unmodified; only the colour changes.

private let contentTestColor = Color(red: 1, green: 0, blue: 0)

/// A rendered frame, read back as a y-down, top-left-origin pixel buffer —
/// matching the coordinate convention every geometry test in this package
/// already assumes (see `NotchShapeTests.pathIsAlwaysWeldedToTheTopEdge`).
@MainActor
private struct RenderedImage {
    let width: Int
    let height: Int
    let scale: CGFloat
    private let bytesPerRow: Int
    private let data: [UInt8]

    init(_ controller: NotchController, scale: CGFloat = 2) {
        NotchRenderTestHook.contentColor = contentTestColor
        defer { NotchRenderTestHook.contentColor = nil }

        let renderer = ImageRenderer(content: NotchRootView(controller: controller))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(
            width: NotchMetrics.canvasSize.width, height: NotchMetrics.canvasSize.height
        )
        guard let cgImage = renderer.cgImage else {
            fatalError("ImageRenderer produced no image — headless rendering is unavailable here")
        }

        self.scale = scale
        width = cgImage.width
        height = cgImage.height
        bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &buffer, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("could not create a bitmap context to read pixels back")
        }
        // No manual flip here, deliberately: `CGContext.draw(_:in:)` already
        // places row 0 of `cgImage` (the top of the rendered SwiftUI canvas)
        // at row 0 of `buffer`, verified empirically against
        // `renderedIslandFillMatchesTheComputedShapePath` below — a flip
        // here would put the island at the bottom of every frame instead of
        // welded to the top, which is exactly what that self-check exists to
        // catch.
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        data = buffer
    }

    private struct Pixel { let r, g, b, a: UInt8 }

    private func pixel(atPixelX px: Int, pixelY py: Int) -> Pixel {
        let offset = py * bytesPerRow + px * 4
        return Pixel(r: data[offset], g: data[offset + 1], b: data[offset + 2], a: data[offset + 3])
    }

    /// A pixel painted (at any opacity, over any background) with
    /// `contentTestColor` — red strictly dominant over green and blue. Never
    /// true of the island's black fill or its antialiased edges, which are
    /// always exactly grayscale.
    private func isContent(_ p: Pixel) -> Bool {
        p.a > 10 && Int(p.r) - Int(max(p.g, p.b)) > 15
    }

    /// A pixel that is part of the island's own opaque black fill (or a
    /// solidly-black antialiased edge sample) — grayscale, dark, opaque.
    private func isIslandFill(_ p: Pixel) -> Bool {
        p.a > 200 && p.r < 40 && p.g < 40 && p.b < 40
    }

    /// Visits every pixel in canvas-point coordinates (i.e. with `scale`
    /// divided back out). Always exhaustive — every assertion in this file
    /// needs the full scan, not just the first hit.
    func forEachPixel(_ body: (_ point: CGPoint, _ isContent: Bool, _ isIslandFill: Bool) -> Void) {
        for py in 0..<height {
            let y = CGFloat(py) / scale
            for px in 0..<width {
                let x = CGFloat(px) / scale
                let p = pixel(atPixelX: px, pixelY: py)
                body(CGPoint(x: x, y: y), isContent(p), isIslandFill(p))
            }
        }
    }
}

// MARK: - Shared fixture

private let testNotchRect = CGRect(x: 0, y: 0, width: 179, height: 32)

@MainActor
private func makeController() -> NotchController {
    NotchController(metrics: NotchMetrics(notchRect: testNotchRect))
}

private struct RenderCheck {
    let islandBounds: CGRect
    let holeRect: CGRect
    let hasContentInsideIsland: Bool
    let contentInsideNotchCount: Int
    let contentOutsideIslandCount: Int
}

@MainActor
private func renderAndClassify(_ controller: NotchController) -> RenderCheck {
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    let islandBounds = NotchShape(controller.parameters).path(in: canvas).boundingRect
    let hole = CGRect(
        x: canvas.midX - testNotchRect.width / 2, y: 0,
        width: testNotchRect.width, height: testNotchRect.height
    )

    let image = RenderedImage(controller)
    var hasContentInsideIsland = false
    var contentInsideNotchCount = 0
    var contentOutsideIslandCount = 0
    // A half-point tolerance absorbs sub-pixel antialiasing right at the
    // `.clipShape` boundary — utterly swamped by the 100+pt this is meant to
    // catch, so it cannot mask a real defect-2-shaped regression.
    let tolerantBounds = islandBounds.insetBy(dx: -0.5, dy: -0.5)
    image.forEachPixel { point, isContent, _ in
        guard isContent else { return }
        if tolerantBounds.contains(point) {
            hasContentInsideIsland = true
        } else {
            contentOutsideIslandCount += 1
        }
        if hole.contains(point) {
            contentInsideNotchCount += 1
        }
    }

    return RenderCheck(
        islandBounds: islandBounds, holeRect: hole,
        hasContentInsideIsland: hasContentInsideIsland,
        contentInsideNotchCount: contentInsideNotchCount,
        contentOutsideIslandCount: contentOutsideIslandCount
    )
}

// MARK: - The three resting states named in the review

@MainActor
@Test func oneActivityContentRendersInsideTheIslandAndClearOfTheNotch() {
    let controller = makeController()
    controller.setActivities(
        [.init(id: "power", title: "Charging · 42%", compactText: "42%")], overflow: 0
    )
    #expect(controller.state == .activity)
    #expect(controller.parameters == controller.metrics.oneActivity)

    let result = renderAndClassify(controller)
    #expect(
        result.hasContentInsideIsland,
        """
        no content pixel found inside the island bounds \(result.islandBounds) \
        — this is defect 1 (opacity stuck at 0 outside .expanded)
        """
    )
    #expect(
        result.contentInsideNotchCount == 0,
        "\(result.contentInsideNotchCount) content pixel(s) drawn inside the notch rect \(result.holeRect)"
    )
    #expect(
        result.contentOutsideIslandCount == 0,
        """
        \(result.contentOutsideIslandCount) content pixel(s) drawn outside the island bounds \
        \(result.islandBounds) — this is defect 2 (.overlay defaulting to centre alignment)
        """
    )
}

@MainActor
@Test func twoActivitiesContentRendersInsideTheIslandAndClearOfTheNotch() {
    let controller = makeController()
    controller.setActivities(
        [
            .init(id: "power", title: "Charging · 42%", detail: "24 min to full", compactText: "42%"),
            .init(id: "device", title: "AirPods Pro connected"),
        ],
        overflow: 0
    )
    #expect(controller.state == .activity)
    #expect(controller.parameters == controller.metrics.twoActivities)

    let result = renderAndClassify(controller)
    #expect(
        result.hasContentInsideIsland,
        """
        no content pixel found inside the island bounds \(result.islandBounds) \
        — this is defect 1 (opacity stuck at 0 outside .expanded)
        """
    )
    #expect(
        result.contentInsideNotchCount == 0,
        "\(result.contentInsideNotchCount) content pixel(s) drawn inside the notch rect \(result.holeRect)"
    )
    #expect(
        result.contentOutsideIslandCount == 0,
        """
        \(result.contentOutsideIslandCount) content pixel(s) drawn outside the island bounds \
        \(result.islandBounds) — this is defect 2 (.overlay defaulting to centre alignment)
        """
    )
}

@MainActor
@Test func expandedContentRendersInsideTheIslandAndClearOfTheNotch() {
    let controller = makeController()
    controller.setActivities(
        [.init(id: "power", title: "Charging · 42%", detail: "24 min to full", compactText: "42%")],
        overflow: 0
    )
    controller.click()
    #expect(controller.state == .expanded)
    #expect(controller.parameters == controller.metrics.expanded)

    let result = renderAndClassify(controller)
    #expect(
        result.hasContentInsideIsland,
        """
        no content pixel found inside the island bounds \(result.islandBounds) \
        — this is defect 1 (opacity stuck at 0 outside .expanded)
        """
    )
    #expect(
        result.contentInsideNotchCount == 0,
        "\(result.contentInsideNotchCount) content pixel(s) drawn inside the notch rect \(result.holeRect)"
    )
    #expect(
        result.contentOutsideIslandCount == 0,
        """
        \(result.contentOutsideIslandCount) content pixel(s) drawn outside the island bounds \
        \(result.islandBounds) — this is defect 2 (.overlay defaulting to centre alignment)
        """
    )
}

// MARK: - Detail row budget

/// Pins the fix for the two-activity detail row overflowing its budget.
/// `twoActivities.height - notchRect.height` gives `detailRow` a 30pt
/// budget below the hole; showing every activity's title (let alone title
/// + detail) measures 38-51pt, which was silently clipped away downward by
/// `.clipShape` — invisible to a pixel check against the parent view (the
/// three tests above), since a clipped pixel is simply an absent pixel, not
/// a failure. Measuring `detailRow`'s own ideal (UNCLIPPED) size directly,
/// via the `detailRowForTesting` seam, is what actually catches content
/// that grows past its budget.
@MainActor
@Test func twoActivityDetailRowIdealHeightFitsItsBudget() {
    let controller = makeController()
    controller.setActivities(
        [
            .init(id: "power", title: "Charging · 42%", detail: "24 min to full", compactText: "42%"),
            .init(id: "device", title: "AirPods Pro connected"),
        ],
        overflow: 0
    )
    #expect(controller.state == .activity)
    #expect(controller.parameters == controller.metrics.twoActivities)

    let budget = controller.metrics.twoActivities.height - controller.metrics.notchRect.height

    let renderer = ImageRenderer(content: NotchRootView(controller: controller).detailRowForTesting)
    renderer.scale = 2
    // Height left unconstrained (`nil`): the point is the subtree's own
    // IDEAL height, not whatever a fixed proposed height would force it
    // into. Width is fixed to match what `islandContent` actually gives it
    // in production (see `detailRowForTesting`'s doc comment).
    renderer.proposedSize = ProposedViewSize(width: controller.parameters.width, height: nil)
    guard let cgImage = renderer.cgImage else {
        fatalError("ImageRenderer produced no image for detailRowForTesting")
    }
    let idealHeight = CGFloat(cgImage.height) / renderer.scale

    #expect(
        idealHeight <= budget,
        """
        detailRow's ideal height \(idealHeight)pt exceeds its \(budget)pt budget at two-activity \
        size — content that doesn't fit is silently clipped downward by `.clipShape`, invisible \
        to a pixel-level check against the full island
        """
    )
}

// MARK: - HUD symbol and bar (Task 5)

/// A lone HUD activity: `detailRow` is gated off at one-activity size (it
/// stays exactly notch-height), so the leading ear's `symbolName` glyph is
/// the ONLY new Task 5 surface reachable here — same reasoning that already
/// makes `compactText` load-bearing in the trailing ear at this size.
@MainActor
@Test func hudSymbolInLeadingEarRendersInsideTheIslandAndClearOfTheNotch() {
    let controller = makeController()
    controller.setActivities(
        [.init(id: "hud", title: "Sound", compactText: "62%", symbolName: "speaker.wave.2.fill")],
        overflow: 0
    )
    #expect(controller.state == .activity)
    #expect(controller.parameters == controller.metrics.hud)

    let result = renderAndClassify(controller)
    #expect(
        result.hasContentInsideIsland,
        """
        no content pixel found inside the island bounds \(result.islandBounds) \
        — the symbolName glyph did not render
        """
    )
    #expect(
        result.contentInsideNotchCount == 0,
        "\(result.contentInsideNotchCount) content pixel(s) drawn inside the notch rect \(result.holeRect)"
    )
    #expect(
        result.contentOutsideIslandCount == 0,
        """
        \(result.contentOutsideIslandCount) content pixel(s) drawn outside the island bounds \
        \(result.islandBounds)
        """
    )
}

/// The realistic concurrent case (spec's HUD priority 100 outranks
/// power's 60): a HUD activity with both `symbolName` and `barFill` shares
/// the two-activity size with another activity. Proves the full Task 5
/// surface — leading-ear glyph AND detail-row bar — renders without
/// leaking outside the island or into the notch, same shape as
/// `twoActivitiesContentRendersInsideTheIslandAndClearOfTheNotch` above.
@MainActor
@Test func hudSymbolAndBarAlongsideAnotherActivityRenderInsideTheIslandAndClearOfTheNotch() {
    let controller = makeController()
    controller.setActivities(
        [
            .init(id: "hud", title: "Volume 62%", compactText: "62%",
                  symbolName: "speaker.wave.2.fill", barFill: 0.62),
            .init(id: "power", title: "Charging · 42%", compactText: "42%"),
        ],
        overflow: 0
    )
    #expect(controller.state == .activity)
    #expect(controller.parameters == controller.metrics.twoActivities)

    let result = renderAndClassify(controller)
    #expect(
        result.hasContentInsideIsland,
        "no content pixel found inside the island bounds \(result.islandBounds)"
    )
    #expect(
        result.contentInsideNotchCount == 0,
        "\(result.contentInsideNotchCount) content pixel(s) drawn inside the notch rect \(result.holeRect)"
    )
    #expect(
        result.contentOutsideIslandCount == 0,
        """
        \(result.contentOutsideIslandCount) content pixel(s) drawn outside the island bounds \
        \(result.islandBounds)
        """
    )
}

/// `twoActivityDetailRowIdealHeightFitsItsBudget` above pins the budget with
/// fixtures that carry no `barFill`, so it cannot tell a rendered bar from a
/// silently-missing one — both measure the same. This pins the bar
/// POSITIVELY, by comparing the same detail row with and without `barFill`:
/// the version with a bar must measure measurably taller (proving the bar
/// actually drew something), while both must still fit the budget.
@MainActor
@Test func detailBarAddsMeasurableHeightAndStillFitsTheTwoActivityBudget() {
    func idealHeight(barFill: Double?) -> CGFloat {
        let controller = makeController()
        controller.setActivities(
            [
                .init(id: "hud", title: "Volume 62%", compactText: "62%", barFill: barFill),
                .init(id: "power", title: "Charging · 42%", compactText: "42%"),
            ],
            overflow: 0
        )
        let renderer = ImageRenderer(content: NotchRootView(controller: controller).detailRowForTesting)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: controller.parameters.width, height: nil)
        guard let cgImage = renderer.cgImage else {
            fatalError("ImageRenderer produced no image for detailRowForTesting")
        }
        return CGFloat(cgImage.height) / renderer.scale
    }

    let withoutBar = idealHeight(barFill: nil)
    let withBar = idealHeight(barFill: 0.62)

    #expect(
        withBar > withoutBar,
        """
        a barFill activity's detail row (\(withBar)pt) should measurably exceed the same row \
        with no bar (\(withoutBar)pt) — otherwise the bar silently isn't rendering
        """
    )

    let controller = makeController()
    let budget = controller.metrics.twoActivities.height - controller.metrics.notchRect.height
    #expect(
        withBar <= budget,
        """
        detailRow's ideal height \(withBar)pt with a barFill activity exceeds its \(budget)pt \
        budget at two-activity size
        """
    )
}

// MARK: - Media panel (Task 8)

/// One-activity size, media alone: the artwork placeholder in the leading
/// ear is the ONLY new Task 8 surface reachable here — same reasoning as
/// `hudSymbolInLeadingEarRendersInsideTheIslandAndClearOfTheNotch` above.
@MainActor
@Test func mediaArtworkInLeadingEarRendersInsideTheIslandAndClearOfTheNotch() {
    let controller = makeController()
    controller.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    controller.setMedia(
        MediaPresentation(title: "Song", artist: "Artist", artwork: nil, isPlaying: true, elapsed: 10, duration: 200)
    )
    #expect(controller.state == .activity)
    #expect(controller.parameters == controller.metrics.oneActivity)

    let result = renderAndClassify(controller)
    #expect(
        result.hasContentInsideIsland,
        """
        no content pixel found inside the island bounds \(result.islandBounds) \
        — the artwork placeholder did not render
        """
    )
    #expect(
        result.contentInsideNotchCount == 0,
        "\(result.contentInsideNotchCount) content pixel(s) drawn inside the notch rect \(result.holeRect)"
    )
    #expect(
        result.contentOutsideIslandCount == 0,
        "\(result.contentOutsideIslandCount) content pixel(s) drawn outside the island bounds \(result.islandBounds)"
    )
}

/// The realistic concurrent case: a HUD activity (priority 100) with
/// `barFill` outranks media (priority 10) at one-activity size. This proves
/// two things at once — the Task 8 guard on `leadingEar`'s media branch
/// (`.first?.id == "media"`) correctly excludes media's artwork when it is
/// NOT the topmost activity, and the Task 8 `trailingEar` design change (a
/// solo `barFill` activity renders a bar, not `compactText`) stays inside
/// the island at exactly the size where `detailRow`'s own bar is gated off.
@MainActor
@Test func hudBarInTrailingEarRendersInsideTheIslandAndClearOfTheNotchAtOneActivitySize() {
    let controller = makeController()
    controller.setActivities(
        [.init(id: "hud", title: "Sound", compactText: "62%", symbolName: "speaker.wave.2.fill", barFill: 0.62)],
        overflow: 0
    )
    controller.setMedia(
        MediaPresentation(title: "Song", artist: "Artist", artwork: nil, isPlaying: true, elapsed: 10, duration: 200)
    )
    #expect(controller.state == .activity)
    #expect(controller.parameters == controller.metrics.hud)

    let result = renderAndClassify(controller)
    #expect(
        result.hasContentInsideIsland,
        "no content pixel found inside the island bounds \(result.islandBounds)"
    )
    #expect(
        result.contentInsideNotchCount == 0,
        "\(result.contentInsideNotchCount) content pixel(s) drawn inside the notch rect \(result.holeRect)"
    )
    #expect(
        result.contentOutsideIslandCount == 0,
        "\(result.contentOutsideIslandCount) content pixel(s) drawn outside the island bounds \(result.islandBounds)"
    )
}

/// The expanded media panel: artwork, title, artist, scrub bar and controls,
/// all below the hole. Same shape as
/// `expandedContentRendersInsideTheIslandAndClearOfTheNotch`, but exercising
/// `MediaPanelView` specifically — that test's fixture never calls
/// `setMedia`, so it cannot catch a `MediaPanelView` defect on its own.
@MainActor
@Test func mediaPanelRendersInsideTheIslandAndClearOfTheNotchWhenExpanded() {
    let controller = makeController()
    controller.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    controller.setMedia(
        MediaPresentation(title: "Song", artist: "Artist", artwork: nil, isPlaying: true, elapsed: 30, duration: 200)
    )
    controller.click()
    #expect(controller.state == .expanded)
    #expect(controller.parameters == controller.metrics.expanded)

    let result = renderAndClassify(controller)
    #expect(
        result.hasContentInsideIsland,
        """
        no content pixel found inside the island bounds \(result.islandBounds) \
        — the media panel did not render
        """
    )
    #expect(
        result.contentInsideNotchCount == 0,
        "\(result.contentInsideNotchCount) content pixel(s) drawn inside the notch rect \(result.holeRect)"
    )
    #expect(
        result.contentOutsideIslandCount == 0,
        "\(result.contentOutsideIslandCount) content pixel(s) drawn outside the island bounds \(result.islandBounds)"
    )
}

/// Pins the media panel to its budget exactly like
/// `twoActivityDetailRowIdealHeightFitsItsBudget` pins the two-activity
/// case: a rendered/clipped pixel check against the full island (the test
/// above) cannot see content silently truncated by `.clipShape` — measuring
/// `detailRow`'s own ideal (UNCLIPPED) height directly, via the same
/// `detailRowForTesting` seam, is what actually catches a panel that has
/// grown past its budget (`expanded.height - notchRect.height`), which would
/// clip away the play/pause row invisibly rather than fail loudly.
@MainActor
@Test func mediaPanelIdealHeightFitsTheExpandedBudget() {
    let controller = makeController()
    let longTitle = "A Fairly Long Now-Playing Song Title"
    controller.setActivities([.init(id: "media", title: longTitle, detail: "An Artist Name")], overflow: 0)
    controller.setMedia(
        MediaPresentation(
            title: longTitle, artist: "An Artist Name", artwork: nil,
            isPlaying: true, elapsed: 30, duration: 200
        )
    )
    controller.click()
    #expect(controller.state == .expanded)

    let budget = controller.metrics.expanded.height - controller.metrics.notchRect.height

    let renderer = ImageRenderer(content: NotchRootView(controller: controller).detailRowForTesting)
    renderer.scale = 2
    renderer.proposedSize = ProposedViewSize(width: controller.parameters.width, height: nil)
    guard let cgImage = renderer.cgImage else {
        fatalError("ImageRenderer produced no image for detailRowForTesting")
    }
    let idealHeight = CGFloat(cgImage.height) / renderer.scale

    #expect(
        idealHeight <= budget,
        """
        media panel's ideal height \(idealHeight)pt exceeds its \(budget)pt budget at expanded \
        size — content that doesn't fit is silently clipped downward by `.clipShape`, invisible \
        to a pixel-level check against the full island
        """
    )
}

// MARK: - Harness self-check

/// Validates the rendering + coordinate-flip pipeline above independently of
/// `NotchRenderTestHook`: the island's own opaque black fill should land at
/// the same bounding box `NotchShape`'s path math says it should — already
/// proven correct by `NotchShapeTests`. If this fails, the three tests above
/// are not trustworthy: the bug would be in this harness, not in
/// `NotchRootView`.
@MainActor
@Test func renderedIslandFillMatchesTheComputedShapePath() {
    let controller = makeController()
    controller.setActivities(
        [.init(id: "power", title: "Charging · 42%", compactText: "42%")], overflow: 0
    )
    controller.click()   // expanded: the tallest, widest state — most margin for error

    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    let expected = NotchShape(controller.parameters).path(in: canvas).boundingRect

    var minX = CGFloat.infinity, maxX = -CGFloat.infinity
    var minY = CGFloat.infinity, maxY = -CGFloat.infinity
    var sawAny = false
    RenderedImage(controller).forEachPixel { point, _, isIslandFill in
        guard isIslandFill else { return }
        sawAny = true
        minX = min(minX, point.x); maxX = max(maxX, point.x)
        minY = min(minY, point.y); maxY = max(maxY, point.y)
    }

    #expect(sawAny, "no black island-fill pixels found at all — rendering pipeline produced nothing")
    guard sawAny else { return }
    let renderedBounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    // Generous tolerance: antialiasing softens the outermost ring of pixels
    // below the opacity/brightness thresholds `isIslandFill` requires — most
    // visibly along the expanded state's wide, shallow concave fillet arcs,
    // measured at ~3.5pt at this scale/threshold.
    let tolerance: CGFloat = 5
    #expect(abs(renderedBounds.minX - expected.minX) < tolerance, "\(renderedBounds) vs \(expected)")
    #expect(abs(renderedBounds.maxX - expected.maxX) < tolerance, "\(renderedBounds) vs \(expected)")
    #expect(abs(renderedBounds.minY - expected.minY) < tolerance, "\(renderedBounds) vs \(expected)")
    #expect(abs(renderedBounds.maxY - expected.maxY) < tolerance, "\(renderedBounds) vs \(expected)")
}
