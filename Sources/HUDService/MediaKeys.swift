import Foundation

/// The hardware keys whose system overlay Ledge replaces.
///
/// Raw values are the `NX_KEYTYPE_*` codes from `IOKit/hidsystem/ev_keymap.h`
/// (spelled out here rather than imported so this file stays a plain,
/// dependency-free value type the tests can drive directly).
public enum MediaKey: UInt32, Sendable, CaseIterable {
    case volumeUp = 0        // NX_KEYTYPE_SOUND_UP
    case volumeDown = 1      // NX_KEYTYPE_SOUND_DOWN
    case brightnessUp = 2    // NX_KEYTYPE_BRIGHTNESS_UP
    case brightnessDown = 3  // NX_KEYTYPE_BRIGHTNESS_DOWN
    case mute = 7            // NX_KEYTYPE_MUTE
}

/// One decoded media-key event.
public struct MediaKeyPress: Sendable, Equatable {
    public let key: MediaKey
    public let isDown: Bool
    public let isRepeat: Bool

    public init(key: MediaKey, isDown: Bool, isRepeat: Bool) {
        self.key = key
        self.isDown = isDown
        self.isRepeat = isRepeat
    }
}

/// Decodes `NSEvent`'s `.systemDefined` events into `MediaKeyPress`es.
///
/// A media key arrives as an `NX_SYSDEFINED` (type 14) event with subtype 8
/// (`NX_SUBTYPE_AUX_CONTROL_BUTTONS`) whose `data1` packs the key code in
/// the high 16 bits and flags in the low 16: bits 8–15 carry the key state
/// (`0x0A` down, `0x0B` up), bit 0 the auto-repeat flag. This is the
/// long-standing layout every media-key tapping app relies on
/// (`Apple's own HID docs, and e.g. BetterDisplay/MonitorControl`).
public enum MediaKeyDecoder {
    public static let systemDefinedEventType: UInt32 = 14   // NX_SYSDEFINED
    public static let auxControlSubtype: Int16 = 8          // NX_SUBTYPE_AUX_CONTROL_BUTTONS

    /// `nil` for anything that is not one of `MediaKey`'s five keys (play/
    /// pause, keyboard backlight, Launchpad …), which the tap must pass
    /// through untouched.
    public static func decode(subtype: Int16, data1: Int) -> MediaKeyPress? {
        guard subtype == auxControlSubtype else { return nil }
        let code = UInt32((data1 & 0xFFFF_0000) >> 16)
        guard let key = MediaKey(rawValue: code) else { return nil }
        let flags = data1 & 0xFFFF
        let state = (flags & 0xFF00) >> 8
        return MediaKeyPress(key: key, isDown: state == 0x0A, isRepeat: (flags & 0x1) != 0)
    }
}

/// How far one key press moves a level. Mirrors the system: a press moves
/// one sixteenth, Shift+Option moves one sixty-fourth, and the result snaps
/// to that grid — so a slider left at 0.53 by a drag goes to 9/16 on the
/// next press, not 0.5925, exactly as macOS's own keys behave.
public enum MediaKeyStepper {
    public static let coarseSteps: Double = 16
    public static let fineSteps: Double = 64

    public static func step(_ level: Double, up: Bool, fine: Bool) -> Double {
        let steps = fine ? fineSteps : coarseSteps
        let current = (min(1, max(0, level)) * steps).rounded()
        let next = current + (up ? 1 : -1)
        return min(1, max(0, next / steps))
    }
}

/// Pairs key-ups with the key-downs this app actually consumed. A key-down
/// that was passed through to the system (no settable volume, a CoreAudio
/// hiccup) must have its key-up passed through too, or the system sees a
/// press with no release (review, 2026-09-29).
public struct MediaKeyUpTracker: Sendable {
    private var consumedDown: Set<MediaKey> = []

    public init() {}

    /// `apply` runs only for key-downs and says whether the press was
    /// handled. Returns whether the event should be consumed.
    public mutating func consume(_ press: MediaKeyPress, apply: () -> Bool) -> Bool {
        guard press.isDown else {
            return consumedDown.remove(press.key) != nil
        }
        let consumed = apply()
        if consumed { consumedDown.insert(press.key) } else { consumedDown.remove(press.key) }
        return consumed
    }
}
