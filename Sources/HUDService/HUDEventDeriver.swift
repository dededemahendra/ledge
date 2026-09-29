import Foundation

/// Turns raw volume and brightness readings into the changes worth showing.
///
/// Pure and deterministic. The CoreAudio and DisplayServices shells do nothing
/// but feed this and forward what comes back.
public struct HUDEventDeriver: Sendable {
    /// Below this, a change is imperceptible and almost certainly float jitter.
    public static let minimumDelta: Double = 0.005

    /// Whether a brightness level is one the system's own keys would land
    /// on: the keys step in sixteenths and snap to that grid, while the
    /// display's own adjustments — dimming on battery, brightening back on
    /// AC, auto-brightness following the room — land anywhere. Used to keep
    /// those system-initiated changes from showing a "Display" HUD when the
    /// media-key tap is not active to say for certain (2026-09-28: plugging
    /// the charger in and out was popping the brightness HUD).
    public static func isOnKeyGrid(_ level: Double, steps: Double = 16, tolerance: Double = 0.004) -> Bool {
        let scaled = level * steps
        return abs(scaled - scaled.rounded()) <= tolerance * steps
    }

    private var lastVolume: Double?
    private var lastMuted: Bool?
    private var lastBrightness: Double?
    private var lastCapsLock: Bool?

    public init() {}

    /// Discards the baseline so the next reading re-establishes it.
    /// Used when rebinding to a different audio device (Review Focus 1).
    public mutating func reset() {
        lastVolume = nil
        lastMuted = nil
        lastBrightness = nil
        lastCapsLock = nil
    }

    /// First reading is a baseline (Caps Lock already on at launch is not
    /// news); every change after that fires.
    public mutating func capsLockChanged(on: Bool) -> HUDEvent? {
        defer { lastCapsLock = on }
        guard let lastCapsLock, lastCapsLock != on else { return nil }
        return .capsLock(on: on)
    }

    /// Volume-only variant for an output-device switch: the new device's
    /// level is not a change the user made, but the display's brightness
    /// baseline is still valid and must not be thrown away with it.
    public mutating func resetVolume() {
        lastVolume = nil
        lastMuted = nil
    }

    public mutating func volumeChanged(level: Double, muted: Bool) -> HUDEvent? {
        let clamped = min(1, max(0, level))

        // Baseline: record and stay silent.
        guard let lastVolume, let lastMuted else {
            self.lastVolume = clamped
            self.lastMuted = muted
            return nil
        }

        let levelMoved = abs(clamped - lastVolume) >= Self.minimumDelta
        let muteToggled = muted != lastMuted
        guard levelMoved || muteToggled else {
            // Deliberately does NOT rebaseline. Comparing against the last value
            // *observed* rather than the last one *fired* would let a slow slider
            // drag creep the baseline in lockstep with the input and never fire.
            return nil
        }

        self.lastVolume = clamped
        self.lastMuted = muted
        return .volume(level: clamped, muted: muted)
    }

    public mutating func brightnessChanged(level: Double) -> HUDEvent? {
        let clamped = min(1, max(0, level))

        guard let lastBrightness else {
            self.lastBrightness = clamped
            return nil
        }

        guard abs(clamped - lastBrightness) >= Self.minimumDelta else {
            // Same reasoning as volumeChanged: never rebaseline on a no-fire.
            return nil
        }

        self.lastBrightness = clamped
        return .brightness(level: clamped)
    }
}
