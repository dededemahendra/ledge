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

// MARK: - The resting states named in the review

@MainActor
@Test func oneActivityContentRendersInsideTheIslandAndClearOfTheNotch() {
    let controller = makeController()
    // A generic activity (not hud/power/device, which each have their own
    // island now): the plain one-activity layout — dot left, value right.
    controller.setActivities(
        [.init(id: "notification", title: "Mail · 3 new", compactText: "3")], overflow: 0
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
@Test func expandedContentRendersInsideTheIslandAndClearOfTheNotch() {
    let controller = makeController()
    // The expanded panel is only ever the now-playing card (2026-09-29).
    controller.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    controller.setMedia(MediaPresentation(title: "Song", artist: "Artist", artwork: nil, isPlaying: true, elapsed: 10, duration: 200))
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
    #expect(controller.parameters == controller.metrics.oneActivity)

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
/// power's 60): a leading HUD activity takes the island ALONE — glyph in
/// one ear, percentage in the other, no detail row — with the other
/// activity queued behind it.
@MainActor
@Test func hudSymbolAndBarAlongsideAnotherActivityRenderInsideTheIslandAndClearOfTheNotch() {
    let controller = makeController()
    controller.setActivities(
        [
            .init(id: "hud", title: "Sound", compactText: "62%",
                  symbolName: "speaker.wave.2.fill", barFill: 0.62),
            .init(id: "power", title: "Charging · 42%", compactText: "42%"),
        ],
        overflow: 0
    )
    #expect(controller.state == .activity)
    #expect(controller.parameters == controller.metrics.oneActivity)

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
@Test func hudPercentInTrailingEarRendersInsideTheIslandAndClearOfTheNotchAtOneActivitySize() {
    let controller = makeController()
    controller.setActivities(
        [.init(id: "hud", title: "Sound", compactText: "62%", symbolName: "speaker.wave.2.fill", barFill: 0.62)],
        overflow: 0
    )
    controller.setMedia(
        MediaPresentation(title: "Song", artist: "Artist", artwork: nil, isPlaying: true, elapsed: 10, duration: 200)
    )
    #expect(controller.state == .activity)
    #expect(controller.parameters == controller.metrics.oneActivity)

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

/// Pins the media panel to its budget: a rendered/clipped pixel check
/// against the full island (the test
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
    controller.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    controller.setMedia(MediaPresentation(title: "Song", artist: "Artist", artwork: nil, isPlaying: true, elapsed: 10, duration: 200))
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

// MARK: - Device artwork (2026-09-28)

/// A device activity carrying a product render: the image (painted in the
/// content test colour so the classifier can see it) must land in the
/// leading ear — inside the island, clear of the notch — at one-activity
/// size, where the ear is only 38pt wide and the render is scaled to 24pt
/// tall. Pins the `artwork`-over-`symbolName` branch of `leadingEar`.
@MainActor
@Test func deviceArtworkInLeadingEarRendersInsideTheIslandAndClearOfTheNotch() throws {
    // A 140x100 solid-red PNG — the same ~1.4:1 aspect as the system's
    // AirPods renders.
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 140, pixelsHigh: 100, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 140, height: 100).fill()
    NSGraphicsContext.restoreGraphicsState()
    let png = try #require(rep.representation(using: .png, properties: [:]))

    let controller = makeController()
    controller.setActivities(
        [.init(id: "device", title: "AirPods Pro", compactText: "87%", symbolName: "airpods.pro", artwork: png)],
        overflow: 0
    )
    #expect(controller.parameters == controller.metrics.oneActivity)

    let result = renderAndClassify(controller)
    #expect(result.hasContentInsideIsland, "the render did not draw")
    #expect(result.contentInsideNotchCount == 0,
            "\(result.contentInsideNotchCount) render pixel(s) inside the notch rect \(result.holeRect)")
    #expect(result.contentOutsideIslandCount == 0,
            "\(result.contentOutsideIslandCount) render pixel(s) outside the island bounds \(result.islandBounds)")
}

// MARK: - Lock screen (2026-09-28)

/// The display-only card (`MediaPanelView.displayOnly`, driven by
/// `NotchController.isLocked`) must render inside the island and clear of
/// the notch exactly like the interactive one — and, being one row
/// shorter, must measure strictly less ideal height than it, which is the
/// only cheap proof that the control row really is gone rather than
/// merely disabled.
@MainActor
@Test func lockedMediaPanelRendersInsideTheIslandWithoutItsControlRow() {
    func controller(locked: Bool) -> NotchController {
        let c = makeController()
        c.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
        c.setMedia(MediaPresentation(title: "Song", artist: "Artist", artwork: nil, isPlaying: true, elapsed: 30, duration: 200))
        if locked { c.setLocked(true) } else { c.click() }
        return c
    }

    let locked = controller(locked: true)
    #expect(locked.state == .expanded)
    #expect(!locked.isPinnedOpen)

    let result = renderAndClassify(locked)
    #expect(result.hasContentInsideIsland, "the display-only card did not render")
    #expect(result.contentInsideNotchCount == 0,
            "\(result.contentInsideNotchCount) content pixel(s) inside the notch rect \(result.holeRect)")
    #expect(result.contentOutsideIslandCount == 0,
            "\(result.contentOutsideIslandCount) content pixel(s) outside the island bounds \(result.islandBounds)")

    let lockedHeight = NSHostingView(rootView: NotchRootView(controller: locked).detailRowForTesting).fittingSize.height
    let interactiveHeight = NSHostingView(rootView: NotchRootView(controller: controller(locked: false)).detailRowForTesting).fittingSize.height
    #expect(lockedHeight < interactiveHeight,
            "display-only \(lockedHeight)pt should be shorter than interactive \(interactiveHeight)pt: the control row must be gone")
}

