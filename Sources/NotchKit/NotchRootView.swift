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

    /// For in-place text swaps (the trailing ear's `compactText`, a detail
    /// row's `title`) — spec §5's "`.blurReplace` transition for text
    /// swaps." A spring reads wrong here: a spring is for something moving
    /// or resizing, and text swapping in place is neither, so `expand`/
    /// `collapse`'s overshoot would look like a glitch, not motion. Short
    /// enough not to lag behind the glanceable values it announces (a
    /// percentage ticking down, say).
    public static let textCrossfadeDuration: Double = 0.2
    public static let textCrossfade = Animation.easeInOut(duration: textCrossfadeDuration)

    public static func textAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : textCrossfade
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

#if DEBUG
/// Test-only seam, reachable only via `@testable import` (never `public`):
/// when set, island content paints with this colour instead of white, so
/// `NotchRenderTests` can classify rendered pixels by colour instead of by
/// brightness/anti-aliasing heuristics. `nil` on every real code path —
/// nothing outside `NotchRenderTests` ever assigns it, and the whole type
/// compiles out of release builds.
@MainActor
enum NotchRenderTestHook {
    static var contentColor: Color?
}
#endif

/// The island itself. Content is clipped to the same shape that defines the
/// silhouette, so nothing can bleed outside during a morph.
public struct NotchRootView: View {
    private let controller: NotchController

    /// Spec §5/§14: click-to-expand is the interaction model. Defaults to a
    /// no-op so every existing call site (including `NotchRenderTests`, which
    /// constructs this view directly with no presenter around) keeps
    /// compiling unchanged; `NotchPresenter` supplies its own `toggle()` so
    /// the window resyncs — mutating the controller alone would leave the
    /// window ordered out, the same bug `toggle()` was written to fix for
    /// the menu bar's "Toggle Panel".
    private let onTap: () -> Void

    /// The target height from before whichever transition is currently
    /// running, so `expanding` below reflects whether the island is
    /// actually growing or shrinking — not which named state it happens to
    /// be heading to. Picking the spring by destination state name meant a
    /// shrink into `.activity` (e.g. dismissing an open panel while an
    /// activity is live, 118 -> 32) used the expand spring's 3.8% overshoot
    /// and briefly undershot past the 32pt notch cutout, exposing the hole.
    ///
    /// Height is the primary signal — it is the one dimension where an
    /// overshoot has a physical consequence (uncovering the notch) — but it
    /// is not sufficient on its own: `.hidden` -> one activity grows 179 ->
    /// 255 in WIDTH at EQUAL height (`NotchMetrics.oneActivity` deliberately
    /// tracks `notchRect.height`, same as `.collapsed`), so a height-only
    /// comparison misclassified the app's single most common grow
    /// transition as a collapse. `previousWidth` below exists only to break
    /// that tie; it is not consulted otherwise, so a shrink that happens to
    /// widen (none exists among the app's states today, but nothing rules
    /// one out) still reads as a collapse from its height alone.
    ///
    /// Spelled out via the underlying `State<Value>` type rather than the
    /// `@State` attribute: this toolchain's CommandLineTools install has no
    /// `SwiftUIMacros` plugin (only the full Xcode.app does), so the `@State`
    /// macro fails to expand here — see `make test`'s own `TESTING_PLUGIN`
    /// workaround in the Makefile for the same class of issue. `State` the
    /// type is ordinary, non-macro public API and needs no plugin; this is
    /// exactly what the attribute would otherwise have synthesized.
    private var _previousHeight: State<CGFloat>
    private var previousHeight: CGFloat {
        get { _previousHeight.wrappedValue }
        nonmutating set { _previousHeight.wrappedValue = newValue }
    }

    /// See `previousHeight` above — same reasoning, same toolchain
    /// workaround, kept in the view (not `NotchController`) per spec §4.
    private var _previousWidth: State<CGFloat>
    private var previousWidth: CGFloat {
        get { _previousWidth.wrappedValue }
        nonmutating set { _previousWidth.wrappedValue = newValue }
    }

