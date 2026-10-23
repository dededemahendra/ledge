import SwiftUI

/// The tab beside the island (2026-10-23), relative to the island's own
/// live parameters: the shape is drawn from the island's right edge out.
///
/// `width` is the tab's body between its two sides, as `NotchShapeParameters.
/// width` is the island's: on a notch the two concave outer fillets reach
/// `outerFillet` further out on each side, so the drawn path is
/// `width + 2 * outerFillet` wide. `gap` is measured to the body, not to the
/// fillet.
public struct NotchTabParameters: Sendable, Equatable, Animatable {
    /// 6 shown, 0 tucked.
    public var gap: CGFloat
    /// 40 shown (a pill: the pill's height), 0 tucked.
    public var width: CGFloat
    /// The notch's height (a pill: the pill's height).
    public var height: CGFloat
    /// 12 (a pill: height / 2).
    public var bottomRadius: CGFloat
    /// 6 on a notch, 0 on a pill.
    public var outerFillet: CGFloat
    /// 0 on a notch, `NotchMetrics.pillTopInset` on a pill.
    public var topInset: CGFloat
    /// 0 on a notch, height / 2 on a pill.
    public var topRadius: CGFloat

    public init(
        gap: CGFloat, width: CGFloat, height: CGFloat, bottomRadius: CGFloat, outerFillet: CGFloat,
        topInset: CGFloat = 0, topRadius: CGFloat = 0
    ) {
        self.gap = gap
        self.width = width
        self.height = height
        self.bottomRadius = bottomRadius
        self.outerFillet = outerFillet
        self.topInset = topInset
        self.topRadius = topRadius
    }

    /// Only the three dimensions that move between tucked and shown; the
    /// corners keep their values and are clamped by the shape while the
    /// width is small.
    public var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(gap, width), height) }
        set {
            gap = newValue.first.first
            width = newValue.first.second
            height = newValue.second
        }
    }
}

extension NotchMetrics {
    public static let tabWidth: CGFloat = 40
    public static let tabGap: CGFloat = 6

    /// The tab, shown, beside whichever island it is drawn with (`NotchTabShape`
    /// takes the island's width): a round bubble, as the iPhone's second
    /// island is (2026-10-23, user's call). On a notch it is as tall as the
    /// notch, its top against the screen's edge like the island's; on a
    /// pill, as tall as the pill at rest, at the pill's top inset.
    public var tab: NotchTabParameters {
        // The resting height, never the island's live one.
        let diameter = isVirtual ? oneActivity.height : notchRect.height
        return NotchTabParameters(
            gap: Self.tabGap, width: diameter, height: diameter, bottomRadius: diameter / 2,
            outerFillet: 0, topInset: isVirtual ? Self.pillTopInset : 0, topRadius: diameter / 2
        )
    }

    /// The tab's budding and merging state: no gap, no width, at the island's
    /// right edge, else as `tab`.
    public var tabTucked: NotchTabParameters {
        var tucked = tab
        tucked.gap = 0
        tucked.width = 0
        return tucked
    }
}

/// The tab's path in the island's canvas: x from `rect.midX + island.width / 2 + tab.gap`.
/// Built like `NotchShape`, so both read as the same material; it takes the
/// island's parameters too, so the tab follows the island's live width.
public struct NotchTabShape: Shape, Animatable {
    public var island: NotchShapeParameters
    public var tab: NotchTabParameters

    public init(island: NotchShapeParameters, tab: NotchTabParameters) {
        self.island = island
        self.tab = tab
    }

    public var animatableData: AnimatablePair<NotchShapeParameters.AnimatableData, NotchTabParameters.AnimatableData> {
        get { AnimatablePair(island.animatableData, tab.animatableData) }
        set {
            island.animatableData = newValue.first
            tab.animatableData = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        let width = max(0, tab.width)
        // Nothing to draw while tucked: no sliver, no stray fillets.
        guard width > 0 else { return Path() }
        let top = rect.minY + max(0, tab.topInset)
        let height = max(0, tab.height)
        let isPill = tab.topRadius > 0
        let bottomRadius: CGFloat
        let topRadius: CGFloat
        if isPill {
            let limit = min(width / 2, height / 2)
            bottomRadius = min(tab.bottomRadius, limit)
            topRadius = min(tab.topRadius, limit)
        } else {
            bottomRadius = min(tab.bottomRadius, width / 2, height)
            topRadius = 0
        }
        // The fillet grows with the bud, so a sliver has no 6 pt flares.
        let budding = min(1, width / NotchMetrics.tabWidth)
        let fillet = isPill ? 0 : max(0, min(tab.outerFillet * budding, height - bottomRadius))

        let left = rect.midX + max(0, island.width) / 2 + tab.gap
        let right = left + width
        let bottom = top + height

        var path = Path()
        if topRadius > 0 {
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
}
