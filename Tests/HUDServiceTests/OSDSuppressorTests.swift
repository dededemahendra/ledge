import Testing
import Foundation
@testable import HUDService

@Test func suppressingStopsEveryHelperFound() {
    #expect(OSDSuppressionPolicy.actions(pids: [42], suppressing: true) == [.stop(42)])
    #expect(OSDSuppressionPolicy.actions(pids: [42, 77], suppressing: true)
            == [.stop(42), .stop(77)],
            "more than one helper can exist across sessions")
}

@Test func notSuppressingResumesEveryHelperFound() {
    #expect(OSDSuppressionPolicy.actions(pids: [42], suppressing: false) == [.resume(42)])
}

// The helper is not resident: most sweeps find nothing, and that is normal.
@Test func noHelperRunningIsNotAnError() {
    #expect(OSDSuppressionPolicy.actions(pids: [], suppressing: true) == [])
    #expect(OSDSuppressionPolicy.actions(pids: [], suppressing: false) == [])
}

@Test func sweepIntervalIsFrequentEnoughToCatchAnOnDemandLaunch() {
    // The helper launches, draws, and lingers briefly. A 1s sweep catches it
    // before the second HUD of a key-repeat burst.
    #expect(OSDSuppressionPolicy.sweepInterval <= 1.0)
    #expect(OSDSuppressionPolicy.sweepInterval > 0)
}

@Test func bundleIdentifierIsTheVerifiedOne() {
    #expect(OSDSuppressor.helperBundleIdentifier == "com.apple.OSDUIHelper")
}

// Review Focus 3: recovery must not depend on a clean shutdown.
@Test func launchRecoveryResumesUnconditionallyWhenNotSuppressing() {
    let actions = OSDSuppressionPolicy.launchRecoveryActions(pids: [42], willSuppress: false)
    #expect(actions == [.resume(42)],
            "a previous crash may have left the helper stopped")
}

@Test func launchRecoveryStillResumesFirstEvenWhenAboutToSuppress() {
    let actions = OSDSuppressionPolicy.launchRecoveryActions(pids: [42], willSuppress: true)
    #expect(actions == [.resume(42)],
            "always hand the system back a working helper, then re-suppress on the next sweep")
}
