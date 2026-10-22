import Foundation

/// How the island announces an update (2026-10-22), shared by the app and
/// the Settings preview so both draw the same blip.
public enum UpdateNotice {
    public static let symbolName = "arrow.down.circle.fill"
    public static func title(_ version: String) -> String { "Ledge \(version) is available" }
    public static func caption(_ version: String) -> String { "Ledge \(version) is available · Download" }
}
