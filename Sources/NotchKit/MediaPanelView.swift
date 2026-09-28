import AppKit
import SwiftUI

/// The expanded media card, laid out to match Alcove's structure (from the
/// user's screenshot of the real thing):
///
///   row 1 — artwork · title/artist · visualizer, edge to edge
///   row 2 — full-width scrubber with the times INLINE at its ends
///   row 3 — five controls on their own centred row:
///           shuffle · previous · play/pause · next · repeat
///
/// Flat black card — Alcove's is, and anything else beside the real notch
/// reads as a different object. The play glyph is simply LARGER than its
/// neighbours (no circle chip); shuffle/repeat are real (`send 6`/`send 7`
/// in the adapter) but stateless for now — `MediaPayload` does not yet
/// decode shuffleMode/repeatMode, so they fire without an active highlight.
/// Alcove's fifth icon is screen-mirroring, which has no backing capability
/// here, so repeat takes that slot rather than shipping a dead button.
///
/// Layout budget is hard: `expanded.height - notchRect.height` = 136pt on
/// the measured display (expanded was raised 118 → 140 → 168 to carry this
/// card at Alcove's own proportions, ~342×169 measured from the screenshot).
/// Ideal height of the rows below ≈ 124pt. Pinned by
/// `NotchRenderTests.mediaPanelIdealHeightFitsTheExpandedBudget`.
struct MediaPanelView: View {
    let media: MediaPresentation
    let reduceMotion: Bool
    /// White in production; a solid test colour under `NotchRenderTests` —
    /// threaded through from `NotchRootView.contentColor` so exactly one
    /// place decides it.
    let contentColor: Color
    /// Artwork-derived (`ArtworkAccent`), kept for the compact ear's paused
    /// visualizer bars. The card itself is white-on-black like Alcove's.
    let accent: Color
    /// Pairs the compact ear's 20pt artwork with the 56pt one below into a
    /// single morphing element across expand/collapse. The pair is exclusive
    /// — `NotchRootView.leadingEar` hides its copy at `.expanded` — which is
    /// the precondition that makes `matchedGeometryEffect`'s hero semantics
    /// valid here at all; see the call-site comment there.
    let artworkNamespace: Namespace.ID
    let emit: (NotchIntent) -> Void
    /// Lock-screen mode (spec §7): metadata and progress only. The control
    /// row is dropped rather than shown inert — a button that cannot be
    /// pressed is a lie — and the scrubber keeps ticking but does not take
    /// a drag. Clicks cannot reliably reach a panel above the lock shield
    /// anyway, so the visible surface should promise nothing it can't do.
    let displayOnly: Bool

    /// In-progress scrub position, `nil` when not dragging. While non-nil the
    /// filled bar renders from THIS, 1:1 with the pointer — feedback must be
    /// continuous during the gesture, not delivered at the end — and the
    /// 1Hz position tick's smoothing animation is suspended so the bar never
    /// lags the pointer chasing a stale target.
    ///
    /// Spelled out via the underlying `State<Value>` type rather than the
    /// `@State` attribute: this toolchain's CommandLineTools install has no
    /// `SwiftUIMacros` plugin, so the attribute fails to expand here. Same
    /// workaround as `NotchRootView.previousHeight`.
    private var _dragFraction: State<CGFloat?> = State(initialValue: nil)
    private var dragFraction: CGFloat? {
        get { _dragFraction.wrappedValue }
        nonmutating set { _dragFraction.wrappedValue = newValue }
    }

    init(
        media: MediaPresentation,
        reduceMotion: Bool,
        contentColor: Color,
        accent: Color,
        artworkNamespace: Namespace.ID,
        emit: @escaping (NotchIntent) -> Void,
        displayOnly: Bool = false
    ) {
        self.media = media
        self.reduceMotion = reduceMotion
        self.contentColor = contentColor
        self.accent = accent
        self.artworkNamespace = artworkNamespace
        self.emit = emit
        self.displayOnly = displayOnly
    }

