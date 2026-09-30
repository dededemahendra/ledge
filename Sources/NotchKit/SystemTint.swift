import AppKit

/// Apple's system colours by the names the Focus database uses
/// ("systemIndigoColor") or their bare form ("indigo"). `nil` for anything
/// else, which the island draws white.
public enum SystemTint {
    public static func color(named raw: String) -> NSColor? {
        var name = raw.lowercased()
        if name.hasPrefix("system") { name.removeFirst("system".count) }
        if name.hasSuffix("color") { name.removeLast("color".count) }
        switch name {
        case "indigo": return .systemIndigo
        case "purple": return .systemPurple
        case "blue":   return .systemBlue
        case "teal":   return .systemTeal
        case "cyan":   return .systemCyan
        case "mint":   return .systemMint
        case "green":  return .systemGreen
        case "yellow": return .systemYellow
        case "orange": return .systemOrange
        case "red":    return .systemRed
        case "pink":   return .systemPink
        case "brown":  return .systemBrown
        case "gray", "grey": return .systemGray
        default:       return nil
        }
    }
}
