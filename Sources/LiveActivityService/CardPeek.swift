import AppKit
import OSLog
@preconcurrency import ScreenCaptureKit

/// The one picture taken of an iPhone Live Activity's card (2026-10-01):
/// its crests. Everything else the card says is read as text — see
/// `CardReader` — but a crest is a picture, and a picture can only be
/// taken while the card is still on screen, so it is taken once, as the
/// card opens, before the window is parked out of sight.
public enum CardCropper {
    /// The card's opaque bounds in a window capture that has transparent
    /// margins (the popover's shadow is faint; `threshold` ignores it).
    public static func opaqueBounds(of image: CGImage, threshold: UInt8 = 200) -> CGRect? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] >= threshold {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // The bitmap's first row in memory is the image's top row, so these
        // are already the top-down coordinates `cropping(to:)` expects.
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// A crest cut from the captured card at the rectangle the card's own
    /// Accessibility tree gives for it, drawn round on transparency —
    /// exact, where guessing at fractions left the badges ragged
    /// (2026-10-01).
    public static func crest(from card: CGImage, at rect: CGRect, scale: CGFloat, size: CGFloat) -> PillImage? {
        let whole = CGRect(x: 0, y: 0, width: card.width, height: card.height)
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                            width: rect.width * scale, height: rect.height * scale).integral.intersection(whole)
        guard pixels.width >= 2, pixels.height >= 2, let cut = card.cropping(to: pixels) else { return nil }
        let side = Int((size * scale).rounded())
        guard side > 1,
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        context.interpolationQuality = .high
        context.addEllipse(in: CGRect(x: 0, y: 0, width: side, height: side))
        context.clip()
        context.draw(cut, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return nil }
        return PillImage(png: png, size: CGSize(width: size, height: size))
    }
}

/// Finds and captures the card's window while it is up.
enum CardPeek {
    static let timeout: Duration = .milliseconds(800)
    static let step: Duration = .milliseconds(30)

    /// The card's window: `MenuBarAgent`'s, on screen, hanging below the
    /// pill and wider than it.
    static func popover(below pill: CGRect) async -> SCWindow? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return nil }
        return content.windows.first { window in
            window.owningApplication?.bundleIdentifier == PillLocator.host
                && window.frame.minY >= pill.maxY - 4 && window.frame.minY < pill.maxY + 40
                && window.frame.width > pill.width * 2 && window.frame.height > 40
        }
    }

    static func capture(_ window: SCWindow, scale: CGFloat) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