    var body: some View {
        VStack(spacing: 7) {
            headerRow
            scrubRow
            if !displayOnly {
                controlsRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .foregroundStyle(contentColor)
    }

    // MARK: - Row 1: artwork · title/artist · visualizer

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            artwork
                .matchedGeometryEffect(id: NotchRootView.artworkGeometryID, in: artworkNamespace)
                // Track-change crossfade, same keyed-`.id` + local-animation
                // pattern as every other in-place swap in this codebase (the
                // root's `.animation(value: parameters)` never attaches for a
                // title change alone).
                .id(media.title)
                .transition(.blurReplace)
                .animation(NotchAnimation.textAnimation(reduceMotion: reduceMotion), value: media.title)

            VStack(alignment: .leading, spacing: 2) {
                // Typography as a set: rounded family matching the system's
                // own media surfaces; hierarchy from weight + size + opacity
                // together. Tracking is size-specific — semibold rounded at
                // 15pt reads slightly loose at 0.
                Text(media.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .tracking(-0.2)
                    .lineLimit(1)
                    .id(media.title)
                    .transition(.blurReplace)
                    .animation(NotchAnimation.textAnimation(reduceMotion: reduceMotion), value: media.title)

                if let artist = media.artist {
                    Text(artist)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(contentColor.opacity(0.62))
                        .lineLimit(1)
                        .id(artist)
                        .transition(.blurReplace)
                        .animation(NotchAnimation.textAnimation(reduceMotion: reduceMotion), value: artist)
                }
            }

            Spacer(minLength: 8)

            // Alcove parks its equalizer glyph top-right of the card. White
            // like the rest of the card; animated only while actually playing.
            AudioVisualizerBars(
                color: contentColor.opacity(0.85),
                isAnimating: media.isPlaying && !reduceMotion
            )
            .opacity(media.isPlaying ? 1 : 0.35)
        }
    }

    @ViewBuilder private var artwork: some View {
        Group {
            if let data = media.artwork, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(contentColor.opacity(0.18))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 20))
                            .foregroundStyle(contentColor.opacity(0.5))
                    }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // Depth: a soft shadow beneath and a hairline catching light on the
        // edge, so the sleeve reads as an object sitting on the card rather
        // than a flat texture. The placeholder gets the identical treatment
        // so the two states don't jump when artwork arrives.
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
    }

    // MARK: - Row 2: full-width scrubber, times inline at the ends

    private var scrubRow: some View {
        let dragging = dragFraction != nil

        return HStack(spacing: 8) {
            // Fixed-width slots so the bar doesn't resize as digits tick
            // over or the remaining count changes length.
            Text(media.elapsedText)
                .frame(width: 34, alignment: .leading)

            GeometryReader { geometry in
                let fraction = dragFraction.map(Double.init) ?? media.progress
                ZStack(alignment: .leading) {
                    Capsule().fill(contentColor.opacity(0.22))
                    Capsule()
                        // White fill, like Alcove's — the accent stays in the
                        // compact ear where it carries the track's identity.
                        .fill(contentColor)
                        .frame(width: max(0, geometry.size.width * fraction))
                        // Smooths the 1Hz position tick into a continuous
                        // slide — but ONLY while not dragging: during a drag
                        // the fill must track the pointer 1:1, and a 1s
                        // animation would lag it by up to a second.
                        .animation(
                            dragging || reduceMotion ? nil : .linear(duration: 1),
                            value: media.progress
                        )
                }
                // Grab affordance: the bar thickens under the pointer,
                // vertically centred in the 18pt gesture strip. Critically
                // damped — a state change, not a thrown object.
                .frame(height: dragging ? 6 : 3.5)
                .frame(maxHeight: .infinity, alignment: .center)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 1.0),
                    value: dragging
                )
                .contentShape(Rectangle())
                // `.subviews` masks out the added gesture only — the
                // display-only card keeps its bar but takes no drag.
                .highPriorityGesture(
                    scrubGesture(width: geometry.size.width),
                    including: displayOnly ? .subviews : .all
                )
            }
            .frame(height: 18)   // the whole strip is the hit target (~10pt slop rule)

            Text(media.remainingText ?? "")
                .frame(width: 34, alignment: .trailing)
        }
        .font(.system(size: 10, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(contentColor.opacity(0.55))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(media.elapsedText)
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        // `.highPriorityGesture`, not `.gesture`: this sits beneath
        // `NotchRootView`'s canvas-wide `.onTapGesture`, and a
        // `DragGesture(minimumDistance: 0)` starts recognising on the same
        // mouse-down a TapGesture does — the exact ambiguity Apple's docs
        // name `.highPriorityGesture` for. Seeking must never also collapse
        // the panel out from under the gesture that's still running.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard width > 0 else { return }
                dragFraction = min(1, max(0, value.location.x / width))
            }
            .onEnded { value in
                guard width > 0 else { dragFraction = nil; return }
                let fraction = min(1, max(0, value.location.x / width))
                emit(.seek(fraction: fraction))
                // One haptic, on the causal event (the commit) only — never
                // during the drag, never on plain buttons. Over-feedback
                // trains people to ignore all of it.
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                dragFraction = nil
            }
    }

    // MARK: - Row 3: shuffle · previous · play/pause · next · repeat

    /// Five controls spread evenly on their own full-width row like Alcove's,
    /// the play glyph simply larger than its neighbours — hierarchy from
    /// size, no chip behind it. Symmetric: mode toggles at the edges,
    /// transport inside, play in the middle.
    private var controlsRow: some View {
        HStack(spacing: 0) {
            controlButton("shuffle", label: "Shuffle", size: 13, opacity: 0.6, .toggleShuffle)
                .frame(maxWidth: .infinity)
            controlButton("backward.fill", label: "Previous", size: 17, opacity: 0.9, .previous)
                .frame(maxWidth: .infinity)
            playPauseButton
                .frame(maxWidth: .infinity)
            controlButton("forward.fill", label: "Next", size: 17, opacity: 0.9, .next)
                .frame(maxWidth: .infinity)
            controlButton("repeat", label: "Repeat", size: 13, opacity: 0.6, .toggleRepeat)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 30)
    }

    private var playPauseButton: some View {
        let symbol = media.isPlaying ? "pause.fill" : "play.fill"
        return Button {
            emit(.togglePlayPause)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .id(symbol)
                .transition(.blurReplace)
                .animation(NotchAnimation.textAnimation(reduceMotion: reduceMotion), value: symbol)
                .frame(width: 34, height: 30)   // hit slop beyond the glyph
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(media.isPlaying ? "Pause" : "Play")
    }

    private func controlButton(
        _ symbol: String, label: String, size: CGFloat, opacity: Double, _ intent: NotchIntent
    ) -> some View {
        Button {
            emit(intent)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .opacity(opacity)
                .frame(width: 30, height: 30)   // hit slop beyond the glyph
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(label)
    }
}