/// Device blip over music, the user's screenshot case: the island stays at
/// one-activity size with the artwork in the leading ear and the device's
/// glyph in the trailing one — both inside the island, clear of the notch.
@MainActor
@Test func deviceGlyphOverMusicRendersInTheTrailingEarInsideTheIsland() {
    let controller = makeController()
    controller.setMedia(MediaPresentation(title: "Song", artist: "Artist", artwork: nil, isPlaying: true, elapsed: 10, duration: 200))
    controller.setActivities(
        [.init(id: "device", title: "External Headphones", symbolName: "headphones"),
         .init(id: "media", title: "Song", detail: "Artist")],
        overflow: 0
    )
    #expect(controller.parameters == controller.metrics.oneActivity)

    let result = renderAndClassify(controller)
    #expect(result.hasContentInsideIsland, "neither the artwork placeholder nor the glyph rendered")
    #expect(result.contentInsideNotchCount == 0,
            "\(result.contentInsideNotchCount) content pixel(s) inside the notch rect \(result.holeRect)")
    #expect(result.contentOutsideIslandCount == 0,
            "\(result.contentOutsideIslandCount) content pixel(s) outside the island bounds \(result.islandBounds)")
}

/// Power at the one-activity island: bolt left, "95%" right, inside the
/// island and clear of the notch — alone and over music.
@MainActor
@Test func powerGlyphAndPercentRenderInsideTheIslandAndClearOfTheNotch() {
    for overMusic in [false, true] {
        let controller = makeController()
        var activities: [NotchController.ActivityDisplay] = [
            .init(id: "power", title: "Charging · 95% · 20 min to full", compactText: "95%", symbolName: "bolt.fill")
        ]
        if overMusic {
            controller.setMedia(MediaPresentation(title: "Song", artist: "Artist", artwork: nil, isPlaying: true, elapsed: 10, duration: 200))
            activities.append(.init(id: "media", title: "Song", detail: "Artist"))
        }
        controller.setActivities(activities, overflow: 0)
        #expect(controller.parameters == controller.metrics.oneActivity)

        let result = renderAndClassify(controller)
        #expect(result.hasContentInsideIsland, "overMusic=\(overMusic): nothing rendered")
        #expect(result.contentInsideNotchCount == 0,
                "overMusic=\(overMusic): \(result.contentInsideNotchCount) content pixel(s) inside the notch rect")
        #expect(result.contentOutsideIslandCount == 0,
                "overMusic=\(overMusic): \(result.contentOutsideIslandCount) content pixel(s) outside the island")
    }
}

/// The output picker's list must fit the budget the island grows to for it
/// — exactly one row per output — and must actually be taller than the
/// closed card, proving the rows rendered.
@MainActor
@Test func outputPickerListFitsTheGrownBudgetAndAddsRows() {
    let metrics = NotchMetrics(notchRect: testNotchRect)
    let media = MediaPresentation(title: "A Fairly Long Now-Playing Song Title", artist: "An Artist Name", artwork: nil, isPlaying: true, elapsed: 30, duration: 200)
    let outputs = [
        OutputOption(id: "builtin", name: "MacBook Air Speakers", symbolName: "laptopcomputer", isCurrent: true),
        OutputOption(id: "bt-1", name: "Dede's AirPods Pro", symbolName: "airpods.pro", isCurrent: false),
        OutputOption(id: "ap-1", name: "Living Room", symbolName: "airplay.audio", isCurrent: false),
        OutputOption(id: "usb-1", name: "Studio Display Speakers", symbolName: "speaker.wave.2", isCurrent: false),
    ]
    let namespace = Namespace().wrappedValue

    func idealHeight(pickerOpen: Bool) -> CGFloat {
        let panel = MediaPanelView(
            media: media, reduceMotion: true, contentColor: .red,
            artworkNamespace: namespace, emit: { _ in }, outputs: outputs, outputPickerOpen: pickerOpen
        )
        let renderer = ImageRenderer(content: panel.frame(width: metrics.expanded.width))
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: metrics.expanded.width, height: nil)
        guard let image = renderer.cgImage else { fatalError("no image") }
        return CGFloat(image.height) / renderer.scale
    }

    let closed = idealHeight(pickerOpen: false)
    let open = idealHeight(pickerOpen: true)
    let closedBudget = metrics.expanded.height - metrics.notchRect.height
    let openBudget = metrics.expanded(outputRows: outputs.count).height - metrics.notchRect.height
    #expect(closed <= closedBudget)
    #expect(open <= openBudget, "open list: \(open)pt exceeds the grown \(openBudget)pt budget")
    #expect(open - closed >= CGFloat(outputs.count) * NotchMetrics.outputRowHeight - 1,
            "the list must add one row per output (\(open - closed)pt for \(outputs.count) rows)")
}

