import AppKit
import SwiftUI

/// The expanded media card: artwork, title/artist, an accent-tinted scrubber
/// with live drag tracking, and prev/play/next with the play button as the
/// visual focal point. Rendered by `NotchRootView.detailRow` only at
/// `.expanded` size, entirely **below** the notch cutout — never inside
/// `controller.metrics.notchRect`, which has no pixels.
///
/// Layout budget is hard: `expanded.height - notchRect.height` = 108pt on
/// the measured display. Measured ideal height of everything below — title
/// (~18) + artist(~16) + scrub block(~19) + controls(28) + spacings/padding
/// ≈ 97pt against a 108pt budget (`expanded.height` was raised 118 → 140
/// during this redesign — the compact states must never grow, but expanded
/// is the deliberate full-panel state and its container serves its panel).
/// Pinned by `NotchRenderTests.mediaPanelIdealHeightFitsTheExpandedBudget`.
struct MediaPanelView: View {
    let media: MediaPresentation
    let reduceMotion: Bool
    /// White in production; a solid test colour under `NotchRenderTests` —
    /// threaded through from `NotchRootView.contentColor` so exactly one
    /// place decides it.
    let contentColor: Color
    /// Dominant-ish colour pulled from the artwork (`ArtworkAccent`), owned
    /// and cached by `NotchRootView` so the compact ear's progress sliver and
    /// this card always agree. Equals `contentColor` under the render-test
    /// hook, so pixel classification stays two-colour there.
    let accent: Color
    /// Pairs the compact ear's 20pt artwork with the 60pt one below into a
    /// single morphing element across expand/collapse. The pair is exclusive
    /// — `NotchRootView.leadingEar` hides its copy at `.expanded` — which is
    /// the precondition that makes `matchedGeometryEffect`'s hero semantics
    /// valid here at all; see the call-site comment there.
    let artworkNamespace: Namespace.ID
    let emit: (NotchIntent) -> Void

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
        emit: @escaping (NotchIntent) -> Void
    ) {
        self.media = media
        self.reduceMotion = reduceMotion
        self.contentColor = contentColor
        self.accent = accent
        self.artworkNamespace = artworkNamespace
        self.emit = emit
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            artwork
                .matchedGeometryEffect(id: NotchRootView.artworkGeometryID, in: artworkNamespace)
                // Track-change crossfade, same keyed-`.id` + local-animation
                // pattern as every other in-place swap in this codebase (the
                // root's `.animation(value: parameters)` never attaches for a
                // title change alone).
                .id(media.title)
                .transition(.blurReplace)
                .animation(NotchAnimation.textAnimation(reduceMotion: reduceMotion), value: media.title)

            VStack(alignment: .leading, spacing: 1) {
                // Typography as a set, not defaults: rounded family matching
                // the system's own media surfaces; hierarchy from weight +
                // size + opacity together. Title tracking pulled in a touch —
                // tracking is size-specific, and semibold rounded at 15pt
                // reads slightly loose at 0.
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
                        .foregroundStyle(contentColor.opacity(0.68))
                        .lineLimit(1)
                        .id(artist)
                        .transition(.blurReplace)
                        .animation(NotchAnimation.textAnimation(reduceMotion: reduceMotion), value: artist)
                }

                scrubBlock
                    .padding(.top, 4)

                controls
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 6)
        .foregroundStyle(contentColor)
    }

    // MARK: - Artwork

    @ViewBuilder private var artwork: some View {
        Group {
            if let data = media.artwork, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(contentColor.opacity(0.18))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 20))
                            .foregroundStyle(contentColor.opacity(0.5))
                    }
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        // Depth: a soft shadow beneath and a hairline catching light on the
        // edge, so the sleeve reads as an object sitting on the card rather
        // than a flat texture. The placeholder gets the identical treatment
        // so the two states don't jump when artwork arrives.
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
    }

    // MARK: - Scrubber

    /// Bar + timestamps as ONE gesture surface (~19pt tall), so the hit
    /// target meets the ~10pt-slop rule without the bar itself growing past
    /// its 3.5pt visual weight — a 3.5pt-tall drag target on its own is
    /// nearly unhittable.
    private var scrubBlock: some View {
        let dragging = dragFraction != nil

        return VStack(spacing: 3) {
            GeometryReader { geometry in
                let fraction = dragFraction.map(Double.init) ?? media.progress
                ZStack(alignment: .leading) {
                    Capsule().fill(contentColor.opacity(0.18))
                    Capsule()
                        .fill(accent)
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
                .contentShape(Rectangle())
                .highPriorityGesture(scrubGesture(width: geometry.size.width))
            }
            // Grab affordance: the bar thickens under the pointer. Critically
            // damped — this is a state change, not a thrown object.
            .frame(height: dragging ? 6 : 3.5)
            .animation(
                reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 1.0),
                value: dragging
            )

            HStack {
                Text(media.elapsedText)
                Spacer()
                if let remaining = media.remainingText { Text(remaining) }
            }
            .font(.system(size: 10, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(contentColor.opacity(0.55))
        }
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

    // MARK: - Controls

    /// Play/pause is the primary action and looks like it: a 28pt filled
    /// circle behind a 20pt glyph, flanked by 15pt skips at reduced opacity.
    /// Grouped tight (14pt) and centred under the text column.
    private var controls: some View {
        HStack(spacing: 14) {
            skipButton("backward.fill", label: "Previous", .previous)
            playPauseButton
            skipButton("forward.fill", label: "Next", .next)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
    }

    private var playPauseButton: some View {
        let symbol = media.isPlaying ? "pause.fill" : "play.fill"
        return Button {
            emit(.togglePlayPause)
        } label: {
            ZStack {
                Circle().fill(contentColor.opacity(0.14))
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .id(symbol)
                    .transition(.blurReplace)
                    .animation(NotchAnimation.textAnimation(reduceMotion: reduceMotion), value: symbol)
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(PressableButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(media.isPlaying ? "Pause" : "Play")
    }

    private func skipButton(_ symbol: String, label: String, _ intent: NotchIntent) -> some View {
        Button {
            emit(intent)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .opacity(0.85)
                .frame(width: 24, height: 24)   // hit slop beyond the glyph
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(label)
    }
}
