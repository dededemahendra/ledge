import Testing
import SwiftUI
@testable import NotchKit

@Test func springParametersMatchTheSpec() {
    #expect(NotchAnimation.expandResponse == 0.35)
    #expect(NotchAnimation.expandDamping == 0.72)
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
    #expect(expand > 0.03 && expand < 0.05, "one small confident overshoot, ~3.8%")
    #expect(collapse < 0.005, "closing must not draw attention")
    #expect(expand > collapse)
}
