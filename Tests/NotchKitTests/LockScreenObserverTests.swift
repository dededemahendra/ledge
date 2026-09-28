import Testing
import Foundation
@testable import NotchKit

@Test func onlyTheTwoLoginwindowNotificationsMapToALockState() {
    #expect(LockScreenObserver.lockedState(for: LockScreenObserver.lockedNotification) == true)
    #expect(LockScreenObserver.lockedState(for: LockScreenObserver.unlockedNotification) == false)
    #expect(LockScreenObserver.lockedState(for: Notification.Name("com.apple.screensaver.didstart")) == nil,
            "the screen saver starting is not a lock")
    #expect(LockScreenObserver.lockedNotification.rawValue == "com.apple.screenIsLocked")
    #expect(LockScreenObserver.unlockedNotification.rawValue == "com.apple.screenIsUnlocked")
}
