import Testing
import SwiftUI
@testable import NotchKit

@Test func springParametersMatchTheSpec() {
    // Expand retuned 0.35/0.72 -> 0.4/0.8 at the user's explicit request
    // during the media-player redesign. Collapse deliberately unchanged.
    #expect(NotchAnimation.expandResponse == 0.4)
    #expect(NotchAnimation.expandDamping == 0.8)
    #expect(NotchAnimation.collapseResponse == 0.30)
    #expect(NotchAnimation.collapseDamping == 0.92)
    #expect(NotchAnimation.reducedDuration == 0.15)
}

@Test func reduceMotionAlwaysYieldsTheCrossfade() {
    #expect(NotchAnimation.animation(expanding: true, reduceMotion: true) == NotchAnimation.reduced)
    #expect(NotchAnimation.animation(expanding: false, reduceMotion: true) == NotchAnimation.reduced)
}

@Test func normalMotionPicksDirectionSpecificSprings() {
    #expect(NotchAnimation.animation(expanding: true, reduceMotion: false) == NotchAnimation.expand)
    #expect(NotchAnimation.animation(expanding: false, reduceMotion: false) == NotchAnimation.collapse)
}

/// Pins `textAnimation`'s reduce-motion branching. Does NOT (and cannot,
/// from a unit test) prove the `.blurReplace` transition it drives actually
/// plays at runtime — that needs a live, in-progress animation, which
/// neither this nor `NotchRenderTests`' single-frame `ImageRenderer` can
/// observe. This is the same class of limitation already on record for
/// spring selection (see `NotchRootView.body`'s `expanding` comment): the
/// constants/branching are pinned; the live behaviour is reasoned, not
/// observed.
@Test func textAnimationHonoursReduceMotion() {
    #expect(NotchAnimation.textAnimation(reduceMotion: true) == NotchAnimation.reduced)
    #expect(NotchAnimation.textAnimation(reduceMotion: false) == NotchAnimation.textCrossfade)
    #expect(NotchAnimation.textAnimation(reduceMotion: false) != NotchAnimation.expand)
    #expect(NotchAnimation.textAnimation(reduceMotion: false) != NotchAnimation.collapse)
}

@Test func expandOvershootsAndCollapseBarelyDoes() {
    // overshoot = exp(-zeta * pi / sqrt(1 - zeta^2))
    func overshoot(_ zeta: Double) -> Double {
        guard zeta < 1 else { return 0 }
        return exp(-zeta * .pi / (1 - zeta * zeta).squareRoot())
    }
    let expand = overshoot(NotchAnimation.expandDamping)
    let collapse = overshoot(NotchAnimation.collapseDamping)
    #expect(expand > 0.010 && expand < 0.025, "one small confident overshoot, ~1.5% at damping 0.8")
    #expect(collapse < 0.005, "closing must not draw attention")
    #expect(expand > collapse)
}

/// Spring direction by area (2026-09-29). Every resting-state pair the app
/// has, in both directions.
@Test func springDirectionIsDecidedByArea() {
    let collapsed = CGSize(width: 179, height: 32)
    let peek = CGSize(width: 179, height: 38)
    let activity = CGSize(width: 255, height: 32)
    let expanded = CGSize(width: 390, height: 168)
    #expect(NotchAnimation.isExpanding(from: collapsed, to: peek))
    #expect(NotchAnimation.isExpanding(from: collapsed, to: activity))
    #expect(NotchAnimation.isExpanding(from: peek, to: activity), "6pt shorter but far wider: this is growth, not a collapse")
    #expect(NotchAnimation.isExpanding(from: activity, to: expanded))
    #expect(NotchAnimation.isExpanding(from: peek, to: expanded))
    #expect(!NotchAnimation.isExpanding(from: expanded, to: activity))
    #expect(!NotchAnimation.isExpanding(from: activity, to: peek))
    #expect(!NotchAnimation.isExpanding(from: activity, to: collapsed))
    #expect(!NotchAnimation.isExpanding(from: expanded, to: collapsed))
    #expect(!NotchAnimation.isExpanding(from: activity, to: activity), "no change is not growth")
}

/// The visualizer's level function: bounded, alive, and not in lockstep.
@Test func visualizerLevelsStayInRangeAndBarsDoNotMoveAsOne() {
    var minSeen = 1.0, maxSeen = 0.0
    var identical = 0, samples = 0
    for step in 0..<600 {   // ten seconds at 60 Hz
        let t = Double(step) / 60
        let levels = (0..<4).map { AudioVisualizerBars.level(bar: $0, time: t) }
        minSeen = min(minSeen, levels.min()!)
        maxSeen = max(maxSeen, levels.max()!)
        if abs(levels[0] - levels[1]) < 0.01 { identical += 1 }
        samples += 1
    }
    #expect(minSeen >= 0 && maxSeen <= 1)
    #expect(maxSeen - minSeen > 0.5, "it must actually move: range \(minSeen)...\(maxSeen)")
    #expect(Double(identical) / Double(samples) < 0.1, "neighbouring bars share motion but are not the same bar")
}

/// Continuity: at the display's refresh rate no single frame jumps more
/// than a fraction of the range — what makes it read as motion, not steps.
@Test func visualizerIsContinuousFrameToFrame() {
    var worst = 0.0
    var previous = (0..<4).map { AudioVisualizerBars.level(bar: $0, time: 0) }
    for step in 1..<600 {
        let t = Double(step) / 60
        let levels = (0..<4).map { AudioVisualizerBars.level(bar: $0, time: t) }
        for bar in 0..<4 { worst = max(worst, abs(levels[bar] - previous[bar])) }
        previous = levels
    }
    #expect(worst < 0.35, "largest per-frame change \(worst) — the beat's attack is the only fast edge, and it stays under the range")
}