/// The song-change caption: artwork and bars in the (wider) ears, one text
/// line under the hole — inside the island, clear of the notch.
@MainActor
@Test func captionRowRendersUnderTheHoleInsideTheIsland() {
    let controller = makeController()
    controller.setMedia(MediaPresentation(title: "Tangerine Rays", artist: "Zedd, Bea Miller & Grey", artwork: nil, isPlaying: true, elapsed: 3, duration: 200))
    controller.setActivities([.init(id: "media", title: "Tangerine Rays", detail: "Zedd")], overflow: 0)
    controller.setCaption("Tangerine Rays · Zedd, Bea Miller & Grey")
    #expect(controller.parameters.height == controller.metrics.captioned.height && controller.parameters.width >= NotchMetrics.captionedMinimumWidth)

    let result = renderAndClassify(controller)
    #expect(result.hasContentInsideIsland, "the caption did not render")
    #expect(result.contentInsideNotchCount == 0,
            "\(result.contentInsideNotchCount) content pixel(s) inside the notch rect \(result.holeRect)")
    #expect(result.contentOutsideIslandCount == 0,
            "\(result.contentOutsideIslandCount) content pixel(s) outside the island bounds \(result.islandBounds)")
}

/// The hover preview of the next event (2026-09-29): the peek at
/// `captioned` size with the calendar glyph, the countdown and the caption
/// line — all inside the island, none of it in the notch.
@MainActor
@Test func upcomingPreviewRendersInsideTheIslandAndClearOfTheNotch() {
    let controller = makeController()
    controller.setUpcoming(UpcomingEvent(title: "Design review", compactText: "42m", caption: "Design review · 14:00", url: nil))
    controller.setHovered(true)
    #expect(controller.state == .peek)
    #expect(controller.parameters.height == controller.metrics.captioned.height && controller.parameters.width >= NotchMetrics.captionedMinimumWidth)

    let result = renderAndClassify(controller)
    #expect(result.hasContentInsideIsland, "no content pixel inside \(result.islandBounds) — the preview did not render")
    #expect(result.contentInsideNotchCount == 0, "\(result.contentInsideNotchCount) content pixel(s) inside the notch rect")
    #expect(result.contentOutsideIslandCount == 0, "\(result.contentOutsideIslandCount) content pixel(s) outside the island")
}

/// A Focus blip with a long name (2026-09-30): the island stretched to
/// fit the trailing text — everything still inside it, nothing in the
/// notch, the text not spilling past the ear.
@MainActor
@Test func aWideFocusBlipRendersInsideTheIslandAndClearOfTheNotch() {
    let controller = makeController()
    controller.setActivities(
        [.init(id: "focus", title: "Reduce Interruptions", compactText: "Reduce Interruptions", symbolName: "moon.fill")],
        overflow: 0
    )
    #expect(controller.parameters.width > controller.metrics.oneActivity.width)

    let result = renderAndClassify(controller)
    #expect(result.hasContentInsideIsland, "no content pixel inside \(result.islandBounds)")
    #expect(result.contentInsideNotchCount == 0, "\(result.contentInsideNotchCount) content pixel(s) inside the notch rect")
    #expect(result.contentOutsideIslandCount == 0, "\(result.contentOutsideIslandCount) content pixel(s) outside the island")
}

/// The calendar mode (2026-09-30): four rows and the dots, inside the
/// island, clear of the notch.
@MainActor
@Test func calendarModeRendersInsideTheIslandAndClearOfTheNotch() {
    let controller = makeController()
    controller.setMedia(MediaPresentation(title: "Song", artist: "Artist", artwork: nil, isPlaying: true, elapsed: 10, duration: 200))
    controller.setActivities([.init(id: "media", title: "Song", detail: "Artist")], overflow: 0)
    controller.setCalendarMode(CalendarModeData(
        now: Date(), calendar: Calendar.current, markedDays: [1, 15, 30],
        items: (1...3).map { UpcomingEvent(title: "Item \($0)", compactText: "\($0)h", caption: "Item \($0) · 1\($0):00", when: "1\($0):00–1\($0):30", url: nil) }
    ))
    controller.setHovered(true)
    #expect(controller.swipe(.next) && controller.panel == .calendar)
    let result = renderAndClassify(controller)
    #expect(result.hasContentInsideIsland)
    #expect(result.contentInsideNotchCount == 0, "\(result.contentInsideNotchCount) content pixel(s) inside the notch rect")
    #expect(result.contentOutsideIslandCount == 0, "\(result.contentOutsideIslandCount) content pixel(s) outside the island")
}
