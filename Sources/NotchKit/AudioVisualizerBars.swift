import SwiftUI

/// The compact now-playing visualizer — four thin capsules breathing while
/// music plays, the signature ear glyph of every notch media surface (and
/// spec §6's original "trailing ear: waveform"). Not a real spectrum:
/// MediaRemote gives no audio tap, and the reference app's bars are
/// decorative too. What makes decorative bars read as music (2026-09-29,
/// after "make it move more natural and minimal"):
///
/// - **continuous motion**: a `TimelineView(.animation)` at the display's
///   refresh rate, not a 12 fps step schedule — the eye reads the steps as
///   a ticking machine, never as sound;
/// - **a meter's envelope**: each beat is a fast attack and a slow
///   exponential decay, on top of an energy level that drifts over
///   seconds — the shape of a VU needle, not a sine;
/// - **one spectrum, not four metronomes**: neighbouring bars share most
///   of one wobble and keep a little of their own, and each sits a hair
///   off the beat, so they move together without moving in lockstep;
/// - **restraint**: 2pt bars, a modest 4–14pt range, nothing frantic.
///
/// Cost stays bounded for an always-running agent: it animates only while
/// `isAnimating` (callers gate on `isPlaying` AND Reduce Motion off), and
/// four capsules per frame is nothing. Paused or reduced, a static pose.
struct AudioVisualizerBars: View {
    let color: Color
    let isAnimating: Bool

    private static let barCount = 4
    private static let barWidth: CGFloat = 2
    private static let barSpacing: CGFloat = 2.5
    private static let minHeight: CGFloat = 4
    private static let maxHeight: CGFloat = 14
    /// The decorative tempo. Real music has another; nobody can tell from
    /// four bars, but a pulse at all is what says "music" rather than "busy".
    private static let beatsPerMinute: Double = 104

    var body: some View {
        if isAnimating {
            TimelineView(.animation) { context in
                bars(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            bars(at: nil)
        }
    }

    private func bars(at time: TimeInterval?) -> some View {
        HStack(alignment: .center, spacing: Self.barSpacing) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: Self.barWidth, height: height(bar: index, time: time))
            }
        }
        .frame(height: 16, alignment: .center)
    }

    /// `0...1` level for a bar at a moment — pure, so `level(bar:time:)` can
    /// be reasoned about: every term is bounded and the sum is clamped.
    static func level(bar: Int, time t: TimeInterval) -> Double {
        let i = Double(bar)
        // Beat: a fast attack and exponential decay, each bar a hair off
        // the beat so the row ripples instead of jumping as one.
        let beatPhase = (t * beatsPerMinute / 60 + i * 0.09).truncatingRemainder(dividingBy: 1)
        let beat = exp(-4 * beatPhase)
        // Energy drifting over seconds — verses and choruses, loosely.
        let drift = 0.5 + 0.5 * sin(t * 0.43 + i * 1.3)
        // The spectrum's shared wobble, plus a little of each bar's own.
        let shared = sin(t * 2.3 + i * 0.7)
        let own = sin(t * (3.1 + i * 0.37) + i * 2.1)
        let level = 0.16 + 0.30 * drift + 0.34 * beat + 0.10 * shared + 0.10 * own
        return min(1, max(0, level))
    }

    private func height(bar: Int, time: TimeInterval?) -> CGFloat {
        // Static pose for paused / Reduce Motion — reads as "audio", holds still.
        guard let time else { return [7, 11, 9, 6][bar] }
        return Self.minHeight + (Self.maxHeight - Self.minHeight) * CGFloat(Self.level(bar: bar, time: time))
    }
}
