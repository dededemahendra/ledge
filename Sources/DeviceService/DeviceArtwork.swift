import Foundation

/// Apple's own photo-real product renders for AirPods, read from the
/// system at runtime — the pictures System Settings' headphone panes use.
///
/// Found 2026-09-28 under `HeadphoneAssets.framework`: 996×702 PNGs with
/// transparent backgrounds, one per model (`B788` AirPods Pro 3, `B698`
/// AirPods Pro 2, `B768` AirPods 4, `B868` AirPods 3, `B515d` AirPods Max
/// in five colourways). Nothing is copied into Ledge's bundle: the files
/// are read from the running system, so a macOS update that moves or drops
/// them simply makes `load` return `nil` and the ear falls back to the
/// SF Symbol. Personal-use only, like the rest of the app (spec §1).
///
/// CoreAudio names a device by what the user called it ("Dede's AirPods
/// Pro"), which does not say which generation, so the mapping goes by
/// product family and prefers the newest render; siblings look alike at
/// 24pt anyway. Colour is unknown too: AirPods Max gets the darkest
/// colourway, which reads best on the black island.
public enum DeviceArtwork {
    public static let resourceRoot =
        "/System/Library/PrivateFrameworks/HeadphoneAssets.framework/Versions/A/Resources"

    /// Ordered candidates, most preferred first. Empty for anything that
    /// is not an AirPods product.
    public static func candidateFiles(forDeviceNamed name: String) -> [String] {
        let lower = name.lowercased()
        if lower.contains("airpods max") {
            return ["B515d-Translate-CL18.ca/assets/AirPodsMax1-2_CL-18_Translate_v14.png"]
        }
        if lower.contains("airpods pro") {
            return [
                "B788_Translate.ca/assets/AirPodsPro1-3_translate.png",
                "B698_Translate.ca/assets/AirPodsPro1-2_translator_996x702.png",
            ]
        }
        if lower.contains("airpods") {
            return [
                "B768_Translate.ca/assets/AirPods1-4_translator_996x702.png",
                "B868_Translate.ca/assets/Airpods3-7_CL-0_Translate.png",
            ]
        }
        return []
    }

    /// PNG bytes of the first candidate that exists on this system.
    public static func load(forDeviceNamed name: String, root: String = resourceRoot) -> Data? {
        for file in candidateFiles(forDeviceNamed: name) {
            let url = URL(fileURLWithPath: root).appendingPathComponent(file)
            if let data = try? Data(contentsOf: url), !data.isEmpty { return data }
        }
        return nil
    }
}
