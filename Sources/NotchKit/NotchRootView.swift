import SwiftUI

/// Motion constants. The original 0.35/0.72 pair was chosen by comparing
/// candidates against "which would you still tolerate on the fiftieth
/// repeat" (spec §5); the expand spring was later retuned to 0.4/0.8 at the
/// user's explicit request during the media-player redesign — a touch wider
/// and calmer, with roughly 1.5% overshoot instead of 3.8%. Collapse stays
/// deliberately duller: closing should not draw attention.
public enum NotchAnimation {
    public static let expandResponse: Double = 0.4
    public static let expandDamping: Double = 0.8
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

    /// How long after a collapse to `.hidden` begins the island is gone —
    /// the collapse spring within a pixel of the notch and the root's late
    /// fade (`hideAnimation`) done. The presenter keeps the window up this
    /// long; ordering it out on the first frame cut every retract short
    /// (user report 2026-09-29: "unhover is not smooth").
    public static let hideSettle: Double = 0.5

    /// The root's opacity on the way to `.hidden`: full while the shape
    /// retracts into the notch, then a short fade over the last few
    /// points. Nothing on the way in — the island arrives by growing.
    public static func hideAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : .easeOut(duration: 0.2).delay(0.15)
    }

    public static func animation(expanding: Bool, reduceMotion: Bool) -> Animation {
        if reduceMotion { return reduced }
        return expanding ? expand : collapse
    }

    /// The blip spring (2026-09-29, user's call: "magnification when
    /// interactions"): a blip is something thrown INTO the island — a
    /// volume press, the charger going in — and that is exactly where
    /// Apple's guidance allows overshoot. ~8% in width; height cannot
    /// overshoot, every blip is notch-height. The panel's calm `expand`
    /// stays as tuned: opening a card is not a throw.
    public static let popResponse: Double = 0.42
    public static let popDamping: Double = 0.62
    public static let pop = Animation.spring(response: popResponse, dampingFraction: popDamping)

    /// `fromHidden`: the island was the bare notch a moment ago — the case
    /// that gets `pop`. Every other growth gets `expand`, every shrink
    /// `collapse`.
    public static func animation(expanding: Bool, fromHidden: Bool, reduceMotion: Bool) -> Animation {
        if reduceMotion { return reduced }
        if expanding && fromHidden { return pop }
        return expanding ? expand : collapse
    }

    /// Whether a change of size is an arrival: growth out of what a hidden
    /// island draws (2026-10-21). On a real notch `retracted` is the notch,
    /// as `collapsed` was before; on a pill it is the point, so the hover
    /// pill opening into the card is not mistaken for an arrival.
    public static func isArrival(from previous: CGSize, retracted: NotchShapeParameters) -> Bool {
        previous.width <= retracted.width && previous.height <= retracted.height
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

    /// Which spring a transition gets: the confident one when the island
    /// GROWS, the dull one when it shrinks. By area, not height: height
    /// alone called peek (179×38) -> activity (255×32) a collapse because
    /// it is 6pt shorter, and could not tell hidden -> activity (equal
    /// height) from a no-op at all. Area is monotone in what the eye sees
    /// — more island or less — for every pair of resting states.
    nonisolated public static func isExpanding(from: CGSize, to: CGSize) -> Bool {
        to.width * to.height > from.width * from.height
    }
}

/// The island's LIVE size — the spring's interpolated value, not the
/// target — published to the content subtree by `AnimatedIslandParameters`
/// so the ears are laid out where the shape actually is on each frame.
/// `nil` outside the island (tests that render subtrees on their own).
private struct LiveIslandParametersKey: EnvironmentKey {
    static let defaultValue: NotchShapeParameters? = nil
}

extension EnvironmentValues {
    var liveIslandParameters: NotchShapeParameters? {
        get { self[LiveIslandParametersKey.self] }
        set { self[LiveIslandParametersKey.self] = newValue }
    }
}

/// Same trick as `ContentFade`: a modifier whose `animatableData` IS the
/// island's parameters, so SwiftUI hands its `body` the interpolated value
/// on every frame of the morph, and the environment carries it down to
/// `IslandEarsRow`. A view body reading `controller.parameters` only ever
/// sees the target — which is why, before this (2026-09-29), the ears
/// jumped to their final x on the first frame of every expand/collapse and
/// were then revealed by the moving clip mask rather than travelling with
/// the shape.
struct AnimatedIslandParameters: ViewModifier, Animatable {
    var parameters: NotchShapeParameters

    nonisolated var animatableData: NotchShapeParameters.AnimatableData {
        get { parameters.animatableData }
        set { parameters.animatableData = newValue }
    }

    func body(content: Content) -> some View {
        content.environment(\.liveIslandParameters, parameters)
    }
}

/// A bump on every value change (2026-09-29): the view scales to 120% and
/// springs back — iOS's volume HUD does this on each press, and it is
/// what makes a held key feel like a stream of presses rather than a
/// number quietly ticking. Keyed on `trigger`; nothing happens at rest.
/// Reduce Motion: no scaling at all.
struct ValueBump<Trigger: Equatable & Sendable>: ViewModifier {
    let trigger: Trigger
    let enabled: Bool

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, scale in
            view.scaleEffect(enabled ? scale : 1)
        } keyframes: { _ in
            // 10%, down from 20% (2026-09-29): a tick beside the rolling
            // digits, not a jump.
            SpringKeyframe(1.1, duration: 0.12, spring: .snappy)
            SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
        }
    }
}

/// The cover flips in edge-on when the track changes (the reference app's
/// "artwork flip", 2026-09-29): a jump to -90° about the vertical axis,
/// then a bouncy spring back to flat, keyed on the title. Nothing at rest.
struct FlipOnChange<Trigger: Equatable & Sendable>: ViewModifier {
    let trigger: Trigger
    let enabled: Bool

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, angle in
            view.rotation3DEffect(.degrees(enabled ? angle : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        } keyframes: { _ in
            LinearKeyframe(-90, duration: 0.001)
            SpringKeyframe(0, duration: 0.6, spring: .bouncy)
        }
    }
}

/// The ears row, laid out from the LIVE island width (see
/// `AnimatedIslandParameters`), with both ears keyed on the identity of
/// what they show: when one blip replaces another at the same island size
/// (volume expiring back to the artwork, headphones appearing beside it),
/// the shape does not change, so nothing else would animate — the ears
/// used to swap instantly. Keying the containers on `key` turns every such
/// swap into a `.blurReplace` crossfade, and `.animation(value: key)`
/// supplies the transaction the transition needs.
private struct IslandEarsRow<Leading: View, Trailing: View>: View {
    // Spelled-out `Environment`, like every `State` in this file (no macro
    // plugin on this toolchain).
    private var _live: Environment<NotchShapeParameters?> = Environment(\.liveIslandParameters)
    private var live: NotchShapeParameters? { _live.wrappedValue }

    let target: NotchShapeParameters
    let notch: CGRect
    let key: String
    let animation: Animation
    let reduceMotion: Bool
    /// Where a wider island keeps its ears (2026-10-21): each side's
    /// content in a slot this wide at the island's OUTER end, rather than
    /// centred in an ear that grew with the caption under it. `nil`
    /// centres in the whole ear, which is right wherever the ear is sized
    /// to its content (a Focus's name, a pair of bud readings).
    let edgeSlot: CGFloat?
    let leading: Leading
    let trailing: Trailing

