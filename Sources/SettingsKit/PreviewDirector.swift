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
    /// How long a row stays pointed at after the pointer leaves it, so crossing the gap to the next row does not flash the cycle (2026-10-22).
    public static let leaveGrace: TimeInterval = 0.2

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
    /// Bumped when a switch is turned on for the scene already showing, so
    /// the strip plays it again from the start (2026-10-22).
    public private(set) var replays = 0
    /// `staged`, read without observing it (2026-10-22): a strip reads this
    /// for its first frame, so the pane that builds the strip is not drawn
    /// again with every scene change.
    @ObservationIgnored public private(set) var stagedUntracked: PreviewScene?

    @ObservationIgnored private var pointed: PreviewScene?
    @ObservationIgnored private var leaving: (scene: PreviewScene, at: Date)?
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
        leaving = nil
        pointed = scene
        resolve()
    }

    /// The pointer left `scene`'s row. A leave that arrives after the next
    /// row's enter changes nothing.
    public func leave(_ scene: PreviewScene, now: Date = Date()) {
        self.now = now
        guard pointed == scene else { return }
        leaving = (scene, now)
    }

    public func switchedOn(_ scene: PreviewScene, now: Date = Date()) {
        self.now = now
        let before = self.scene
        playing = (scene, now + Self.playDuration)
        resolve()
        // Already showing (the row pointed at, or in the cycle): play it
        // again from the start, two-step hover included.
        if before == scene, self.scene == scene {
            sceneSince = now
            replays += 1
            resolve()
        }
    }

    public func tick(at now: Date) {
        self.now = now
        if let leaving, now >= leaving.at + Self.leaveGrace {
            self.leaving = nil
            pointed = nil
            nextCycle = now + Self.cycleInterval
        }
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
        stagedUntracked = nextStaged
    }
}
