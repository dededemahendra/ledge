import SwiftUI

/// The expanded media panel: 60pt artwork, title, artist, a drag-to-seek
/// scrub bar with elapsed/remaining time, and previous/play-pause/next
/// controls. Rendered by `NotchRootView.detailRow` only at `.expanded` size,
/// entirely **below** the notch cutout — never inside `controller.metrics
/// .notchRect`, which has no pixels.
///
/// No `matchedGeometryEffect` here — see the doc comment on
/// `NotchRootView`'s call site for why one was deliberately not added.
struct MediaPanelView: View {
    let media: MediaPresentation
    let reduceMotion: Bool
    /// White in production; a solid test colour under `NotchRenderTests` —
    /// threaded through from `NotchRootView.contentColor` rather than reading
    /// `NotchRenderTestHook` a second time, so there is exactly one place
    /// that decides it.
    let contentColor: Color
    let emit: (NotchIntent) -> Void

    var body: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                // Keyed and animated exactly like `NotchRootView.detailTitle`:
                // `.transition` alone only supplies the insertion/removal
                // `.id(_:)` creates; it still needs an animated transaction,
                // which nothing above this view provides for a `media` change
                // while already `.expanded` (the root's `.animation(value:
                // parameters)` does not attach — `parameters` stays equal).
                Text(media.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .id(media.title)
                    .transition(.blurReplace)
                    .animation(NotchAnimation.textAnimation(reduceMotion: reduceMotion), value: media.title)

                if let artist = media.artist {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(contentColor.opacity(0.6))
                        .lineLimit(1)
                        .id(artist)
                        .transition(.blurReplace)
                        .animation(NotchAnimation.textAnimation(reduceMotion: reduceMotion), value: artist)
                }

                scrubber

                HStack(spacing: 22) {
                    button("backward.fill", label: "Previous", .previous)
                    playPauseButton
                    button("forward.fill", label: "Next", .next)
                }
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .foregroundStyle(contentColor)
    }

    @ViewBuilder private var artwork: some View {
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

    private var scrubber: some View {
        VStack(spacing: 2) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(contentColor.opacity(0.22))
                    Capsule()
                        .fill(contentColor)
                        .frame(width: geometry.size.width * media.progress)
                        // Smooths the once-a-second position tick into a
                        // continuous slide instead of a visible per-second
                        // jump. Matches the 1Hz tick cadence exactly, so it
                        // never has to catch up or overshoot between ticks.
                        .animation(reduceMotion ? nil : .linear(duration: 1), value: media.progress)
                }
                .contentShape(Rectangle())
                // `.highPriorityGesture`, not `.gesture`: this view sits
                // beneath `NotchRootView`'s canvas-wide `.onTapGesture`
                // (click anywhere on the island to expand/collapse). A plain
                // `.gesture` here would normally still win by SwiftUI's
                // nested-view precedence (the same reason the buttons below
                // need no special handling), but a `DragGesture(minimumDistance:
                // 0)` starts recognising on the same touch-down a TapGesture
                // does, which is exactly the ambiguous case Apple's own docs
                // call out `.highPriorityGesture` for. This makes the scrub
                // bar's own drag/tap unambiguously win — seeking must never
                // also collapse the panel out from under the gesture that's
                // still running. See the task report for the full analysis.
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0).onEnded { value in
                        let fraction = min(1, max(0, value.location.x / geometry.size.width))
                        emit(.seek(fraction: fraction))
                    }
                )
            }
            .frame(height: 4)

            HStack {
                Text(media.elapsedText)
                Spacer()
                if let remaining = media.remainingText { Text(remaining) }
            }
            .font(.system(size: 9))
            .monospacedDigit()
            .foregroundStyle(contentColor.opacity(0.5))
        }
    }

    /// Split out from `button(_:label:_:)` only because its symbol AND label
    /// both depend on `media.isPlaying` — same keyed-crossfade treatment as
    /// the title/artist above and `NotchRootView.leadingEar`'s HUD symbol,
    /// so the glyph swap between play/pause reads as a deliberate change
    /// rather than a flicker.
    private var playPauseButton: some View {
        let symbol = media.isPlaying ? "pause.fill" : "play.fill"
        return Button {
            emit(.togglePlayPause)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .id(symbol)
                .transition(.blurReplace)
                .animation(NotchAnimation.textAnimation(reduceMotion: reduceMotion), value: symbol)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(media.isPlaying ? "Pause" : "Play")
    }

    private func button(_ symbol: String, label: String, _ intent: NotchIntent) -> some View {
        Button {
            emit(intent)
        } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
