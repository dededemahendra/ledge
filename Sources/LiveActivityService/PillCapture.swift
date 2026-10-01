import AppKit
import OSLog
@preconcurrency import ScreenCaptureKit

/// Pixels on transparency (see `PillKeyer`) and their size in points.
public struct PillImage: Sendable, Equatable {
    public let png: Data
    public let size: CGSize
    /// `false` when nothing is drawn in it.
    public let hasContent: Bool

    public init(png: Data, size: CGSize, hasContent: Bool = true) {
        self.png = png
        self.size = size
        self.hasContent = hasContent
    }
}

/// One frame of the pill: the whole, and its two compact slots when
/// Accessibility reports them — the leading and trailing views, to go
/// either side of the notch the way the phone's island splits them.
public struct PillFrame: Sendable, Equatable {
    public let whole: PillImage
    public let leading: PillImage?
    public let trailing: PillImage?

    public init(whole: PillImage, leading: PillImage? = nil, trailing: PillImage? = nil) {
        self.whole = whole
        self.leading = leading
        self.trailing = trailing
    }
}

/// Pure geometry for the capture (tested): the display-relative source
/// rectangle and the pixel size at the screen's scale.
public enum CaptureGeometry {
    /// `frame` and `display` both in screen points, top-left origin.
    public static func sourceRect(for frame: CGRect, inDisplay display: CGRect) -> CGRect {
        CGRect(x: frame.minX - display.minX, y: frame.minY - display.minY, width: frame.width, height: frame.height)
    }

    /// A slot's rectangle in the pill's captured pixels: clipped to the
    /// pill (the slots' frames span the whole menu bar's height), moved
    /// to the pill's origin and scaled. `nil` when they do not meet.
    public static func sliceRect(slot: CGRect, inPill pill: CGRect, scale: CGFloat) -> CGRect? {
        let clipped = slot.intersection(pill)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        return CGRect(x: (clipped.minX - pill.minX) * scale, y: (clipped.minY - pill.minY) * scale,
                      width: clipped.width * scale, height: clipped.height * scale).integral
    }

    public static func pixelSize(for frame: CGRect, scale: CGFloat) -> (width: Int, height: Int) {
        (max(1, Int((frame.width * scale).rounded())), max(1, Int((frame.height * scale).rounded())))
    }

    /// The backing scale of the screen under a point given in top-left
    /// screen coordinates; AppKit's screens are bottom-left, so the point
    /// is flipped through the primary screen's height first.
    @MainActor
    public static func scale(at point: CGPoint) -> CGFloat {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let flipped = CGPoint(x: point.x, y: primaryHeight - point.y)
        return NSScreen.screens.first(where: { $0.frame.contains(flipped) })?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2
    }
}

/// The pill's pixels, live: a ScreenCaptureKit screenshot of just its
/// rectangle of the display at the screen's own scale, twice a second,
/// published only when the pixels change — 46×24 pt is some four
/// thousand pixels, nothing measurable. Screenshots, not a stream, on
/// purpose (2026-10-01): a stream plants the purple screen-recording
/// capsule in the menu bar for as long as the activity runs, shifting
/// the very pill under capture; single screenshots only light the
/// corner's privacy dot. Needs the Screen Recording grant; this app's
/// own windows are excluded.
actor PillCapture {
    private nonisolated static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "live-activity")
    static let interval: Duration = .milliseconds(500)

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let onFrame: @Sendable (PillFrame) -> Void
    private var filter: SCContentFilter?
    private var configuration: SCStreamConfiguration?
    private var pointSize: CGSize = .zero
    private var slices: [CGRect] = []
    private var scale: CGFloat = 2
    private var lastFrame: PillFrame?
    private var loop: Task<Void, Never>?

    init(onFrame: @escaping @Sendable (PillFrame) -> Void) {
        self.onFrame = onFrame
    }

    /// Starts (or moves) the capture over `frame`, screen points top-left.
    func capture(frame: CGRect, slots: [CGRect] = [], scale: CGFloat) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.frame.contains(frame.origin) }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CaptureGeometry.sourceRect(for: frame, inDisplay: display.frame)
        let pixels = CaptureGeometry.pixelSize(for: frame, scale: scale)
        configuration.width = pixels.width
        configuration.height = pixels.height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        self.configuration = configuration
        pointSize = frame.size
        self.scale = scale
        slices = slots.compactMap { CaptureGeometry.sliceRect(slot: $0, inPill: frame, scale: scale) }
        lastFrame = nil
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.shoot()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        lastFrame = nil
    }

    private func shoot() async {
        guard let filter, let configuration else { return }
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            guard let keyed = PillKeyer.key(image), let whole = encode(keyed.image, size: pointSize) else { return }
            var sides: [PillImage?] = [nil, nil]
            for (index, slice) in slices.prefix(2).enumerated() {
                guard let cropped = keyed.image.cropping(to: slice) else { continue }
                sides[index] = encode(cropped, size: CGSize(width: slice.width / scale, height: slice.height / scale))
            }
            let frame = PillFrame(whole: whole, leading: sides[0], trailing: sides[1])
            guard frame != lastFrame else { return }
            lastFrame = frame
            onFrame(frame)
        } catch {
            Self.log.notice("live activity: screenshot failed — \(error.localizedDescription, privacy: .public)")
        }
    }

    private func encode(_ image: CGImage, size: CGSize) -> PillImage? {
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
        return PillImage(png: png, size: size, hasContent: PillKeyer.hasContent(image))
    }

    enum CaptureError: Error { case noDisplay }
}
