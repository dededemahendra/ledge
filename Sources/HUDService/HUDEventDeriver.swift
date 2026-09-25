import Foundation

/// Turns raw volume and brightness readings into the changes worth showing.
///
/// Pure and deterministic. The CoreAudio and DisplayServices shells do nothing
/// but feed this and forward what comes back.
public struct HUDEventDeriver: Sendable {
    /// Below this, a change is imperceptible and almost certainly float jitter.
    public static let minimumDelta: Double = 0.005

    private var lastVolume: Double?
    private var lastMuted: Bool?
    private var lastBrightness: Double?

    public init() {}

    /// Discards the baseline so the next reading re-establishes it.
    /// Used when rebinding to a different audio device (Review Focus 1).
    public mutating func reset() {
        lastVolume = nil
        lastMuted = nil
        lastBrightness = nil
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
