import SwiftUI

/// Motion constants. Chosen by comparing candidates against "which would you
/// still tolerate on the fiftieth repeat" — see spec §5.
public enum NotchAnimation {
    public static let expandResponse: Double = 0.35
    public static let expandDamping: Double = 0.72
    public static let collapseResponse: Double = 0.30
    public static let collapseDamping: Double = 0.92
    public static let reducedDuration: Double = 0.15

    public static let expand = Animation.spring(
        response: expandResponse, dampingFraction: expandDamping
    )
    public static let collapse = Animation.spring(
        response: collapseResponse, dampingFraction: collapseDamping
    )
    public static let reduced = Animation.easeInOut(duration: reducedDuration)

    public static func animation(expanding: Bool, reduceMotion: Bool) -> Animation {
        if reduceMotion { return reduced }
        return expanding ? expand : collapse
    }
}

/// The island itself. Content is clipped to the same shape that defines the
/// silhouette, so nothing can bleed outside during a morph.
public struct NotchRootView: View {
    private let controller: NotchController

    public init(controller: NotchController) {
        self.controller = controller
    }

    public var body: some View {
        let parameters = controller.parameters
        let shape = NotchShape(parameters)

        ZStack(alignment: .top) {
            shape
                .fill(.black)
                .overlay {
                    islandContent(parameters: parameters)
                        .clipShape(shape)
                }
        }
        .frame(
            width: NotchMetrics.canvasSize.width,
            height: NotchMetrics.canvasSize.height,
            alignment: .top
        )
        .animation(
            NotchAnimation.animation(
                expanding: controller.state == .expanded || controller.state == .activity,
                reduceMotion: controller.reduceMotion
            ),
            value: parameters
        )
        .opacity(controller.isVisible ? 1 : 0)
        .allowsHitTesting(controller.isVisible)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ledge notch island")
    }

    /// Content lives in the ears and below the hole. Nothing may be drawn
    /// inside `controller.metrics.notchRect` — there are no pixels there.
    @ViewBuilder
    private func islandContent(parameters: NotchShapeParameters) -> some View {
        let notch = controller.metrics.notchRect
        let ear = controller.metrics.earWidth(forIslandWidth: parameters.width)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leadingEar.frame(width: ear, height: notch.height)
                Color.clear.frame(width: notch.width, height: notch.height)   // the hole
                trailingEar.frame(width: ear, height: notch.height)
            }
            if parameters.height > notch.height + 8 {
                detailRow
                    .frame(maxWidth: .infinity)
                    .frame(height: parameters.height - notch.height)
            }
        }
        .frame(width: parameters.width, alignment: .top)
        .foregroundStyle(.white)
    }

    @ViewBuilder private var leadingEar: some View {
        if controller.activityCount > 0 {
            Circle().fill(.white.opacity(0.28)).padding(6)
        }
    }

    @ViewBuilder private var trailingEar: some View {
        if controller.activityCount > 2 {
            Text("+\(controller.activityCount - 2)")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
        }
    }

    @ViewBuilder private var detailRow: some View {
        EmptyView()
    }
}
