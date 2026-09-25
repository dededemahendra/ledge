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
