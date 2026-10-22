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

    /// No hardware notch behind `notchRect` (2026-10-21): it is
    /// `NotchGeometry.virtualNotchRect`, drawn on a screen without one.
    public let isVirtual: Bool

    public init(notchRect: CGRect, isVirtual: Bool = false) {
        self.notchRect = notchRect
        self.isVirtual = isVirtual
    }

    /// What the island draws while hidden or tucked. On a real notch that
    /// is the notch itself, invisible against the hardware. A pill has
    /// nothing to hide behind, so it shrinks into a point at the top
    /// centre and grows back out of it (2026-10-21). `collapsed` is where
    /// hover finds a hidden island, either way.
    public var retracted: NotchShapeParameters {
        guard isVirtual else { return collapsed }
        return pill(width: 0, height: 0, radius: notchRect.height / 2)
    }

    public var collapsed: NotchShapeParameters {
        // The pill's resting footprint is its one-activity size: never
        // drawn while hidden, it is where hover finds the island.
        if isVirtual { return oneActivity }
        return NotchShapeParameters(
            width: notchRect.width,
            height: notchRect.height,
            bottomRadius: 9,
            outerFillet: 0
        )
    }

    public var peek: NotchShapeParameters {
        // An empty pill, so the hover is acknowledged (2026-10-21).
        if isVirtual { return collapsed }
        return NotchShapeParameters(
            width: notchRect.width,
            height: notchRect.height + 6,
            bottomRadius: 11,
            outerFillet: 4
        )
    }

    /// The now-playing island with a song-change caption under the hole
    /// (2026-09-29, from the reference app): wider ears and one text row
    /// below. Height is the notch plus the row, so the island springs
    /// down and back rather than swapping shapes.
    public static let captionRowHeight: CGFloat = 26

    public var captioned: NotchShapeParameters { captioned(fitting: 342) }

    /// The caption line's island, as wide as the line needs (2026-10-01,
    /// user's call: the fixed 342 pt left a short title in a sea of black)
    /// and never narrower than the ears want or wider than the card.
    public static let captionedMinimumWidth: CGFloat = 255
    public static let captionedMaximumWidth: CGFloat = 430

    public func captioned(fitting width: CGFloat) -> NotchShapeParameters {
        let width = min(Self.captionedMaximumWidth, max(Self.captionedMinimumWidth, width))
        let height = notchRect.height + Self.captionRowHeight
        if isVirtual { return pill(width: width, height: height, radius: 18) }
        return NotchShapeParameters(width: width, height: height, bottomRadius: 18, outerFillet: 9)
    }

    /// The ear beside the hole at one-activity size: 38 pt, room for a
    /// 24 pt glyph or "100%" (32 pt).
    public static let activityEarWidth: CGFloat = 38
    /// How far an ear may stretch for a long trailing text before the
    /// text is cut instead — about "Reduce Interruptions".
    public static let activityEarMaximum: CGFloat = 130

    public var oneActivity: NotchShapeParameters { oneActivity(earWidth: Self.activityEarWidth) }

    /// One activity with ears at least `earWidth` wide (2026-09-30): a
    /// Focus's name in the trailing ear stretches the island to fit, the
    /// way the Dynamic Island stretches for content; everything else
    /// leaves the default, the notch and two 38 pt ears, 255 pt on the
    /// measured notch.
    public func oneActivity(earWidth: CGFloat) -> NotchShapeParameters {
        let ear = min(Self.activityEarMaximum, max(Self.activityEarWidth, earWidth))
        // The pill's middle is a gap, not a camera (2026-10-21): its width
        // follows the 44 pt virtual notch, so the ears sit close, and the
        // ends are round.
        if isVirtual {
            return pill(width: notchRect.width + 2 * ear, height: notchRect.height, radius: notchRect.height / 2)
        }
        // Height tracks the hardware, not a literal: with a single activity the
        // island stays exactly notch-height. Hardcoding 32 would make the island
        // SHORTER than the cutout on a scaling mode with a taller notch, so it
        // would shrink at the moment it is supposed to grow and would stop
        // covering the hole. Width likewise (2026-10-21): a fixed 255 left a
        // scaled mode's 208 pt notch 23.5 pt ears, "100%" clipped at the edge.
        return NotchShapeParameters(
            width: notchRect.width + 2 * ear,
            height: notchRect.height,
            bottomRadius: 12,
            outerFillet: 6
        )
    }

    public var expanded: NotchShapeParameters { expanded(outputRows: 0) }

    /// One list row of the output picker, and the gap above the list.
    public static let outputRowHeight: CGFloat = 30
    public static let outputListInset: CGFloat = 10

    /// The panel, grown downward by the output picker's list (2026-09-29,
    /// user's call: "expand bottom" rather than swap the control row for
    /// chips). Width and corners unchanged; only the height follows the
    /// number of rows, so the spring morphs the card taller in place.
    /// `earsShowing`: only the pill reads it — see `cardTopBand(earsShowing:)`.
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
    /// Room for the call card's content below its top (2026-10-22): two
    /// rows, the app and its controls over the mic and "Not a call".
    public static let callCardContentHeight: CGFloat = 96

    /// The call card (2026-10-22, polish): as wide as the other cards, only
    /// as tall as its two rows. Its ears give way to it, so a pill keeps
    /// the short top band.
    public var callCard: NotchShapeParameters {
        if isVirtual {
            return pill(width: Self.expandedWidth, height: Self.callCardContentHeight + cardTopBand(earsShowing: false),
                        radius: 26)
        }
        return NotchShapeParameters(
            width: Self.expandedWidth,
            height: atLeastNotchHeight(notchRect.height + Self.callCardContentHeight),
            bottomRadius: 26,
            outerFillet: 13
        )
    }

    /// A pill's parameters: every corner `radius`, no fillets, floating at
    /// `pillTopInset`.
    private func pill(width: CGFloat, height: CGFloat, radius: CGFloat) -> NotchShapeParameters {
        NotchShapeParameters(
            width: width, height: height, bottomRadius: radius, outerFillet: 0,
            topInset: Self.pillTopInset, topRadius: radius
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
