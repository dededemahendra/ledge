import AppKit
import SwiftUI

/// The expanded card's translucent material — desktop blur sampled from
/// behind the (transparent) panel window, so the card reads as glass rather
/// than a flat opaque slab.
///
/// Two things worth knowing before touching this:
/// - `ImageRenderer` renders `NSViewRepresentable` content as EMPTY, so this
///   view contributes nothing in `NotchRenderTests`. That is why the island's
///   black base fill stays in place underneath (at reduced opacity when
///   expanded) rather than being replaced: the silhouette the render tests
///   pin — and the bezel blend at the top edge — both come from the fill,
///   never from this material.
/// - `.behindWindow` samples the DESKTOP, not in-window siblings, which is
///   the effect wanted here; `.withinWindow` would blur our own black fill
///   into itself and read as nothing.
struct VibrancyBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
