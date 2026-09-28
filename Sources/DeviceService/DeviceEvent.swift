import Foundation

/// How audio reaches the current default output device. Mapped from
/// CoreAudio's `kAudioDevicePropertyTransportType`.
public enum AudioTransport: Sendable, Equatable {
    case builtIn
    case bluetooth
    case usb
    case hdmi
    case displayPort
    case airPlay
    case other
}

public enum DeviceEvent: Sendable, Equatable {
    /// The default output moved to a different device. Announced by NAME,
    /// including a move back to the built-in speakers: CoreAudio only says
    /// where sound goes now, not whether the previous device disconnected
    /// or the user merely switched, so "AirPods disconnected" would be a
    /// guess. `IOBluetooth`, which could tell, needs the Bluetooth privacy
    /// prompt (the app crashed at launch without a usage description on
    /// 2026-09-28) — a permission this service promised not to need.
    case outputChanged(name: String, transport: AudioTransport, batteryPercent: Int?)

    public var activityTitle: String {
        switch self {
        case .outputChanged(let name, _, _): return name
        }
    }

    /// Battery for the trailing ear; nothing when unknown, so the ear stays
    /// empty rather than showing a made-up value.
    public var compactText: String? {
        if case .outputChanged(_, _, let battery?) = self { return "\(battery)%" }
        return nil
    }

    /// SF Symbol for the leading ear. Product-specific glyphs where the
    /// name gives them away, transport-generic ones otherwise.
    public var symbolName: String {
        switch self {
        case .outputChanged(let name, let transport, _):
            let lower = name.lowercased()
            if lower.contains("airpods max") { return "airpods.max" }
            if lower.contains("airpods pro") { return "airpods.pro" }
            if lower.contains("airpods")     { return "airpods" }
            if lower.contains("beats")       { return "beats.headphones" }
            // The headphone jack is the BUILT-IN device renamed ("External
            // Headphones"), so the name has to win over the transport here
            // or wired headphones get the laptop glyph.
            if lower.contains("headphone")   { return "headphones" }
            switch transport {
            case .bluetooth:                       return "headphones"
            case .airPlay:                         return "airplay.audio"
            case .builtIn:                         return "laptopcomputer"
            case .usb, .hdmi, .displayPort, .other: return "speaker.wave.2"
            }
        }
    }
}

/// Turns raw route observations into the events worth showing. Pure, so
/// the observer stays a dumb shell.
public struct DeviceEventDeriver: Sendable {
    private var lastOutputUID: String?

    public init() {}

    /// The first call is a baseline: the device in use at launch is not
    /// news. The same UID reported again (CoreAudio re-notifies freely) is
    /// silent too.
    public mutating func outputChanged(
        uid: String, name: String, transport: AudioTransport, batteryPercent: Int?
    ) -> DeviceEvent? {
        defer { lastOutputUID = uid }
        guard let last = lastOutputUID, last != uid else { return nil }
        return .outputChanged(name: name, transport: transport, batteryPercent: batteryPercent)
    }
}
