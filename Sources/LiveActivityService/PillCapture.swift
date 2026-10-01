import AppKit
import CoreImage
import OSLog
@preconcurrency import ScreenCaptureKit

/// One frame of the pill: its pixels as PNG and its size in points.
public struct PillFrame: Sendable, Equatable {
    public let png: Data
    public let size: CGSize

    public init(png: Data, size: CGSize) {
        self.png = png
        self.size = size
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

/// The pill's pixels, live: a ScreenCaptureKit stream over just its
/// rectangle of the display at the screen's own scale, at most ten
/// frames a second and only when the pixels change — 46×24 pt is some
/// four thousand pixels, nothing measurable. Needs the Screen Recording
/// grant; this app's own windows are excluded from the capture.
final class PillCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "live-activity")

    private let queue = DispatchQueue(label: "com.dedemahendra.ledge.pill-capture")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let onFrame: @Sendable (PillFrame) -> Void
    // Touched on `queue` only.
    private var stream: SCStream?
    private var lastPNG: Data?
    private var pointSize: CGSize = .zero

    init(onFrame: @escaping @Sendable (PillFrame) -> Void) {
        self.onFrame = onFrame
    }

    /// Starts (or moves) the stream over `frame`, screen points top-left.
    func capture(frame: CGRect, scale: CGFloat) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.frame.contains(frame.origin) }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CaptureGeometry.sourceRect(for: frame, inDisplay: display.frame)
        let pixels = CaptureGeometry.pixelSize(for: frame, scale: scale)
        configuration.width = pixels.width
        configuration.height = pixels.height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.queueDepth = 3
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        let existing = queue.sync { () -> SCStream? in pointSize = frame.size; lastPNG = nil; return stream }
        if let existing {
            try await existing.updateContentFilter(filter)
            try await existing.updateConfiguration(configuration)
            return
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        queue.sync { self.stream = stream }
    }

    func stop() async {
        let stream = queue.sync { () -> SCStream? in let s = self.stream; self.stream = nil; lastPNG = nil; return s }
        guard let stream else { return }
        try? await stream.stopCapture()
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: status) == .complete,
              let pixels = sampleBuffer.imageBuffer
        else { return }
        let image = CIImage(cvPixelBuffer: pixels)
        guard let cgImage = context.createCGImage(image, from: image.extent),
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        else { return }
        // Already on `queue` (the sample handler queue).
        guard png != lastPNG else { return }
        lastPNG = png
        onFrame(PillFrame(png: png, size: pointSize))
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Self.log.notice("live activity: capture stopped — \(error.localizedDescription, privacy: .public)")
        queue.async { [self] in
            if self.stream === stream { self.stream = nil }
        }
    }

    enum CaptureError: Error { case noDisplay }
}
