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

/// Fades island content in as the shape grows, so text never appears before there
/// is room for it.
///
/// Carrying progress as this modifier's own `animatableData` is what makes
/// SwiftUI's interpolated value visible to `body(content:)` — a view body reading
/// `controller.parameters` only ever sees the target.
struct ContentFade: ViewModifier, Animatable {
    var progress: Double
    let metrics: NotchMetrics

    // `ViewModifier.body` is @MainActor (inferred onto the whole conforming
    // type), but `Animatable.animatableData` is a nonisolated requirement —
    // SwiftUI's animation system interpolates it outside that isolation. This
    // property only ever touches the plain `Double` above, so it is safe to
    // exempt from the type's inferred MainActor isolation.
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(metrics.contentOpacity(progress: progress))
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
                        .modifier(ContentFade(
                            progress: growthProgress(parameters),
                            metrics: controller.metrics
                        ))
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

    /// How far the shape has grown between its resting extremes, 0 at the
    /// smallest (collapsed) and 1 at the largest (expanded). Feeds `ContentFade`
    /// so content fades in over the same interpolated progress the shape itself
    /// is animating through, not a fixed-duration approximation of it.
    private func growthProgress(_ parameters: NotchShapeParameters) -> Double {
        let floor = controller.metrics.collapsed.height
        let ceiling = controller.metrics.expanded.height
        guard ceiling > floor else { return 1 }
        return Double((parameters.height - floor) / (ceiling - floor))
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
        if controller.overflowCount > 0 {
            Text("+\(controller.overflowCount)")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
        } else if let compact = controller.activities.first?.compactText {
            // At one activity the island is notch-height and `detailRow` is gated
            // off, so this ear is the ONLY place a value can appear. Without it the
            // island widens, shows a glyph, and says nothing.
            Text(compact)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .transition(.blurReplace)
        }
    }

    @ViewBuilder private var detailRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(controller.activities) { activity in
                Text(activity.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .transition(.blurReplace)
                if let detail = activity.detail {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