    public init(controller: NotchController, onTap: @escaping () -> Void = {}) {
        self.controller = controller
        self.onTap = onTap
        _previousHeight = State(initialValue: controller.parameters.height)
        _previousWidth = State(initialValue: controller.parameters.width)
    }

    public var body: some View {
        let parameters = controller.parameters
        let shape = NotchShape(parameters)
        let expanding = parameters.height == previousHeight
            ? parameters.width > previousWidth
            : parameters.height > previousHeight

        ZStack(alignment: .top) {
            shape
                .fill(.black)
                // `.overlay`'s default alignment is `.center`: a `Shape` fill
                // occupies its ENTIRE proposed canvas (640x320), not the
                // island's own drawn extent, so uncentred content here would
                // render 100+pt below the island, over the desktop, in every
                // state but the tallest. `.top` is what makes it land where
                // the island actually is.
                .overlay(alignment: .top) {
                    islandContent(parameters: parameters)
                        .modifier(ContentFade(
                            // `ContentFade` is `Animatable`: handing it a
                            // plain 0/1 target lets SwiftUI interpolate this
                            // modifier's own `animatableData` across whatever
                            // morph is already running (driven by the
                            // `.animation(value: parameters)` below), so
                            // `contentOpacity`'s 0.45...0.83 window is read
                            // against the TRANSITION's own progress — not
                            // against a height normalised over the global
                            // collapsed...expanded span, which is 0 at both
                            // `.hidden` and one activity (they share a height)
                            // and never reaches the fade-in window at two
                            // activities either.
                            progress: controller.isVisible ? 1 : 0,
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
        // Spec §5: `peek ──click──▶ expanded`, and `.leftMouseDown`/Escape
        // dismissal (both in `NotchPresenter`) close it again. AppKit's own
        // hit-testing (`NotchHostingView.hitTest`, driven by
        // `interactivePath`) already restricts which points ever reach this
        // view, so no extra region check is needed here.
        .onTapGesture { onTap() }
        .animation(
            NotchAnimation.animation(expanding: expanding, reduceMotion: controller.reduceMotion),
            value: parameters
        )
        .opacity(controller.isVisible ? 1 : 0)
        .allowsHitTesting(controller.isVisible)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ledge notch island")
        .onChange(of: parameters) { _, newValue in
            // Recorded AFTER this transition's spring was already chosen
            // above, so it becomes the "before" height/width for whichever
            // transition comes next.
            previousHeight = newValue.height
            previousWidth = newValue.width
        }
    }

    /// Content lives in the ears and below the hole. Nothing may be drawn
    /// inside `controller.metrics.notchRect` — there are no pixels there.
    @ViewBuilder
    private func islandContent(parameters: NotchShapeParameters) -> some View {
        let notch = controller.metrics.notchRect
        let ear = controller.metrics.earWidth(forIslandWidth: parameters.width)

        #if DEBUG
        let _ = assertContentStaysInsideIslandAndClearOfNotch(parameters: parameters, notch: notch, ear: ear)
        #endif

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leadingEar.frame(width: ear, height: notch.height)
                Color.clear.frame(width: notch.width, height: notch.height)   // the hole
                trailingEar.frame(width: ear, height: notch.height)
            }
            if parameters.height > notch.height + 8 {
                detailRow
                    .frame(maxWidth: .infinity)
                    // `alignment: .top`, not the default `.center`: if the
                    // detail row's content is ever taller than its budget
                    // (e.g. two priority-2 activities each with a title),
                    // the excess must overflow DOWNWARD, where the
                    // `.clipShape` below trims it invisibly — never upward,
                    // which would paint over the ear row and the notch
                    // rect itself. Caught by `NotchRenderTests`.
                    .frame(height: parameters.height - notch.height, alignment: .top)
            }
        }
        .frame(width: parameters.width, alignment: .top)
        .foregroundStyle(contentColor)
    }

    /// Spec §6/§10: content must stay inside the island's own rect and clear
    /// of the notch rect. Pure arithmetic against the exact values that size
    /// the frames above (no `GeometryReader` needed — the layout is fully
    /// determined by `parameters`/`notch`/`ear`), so this is cheap enough to
    /// run on every body evaluation in debug builds. This is the always-on
    /// canary during `make dev`; `NotchRenderTests` is the version of this
    /// check that can actually fail a CI run on rendered pixels.
    #if DEBUG
    private func assertContentStaysInsideIslandAndClearOfNotch(
        parameters: NotchShapeParameters, notch: CGRect, ear: CGFloat
    ) {
        let island = CGRect(x: 0, y: 0, width: parameters.width, height: parameters.height)
        let hole = CGRect(x: ear, y: 0, width: notch.width, height: notch.height)
        let regions: [(String, CGRect)] = [
            ("leading ear", CGRect(x: 0, y: 0, width: ear, height: notch.height)),
            ("trailing ear", CGRect(x: ear + notch.width, y: 0, width: ear, height: notch.height)),
            ("detail row", CGRect(
                x: 0, y: notch.height,
                width: parameters.width, height: max(0, parameters.height - notch.height)
            )),
        ]
        for (label, rect) in regions where rect.width > 0 && rect.height > 0 {
            assert(island.contains(rect), "\(label) must stay inside the island rect")
            if hole.width > 0, hole.height > 0 {
                assert(!rect.intersects(hole), "\(label) must not draw over the notch")
            }
        }
    }
    #endif

    /// White in production; overridden to a solid test colour only inside
    /// `NotchRenderTests`, which cannot reach this file except via
    /// `@testable import`. See `NotchRenderTestHook`.
    private var contentColor: Color {
        #if DEBUG
        NotchRenderTestHook.contentColor ?? .white
        #else
        .white
        #endif
    }

    @ViewBuilder private var leadingEar: some View {
        if let symbol = controller.activities.first?.symbolName {
            // Keyed and animated exactly like `trailingEar`'s `compact` text and
            // `detailTitle`'s title below: `AppModel` gives every HUD record the
            // same id ("hud"), so a symbol changing (e.g. wave.1 -> wave.2 as
            // volume rises, or the mute slash toggling) is an in-place update to
            // the SAME view, not an insertion — `.transition` only plays on
            // insertion/removal, so it needs this value-keyed `.id` to register
            // as one, and a local `.animation(value:)` to get an actually-
            // animated transaction (the root view's `.animation(value:
            // parameters)` does not attach for a symbol change alone, since
            // `parameters` — state/activityCount/metrics — stays equal).
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .id(symbol)
                .transition(.blurReplace)
                .animation(
                    NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion),
                    value: symbol
                )
        } else if controller.activityCount > 0 {
            Circle().fill(contentColor.opacity(0.28)).padding(6)
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
                // `AppModel` gives every power record the same `id`
                // ("power"), so `compact` changing (e.g. 87% -> 86%) is an
                // in-place update to the SAME `Text`, not an insertion —
                // `.transition` only ever plays on insertion/removal, so
                // without a value-keyed `.id` here it never ran. Re-keying
                // on the value itself is what makes each change register as
                // a fresh view for `.blurReplace` to animate.
                .id(compact)
                .transition(.blurReplace)
                // `.transition` needs an ANIMATED transaction to actually
                // play, not just the insertion/removal `.id` gives it above.
                // The only animation in scope, `.animation(value: parameters)`
                // on the root view, attaches only when `parameters` itself
                // changes — a percent tick (87% -> 86%) changes `compact`
                // but leaves `parameters` equal, so without this, nothing
                // attaches and the swap is instantaneous. Keyed on `compact`
                // specifically, so only an actual value change animates.
                .animation(
                    NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion),
                    value: compact
                )
        }
    }