    init(
        target: NotchShapeParameters, notch: CGRect, key: String, animation: Animation, reduceMotion: Bool,
        edgeSlot: CGFloat? = nil,
        @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing
    ) {
        self.target = target
        self.notch = notch
        self.key = key
        self.animation = animation
        self.reduceMotion = reduceMotion
        self.edgeSlot = edgeSlot
        self.leading = leading()
        self.trailing = trailing()
    }

    /// New ear content POPS in — scaling up from 60% on the blip spring
    /// while it sharpens — and merely dissolves on the way out. The
    /// insertion carries its own spring so the pop happens even when the
    /// surrounding transaction is a crossfade (one blip replacing another
    /// at the same size). Reduce Motion: a plain crossfade.
    /// `towardsHole`: +1 for the leading ear (the hole is to its right),
    /// -1 for the trailing (hole to its left). New content starts 10pt
    /// towards the hole — as if sliding out from under the notch, the
    /// Dynamic Island's own gesture — while scaling up from 60% and
    /// sharpening, all on the blip spring. Removal just dissolves.
    private func earTransition(towardsHole: CGFloat) -> AnyTransition {
        guard !reduceMotion else { return AnyTransition(BlurReplaceTransition(configuration: .downUp)) }
        let emerge = OffsetTransition(CGSize(width: 10 * towardsHole, height: 0))
            .combined(with: ScaleTransition(0.6))
            .combined(with: BlurReplaceTransition(configuration: .downUp))
            .animation(NotchAnimation.pop)
        return .asymmetric(
            insertion: AnyTransition(emerge),
            removal: AnyTransition(BlurReplaceTransition(configuration: .downUp))
        )
    }

    var body: some View {
        let width = live?.width ?? target.width
        let ear = max(0, (width - notch.width) / 2)
        let slot = min(ear, edgeSlot ?? ear)
        HStack(spacing: 0) {
            ZStack { leading }
                .id(key)
                .transition(earTransition(towardsHole: 1))
                .frame(width: slot, height: notch.height)
                .frame(width: ear, alignment: .leading)
            Color.clear.frame(width: notch.width, height: notch.height)   // the hole
            ZStack { trailing }
                .id(key)
                .transition(earTransition(towardsHole: -1))
                .frame(width: slot, height: notch.height)
                .frame(width: ear, alignment: .trailing)
        }
        .animation(animation, value: key)
        .frame(width: width, height: notch.height)
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

    /// Blur at the fully-faded end of the window. Content resolves out of a
    /// soft haze as it fades in (and dissolves back into one on the way
    /// out) instead of a bare opacity ramp — the reference HUD's glyph,
    /// label and bar arrive this way, and it hides the frame where text is
    /// legible but the ear is not yet wide enough to hold it. Exactly 0 at
    /// rest, so a resting render is pixel-identical to an unblurred one
    /// (`NotchRenderTests` classify resting frames only).
    static let blurRadius: CGFloat = 6

    func body(content: Content) -> some View {
        let opacity = metrics.contentOpacity(progress: progress)
        content
            .opacity(opacity)
            .blur(radius: (1 - opacity) * Self.blurRadius)
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

    /// Spec §5/§14: hover opens the panel; a tap PINS it open (or unpins
    /// it) so it survives the cursor leaving — see
    /// `NotchController.isPinnedOpen`. Defaults to a no-op so every
    /// existing call site (including `NotchRenderTests`, which constructs
    /// this view directly with no presenter around) keeps compiling
    /// unchanged; `NotchPresenter` supplies its own `toggle()` so the
    /// window resyncs — mutating the controller alone would leave the
    /// window ordered out, the same bug `toggle()` was written to fix for
    /// the menu bar's "Toggle Panel".
    private let onTap: () -> Void

    /// Mouse held down on a clickable island (`controller.linkURL`): the
    /// content dips like a button's, on press-down, not release.
    private var _pressed: State<Bool> = State(initialValue: false)
    private var pressed: Bool {
        get { _pressed.wrappedValue }
        nonmutating set { _pressed.wrappedValue = newValue }
    }

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
    /// The last tab item, held while Reduce Motion fades the tab out in place.
    private var _heldTab: State<NotchController.ActivityDisplay?> = State(initialValue: nil)
    private var heldTab: NotchController.ActivityDisplay? {
        get { _heldTab.wrappedValue }
        nonmutating set { _heldTab.wrappedValue = newValue }
    }
    /// Counts tabs landing (nil to an item), the tab's own pulse trigger.
    private var _tabLanded: State<Int> = State(initialValue: 0)
    private var tabLanded: Int {
        get { _tabLanded.wrappedValue }
        nonmutating set { _tabLanded.wrappedValue = newValue }
    }

    private var _previousWidth: State<CGFloat>
    private var previousWidth: CGFloat {
        get { _previousWidth.wrappedValue }
        nonmutating set { _previousWidth.wrappedValue = newValue }
    }

    /// Hero-pair id for the compact-ear ↔ panel artwork morph.
    static let artworkGeometryID = "media-artwork"
    /// The crests fly the same way between the ears and the open card
    /// (2026-10-01, user's call: "like music player").
    static let homeCrestGeometryID = "live-home-crest"
    static let awayCrestGeometryID = "live-away-crest"

    /// See `previousHeight` above for why this is the spelled-out property
    /// wrapper type rather than the attribute. `Namespace` is a
    /// `DynamicProperty` like `State`, installed by reflection the same way.
    private var _artworkNamespace: Namespace = Namespace()
    private var artworkNamespace: Namespace.ID { _artworkNamespace.wrappedValue }

    /// The purely-visual expanded-card effects (hairline border, drop
    /// shadow) are suppressed while the render-test hook is active: a
    /// half-outside stroke or a soft shadow ring would pollute the
    /// silhouette-match test's fill classification, and neither is what
    /// those tests exist to pin (geometry and content placement are).
    private var visualEffectsSuppressed: Bool {
        #if DEBUG
        NotchRenderTestHook.contentColor != nil
        #else
        false
        #endif
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
        let expanding = NotchAnimation.isExpanding(
            from: CGSize(width: previousWidth, height: previousHeight),
            to: CGSize(width: parameters.width, height: parameters.height)
        )
        let fromHidden = NotchAnimation.isArrival(
            from: CGSize(width: previousWidth, height: previousHeight),
            retracted: controller.metrics.retracted
        )

        let expanded = controller.state == .expanded
        let showEffects = expanded && !visualEffectsSuppressed

        let islandLayer = ZStack(alignment: .top) {
            shape
                // Flat, fully opaque black in every state — the real Alcove
                // card is a flat slab, and it has to be: the island sits
                // flush against the actual notch, and any translucency or
                // artwork tint on the surface breaks the illusion that
                // island and bezel are one object. Depth comes from the
                // hairline + shadow below, not from the fill.
                .fill(.black)
                // `.overlay`'s default alignment is `.center`: a `Shape` fill
                // occupies its ENTIRE proposed canvas (640x320), not the
                // island's own drawn extent, so uncentred content here would
                // render 100+pt below the island, over the desktop, in every
                // state but the tallest. `.top` is what makes it land where
                // the island actually is.
                .overlay(alignment: .top) {
                    islandContent(parameters: parameters)
                        // Down by the pill's float (2026-10-21), so the
                        // content sits inside the shape; 0 on a notch.
                        .padding(.top, parameters.topInset)
                        // Press feedback where a click does something
                        // (`NotchController.linkURL`): the same dip as the
                        // panel's buttons, so a clickable blip feels like one.
                        .scaleEffect(pressed && controller.linkURL != nil && !controller.reduceMotion ? 0.96 : 1, anchor: .top)
                        .opacity(pressed && controller.linkURL != nil ? PressableButtonStyle.pressedOpacity : 1)
                        .animation(.spring(response: 0.2, dampingFraction: 1.0), value: pressed)
                        // Interpolated size for the ears — see
                        // `AnimatedIslandParameters`. Driven by the same
                        // `.animation(value: parameters)` below as the shape.
                        .modifier(AnimatedIslandParameters(parameters: parameters))
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
                // Hairline separating the floating card from the desktop
                // behind it. Plain `.stroke` (centred on the path, half a
                // point outside) rather than `strokeBorder` — `NotchShape` is
                // not `InsettableShape`, and at 9% white the half-pixel
                // outside the silhouette is invisible against the shadow.
                .overlay {
                    shape.stroke(
                        Color.white.opacity(showEffects ? 0.09 : 0),
                        lineWidth: 1
                    )
                }
        }
        // The press dip belongs to the island's own area, never the tab's.
        .contentShape(shape)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true } }
                .onEnded { _ in pressed = false }
        )
        // The blip pulse (`NotchController.blipPulse`): the whole island
        // swells ~5% from its top edge — the notch stays welded — and
        // springs back, for a blip that lands with no shape change to
        // announce it. Keyframed, so the resting frame is exactly 1.0.
        .keyframeAnimator(initialValue: 1.0, trigger: controller.blipPulse) { [reduceMotion = controller.reduceMotion] view, scale in
            view.scaleEffect(reduceMotion ? 1 : scale, anchor: .top)
        } keyframes: { _ in
            SpringKeyframe(1.07, duration: 0.14, spring: .snappy)
            SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
        }
        // Flatten before shadowing so the island casts ONE silhouette shadow
        // rather than every layer casting its own.
        .compositingGroup()
        .shadow(
            color: .black.opacity(showEffects ? 0.5 : 0),
            radius: 16, y: 6
        )

        // The tab sits outside the island's pulse, with its own shadow.
        return ZStack(alignment: .top) {
            islandLayer
            tabLayer(island: parameters, showEffects: showEffects)
                .compositingGroup()
                .shadow(color: .black.opacity(showEffects ? 0.5 : 0), radius: 16, y: 6)
        }
        .frame(
            width: NotchMetrics.canvasSize.width,
            height: NotchMetrics.canvasSize.height,
            alignment: .top
        )
        // Spec §5: `hover ──▶ expanded`; a tap pins/unpins, and
        // `.leftMouseDown`-outside/Escape (both in `NotchPresenter`) unpin.
        // AppKit's own
        // hit-testing (`NotchHostingView.hitTest`, driven by
        // `interactivePath`) already restricts which points ever reach this
        // view, so no extra region check is needed here.
        .onTapGesture { onTap() }
        // The link pointer over a clickable island, the arrow elsewhere.
        .pointerStyle(controller.linkURL != nil ? .link : .default)
        .animation(
            NotchAnimation.animation(expanding: expanding, fromHidden: fromHidden, reduceMotion: controller.reduceMotion),
            value: parameters
        )
        // The tab buds and merges on the island's own springs.
        .animation(
            NotchAnimation.animation(expanding: expanding, fromHidden: fromHidden, reduceMotion: controller.reduceMotion),
            value: controller.tabParameters
        )
        // Animated on the way OUT only (see `NotchAnimation.hideAnimation`):
        // this sits after the shape's `.animation(value: parameters)`, so
        // without its own it snapped to 0 on the first frame of a collapse.
        .opacity(controller.isVisible ? 1 : 0)
        .animation(controller.isVisible ? nil : NotchAnimation.hideAnimation(reduceMotion: controller.reduceMotion),
                   value: controller.isVisible)
        .allowsHitTesting(controller.isVisible)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ledge notch island")
        .onChange(of: controller.tab) { _, newValue in
            if let newValue { heldTab = newValue }
        }
        .onChange(of: controller.tab?.id) { old, new in
            if old == nil, new != nil { tabLanded += 1 }
        }
        .task(id: controller.tab == nil) {
            // Reduce Motion: drop the held item once its fade has played.
            guard controller.tab == nil, heldTab != nil else { return }
            try? await Task.sleep(for: .milliseconds(300))
            if controller.tab == nil { heldTab = nil }
        }
        .onChange(of: parameters) { _, newValue in
            // Recorded AFTER this transition's spring was already chosen
            // above, so it becomes the "before" height/width for whichever
            // transition comes next.
            previousHeight = newValue.height
            previousWidth = newValue.width
        }
    }

