import Foundation
import Observation

/// Decides which scene a Settings pane's strip shows (2026-10-22): the row
/// the pointer rests on; a switch just turned on, once; or, at rest, the
/// pane's switched-on scenes in turn. Clock-fed, so it is testable; the
/// strip calls `tick(at:)` four times a second while it is on screen.
@MainActor
@Observable
public final class PreviewDirector {
    public static let cycleInterval: TimeInterval = 2.5
    public static let playDuration: TimeInterval = 3

    /// The pane's scenes, in row order.
    public let scenes: [PreviewScene]
    @ObservationIgnored private let isOn: @MainActor (PreviewScene) -> Bool

    /// General › Open the island on hover: how long the hover scene shows
    /// now playing before the card opens.
    public var hoverDwell: TimeInterval = 0.2

    /// The row the strip is about.
    public private(set) var scene: PreviewScene?
    /// What the strip puts on the island now: `scene`, except that the
    /// hover scene is now playing until `hoverDwell` has passed.
    public private(set) var staged: PreviewScene?

    @ObservationIgnored private var pointed: PreviewScene?
    @ObservationIgnored private var playing: (scene: PreviewScene, until: Date)?
    @ObservationIgnored private var cycleIndex = 0
    @ObservationIgnored private var nextCycle: Date?
    @ObservationIgnored private var sceneSince: Date
    @ObservationIgnored private var now: Date

    public init(scenes: [PreviewScene], isOn: @escaping @MainActor (PreviewScene) -> Bool, now: Date = Date()) {
        self.scenes = scenes
        self.isOn = isOn
        self.now = now
        sceneSince = now
        resolve()
    }

    /// The scene showing belongs to an option that is switched off.
    public var isShowingOff: Bool {
        scene.map { !isOn($0) } ?? false
    }

    public func point(at scene: PreviewScene, now: Date = Date()) {
        self.now = now
        pointed = scene
        resolve()
    }

    /// The pointer left `scene`'s row. A leave that arrives after the next
    /// row's enter changes nothing.
    public func leave(_ scene: PreviewScene, now: Date = Date()) {
        self.now = now
        guard pointed == scene else { return }
        pointed = nil
        nextCycle = now + Self.cycleInterval
        resolve()
    }

    public func switchedOn(_ scene: PreviewScene, now: Date = Date()) {
        self.now = now
        playing = (scene, now + Self.playDuration)
        resolve()
    }

    public func tick(at now: Date) {
        self.now = now
        if let playing, now >= playing.until {
            self.playing = nil
            nextCycle = now + Self.cycleInterval
        }
        if pointed == nil, playing == nil {
            if let due = nextCycle {
                if now >= due {
                    cycleIndex += 1
                    nextCycle = now + Self.cycleInterval
                }
            } else {
                nextCycle = now + Self.cycleInterval
            }
        }
        resolve()
    }

    private func resolve() {
        let next: PreviewScene?
        if let pointed {
            next = pointed
        } else if let playing {
            next = playing.scene
        } else {
            let on = scenes.filter { isOn($0) }
            next = on.isEmpty ? nil : on[cycleIndex % on.count]
        }
        if next != scene {
            scene = next
            sceneSince = now
        }
        let nextStaged = (scene == .hoverCard && now < sceneSince + hoverDwell) ? .nowPlaying : scene
        if nextStaged != staged { staged = nextStaged }
    }
}
