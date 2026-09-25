import SwiftUI

/// The four animated dimensions of the island.
public struct NotchShapeParameters: Sendable, Equatable, Animatable {
    public var width: CGFloat
    public var height: CGFloat
    public var bottomRadius: CGFloat
    public var outerFillet: CGFloat

    public init(width: CGFloat, height: CGFloat, bottomRadius: CGFloat, outerFillet: CGFloat) {
        self.width = width
        self.height = height
        self.bottomRadius = bottomRadius
        self.outerFillet = outerFillet
    }

    public var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, CGFloat>
    > {
        get {
            AnimatablePair(
                AnimatablePair(width, height),
                AnimatablePair(bottomRadius, outerFillet)
            )
        }
        set {
            width = newValue.first.first
            height = newValue.first.second
            bottomRadius = newValue.second.first
            outerFillet = newValue.second.second
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
            outerFillet: mix(a.outerFillet, b.outerFillet)
        )
    }
}

/// The island: square top welded to the bezel, rounded bottom corners, and
/// concave outer fillets blending the sides into the menu bar.
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
        let top = rect.minY
        let height = max(0, parameters.height)
        let halfWidth = max(0, parameters.width) / 2
        // Radii cannot exceed the box they round, or the path self-intersects.
        let bottomRadius = min(parameters.bottomRadius, halfWidth, height)
        let fillet = max(0, min(parameters.outerFillet, height - bottomRadius))

        let left = centreX - halfWidth
        let right = centreX + halfWidth
        let bottom = top + height

        var path = Path()
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

        path.closeSubpath()
        return path
    }
}
