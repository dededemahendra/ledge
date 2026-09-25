import Foundation
import Observation

public enum NotchState: Sendable, Equatable {
    case hidden
    case peek
    case activity
    case expanded
}

/// Single source of truth for what the island is doing.
///
/// Deliberately free of timers, AppKit and IO so every transition is testable.
/// Whoever owns this calls the mutators; TTL expiry lives in `ActivityQueue`.
@MainActor
@Observable
public final class NotchController {
    public private(set) var state: NotchState = .hidden
    public private(set) var isHovered = false
    public private(set) var activityCount = 0

    public var metrics: NotchMetrics
    public let reduceMotion: Bool

    public init(metrics: NotchMetrics, reduceMotion: Bool = false) {
        self.metrics = metrics
        self.reduceMotion = reduceMotion
    }

    public var isVisible: Bool { state != .hidden }

    public var parameters: NotchShapeParameters {
        switch state {
        case .hidden:
            return metrics.collapsed
        case .peek:
            return metrics.peek
        case .activity:
            return activityCount >= 2 ? metrics.twoActivities : metrics.oneActivity
        case .expanded:
            return metrics.expanded
        }
    }

    public func setHovered(_ hovered: Bool) {
        isHovered = hovered
        recomputeState()
    }

    public func click() {
        state = .expanded
    }

    public func dismiss() {
        guard state == .expanded else { return }
        state = .hidden          // recomputeState restores peek/activity if warranted
        recomputeState()
    }

    public func setActivityCount(_ count: Int) {
        activityCount = max(0, count)
        recomputeState()
    }

    /// An open panel outranks everything; otherwise activities outrank hover,
    /// and hover outranks nothing at all.
    private func recomputeState() {
        if state == .expanded { return }
        if activityCount > 0 {
            state = .activity
        } else if isHovered {
            state = .peek
        } else {
            state = .hidden
        }
    }
}
