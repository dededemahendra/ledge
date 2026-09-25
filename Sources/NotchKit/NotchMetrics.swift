import CoreGraphics

/// Geometry of the island at each resting size, derived from the live notch.
/// Target sizes come from the spec; the collapsed size comes from the hardware.
public struct NotchMetrics: Sendable, Equatable {
    /// Transparent canvas the island animates inside. The window is this size
    /// and never resizes — see spec §5.
    public static let canvasSize = CGSize(width: 640, height: 320)

    /// Progress window over which content fades in.
    public static let contentFadeIn: ClosedRange<Double> = 0.45...0.83

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
        NotchShapeParameters(width: 255, height: 32, bottomRadius: 12, outerFillet: 6)
    }

    public var twoActivities: NotchShapeParameters {
        NotchShapeParameters(width: 342, height: 62, bottomRadius: 20, outerFillet: 10)
    }

    public var expanded: NotchShapeParameters {
        NotchShapeParameters(width: 390, height: 118, bottomRadius: 26, outerFillet: 13)
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
