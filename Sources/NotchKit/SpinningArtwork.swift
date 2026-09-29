import SwiftUI

/// Album art as a disc (2026-09-29, user's call: "make the cover spin like
/// a DVD"): the content is clipped to a circle and turns slowly while music
/// plays, holds its angle the moment playback pauses, and resumes from
/// there. Used for both the ear's 20pt sleeve and the card's 56pt one, so
/// the hero morph between them carries the rotation along.
///
/// No `repeatForever` animation: that cannot pause without snapping back.
/// The angle is arithmetic on a `TimelineView` instead — an anchor angle
/// plus the time since playback (re)started — and the anchor is frozen
/// on pause. Paused under Reduce Motion, always.
struct SpinningArtwork<Content: View>: View {
    let isPlaying: Bool
    let reduceMotion: Bool
    let content: Content

    /// One full turn every 12 s: a slow, deliberate spin that reads as a
    /// disc at rest-ish, not a vinyl at 33 rpm.
    static var secondsPerRevolution: Double { 12 }

    private struct Anchor {
        var angle: Double
        var since: Date?
    }

    // Spelled-out `State`, like every other in this module (no macro plugin).
    private var _anchor: State<Anchor> = State(initialValue: Anchor(angle: 0, since: nil))
    private var anchor: Anchor {
        get { _anchor.wrappedValue }
        nonmutating set { _anchor.wrappedValue = newValue }
    }

    init(isPlaying: Bool, reduceMotion: Bool, @ViewBuilder content: () -> Content) {
        self.isPlaying = isPlaying
        self.reduceMotion = reduceMotion
        self.content = content()
    }

    private var spinning: Bool { isPlaying && !reduceMotion }

    private func angle(at date: Date) -> Double {
        let elapsed = anchor.since.map { date.timeIntervalSince($0) } ?? 0
        return anchor.angle + elapsed * 360 / Self.secondsPerRevolution
    }

    var body: some View {
        TimelineView(.animation(paused: !spinning)) { context in
            content
                .clipShape(Circle())
                .rotationEffect(.degrees(angle(at: context.date)))
        }
        .onAppear {
            if spinning { anchor = Anchor(angle: anchor.angle, since: Date()) }
        }
        .onChange(of: spinning) { _, nowSpinning in
            if nowSpinning {
                anchor = Anchor(angle: anchor.angle, since: Date())
            } else {
                anchor = Anchor(angle: angle(at: Date()).truncatingRemainder(dividingBy: 360), since: nil)
            }
        }
    }
}