    /// Budget below the hole is tight: at two (or three+, which shares the
    /// same `twoActivities` size) activities it is `twoActivities.height -
    /// notch.height` = 30pt. Measured ideal height of every activity's
    /// title+detail stacked: 51pt; even titles-only (no detail lines): 38pt.
    /// Both blow the budget — growing the island to fit was rejected (62pt
    /// is the spec value; "ears first, grow down only when crowded" was
    /// chosen over "grow to fit text"), and so was accepting truncation
    /// (silently clipping the state spec §6 says shows the top two is not a
    /// defensible resting state). So only the highest-priority activity's
    /// TITLE (no detail) renders here — both activities stay represented
    /// regardless, each via its own ear (`leadingEar`/`trailingEar`).
    /// `.expanded` has far more room (86pt) and shows every activity in
    /// full. Pinned by `NotchRenderTests`'
    /// `twoActivityDetailRowIdealHeightFitsItsBudget`, which measures this
    /// subtree's own ideal (unclipped) height directly — a rendered/clipped
    /// pixel check can't see content silently truncated by `.clipShape`.
    @ViewBuilder private var detailRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            if controller.state == .expanded {
                ForEach(controller.activities) { activity in
                    detailTitle(activity.title)
                    if let fill = activity.barFill {
                        detailBar(fill)
                    }
                    if let detail = activity.detail {
                        Text(detail)
                            .font(.system(size: 9))
                            .foregroundStyle(contentColor.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            } else if let activity = controller.activities.first {
                detailTitle(activity.title)
                if let fill = activity.barFill {
                    detailBar(fill)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One activity title, keyed and transitioned exactly like `trailingEar`'s
    /// `compact` text above. `.transition` alone only supplies the
    /// insertion/removal `.id(title)` creates; it still needs an ANIMATED
    /// transaction to actually play, which `.animation(value: parameters)`
    /// on the root view does NOT supply for a title change on its own (a
    /// title changing leaves `parameters` — state/activityCount/metrics —
    /// equal, so that root-level animation never attaches). This local
    /// `.animation(value:)` supplies one directly, keyed on the title
    /// itself so only an actual change animates.
    private func detailTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .id(title)
            .transition(.blurReplace)
            .animation(
                NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion),
                value: title
            )
    }

    /// `barFill`'s progress bar, shown directly below its activity's title —
    /// the same slot `detail` occupies when present, each gated by its own
    /// `if let` so an activity with neither contributes no extra height.
    /// Fixed at 4pt tall via the outer `.frame(height:)` regardless of what
    /// `GeometryReader` itself would report as an ideal size — that is what
    /// makes this a small, KNOWN addition to `detailRow`'s ideal-height
    /// measurement in `NotchRenderTests`
    /// (`twoActivityDetailRowIdealHeightFitsItsBudget`), rather than an
    /// unbounded one.
    private func detailBar(_ fill: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(contentColor.opacity(0.22))
                Capsule()
                    .fill(contentColor)
                    .frame(width: geometry.size.width * fill)
            }
        }
        .frame(height: 4)
    }

    #if DEBUG
    /// Test-only seam (see `NotchRenderTestHook` above): lets
    /// `NotchRenderTests` measure `detailRow`'s own ideal (UNCLIPPED)
    /// height in isolation, at the exact width it receives in production
    /// (`islandContent`'s `.frame(width: parameters.width, ...)`). A
    /// pixel-level check against the full, clipped `NotchRootView` cannot
    /// see this: `.clipShape` hides any overflow instead of erroring, which
    /// is exactly how the previous top-alignment fix converted "bleeds
    /// upward into the notch" into "silently truncated downward" without
    /// either automated check catching it. Reachable only via
    /// `@testable import` (never `public`).
    var detailRowForTesting: some View {
        detailRow.frame(width: controller.parameters.width, alignment: .top)
    }
    #endif
}
