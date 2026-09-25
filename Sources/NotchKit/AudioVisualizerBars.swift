import SwiftUI

/// The compact now-playing visualizer — four capsules breathing while music
/// plays, the signature ear glyph of every notch media surface (and spec §6's
/// original "trailing ear: waveform"). Not a real spectrum: MediaRemote gives
/// no audio tap, and Alcove's own bars are decorative too. The wobble is a
/// pair of incommensurate sines per bar, so the pattern never visibly loops.
///
/// Cost is deliberately bounded for an always-running agent: a 12fps
/// `TimelineView` schedule (not per-frame), driving four capsules — and it
/// runs only while `isAnimating`, which callers gate on `isPlaying` AND
/// Reduce Motion being off. Paused or reduced, the bars are a static shape.
struct AudioVisualizerBars: View {
    let color: Color
    let isAnimating: Bool

    var body: some View {
        if isAnimating {
            TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { context in
                bars(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            bars(at: nil)
        }
    }

    private func bars(at time: TimeInterval?) -> some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: height(bar: index, time: time))
            }
        }
        .frame(height: 16, alignment: .center)
    }

    private func height(bar: Int, time: TimeInterval?) -> CGFloat {
        // Static pose for paused / Reduce Motion — reads as "audio", holds still.
        guard let time else { return [7, 12, 9, 6][bar] }
        let phase = time * (1.7 + Double(bar) * 0.31) + Double(bar) * 1.9
        let wobble = (sin(phase) + sin(phase * 1.61 + 0.7)) / 2
        return 9.5 + wobble * 6.0   // 3.5 ... 15.5pt
    }
}