    /// The tab beside the island (2026-10-23): a second shape in the same
    /// material, its item's short form centred in it. Its tap is its own
    /// (`NotchController.tapTab`) and never reaches the island's.
    @ViewBuilder
    private func tabLayer(island: NotchShapeParameters, showEffects: Bool) -> some View {
        let reduceMotion = controller.reduceMotion
        // Reduce Motion: no bud. The shape stays at full size and fades in place.
        let shownTab = controller.tab ?? (reduceMotion ? heldTab : nil)
        let tab = reduceMotion && shownTab != nil
            ? controller.metrics.tab(beside: island)
            : controller.tabParameters
        let tabShape = NotchTabShape(island: island, tab: tab)
        let centerX = NotchMetrics.canvasSize.width / 2 + island.width / 2 + tab.gap + tab.width / 2
        let centerY = tab.topInset + tab.height / 2
        let pulseAnchor = UnitPoint(
            x: centerX / NotchMetrics.canvasSize.width, y: tab.topInset / NotchMetrics.canvasSize.height
        )
        ZStack(alignment: .top) {
            tabShape.fill(.black)
            if let display = shownTab {
                TabGlyph(
                    display: display, controller: controller, contentColor: contentColor,
                    tintColor: { tintColor(for: $0) }
                )
                .id(display.id)
                .transition(.blurReplace)
                .animation(NotchAnimation.textAnimation(reduceMotion: reduceMotion), value: display.id)
                .frame(width: max(tab.width, 1), height: tab.height)
                .position(x: centerX, y: centerY)
                .clipShape(tabShape)
            }
            tabShape.stroke(Color.white.opacity(showEffects ? 0.09 : 0), lineWidth: 1)
        }
        .opacity(reduceMotion && !controller.isTabShowing ? 0 : 1)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : nil, value: controller.isTabShowing)
        .contentShape(tabShape)
        .allowsHitTesting(controller.isTabShowing)
        .onTapGesture { controller.tapTab() }
        .keyframeAnimator(initialValue: 1.0, trigger: tabLanded) { view, scale in
            view.scaleEffect(reduceMotion ? 1 : scale, anchor: pulseAnchor)
        } keyframes: { _ in
            SpringKeyframe(1.07, duration: 0.14, spring: .snappy)
            SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
        }
    }

    /// Content lives in the ears and below the hole. Nothing may be drawn
    /// inside `controller.metrics.notchRect` — there are no pixels there.
    @ViewBuilder
    private func islandContent(parameters: NotchShapeParameters) -> some View {
        let notch = controller.metrics.notchRect
        let ear = controller.metrics.earWidth(forIslandWidth: parameters.width)
        // The row of ears. Above an open card on a pill it is the card's
        // top band, 12 pt while the ears are empty (2026-10-21); everywhere
        // else, and always on a MacBook, it is the notch's height.
        let rowHeight = controller.state == .expanded
            ? controller.metrics.cardTopBand(earsShowing: controller.earsShowAboveCard)
            : notch.height
        let row = CGRect(x: notch.minX, y: notch.minY, width: notch.width, height: rowHeight)

        #if DEBUG
        let _ = assertContentStaysInsideIslandAndClearOfNotch(parameters: parameters, notch: row, ear: ear)
        #endif

        VStack(spacing: 0) {
            IslandEarsRow(
                target: parameters,
                notch: row,
                key: earContentKey,
                animation: NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion),
                reduceMotion: controller.reduceMotion,
                // A long caption widens the island under the ears; they
                // keep a one-activity ear's 38 pt at the ends, as the
                // Dynamic Island keeps its own (2026-10-21). On a MacBook
                // they drifted up to 43 pt in towards the notch. A longer
                // trailing word widens them to fit (2026-10-22).
                edgeSlot: controller.captionText == nil ? nil : controller.captionedEarSlot,
                leading: { leadingEar },
                trailing: { trailingEar }
            )
            // Gated on the TARGET height, so the card is inserted on the
            // first frame of an expand and removed on the first frame of a
            // collapse — and `.transition(.blurReplace)` then fades and
            // sharpens it over the spring (the root's `.animation(value:
            // parameters)` is the transaction). Before this the card was
            // simply sliced by the moving clip mask on the way out.
            if let caption = controller.captionText {
                // Song-change or meeting caption (see `NotchController.
                // caption`), or the previewed next event on hover
                // (`NotchController.upcoming`): one line under the hole,
                // fading in over the island's spring and out again when it
                // goes. Keyed on the text so a second change inside the
                // window crossfades in place.
                captionRow(caption)
                    .frame(width: parameters.width, height: parameters.height - row.height)
                    .id(caption)
                    .transition(BlurReplaceTransition(configuration: .downUp).combined(with: OffsetTransition(CGSize(width: 0, height: 6))))
            } else if parameters.height > row.height + 8 {
                detailRow
                    // Look only on the lock screen (2026-10-21): no row or
                    // button on the card takes a press, so none dips.
                    .allowsHitTesting(!controller.isLocked)
                    // Mode changes slide the way the swipe went, on the
                    // expand spring (2026-09-30, user's call); the island's
                    // clip keeps the outgoing panel inside.
                    .animation(
                        // Calm (user's call, 2026-09-30: "less, but keep it
                        // smooth"): critically damped, a third of a second.
                        controller.reduceMotion ? NotchAnimation.reduced : .spring(response: 0.32, dampingFraction: 1.0),
                        value: controller.panel
                    )
                    .frame(maxWidth: .infinity)
                    // `alignment: .top`, not the default `.center`: content
                    // taller than its budget must overflow DOWNWARD, where
                    // the `.clipShape` below trims it invisibly — never
                    // upward into the ear row and the notch rect. Caught by
                    // `NotchRenderTests`.
                    .frame(height: parameters.height - row.height, alignment: .top)
                    // Target width, not live: the card's text must not
                    // reflow mid-morph.
                    .frame(width: parameters.width)
                    .transition(.blurReplace)
            }
        }
        .foregroundStyle(contentColor)
    }

    private func tintColor(for tint: NotchController.ActivityDisplay.Tint?) -> Color? {
        #if DEBUG
        if NotchRenderTestHook.contentColor != nil { return nil }
        #endif
        switch tint {
        case .positive?:          return Color(nsColor: .systemGreen)
        case .warning?:           return Color(nsColor: .systemRed)
        case .system(let name)?:  return SystemTint.color(named: name).map { Color(nsColor: $0) }
        case let .color(red, green, blue)?: return Color(red: red, green: green, blue: blue)
        case nil:                 return nil
        }
    }

    /// A reminder's ring in its list's colour, grey for a list without one
    /// (2026-10-21); `nil`, white, for an event's calendar glyph and under
    /// the render test hook.
    private func ringColor(for upcoming: UpcomingEvent) -> Color? {
        guard upcoming.kind == .reminder else { return nil }
        return tintColor(for: upcoming.tint.map { .color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .system("gray"))
    }

    /// An overdue reminder's time, in the calendar card's red, as Reminders
    /// marks one (2026-10-21). Never under the render test hook.
    private var pastDueColor: Color? {
        #if DEBUG
        if NotchRenderTestHook.contentColor != nil { return nil }
        #endif
        return .calendarRed
    }

    /// "Title · Artist": the title carries the weight, the artist sits back.
    /// Left-aligned like the reference, under the artwork's ear. One line,
    /// tail-truncated; the caption row is 26pt, the text 11pt. A previewed
    /// reminder that is overdue has its time in red. Split at the LAST
    /// separator, so a title with " · " in it stays whole (2026-10-21); a
    /// GitHub blip's caption splits at the FIRST (2026-10-22).
    private func captionRow(_ caption: String) -> some View {
        // Bold up to the last separator, so a title with one in it stays bold (2026-10-21); a GitHub blip's caption splits at the first, its PR's title bold and the rest dim (2026-10-22).
        let split = controller.isGitHubLeading ? caption.range(of: " · ") : caption.range(of: " · ", options: .backwards)
        let title = split.map { String(caption[..<$0.lowerBound]) } ?? caption
        let artist = split.map { String(caption[$0.upperBound...]) } ?? ""
        let overdue = controller.isPreviewingUpcoming && controller.upcoming?.isPastDue == true
        let titleText = Text(title).font(.system(size: 11, weight: .semibold))
        let separatorText = Text(artist.isEmpty ? "" : " · ")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(contentColor.opacity(0.6))
        let artistText = Text(artist)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle((overdue ? pastDueColor : nil) ?? contentColor.opacity(0.6))
        return HStack(spacing: 0) {
            Text("\(titleText)\(separatorText)\(artistText)")
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 3)
    }

    /// What the ears are currently ABOUT — the leading activity and whether
    /// media sits behind it — not what they show pixel for pixel (a value
    /// ticking 87% -> 86% keeps its own inner `.id`). Changing this is what
    /// crossfades both ears; see `IslandEarsRow`. Deliberately excludes
    /// `state == .expanded`: the artwork's hand-off to the panel at expand
    /// is a `matchedGeometryEffect` hero, and re-keying the ear container
    /// at that moment would fade a ghost of the artwork in place beside the
    /// flying copy.
    private var earContentKey: String {
        let first = controller.activities.first
        let hint = controller.skipHint.map { $0 == .next ? "n" : "p" } ?? "-"
        return "\(NotchController.earSlot(forActivity: first?.id))|\(controller.media == nil ? 0 : 1)|\(hint)|\(controller.isPreviewingUpcoming ? "u" : "-")"
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
        if controller.isPreviewingUpcoming, let upcoming = controller.upcoming {
            // The next event or reminder on hover (`NotchController.
            // upcoming`): its glyph, same size and weight as a blip's, a
            // reminder's ring in its list's colour.
            Image(systemName: upcoming.symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ringColor(for: upcoming) ?? contentColor)
        } else if let hint = controller.skipHint, controller.media != nil, controller.state != .expanded {
            // Swipe-to-skip feedback (`NotchController.skipHint`): the skip
            // glyph takes the artwork's place for a beat. The ear key
            // includes it, so this is a crossfade in and back out.
            Image(systemName: hint == .next ? "forward.fill" : "backward.fill")
                .font(.system(size: 13, weight: .semibold))
        } else if controller.isDeviceLeading, let media = controller.media, controller.state != .expanded {
            // Device blip over music: the artwork stays put and the device
            // goes to the trailing ear (see `NotchController.isDeviceLeading`
            // and `deviceIcon` below). Not at `.expanded`, where the panel
            // owns the artwork and this slot must yield it (same hero-pair
            // rule as the media branch further down).
            mediaArtwork(media)
                .id(media.title)
                .transition(.blurReplace)
                .animation(
                    NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion),
                    value: media.title
                )
        } else if let score = controller.score {
            // The open card owns the pair, exactly as it owns the artwork
            // when music is playing: this slot yields it so the crest can
            // fly down into the card instead of being drawn twice.
            // `Color.clear`, not `EmptyView`, keeps the ear's width.
            if controller.state == .expanded, controller.panel == .liveActivity {
                Color.clear
            } else {
                scoreSide(score.home, crest: controller.homeCrestImage, crestLeading: true,
                          geometryID: Self.homeCrestGeometryID)
            }
        } else if let activity = controller.activities.first, activity.id == NotchController.callActivityID {
            // A call (2026-10-22): the app's own icon, a red crossed-out mic
            // when muted, a red hang-up when it has ended. Its card carries
            // both itself, so the ear gives way while it is open.
            if controller.state == .expanded, controller.panel == .call {
                Color.clear
            } else {
                callGlyph(activity)
            }
        } else if let activity = controller.activities.first, activity.id == NotchController.githubActivityID {
            // A GitHub blip (2026-10-22): who did it, or what happened.
            // Before the product-render branch, which would draw the
            // avatar square and unbadged.
            GitHubBlipGlyph(avatar: controller.githubAvatarImage, symbol: activity.symbolName ?? "circle.fill",
                            color: tintColor(for: activity.tint) ?? Color(nsColor: .systemGray))
                .id(activity.title)
                .transition(.blurReplace)
                .animation(NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion), value: activity.title)
        } else if let activity = controller.activities.first,
                  activity.id == NotchController.agentActivityID
                    || activity.id == NotchController.agentWaitingActivityID
                    || activity.id == NotchController.agentRunActivityID {
            // An agent item (2026-10-23): Claude's orange asterisk, turning
            // while one works, the count of sessions it stands for.
            // The open Agents card says it all, so the ear gives way.
            if controller.state == .expanded, controller.panel == .agents {
                Color.clear
            } else {
                AgentGlyph(color: AgentColors.orange,
                           turning: activity.id == NotchController.agentRunActivityID,
                           count: activity.badge, reduceMotion: controller.reduceMotion)
            }
        } else if let activity = controller.activities.first,
           let data = activity.artwork, let image = NSImage(data: data) {
            // A product render (AirPods et al.) in place of the glyph. 24pt
            // tall in a 32pt ear, width from the render's own aspect (the
            // system's are ~1.4:1, so ~34pt — inside the 38pt ear of the
            // one-activity island with a little air). No clip shape: the
            // renders carry their own transparency, and a rounded box
            // around a pair of earbuds would look like a sticker.
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 24)
                .id(activity.title)
                .transition(.blurReplace)
                .animation(
                    NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion),
                    value: activity.title
                )
        } else if let activity = controller.activities.first, activity.id == NotchController.githubRunActivityID {
            // GitHub checks or a run going (2026-10-22): an amber arc
            // turning, the count of what runs on it.
            // A segment per check of the leading PR (2026-10-22); a run
            // outside a PR has none and keeps the turning arc.
            if let segments = activity.segments, !segments.isEmpty {
                CheckRing(segments: segments, reduceMotion: controller.reduceMotion)
            } else {
                GitHubRunRing(color: tintColor(for: activity.tint) ?? contentColor, count: activity.badge,
                              reduceMotion: controller.reduceMotion)
            }
        } else if let activity = controller.activities.first, activity.id == NotchController.timerActivityID,
                  let fill = activity.barFill {
            // A running countdown (2026-09-29): a ring emptying clockwise
            // from the top, the Dynamic Island's own timer glyph. Paused
            // and stopwatch records carry no `barFill` and fall through to
            // their symbols below.
            TimerRing(fill: fill, color: tintColor(for: activity.tint) ?? contentColor,
                      reduceMotion: controller.reduceMotion)
        } else if let activity = controller.activities.first, let symbol = activity.symbolName,
                  symbol.hasPrefix("battery."), let level = activity.barFill {
            // A battery the way the phone draws one (2026-10-06, user's
            // call): the cell filled to the charge in the state's own
            // colour — green on the charger, red when low — with a dim
            // rim, and a white bolt across it while it is charging. The
            // flat symbol tinted end to end read as a green outline, not
            // as a battery with something in it.
            batteryGlyph(level: level, fill: tintColor(for: activity.tint) ?? contentColor,
                         bolt: symbol.contains(".bolt"))
        } else if let activity = controller.activities.first, let symbol = activity.symbolName {
            // `variableValue` lights the symbol's own level layers (speaker
            // waves, sun rays) from `barFill` — the macOS-OSD way to show a
            // level in a glyph. Non-HUD symbols carry no `barFill` (nil) and
            // no variable layers, so this is inert for them.
            //
            // Keyed and animated exactly like `trailingEar`'s `compact` text:
            // `AppModel` gives every HUD record the
            // same id ("hud"), so a symbol changing (now only the mute slash
            // toggling — the level symbol itself is constant) is an in-place
            // update to the SAME view, not an insertion — `.transition` only
            // plays on insertion/removal, so it needs this value-keyed `.id` to
            // register as one, and a local `.animation(value:)` to get an
            // actually-animated transaction (the root view's `.animation(value:
            // parameters)` does not attach for a symbol change alone, since
            // `parameters` — state/activityCount/metrics — stays equal).
            let glyph = Image(systemName: symbol, variableValue: activity.barFill)
                .font(.system(size: 13, weight: .medium))
                // Colour only where the system's own indicator colours
                // itself (green charging, red low). Never under the render
                // test hook, whose classifier expects one content colour.
                .foregroundStyle(tintColor(for: activity.tint) ?? contentColor)
                // A symbol swap (mute on/off, bolt -> plug) MORPHS with SF
                // Symbols' replace effect. The glyph does NOT bounce on
                // every press any more (2026-09-29, user's call — with the
                // number bumping beside it, two motions per key press was
                // "too much"): the waves lighting up with the level is the
                // press; the number's roll is the motion.
                .contentTransition(.symbolEffect(.replace.downUp))
                .animation(
                    NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion),
                    value: symbol
                )
            glyph
        } else if controller.activities.first?.id == Self.mediaActivityID, let media = controller.media {
            // Task 8: media's artwork takes the leading ear once it is the
            // TOPMOST activity — guarded on `.first?.id`, not just
            // `controller.media != nil`, because `controller.media` stays
            // set (sticky) even while something higher-priority (e.g. power,
            // which — like media — has no `symbolName` of its own) currently
            // occupies the ear. Without that guard this branch would show
            // media's artwork here while `trailingEar` below (which also
            // only ever reads `.first`) showed the OTHER activity's value —
            // two ears telling two different stories.
            if controller.state == .expanded {
                // The panel owns the artwork at `.expanded`: this slot yields
                // it entirely, which is what turns the pair below into a true
                // insert/remove hand-off — the precondition
                // `matchedGeometryEffect`'s hero semantics require. Earlier
                // code dropped the effect precisely because both copies used
                // to stay visible together; hiding this one is what made it
                // valid. `Color.clear`, not `EmptyView`: an `EmptyView` here
                // collapses the ear's width reservation and re-centres the
                // whole ears row into the notch — the exact trap documented
                // on `trailingEar`'s own fallback branch.
                Color.clear
            } else {
                mediaArtwork(media)
                    .matchedGeometryEffect(id: Self.artworkGeometryID, in: artworkNamespace)
                    .id(media.title)
                    .transition(.blurReplace)
                    .animation(
                        NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion),
                        value: media.title
                    )
            }
        } else if controller.activityCount > 0 {
            Circle().fill(contentColor.opacity(0.28)).padding(6)
        }
    }

    /// The trailing ear's value — "95%", "50%", "+2". One helper for HUD,
    /// power and device so the three read identically.
    ///
    /// `AppModel` gives every record of a kind the same `id` ("power",
    /// "hud"), so `compact` changing (87% -> 86%) is an in-place update to
    /// the SAME `Text`, not an insertion — `.transition` only ever plays on
    /// insertion/removal, so it needs the value-keyed `.id` to register as
    /// one, and its own animated transaction: the root's `.animation(value:
    /// parameters)` never attaches for a value tick alone.
    /// Several readings side by side — left bud, right bud, case
    /// (2026-09-30): each its glyph and figure at 10 pt, the island
    /// widened to fit by `NotchController.leadingEarWidth`.
    private func readings(_ parts: [NotchController.ActivityDisplay.Part]) -> some View {
        HStack(spacing: 7) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                HStack(spacing: 2) {
                    if let symbol = part.symbolName {
                        Image(systemName: symbol)
                            .font(.system(size: 10, weight: .medium))
                    }
                    Text(part.text)
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                }
            }
        }
        .fixedSize()
    }

    /// Whether the leading activity has something of its own for the
    /// trailing ear — a figure, readings, a value, or music's output glyph.
    private var leadingActivityFillsTrailingEar: Bool {
        guard let first = controller.activities.first else { return false }
        if first.score != nil || first.compactText != nil { return true }
        if let parts = first.parts, !parts.isEmpty { return true }
        return first.id == Self.mediaActivityID && controller.media != nil && controller.state != .expanded
    }

    /// A call's leading glyph (2026-10-22). Red for muted and ended — the
    /// system's own red, like a low battery — else the app's icon, decoded
    /// once by the controller; a green mic if it has none.
    @ViewBuilder
    private func callGlyph(_ activity: NotchController.ActivityDisplay) -> some View {
        let symbol = activity.symbolName ?? "mic.fill"
        Group {
            if symbol == "mic.slash.fill" || symbol == "phone.down.fill" {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tintColor(for: .warning) ?? contentColor)
            } else if let icon = controller.callIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tintColor(for: .positive) ?? contentColor)
            }
        }
        .id(symbol)
        .transition(.blurReplace)
        .animation(NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion), value: symbol)
    }

    /// The charging battery: the cell filled to its level, the rim held
    /// back, and the bolt laid over it in the island's own white. Sized
    /// from the ear's glyph size so it sits with the other blips.
    /// Where the cell's inside begins and how far it runs, as fractions
    /// of the symbol's width. Measured off the rendered symbol rather
    /// than guessed: `battery.100percent` ignores a variable value and
    /// always draws itself full, so the fill is clipped here instead
    /// (checked 2026-10-06, green from 0.156 to 0.733).
    private static let batteryCellStart: CGFloat = 0.156
    private static let batteryCellSpan: CGFloat = 0.578
    /// Bigger than the ear's other glyphs (2026-10-06, user's call): a
    /// battery is wide and low, so at the 13 pt the rest use it sat well
    /// under the figure beside it. At 16 its cell stands as tall as the
    /// digits do. The bolt follows the same size.
    private static let batterySize: CGFloat = 16
    private static let batteryBoltRatio: CGFloat = 0.46

    private func batteryGlyph(level: Double, fill: Color, bolt: Bool) -> some View {
        let level = min(1, max(0, level))
        let glyph = Font.system(size: Self.batterySize, weight: .medium)
        return Image(systemName: "battery.100percent")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.clear, contentColor.opacity(0.45))
            .font(glyph)
            .overlay {
                GeometryReader { proxy in
                    Image(systemName: "battery.100percent")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(fill, .clear)
                        .font(glyph)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: proxy.size.width * (Self.batteryCellStart + Self.batteryCellSpan * level))
                        }
                }
            }
            .overlay {
                if bolt {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: Self.batterySize * Self.batteryBoltRatio, weight: .black))
                        .foregroundStyle(contentColor)
                }
            }
            .animation(NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion), value: level)
    }

    /// One side of a scoreline in an ear (2026-10-01): the crest outward,
    /// the figure toward the notch, as the phone's island draws a match
    /// around its camera. The figure rolls between values like every
    /// other number on the island.
    private func scoreSide(_ side: NotchController.ActivityDisplay.Score.Side, crest: NSImage?,
                           crestLeading: Bool, geometryID: String) -> some View {
        let badge = Group {
            if let crest {
                Image(nsImage: crest).resizable().interpolation(.high)
            } else {
                Circle().fill(contentColor.opacity(0.22))
            }
        }
        .frame(width: 20, height: 20)
        .matchedGeometryEffect(id: geometryID, in: artworkNamespace)
        let figure = Text(side.value)
            .font(.system(size: 15, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(contentColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .contentTransition(.numericText())
            .animation(NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion), value: side.value)
        return HStack(spacing: 5) {
            if crestLeading { badge; figure } else { figure; badge }
        }
    }

    private func compactValue(_ compact: String, bump: Bool = true, color: Color? = nil) -> some View {
        Text(compact)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(color ?? contentColor)
            .lineLimit(1)
            // Never truncate: the ear (38pt) holds the widest label ("100%",
            // 32pt), but the numeric transition below re-measures the text
            // and, at a 3x backing scale, rounds it a third of a point short
            // — enough for a "100…" ellipsis (seen in headless renders,
            // 2026-09-29; 2x is unaffected). Sizing to the ideal width
            // sidesteps the rounding at every scale.
            .fixedSize(horizontal: true, vertical: false)
            // Digits ROLL between values (Apple's numeric text transition)
            // instead of crossfading — 50% -> 55% reads as a dial turning.
            // No `.id`: the Text must stay the same view for that.
            .contentTransition(.numericText())
            .animation(
                NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion),
                value: compact
            )
            .modifier(ValueBump(trigger: compact, enabled: bump && !controller.reduceMotion))
    }

    /// A device's icon for an ear: the system's product render when there
    /// is one (24pt tall, own transparency, no sticker box), else its SF
    /// Symbol at the ear glyph size. Keyed on the title so one device
    /// replacing another inside the 3s window crossfades.
    @ViewBuilder
    private func deviceIcon(_ activity: NotchController.ActivityDisplay) -> some View {
        Group {
            if let data = activity.artwork, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: 24)
            } else if let symbol = activity.symbolName {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
            } else {
                Color.clear
            }
        }
        .id(activity.title)
        .transition(.blurReplace)
        .animation(
            NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion),
            value: activity.title
        )
    }

    /// `AppModel` inserts the sticky media activity with this id
    /// (`ActivityKind.media.rawValue` — a string, not the enum itself, since
    /// `NotchKit` has no dependency on `ActivityKit`; see `Package.swift`).
    /// Same cross-module id convention already relied on above and in
    /// `trailingEar` below (`AppModel` gives every HUD/power
    /// record a fixed id too — "hud", "power" — so a value changing there is
    /// an in-place update, not an insertion).
    private static let mediaActivityID = "media"

    @ViewBuilder
    private func mediaArtwork(_ media: MediaPresentation) -> some View {
        SpinningArtwork(isPlaying: media.isPlaying, reduceMotion: controller.reduceMotion) {
            Group {
                if let image = controller.mediaArtworkImage {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Circle().fill(contentColor.opacity(0.25))
                }
            }
            .frame(width: 20, height: 20)
        }
        .modifier(FlipOnChange(trigger: media.title, enabled: !controller.reduceMotion))
    }

    /// The current output's glyph (headphones, laptop, AirPods…) for the
    /// trailing ear while music leads — in place of the equalizer bars
    /// (user's call, 2026-09-29). Bright while playing, dim while paused,
    /// so the ear still says which. Crossfades when the route changes.
    private var currentOutputGlyph: some View {
        let symbol = controller.outputs.first(where: \.isCurrent)?.symbolName ?? "speaker.wave.2"
        let playing = controller.media?.isPlaying ?? false
        return Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .opacity(playing ? 0.9 : 0.35)
            .id(symbol)
            .transition(.blurReplace)
            .animation(NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion), value: symbol)
            .animation(NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion), value: playing)
    }

    /// At one activity the island is notch-height and `detailRow` is gated
    /// off, so this ear is the ONLY place a value can appear — without
    /// something here the island widens, shows a glyph, and says nothing.
    ///
    /// Task 8 design change: `barFill` wins over `compactText` when both are
    /// present (true today only for HUD's volume/brightness activities —
    /// power/device/notification/media carry no `barFill`). Before this, a
    /// single HUD activity computed and tested a `barFill` that never
    /// rendered anywhere — `detailRow`'s own bar is gated off at exactly this
    /// size, the same dead-value shape that already cost two Critical
    /// defects in this codebase's history. A bar reads a level faster than
    /// three digits at a glance, so volume/brightness now show glyph + bar;
    /// battery keeps glyph + `87%`, having no `barFill` to prefer.
    @ViewBuilder private var trailingEar: some View {
        if controller.isPreviewingUpcoming, let upcoming = controller.upcoming {
            // The next event's countdown — "42m", "2h 10m", "Now" — red
            // once a reminder is overdue.
            compactValue(upcoming.compactText, color: upcoming.isPastDue ? pastDueColor : nil)
        } else if controller.isDeviceLeading, controller.media != nil, controller.state != .expanded,
           let activity = controller.activities.first {
            // The device's icon in place of the visualizer bars
            // for the blip's lifetime — see `leadingEar`'s first branch.
            deviceIcon(activity)
        } else if controller.isHUDLeading, let compact = controller.activities.first?.compactText {
            // A live HUD owns both ears (see `NotchController.isHUDLeading`):
            // its percentage beats the overflow pip, which would otherwise
            // replace it the moment music was playing behind a volume press.
            compactValue(compact)
        } else if controller.overflowCount > 0, !leadingActivityFillsTrailingEar {
            // The "+N" pip only where the leading activity leaves the ear
            // empty (2026-10-01): a Clock timer's clock or a Live
            // Activity's pill over music and charging must not give way
            // to a count of what is queued behind them.
            Text("+\(controller.overflowCount)")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
        } else if let activity = controller.activities.first {
            if let score = controller.score {
                if controller.state == .expanded, controller.panel == .liveActivity {
                    Color.clear
                } else {
                    scoreSide(score.away, crest: controller.awayCrestImage, crestLeading: false,
                              geometryID: Self.awayCrestGeometryID)
                }
            } else if let parts = activity.parts, !parts.isEmpty {
                readings(parts)
            } else if activity.id == NotchController.callActivityID, controller.state == .expanded,
                      controller.panel == .call {
                // The call card's own clock is the one that shows (2026-10-22).
                Color.clear
            } else if (activity.id == NotchController.agentActivityID
                        || activity.id == NotchController.agentWaitingActivityID
                        || activity.id == NotchController.agentRunActivityID),
                      controller.state == .expanded, controller.panel == .agents {
                // The Agents card carries it (2026-10-23).
                Color.clear
            } else if let compact = activity.compactText {
                // A ticking clock must not bump every second; its digits
                // still roll.
                // Only the Clock's timer colours its digits (orange end to
                // end, as on the phone); every other tinted record — the
                // charging battery, say — keeps its figure white.
                // …and the GitHub running item's clock, amber (2026-10-22).
                let isTicking = activity.id == NotchController.timerActivityID
                    || activity.id == NotchController.githubRunActivityID
                    || activity.id == NotchController.callActivityID
                    || activity.id == NotchController.agentRunActivityID
                // …and a GitHub blip's word, in its event's colour (2026-10-22).
                // …and an agent blip's or waiting item's word, in its record's tint (2026-10-23).
                let isGitHub = activity.id == NotchController.githubActivityID
                    || activity.id == NotchController.agentActivityID
                    || activity.id == NotchController.agentWaitingActivityID
                compactValue(compact, bump: !isTicking, color: (isTicking || isGitHub) ? tintColor(for: activity.tint) : nil)
            } else if activity.id == Self.mediaActivityID,
                      controller.media != nil,
                      controller.state != .expanded {
                // Compact now-playing: the current output's glyph, bright
                // while playing and dim while paused (2026-09-29 — it
                // replaced the equalizer bars at the user's request; the
                // route says more than decorative bars did). At `.expanded`
                // the panel takes over and this yields to the fallback below.
                currentOutputGlyph
            } else {
                // Not decorative — load-bearing. An activity with neither
                // `barFill` nor `compactText` (exactly media's shape: title +
                // detail only) would otherwise make this WHOLE branch
                // evaluate to `EmptyView`. SwiftUI's `EmptyView` collapses to
                // zero size even under an explicit `.frame(width:)` — proven
                // by rendering it here: with a bare `EmptyView` in this slot,
                // the trailing ear's `.frame(width: ear, height:
                // notch.height)` at `islandContent`'s call site stopped
                // reserving `ear`'s width entirely, so the whole ears row
                // measured `ear` narrower than `parameters.width` and got
                // RE-CENTRED within it — shifting the LEADING ear's content
                // sideways into the notch. `Color.clear` is a real view (not
                // `EmptyView`), so it keeps claiming its `ear`-wide slot while
                // drawing nothing.
                Color.clear
            }
        }
    }

    /// Reachable only at `.expanded` (2026-09-29): the two-slot "grow down
    /// when crowded" layout is gone — every activity kind owns the
    /// notch-height island alone while it is live, and whatever is queued
    /// behind it waits (or shows as the `+N` pip). Below the hole there is
    /// now exactly one thing: the panel.
    /// Task 8: `.expanded` shows the rich media panel instead of the generic
    /// per-activity list whenever media exists — deliberately unconditional
    /// on which activity currently leads (unlike the ears above): a click
    /// is always a deliberate action, and the panel's buttons/scrubber are
    /// the only way to control playback, so a transient HUD blip (1.5s TTL)
    /// that happens to still be live must not steal a screen with no
    /// controls on it in place of one that has them. HUD's own preemption
    /// stays fully visible via the ears, which render regardless of state
    /// (spec §6: "ears keep glyphs" at Expanded too).
    ///
    /// `matchedGeometryEffect` pairs the ear's 20pt artwork with the panel's
    /// 56pt one (id `Self.artworkGeometryID`), so expanding morphs one sleeve
    /// between the two slots instead of crossfading two unrelated images.
    /// This was previously dropped — correctly, at the time — because both
    /// copies stayed visible together at `.expanded`, and pairing two
    /// persistently-visible views makes the non-source adopt the source's
    /// frame outright. The redesign resolved that precondition instead of
    /// fighting it: `leadingEar` now yields its artwork slot entirely at
    /// `.expanded` (see its media branch), so the pair really is a transient
    /// insert/remove hand-off, which is the case hero semantics are for.
    /// The panels slide the way the swipe went: the new mode comes in from
    /// the side the finger moved toward, the old one leaves the other way,
    /// both softening as they go. Reduce Motion: a plain crossfade.
    private var panelTransition: AnyTransition {
        guard !controller.reduceMotion else { return .opacity }
        let sign: CGFloat = controller.lastSwipe == .next ? 1 : -1
        let slide: CGFloat = 22   // a nudge in the swipe's direction, not a page flying past
        return .asymmetric(
            insertion: AnyTransition(OffsetTransition(CGSize(width: slide * sign, height: 0))
                .combined(with: BlurReplaceTransition(configuration: .downUp))),
            removal: AnyTransition(OffsetTransition(CGSize(width: -slide * sign, height: 0))
                .combined(with: BlurReplaceTransition(configuration: .downUp)))
        )
    }

    @ViewBuilder private var detailRow: some View {
        if controller.state == .expanded, controller.panel == .liveActivity, let score = controller.liveActivityDisplay?.score {
            ScorePanelView(
                score: score, homeCrest: controller.homeCrestImage, awayCrest: controller.awayCrestImage,
                contentColor: contentColor, crestNamespace: artworkNamespace
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .id("live-activity")
            .transition(panelTransition)
        } else if controller.state == .expanded, controller.panel == .liveActivity, controller.hasCard,
                  let activity = controller.liveActivityDisplay, !activity.lines.isEmpty {
            // Not a match: what the card says, line by line, the first
            // line carrying the weight (2026-10-01).
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(activity.lines.prefix(4).enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.system(size: index == 0 ? 13 : 11, weight: index == 0 ? .semibold : .regular))
                        .foregroundStyle(contentColor.opacity(index == 0 ? 1 : 0.6))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .id("live-activity")
            .transition(panelTransition)
        } else if controller.state == .expanded, controller.panel == .calendar, let data = controller.calendarMode {
            // The calendar mode (2026-09-30).
            CalendarPanelView(
                data: data, contentColor: contentColor,
                reduceMotion: controller.reduceMotion, emit: { controller.emit($0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id("calendar")
            .transition(panelTransition)
        } else if controller.state == .expanded, controller.panel == .github, let data = controller.githubPanel {
            // The GitHub panel (2026-10-22).
            GitHubPanelView(
                data: data, contentColor: contentColor,
                reduceMotion: controller.reduceMotion, emit: { controller.emit($0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id("github")
            .transition(panelTransition)
        } else if controller.state == .expanded, controller.panel == .agents, let data = controller.agentPanel {
            // The Agents card (2026-10-23).
            AgentPanelView(
                data: data, contentColor: contentColor,
                reduceMotion: controller.reduceMotion, emit: { controller.emit($0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id("agents")
            .transition(panelTransition)
        } else if controller.state == .expanded, controller.panel == .call, let data = controller.callPanel {
            // The call card (2026-10-22).
            CallPanelView(
                data: data, contentColor: contentColor,
                reduceMotion: controller.reduceMotion, emit: { controller.emit($0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id("call")
            .transition(panelTransition)
        } else if controller.state == .expanded, let media = controller.media {
            MediaPanelView(
                media: media,
                reduceMotion: controller.reduceMotion,
                contentColor: contentColor,
                artworkNamespace: artworkNamespace,
                emit: { controller.emit($0) },
                displayOnly: controller.isLocked,
                outputs: controller.outputs,
                artworkImage: controller.mediaArtworkImage,
                outputPickerOpen: controller.isOutputPickerOpen,
                toggleOutputs: { controller.setOutputPicker(open: !controller.isOutputPickerOpen) }
            )
            // `.leading` keeps the panel flush at the island's leading edge
            // like every other piece of island content; `maxHeight: .infinity`
            // fills the budget frame so the card floats vertically CENTRED in
            // it (~97pt of content in a 108pt budget) instead of hugging the
            // notch with all the slack pooled at the bottom. Overflow safety
            // is unchanged: the call-site budget frame is still top-aligned,
            // so anything past the budget clips downward, never into the ears.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .id("media")
            .transition(panelTransition)
        } else {
            // Unreachable in practice since 2026-09-29: `.expanded` is only
            // ever the now-playing card (`NotchController.click()` needs
            // media, and the card's departure unpins). The pre-card
            // title-and-bar list that lived here is gone with it. A real
            // view, not `EmptyView`, for the same frame-collapse reason as
            // `trailingEar`'s fallback.
            Color.clear
        }
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
