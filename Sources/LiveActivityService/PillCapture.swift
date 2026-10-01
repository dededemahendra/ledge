import AppKit
import OSLog
@preconcurrency import ScreenCaptureKit

/// One frame of the pill: its pixels as PNG and its size in points.
public struct PillFrame: Sendable, Equatable {
    /// The pill's content on transparency — see `PillKeyer`.
    public let png: Data
    public let size: CGSize
    /// `false` for a pill with nothing drawn in it.
    public let hasContent: Bool

    public init(png: Data, size: CGSize, hasContent: Bool = true) {
        self.png = png
        self.size = size
        self.hasContent = hasContent
    }
}

/// Pure geometry for the capture (tested): the display-relative source
/// rectangle and the pixel size at the screen's scale.
public enum CaptureGeometry {
    /// `frame` and `display` both in screen points, top-left origin.
    public static func sourceRect(for frame: CGRect, inDisplay display: CGRect) -> CGRect {
        CGRect(x: frame.minX - display.minX, y: frame.minY - display.minY, width: frame.width, height: frame.height)
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
    private var lastPNG: Data?
    private var loop: Task<Void, Never>?

    init(onFrame: @escaping @Sendable (PillFrame) -> Void) {
        self.onFrame = onFrame
    }

    /// Starts (or moves) the capture over `frame`, screen points top-left.
    func capture(frame: CGRect, scale: CGFloat) async throws {
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
        lastPNG = nil
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
        lastPNG = nil
    }

    private func shoot() async {
        guard let filter, let configuration else { return }
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            guard let keyed = PillKeyer.key(image),
                  let png = NSBitmapImageRep(cgImage: keyed.image).representation(using: .png, properties: [:]), png != lastPNG
            else { return }
            lastPNG = png
            onFrame(PillFrame(png: png, size: pointSize, hasContent: keyed.hasContent))
        } catch {
            Self.log.notice("live activity: screenshot failed — \(error.localizedDescription, privacy: .public)")
        }
    }

    enum CaptureError: Error { case noDisplay }
}
