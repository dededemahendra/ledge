import SwiftUI

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

/// The island: on a real notch, a square top welded to the bezel, rounded bottom corners, and
/// concave outer fillets blending the sides into the menu bar; on a screen without one, a floating pill (2026-10-21).
///
/// Hand-rolled because `UnevenRoundedRectangle` cannot produce concave corners.
public struct NotchShape: Shape {
    public var parameters: NotchShapeParameters

    public init(_ parameters: NotchShapeParameters) {
        self.parameters = parameters
    }

    public var animatableData: NotchShapeParameters.AnimatableData {
        get { parameters.animatableData }
        set { parameters.animatableData = newValue }
    }

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
}
