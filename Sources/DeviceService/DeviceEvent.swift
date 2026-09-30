import Foundation

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
    case outputChanged(name: String, transport: AudioTransport, battery: PeripheralLevels?)

    /// One reading in the trailing ear beside others (2026-09-30): a bud
    /// or the case, with its glyph where the product has one.
    public struct Part: Sendable, Equatable {
        public let symbolName: String?
        public let text: String

        public init(symbolName: String?, text: String) {
            self.symbolName = symbolName
            self.text = text
        }
    }

    public var activityTitle: String {
        switch self {
        case .outputChanged(let name, _, _): return name
        }
    }

    /// A single figure, for peripherals with one battery. Buds use `parts`.
    public var compactText: String? {
        guard case .outputChanged(_, _, let levels?) = self, !levels.hasBuds, let main = levels.main else { return nil }
        return "\(main)%"
    }

    /// Left, right and case (2026-09-30, user's call), in the flat glyph
    /// style of the phone's own AirPods panel — the product's own bud and
    /// case symbols for AirPods, plain L/R/Case labels for anything else
    /// that reports buds. A component the device did not report is left
    /// out rather than invented.
    public var parts: [Part]? {
        guard case .outputChanged(let name, _, let levels?) = self, levels.hasBuds else { return nil }
        let symbols = Self.budSymbols(name: name)
        var parts: [Part] = []
        if let left = levels.left { parts.append(Part(symbolName: symbols?.left, text: symbols == nil ? "L \(left)" : "\(left)")) }
        if let right = levels.right { parts.append(Part(symbolName: symbols?.right, text: symbols == nil ? "R \(right)" : "\(right)")) }
        if let box = levels.case { parts.append(Part(symbolName: symbols?.case, text: symbols == nil ? "Case \(box)" : "\(box)")) }
        return parts
    }

    public var symbolName: String {
        switch self {
        case .outputChanged(let name, let transport, _):
            return Self.glyph(name: name, transport: transport)
        }
    }

    static func budSymbols(name: String) -> (left: String, right: String, case: String)? {
        let lower = name.lowercased()
        guard lower.contains("airpods"), !lower.contains("max") else { return nil }
        if lower.contains("pro") {
            return ("airpodpro.left", "airpodpro.right", "airpodspro.chargingcase.wireless")
        }
        return ("airpod.gen3.left", "airpod.gen3.right", "airpods.gen3.chargingcase.wireless")
    }

    public static func glyph(name: String, transport: AudioTransport) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpods.max" }
        if lower.contains("airpods pro") { return "airpods.pro" }
        if lower.contains("airpods")     { return "airpods" }
        if lower.contains("beats") {
            if lower.contains("fit pro")      { return "beats.fitpro" }
            if lower.contains("studio buds")  { return "beats.studiobuds" }
            if lower.contains("powerbeats")   { return "beats.powerbeatspro" }
            return "beats.headphones"
        }
        // Other true-wireless buds: Galaxy Buds, Pixel Buds, Redmi Buds,
        // anything calling itself TWS.
        if lower.contains("buds") || lower.contains("tws") || lower.contains("earbud") { return "earbuds" }
        if lower.contains("headphone")   { return "headphones" }
        switch transport {
        case .bluetooth:                       return "headphones"
        case .airPlay:                         return "airplay.audio"
        case .builtIn:                         return "laptopcomputer"
        case .usb, .hdmi, .displayPort, .other: return "speaker.wave.2"
        }
    }
}

public struct DeviceEventDeriver: Sendable {
    private var lastOutputUID: String?

    public init() {}

    public mutating func outputChanged(
        uid: String, name: String, transport: AudioTransport, battery: PeripheralLevels?
    ) -> DeviceEvent? {
        defer { lastOutputUID = uid }
        guard let last = lastOutputUID, last != uid else { return nil }
        return .outputChanged(name: name, transport: transport, battery: battery)
    }
}
