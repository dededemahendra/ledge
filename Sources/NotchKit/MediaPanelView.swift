import AppKit
import SwiftUI

/// The expanded media card, laid out to match Alcove's structure (from the
/// user's screenshot of the real thing):
///
///   row 1 — artwork (a spinning disc) · title/artist · star · output button
///   row 2 — full-width scrubber with the times INLINE at its ends
///   row 3 — Apple Music's transport row:
///           shuffle · previous · play/pause · next · repeat
///   row 4 — (while the output picker is open) one row per audio output,
///           below the controls; the card grows downward to hold them and
///           shrinks back after a pick
///
/// Flat black card — Alcove's is, and anything else beside the real notch
/// reads as a different object. The play glyph is simply LARGER than its
/// neighbours (no circle chip); shuffle/repeat are real (`send 6`/`send 7`
/// in the adapter) but stateless for now — `MediaPayload` does not yet
/// decode shuffleMode/repeatMode, so they fire without an active highlight.
/// Alcove's fifth icon is screen-mirroring, which has no backing capability
/// here; repeat held that slot until 2026-09-28, when the output picker
/// took it (spec §7, DeviceService) — repeat was stateless anyway.
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
    /// The output picker's entries (`NotchController.outputs`).
    let outputs: [OutputOption]
    /// `media.artwork` already decoded (`NotchController.mediaArtworkImage`);
    /// `nil` shows the placeholder.
    let artworkImage: NSImage?

    /// The cascade (2026-09-29): on appear the header, the scrubber and the
    /// controls rise 6pt into place with a slight stagger, the way the
    /// Dynamic Island's expanded content settles in. Starts revealed under
    /// Reduce Motion and under the render-test hook, whose single frame
    /// must be the resting one. Same spelled-out `State` as the rest.
    private var _revealed: State<Bool>
    private var revealed: Bool {
        get { _revealed.wrappedValue }
        nonmutating set { _revealed.wrappedValue = newValue }
    }

    private func cascade<V: View>(_ view: V, order: Int) -> some View {
        view
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 6)
            .animation(
                reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.8).delay(Double(order) * 0.045),
                value: revealed
            )
    }

    /// Whether the output list is open below the controls
    /// (`NotchController.isOutputPickerOpen` — the controller owns it, since
    /// it sizes the island). `toggleOutputs` flips it.
    let outputPickerOpen: Bool
    let toggleOutputs: () -> Void

    /// The row just picked, shown as current until CoreAudio confirms the
    /// route (the highlight and tick glide there at once); `nil` otherwise.
    private var _pendingOutput: State<String?> = State(initialValue: nil)
    private var pendingOutput: String? {
        get { _pendingOutput.wrappedValue }
        nonmutating set { _pendingOutput.wrappedValue = newValue }
    }
    private var _hoveredOutput: State<String?> = State(initialValue: nil)
    private var hoveredOutput: String? {
        get { _hoveredOutput.wrappedValue }
        nonmutating set { _hoveredOutput.wrappedValue = newValue }
    }
    /// Hero pair for the highlight and the tick moving between rows.
    private var _pickerNamespace: Namespace = Namespace()
    private var pickerNamespace: Namespace.ID { _pickerNamespace.wrappedValue }

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
        artworkNamespace: Namespace.ID,
        emit: @escaping (NotchIntent) -> Void,
        displayOnly: Bool = false,
        outputs: [OutputOption] = [],
        artworkImage: NSImage? = nil,
        outputPickerOpen: Bool = false,
        toggleOutputs: @escaping () -> Void = {}
    ) {
        self.media = media
        self.reduceMotion = reduceMotion
        self.contentColor = contentColor
        self.artworkNamespace = artworkNamespace
        self.emit = emit
        self.displayOnly = displayOnly
        self.outputs = outputs
        self.artworkImage = artworkImage
        self.outputPickerOpen = outputPickerOpen
        self.toggleOutputs = toggleOutputs
        var startRevealed = reduceMotion
        #if DEBUG
        if NotchRenderTestHook.contentColor != nil { startRevealed = true }
        #endif
        _revealed = State(initialValue: startRevealed)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 7) {
                cascade(headerRow, order: 0)
                cascade(scrubRow, order: 1)
                if !displayOnly {
                    cascade(controlsRow, order: 2)
                }
            }
            // The output list grows the card downward (the island's height
            // follows via `NotchMetrics.expanded(outputRows:)`); its rows
            // insert individually, each with its own entrance, so the list
            // itself is always present — outside the spaced stack, so an
            // empty list costs nothing while closed.
            if !displayOnly {
                outputsList
                    .padding(.top, outputPickerOpen ? NotchMetrics.outputListInset : 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .foregroundStyle(contentColor)
        .onAppear { revealed = true }
    }

    // MARK: - Row 1: artwork · title/artist · visualizer

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            // Artwork + titles are one button: a click brings the playing
            // app to the front (`NotchIntent.openSource`, 2026-09-29 — the
            // Dynamic Island's own "take me there"). The visualizer stays
            // outside it; it is a status glyph, not a control.
            Button {
                emit(.openSource)
            } label: {
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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(reduceMotion: reduceMotion))
            .disabled(displayOnly)   // no controls on the lock screen, this one included
            .accessibilityLabel("Open in the playing app")

            Spacer(minLength: 8)

            favoriteButton
            outputHeaderButton
        }
    }

    @ViewBuilder private var artwork: some View {
        SpinningArtwork(isPlaying: media.isPlaying, reduceMotion: reduceMotion) {
            Group {
                if let image = artworkImage {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Circle()
                        .fill(contentColor.opacity(0.18))
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 20))
                                .foregroundStyle(contentColor.opacity(0.5))
                        }
                }
            }
            .frame(width: 56, height: 56)
        }
        // Depth: a soft shadow beneath and a hairline catching light on the
        // edge, so the disc reads as an object sitting on the card rather
        // than a flat texture. The placeholder gets the identical treatment
        // so the two states don't jump when artwork arrives.
        .overlay {
            Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
        .modifier(FlipOnChange(trigger: media.title, enabled: !reduceMotion))
    }

    // MARK: - Row 2: full-width scrubber, times inline at the ends

    private var scrubRow: some View {
        let dragging = dragFraction != nil

        return HStack(spacing: 8) {
            // Natural width with a 34pt floor: monospaced digits keep the
            // bar from twitching as seconds tick, and the width only ever
            // changes at a 9:59 → 10:00 boundary. A FIXED 34pt slot used to
            // truncate anything past ten minutes to "-35:…" (2026-09-29,
            // seen on a 38-minute video); an hour-long one needs ~48pt.
            Text(media.elapsedText)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 34, alignment: .leading)

            GeometryReader { geometry in
                let fraction = dragFraction.map(Double.init) ?? media.progress
                ZStack(alignment: .leading) {
                    Capsule().fill(contentColor.opacity(0.22))
                    Capsule()
                        // White fill, like Alcove's.
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
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 34, alignment: .trailing)
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

    /// Apple Music's transport row (user's call, 2026-09-29): play/pause at
    /// the focal size, the skips a step down, shuffle and repeat small and
    /// grey until on — then on a filled highlight, the way Music marks them
    /// — and a soft rounded highlight under the pointer on every control.
    /// Five slots evenly spread. The favourite star lives beside the title
    /// and the output button is the header's glyph, as in Music itself.
    private var controlsRow: some View {
        HStack(spacing: 0) {
            MusicControlButton(
                symbol: "shuffle", label: "Shuffle", size: 14,
                mode: media.isShuffling == nil ? .unavailable : (media.isShuffling == true ? .active : .idle),
                contentColor: contentColor, reduceMotion: reduceMotion
            ) { emit(.toggleShuffle) }
            .frame(maxWidth: .infinity)

            MusicControlButton(
                symbol: "backward.fill", label: "Previous", size: 20,
                contentColor: contentColor, reduceMotion: reduceMotion
            ) { emit(.previous) }
            .frame(maxWidth: .infinity)

            MusicControlButton(
                symbol: media.isPlaying ? "pause.fill" : "play.fill",
                label: media.isPlaying ? "Pause" : "Play", size: 28, weight: .heavy, width: 40,
                contentColor: contentColor, reduceMotion: reduceMotion
            ) { emit(.togglePlayPause) }
            .frame(maxWidth: .infinity)

            MusicControlButton(
                symbol: "forward.fill", label: "Next", size: 20,
                contentColor: contentColor, reduceMotion: reduceMotion
            ) { emit(.next) }
            .frame(maxWidth: .infinity)

            MusicControlButton(
                symbol: media.repeatMode == .one ? "repeat.1" : "repeat", label: "Repeat", size: 14,
                mode: media.repeatMode == nil ? .unavailable : (media.repeatMode == .off ? .idle : .active),
                contentColor: contentColor, reduceMotion: reduceMotion
            ) { emit(.toggleRepeat) }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 30)
    }

    // MARK: - Header buttons: favourite star, output glyph

    /// Beside the title, where Music keeps it: filled when the track is
    /// favourited, hollow when not (or not yet asked), dimmed and disabled
    /// for sources that cannot favourite — see `MusicFavorites`.
    private var favoriteButton: some View {
        let state = media.favorite
        return MusicControlButton(
            symbol: state == .on ? "star.fill" : "star", label: "Favourite", size: 13,
            mode: state == .unsupported ? .unavailable : .idle, width: 28,
            contentColor: contentColor, reduceMotion: reduceMotion
        ) { emit(.toggleFavorite) }
        .opacity(state == .on || state == .unsupported ? 1 : 0.7)
        .accessibilityValue(state == .on ? "on" : (state == .off ? "off" : "unknown"))
    }

    /// Top-right, where the reference card parks its equalizer: the current
    /// output's glyph, and the button that opens the output list below the
    /// controls — lit (filled) while the list is open, disabled with fewer
    /// than two outputs, since one output is not a choice.
    private var outputHeaderButton: some View {
        let current = outputs.first(where: \.isCurrent)
        return MusicControlButton(
            symbol: current?.symbolName ?? "speaker.wave.2", label: "Output: \(current?.name ?? "unknown")",
            size: 13, weight: .medium,
            mode: outputs.count < 2 ? .unavailable : (outputPickerOpen ? .active : .idle), width: 28,
            contentColor: contentColor, reduceMotion: reduceMotion
        ) { toggleOutputs() }
    }

    // MARK: - Output picker (list below the controls)

    /// One row per output — glyph, name, and a tick on the current one —
    /// with a real menu's manners (2026-09-29, user's call: clearer,
    /// minimal, with interaction): a soft highlight under the pointer, a
    /// dip on press (no shrink: a wide row that shrinks looks broken), and
    /// on a pick the highlight and the tick GLIDE to the chosen row, the
    /// list holds for a beat so the landing is seen, then closes. The rows
    /// cascade in when the list opens. Each row is
    /// `NotchMetrics.outputRowHeight`, so the island grows by exactly what
    /// the list needs; the rows live in the `ForEach` so each gets its own
    /// entrance instead of the list appearing as one block.
    private var outputsList: some View {
        VStack(spacing: 0) {
            ForEach(Array((outputPickerOpen ? outputs : []).enumerated()), id: \.element.id) { index, output in
                outputRow(output)
                    .transition(rowTransition(order: index))
            }
        }
        .onChange(of: outputs) { _, _ in pendingOutput = nil }   // the real route arrived
    }

    private func rowTransition(order: Int) -> AnyTransition {
        let fade = BlurReplaceTransition(configuration: .downUp)
        guard !reduceMotion else { return AnyTransition(fade) }
        return .asymmetric(
            insertion: AnyTransition(
                OffsetTransition(CGSize(width: 0, height: -6)).combined(with: fade)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8).delay(Double(order) * 0.04))
            ),
            removal: AnyTransition(fade)
        )
    }

    private func outputRow(_ output: OutputOption) -> some View {
        let currentID = pendingOutput ?? outputs.first(where: \.isCurrent)?.id
        let selected = currentID == output.id
        let hovered = hoveredOutput == output.id
        return Button {
            guard !selected else { toggleOutputs(); return }   // the current one: just close
            withAnimation(reduceMotion ? NotchAnimation.reduced : .spring(response: 0.35, dampingFraction: 0.8)) {
                pendingOutput = output.id
            }
            emit(.selectOutput(id: output.id))
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(480))
                toggleOutputs()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: output.symbolName)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                Text(output.name)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .matchedGeometryEffect(id: "output-tick", in: pickerNamespace)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: NotchMetrics.outputRowHeight - 2)
            .frame(maxWidth: .infinity)
            .opacity(selected || hovered ? 1 : 0.8)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(contentColor.opacity(0.12))
                        .matchedGeometryEffect(id: "output-highlight", in: pickerNamespace)
                } else if hovered {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(contentColor.opacity(0.07))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ListRowButtonStyle(reduceMotion: reduceMotion))
        .onHover { inside in
            if inside { hoveredOutput = output.id } else if hoveredOutput == output.id { hoveredOutput = nil }
        }
        .animation(NotchAnimation.textAnimation(reduceMotion: reduceMotion), value: hovered)
        .frame(height: NotchMetrics.outputRowHeight)
        .accessibilityLabel(output.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

}
