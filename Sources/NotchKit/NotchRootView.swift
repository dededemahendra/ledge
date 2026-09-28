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

    /// Hero-pair id for the compact-ear ↔ panel artwork morph.
    static let artworkGeometryID = "media-artwork"

    /// See `previousHeight` above for why this is the spelled-out property
    /// wrapper type rather than the attribute. `Namespace` is a
    /// `DynamicProperty` like `State`, installed by reflection the same way.
    private var _artworkNamespace: Namespace = Namespace()
    private var artworkNamespace: Namespace.ID { _artworkNamespace.wrappedValue }

    /// Accent derived from the current artwork (`ArtworkAccent`), cached here
    /// so both surfaces would agree, and recomputed only when the artwork
    /// actually changes (see the `.onChange` in `body`) — never per frame.
    /// As of 2026-09-28 nothing draws with it any more (the compact ear's
    /// bars went white at the user's request); kept wired, cheap, in case
    /// a tint comes back.
    private var _accent: State<Color> = State(initialValue: ArtworkAccent.fallback)
    private var accent: Color {
        get { _accent.wrappedValue }
        nonmutating set { _accent.wrappedValue = newValue }
    }

    /// Under `NotchRenderTests` the accent collapses to `contentColor`, so
    /// pixel classification there stays strictly two-colour.
    private var effectiveAccent: Color {
        #if DEBUG
        if NotchRenderTestHook.contentColor != nil { return contentColor }
        #endif
        return accent
    }

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
        let expanding = parameters.height == previousHeight
            ? parameters.width > previousWidth
            : parameters.height > previousHeight

        let expanded = controller.state == .expanded
        let showEffects = expanded && !visualEffectsSuppressed

        ZStack(alignment: .top) {
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
        // Flatten before shadowing so the island casts ONE silhouette shadow
        // rather than every layer casting its own.
        .compositingGroup()
        .shadow(
            color: .black.opacity(showEffects ? 0.5 : 0),
            radius: 16, y: 6
        )
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
        // Accent recomputes only when the artwork itself changes — a 1×1
        // draw, once per track, never per frame. See `ArtworkAccent`.
        .onChange(of: controller.media?.artwork) { _, artwork in
            accent = ArtworkAccent.accent(from: artwork)
        }
        .onAppear {
            accent = ArtworkAccent.accent(from: controller.media?.artwork)
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
        if controller.isDeviceLeading, let media = controller.media, controller.state != .expanded {
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
        } else if let activity = controller.activities.first, let symbol = activity.symbolName {
            // `variableValue` lights the symbol's own level layers (speaker
            // waves, sun rays) from `barFill` — the macOS-OSD way to show a
            // level in a glyph. Non-HUD symbols carry no `barFill` (nil) and
            // no variable layers, so this is inert for them.
            //
            // Keyed and animated exactly like `trailingEar`'s `compact` text and
            // `detailTitle`'s title below: `AppModel` gives every HUD record the
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
                .id(symbol)
                .transition(.blurReplace)
                .animation(
                    NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion),
                    value: symbol
                )
            if controller.hasLabelledEars {
                // The reference HUD's ear: glyph, then a one-word label
                // ("Sound"/"Display"; "Charging"/"On battery" for power),
                // leading-aligned from the island's outer edge — not
                // centred in the ear, which would drift the pair inward as
                // the label's width changes. Only at `NotchMetrics.hud`
                // size, which every labelled activity gets: the 38pt ear
                // of the plain one-activity island has no room for a word.
                //
                // The glyph gets a fixed 18pt slot so the label's x is
                // stable across symbols of different widths (the slashed
                // speaker is narrower than the waved one) and across
                // `variableValue` lighting more or fewer waves.
                HStack(spacing: 6) {
                    glyph.frame(width: 18)
                    hudLabel(activity.earLabel)
                }
                .padding(.leading, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Belt and braces: a label that ever outgrows the ear must
                // clip at the ear's edge (into the hole, where there are no
                // pixels anyway), never truncate with an ellipsis or shove
                // the glyph.
                .clipped()
            } else {
                glyph
            }
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

    /// The HUD ear's word. 12pt semibold measured off the reference HUD
    /// ("Sound" ≈ 35pt, "Display" ≈ 41pt wide), so glyph slot + label sit
    /// inside the 90pt ear with room to spare. Keyed and animated like every
    /// other in-place text swap in this file: `AppModel` gives every HUD
    /// record the same id, so Sound -> Display is an update to the SAME
    /// view and needs the value-keyed `.id` to register as an insertion for
    /// `.blurReplace`, plus its own animated transaction. `fixedSize` keeps
    /// SwiftUI from ever answering a tight proposal with an ellipsis — the
    /// caller's `.clipped()` is the overflow policy.
    private func hudLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .id(title)
            .transition(.blurReplace)
            .animation(
                NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion),
                value: title
            )
    }

    /// `AppModel` inserts the sticky media activity with this id
    /// (`ActivityKind.media.rawValue` — a string, not the enum itself, since
    /// `NotchKit` has no dependency on `ActivityKit`; see `Package.swift`).
    /// Same cross-module id convention already relied on above and in
    /// `trailingEar`/`detailTitle` below (`AppModel` gives every HUD/power
    /// record a fixed id too — "hud", "power" — so a value changing there is
    /// an in-place update, not an insertion).
    private static let mediaActivityID = "media"

    @ViewBuilder
    private func mediaArtwork(_ media: MediaPresentation) -> some View {
        Group {
            if let data = media.artwork, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(contentColor.opacity(0.25))
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
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
        if controller.isDeviceLeading, controller.media != nil, controller.state != .expanded,
           let activity = controller.activities.first {
            // The device's icon in place of the visualizer bars
            // for the blip's lifetime — see `leadingEar`'s first branch.
            deviceIcon(activity)
        } else if controller.isHUDLeading, let fill = controller.activities.first?.barFill {
            // A live HUD owns both ears (see `NotchController.isHUDLeading`):
            // the level bar beats the overflow pip, which would otherwise
            // replace it the moment music was playing behind a volume press.
            trailingBar(fill)
        } else if controller.overflowCount > 0 {
            Text("+\(controller.overflowCount)")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
        } else if let activity = controller.activities.first {
            if let fill = activity.barFill {
                trailingBar(fill)
            } else if let compact = activity.compactText {
                // In the labelled layout the value sits where the HUD's bar
                // ends — 10pt in from the island's edge, at the label's own
                // 12pt semibold — so "Charging …… 95%" reads as one line
                // with its ends aligned to the HUD's. Centred at the
                // plain one-activity size, as before.
                let labelled = controller.hasLabelledEars
                Text(compact)
                    .font(.system(size: labelled ? 12 : 11, weight: labelled ? .semibold : .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: labelled ? .trailing : .center)
                    .padding(.trailing, labelled ? 10 : 0)
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
            } else if activity.id == Self.mediaActivityID,
                      let media = controller.media,
                      controller.state != .expanded {
                // Compact now-playing, spec §6's original "trailing ear:
                // waveform": the visualizer bars, breathing while music
                // plays and held still, dimmed, while paused. ONE element
                // with two states (2026-09-28): a paused track used to swap
                // in an accent-coloured progress sliver instead, which read
                // as a stray dash — position belongs to the panel's
                // scrubber, where it comes with times. Same paused
                // treatment the expanded card gives its own bars. The
                // brief's notch-edge progress ring stays impossible: it
                // would draw across the cutout. At `.expanded` the panel
                // takes over and this yields to the fallback below.
                // White, like the card's own bars — not the artwork accent
                // (user's call, 2026-09-28): the island is a flat black
                // slab with white content everywhere else, and a coloured
                // ear read as a different object. Same 0.85/paused-dim
                // pair the card uses.
                AudioVisualizerBars(
                    color: contentColor.opacity(media.isPlaying ? 0.85 : 0.3),
                    isAnimating: media.isPlaying && !controller.reduceMotion
                )
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

    /// `barFill`'s progress bar in the trailing ear — same visual language as
    /// `detailBar` below, sized for the HUD ear (`NotchMetrics.hudEarWidth`).
    /// Measured off the reference HUD at its 90pt ear: a 68pt track ending
    /// 10pt short of the island's outer edge, so 12pt of lead-in from the
    /// hole and 10pt of trailing inset. 5pt tall — a hair thicker than
    /// `detailBar`'s 4pt, because this one IS the reading, not an
    /// annotation under a title. The track's 22% white matches the
    /// reference's measured ~23%.
    /// The fill ANIMATES between values: volume/brightness keys step in
    /// sixteenths, and an unanimated bar jumps those steps — a short
    /// critically-damped spring turns them into one continuous slide, the
    /// same "state change, not thrown object" tuning as the scrubber's
    /// thickening. Local `.animation(value: fill)`, because the root's
    /// `.animation(value: parameters)` never attaches for a fill change
    /// alone (same reason every text swap above carries its own).
    private func trailingBar(_ fill: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(contentColor.opacity(0.22))
                Capsule()
                    .fill(contentColor)
                    .frame(width: geometry.size.width * fill)
                    .animation(
                        controller.reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 1.0),
                        value: fill
                    )
            }
        }
        .frame(height: 5)
        .padding(.leading, 12)
        .padding(.trailing, 10)
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
    @ViewBuilder private var detailRow: some View {
        if controller.state == .expanded, let media = controller.media {
            MediaPanelView(
                media: media,
                reduceMotion: controller.reduceMotion,
                contentColor: contentColor,
                accent: effectiveAccent,
                artworkNamespace: artworkNamespace,
                emit: { controller.emit($0) },
                displayOnly: controller.isLocked
            )
            // `.leading` keeps the panel flush at the island's leading edge
            // like every other piece of island content; `maxHeight: .infinity`
            // fills the budget frame so the card floats vertically CENTRED in
            // it (~97pt of content in a 108pt budget) instead of hugging the
            // notch with all the slack pooled at the bottom. Overflow safety
            // is unchanged: the call-site budget frame is still top-aligned,
            // so anything past the budget clips downward, never into the ears.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
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
                    // Same slide-not-jump tuning as `trailingBar` above.
                    .animation(
                        controller.reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 1.0),
                        value: fill
                    )
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
