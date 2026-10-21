import Foundation

/// One calendar or reminder list as the Settings window lists it
/// (2026-09-30): grouped by account, with its colour and a switch.
public struct CalendarInfo: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case event, reminder
    }

    public struct RGB: Sendable, Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// Rec. 709 weights over the sRGB values as stored: rough, but
        /// enough to tell a colour that vanishes on black.
        public var luminance: Double {
            0.2126 * red + 0.7152 * green + 0.0722 * blue
        }

        /// Below this a list's colour, drawn as a 1.5 pt ring on the
        /// island's black, all but disappears.
        public static let minimumLuminanceOnBlack = 0.18

        /// This colour as a ring or bar on the island (2026-10-21): Apple's
        /// own list colours as they are, a near-black one mixed toward
        /// white just enough to show. The hue stays.
        public var visibleOnBlack: RGB {
            let floor = Self.minimumLuminanceOnBlack
            guard luminance < floor else { return self }
            let t = (floor - luminance) / (1 - luminance)
            return RGB(red: red + (1 - red) * t, green: green + (1 - green) * t, blue: blue + (1 - blue) * t)
        }
    }

    public let id: String
    public let title: String
    public let source: String
    public let kind: Kind
    public let color: RGB?

    public init(id: String, title: String, source: String, kind: Kind, color: RGB?) {
        self.id = id
        self.title = title
        self.source = source
        self.kind = kind
        self.color = color
    }

    /// Accounts in alphabetical order, calendars alphabetical within.
    public static func grouped(_ calendars: [CalendarInfo]) -> [(source: String, calendars: [CalendarInfo])] {
        let bySource = Dictionary(grouping: calendars, by: \.source)
        return bySource.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { source in
            (source, bySource[source]!.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
        }
    }
}
