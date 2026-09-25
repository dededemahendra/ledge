import CoreGraphics

/// Geometry of the island at each resting size, derived from the live notch.
/// Target sizes come from the spec; the collapsed size comes from the hardware.
public struct NotchMetrics: Sendable, Equatable {
    /// Transparent canvas the island animates inside. The window is this size
    /// and never resizes — see spec §5.
    public static let canvasSize = CGSize(width: 640, height: 320)

    /// Progress window over which content fades in.
    public static let contentFadeIn: ClosedRange<Double> = 0.45...0.83

    /// `.origin.x` is computed, coordinate-converted (see `NotchGeometry`),
    /// and tested, but read by no production code — every consumer
    /// (`NotchShape`, `NotchRootView`) re-derives horizontal placement from
    /// `screen.frame.midX`/the canvas's own centre instead, i.e. every
    /// island this metrics value describes is assumed centred on its
    /// screen. Recorded here, not restructured: only `.width`/`.height` are
    /// actually load-bearing today.
    public let notchRect: CGRect

    public init(notchRect: CGRect) {
        self.notchRect = notchRect
    }

    public var collapsed: NotchShapeParameters {
        NotchShapeParameters(
            width: notchRect.width,
            height: notchRect.height,
            bottomRadius: 9,
            outerFillet: 0
        )
    }

    public var peek: NotchShapeParameters {
        NotchShapeParameters(
            width: notchRect.width,
            height: notchRect.height + 6,
            bottomRadius: 11,
            outerFillet: 4
        )
    }

    public var oneActivity: NotchShapeParameters {
        // Height tracks the hardware, not a literal: with a single activity the
        // island stays exactly notch-height. Hardcoding 32 would make the island
        // SHORTER than the cutout on a scaling mode with a taller notch, so it
        // would shrink at the moment it is supposed to grow and would stop
        // covering the hole.
        NotchShapeParameters(
            width: 255,
            height: notchRect.height,
            bottomRadius: 12,
            outerFillet: 6
        )
    }

    public var twoActivities: NotchShapeParameters {
        NotchShapeParameters(
            width: 342,
            height: atLeastNotchHeight(62),
            bottomRadius: 20,
            outerFillet: 10
        )
    }

    public var expanded: NotchShapeParameters {
        NotchShapeParameters(
            width: 390,
            // 118 -> 140 during the media-player redesign: the richer card
            // (15pt rounded title, focal 26pt play button, scrub block with
            // live-drag affordance) measures ~97pt of ideal height, and 118's
            // 86pt budget silently clipped its control row. Growing was ruled
            // out for the COMPACT states (layout C, "ears first"), never for
            // expanded — the deliberate full-panel state exists to fit its
            // panel. Pinned by NotchRenderTests'
            // mediaPanelIdealHeightFitsTheExpandedBudget.
            height: atLeastNotchHeight(168),
            bottomRadius: 26,
            outerFillet: 13
        )
    }

    /// The spec's target heights assume the measured 32pt notch. On a display
    /// scaling mode with a taller notch the island must still cover the cutout,
    /// so every target is floored at the notch's own height.
    private func atLeastNotchHeight(_ target: CGFloat) -> CGFloat {
        max(target, notchRect.height)
    }

    /// Ear width available beside the hole at a given island width.
    public func earWidth(forIslandWidth width: CGFloat) -> CGFloat {
        max(0, (width - notchRect.width) / 2)
    }

    public func contentOpacity(progress: Double) -> Double {
        let range = Self.contentFadeIn
        if progress <= range.lowerBound { return 0 }
        if progress >= range.upperBound { return 1 }
        return (progress - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}
