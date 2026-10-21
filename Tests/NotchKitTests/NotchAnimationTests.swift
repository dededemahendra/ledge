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
    // A pill's hidden island is a point (2026-10-21): coming out of it is
    // growth, going back is a collapse.
    let retracted = CGSize(width: 0, height: 0)
    #expect(NotchAnimation.isExpanding(from: retracted, to: peek))
    #expect(NotchAnimation.isExpanding(from: retracted, to: activity))
    #expect(!NotchAnimation.isExpanding(from: activity, to: retracted))
    #expect(!NotchAnimation.isExpanding(from: expanded, to: retracted))
}

/// The blip spring: a visible pop, ~8% overshoot, more than expand's ~1.5%
/// and well under anything that reads as a toy.
@Test func popOvershootsMoreThanExpandButStaysModest() {
    func overshoot(_ zeta: Double) -> Double {
        guard zeta < 1 else { return 0 }
        return exp(-zeta * .pi / (1 - zeta * zeta).squareRoot())
    }
    let pop = overshoot(NotchAnimation.popDamping)
    let expand = overshoot(NotchAnimation.expandDamping)
    #expect(pop > 0.05 && pop < 0.12, "pop overshoot \(pop)")
    #expect(pop > expand)
}

@Test func onlyGrowthFromTheBareNotchGetsThePopSpring() {
    #expect(NotchAnimation.animation(expanding: true, fromHidden: true, reduceMotion: false) == NotchAnimation.pop)
    #expect(NotchAnimation.animation(expanding: true, fromHidden: false, reduceMotion: false) == NotchAnimation.expand, "opening the panel is not a throw")
    #expect(NotchAnimation.animation(expanding: false, fromHidden: false, reduceMotion: false) == NotchAnimation.collapse)
    #expect(NotchAnimation.animation(expanding: true, fromHidden: true, reduceMotion: true) == NotchAnimation.reduced)
}

/// An arrival is growth out of what a hidden island draws (2026-10-21):
/// the notch on a MacBook, as before; the point on a pill, so the hover
/// pill opening into the card keeps the expand spring, as a MacBook's
/// hover lip does.
@Test func anArrivalIsGrowthOutOfWhatAHiddenIslandDraws() {
    let real = NotchMetrics(notchRect: CGRect(x: 645.5, y: 0, width: 179, height: 32))
    #expect(NotchAnimation.isArrival(from: CGSize(width: 179, height: 32), retracted: real.retracted))
    #expect(!NotchAnimation.isArrival(from: CGSize(width: 179, height: 38), retracted: real.retracted), "the hover lip is not hidden")
    let pill = NotchMetrics(notchRect: CGRect(x: 938, y: 0, width: 44, height: 32), isVirtual: true)
    #expect(NotchAnimation.isArrival(from: .zero, retracted: pill.retracted))
    #expect(!NotchAnimation.isArrival(from: CGSize(width: 120, height: 32), retracted: pill.retracted), "the hover pill is not hidden")
}
