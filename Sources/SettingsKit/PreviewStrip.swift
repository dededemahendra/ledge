import SwiftUI
import AppKit
import NotchKit

/// The live preview at the top of a Settings pane (2026-10-22, user's
/// call): a strip of the user's desktop with the real island on it, run by
/// a private `NotchController` that `PreviewStage` puts into the
/// director's scene. Fenced: nothing in it takes a click and its
/// controller's intents go nowhere. Its clock runs only while it is on
/// screen.
public struct PreviewStrip: View {
    public static let shortHeight: CGFloat = 104
    public static let tallHeight: CGFloat = 214

    let director: PreviewDirector
    let height: CGFloat
    let options: PreviewStage.Options
    let wallpaper: NSImage?
    let content: () -> PreviewContent

    // Spelled-out State: no macro plugin on this toolchain.
    private var _controller: State<NotchController>
    private var controller: NotchController { _controller.wrappedValue }
    private var _caption: State<PreviewCaption?>
    private var caption: PreviewCaption? {
        get { _caption.wrappedValue }
        nonmutating set { _caption.wrappedValue = newValue }
    }

    public init(director: PreviewDirector, height: CGFloat, options: PreviewStage.Options = .init(),
                metrics: NotchMetrics? = nil, wallpaper: NSImage? = PreviewStrip.desktopPicture(),
                content: @escaping () -> PreviewContent) {
        self.director = director
        self.height = height
        self.options = options
        self.wallpaper = wallpaper
        self.content = content
        let controller = Self.makeController(metrics: metrics ?? Self.hostMetrics())
        // The first scene goes on now, so the strip is right on its first
        // frame (and in a headless render, which runs no `onChange`).
        let first = director.staged.map { PreviewStage.apply($0, content: content(), to: controller, options: options) }
        _controller = State(initialValue: controller)
        _caption = State(initialValue: first)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            backdrop
            Rectangle()
                .fill(Color.black.opacity(0.3))
                .frame(height: 18)
            if director.staged == .lockScreen {
                Text(Date.now, format: .dateTime.hour().minute())
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.top, 46)
            }
            // The island's own fixed canvas, centred and cropped by the strip.
            NotchRootView(controller: controller)
                .frame(width: NotchMetrics.canvasSize.width, height: NotchMetrics.canvasSize.height, alignment: .top)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            if let caption {
                Text(caption.text + (director.isShowingOff ? " · Off" : ""))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: director.staged) { _, staged in show(staged) }
        .onChange(of: director.replays) { _, _ in show(director.staged) }
        .onChange(of: options) { _, _ in show(director.staged) }
        .task {
            while !Task.isCancelled {
                director.tick(at: Date())
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    @ViewBuilder private var backdrop: some View {
        if let wallpaper {
            Image(nsImage: wallpaper)
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                .overlay(Color.black.opacity(director.staged == .lockScreen ? 0.35 : 0))
        } else {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.43, blue: 0.55), Color(red: 0.24, green: 0.25, blue: 0.62),
                         Color(red: 0.64, green: 0.27, blue: 0.54)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private func show(_ staged: PreviewScene?) {
        guard let staged else {
            PreviewStage.reset(controller)
            caption = nil
            return
        }
        caption = PreviewStage.apply(staged, content: content(), to: controller, options: options)
    }

    /// The island's size on this Mac: the notch, or the pill without one.
    static func hostMetrics() -> NotchMetrics {
        let placement = NSScreen.islandHost?.placement
        let size = placement?.notchRect.size ?? CGSize(width: 179, height: 32)
        return NotchMetrics(notchRect: CGRect(origin: .zero, size: size), isVirtual: placement?.isVirtual ?? false)
    }

    static func makeController(metrics: NotchMetrics) -> NotchController {
        let controller = NotchController(metrics: metrics, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        controller.onIntent = nil
        return controller
    }

    private static var picture: (url: URL, image: NSImage?)?

    /// The desktop picture behind the island's screen, read once per
    /// picture; `nil` when there is none to read (the strip then draws a
    /// gradient).
    public static func desktopPicture() -> NSImage? {
        guard let screen = NSScreen.islandHost?.screen ?? NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        if let picture, picture.url == url { return picture.image }
        let image = NSImage(contentsOf: url)
        picture = (url, image)
        return image
    }
}
