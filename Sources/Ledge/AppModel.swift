import AppKit
import Foundation
import ActivityKit
import NotchKit
import PowerService
import OSLog

/// Consumes service streams, maintains the queue, drives the controller.
/// The only place where services and UI meet.
@MainActor
final class AppModel {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "model")

    private let presenter: NotchPresenter
    private let power = PowerService()

    private var queue = ActivityQueue()
    private var tasks: [Task<Void, Never>] = []
    private var pruneTimer: Timer?

    init(presenter: NotchPresenter) {
        self.presenter = presenter
    }

    var powerStatus: String { power.availability.statusText }

    func start() {
        let stream = power.start()
        tasks.append(Task { [weak self] in
            for await event in stream {
                self?.handle(event)
            }
        })

        // Expiry is driven here, not inside the queue, so the queue stays pure.
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.prune() }
        }
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        pruneTimer?.invalidate()
        pruneTimer = nil
        power.stop()
    }

    private func handle(_ event: PowerEvent) {
        queue.insert(
            ActivityRecord(
                id: ActivityKind.power.rawValue,
                kind: .power,
                insertedAt: Date(),
                ttl: ActivityKind.power.defaultTTL,
                title: event.activityTitle
            )
        )
        publish()
    }

    private func prune() {
        let before = queue.count
        queue.prune(at: Date(), hovered: presenter.controller.isHovered)
        if queue.count != before { publish() }
    }

    private func publish() {
        let display = queue.visible.map {
            NotchController.ActivityDisplay(id: $0.id, title: $0.title, detail: $0.detail)
        }
        // `setActivities` sets the count itself — do not also call
        // `setActivityCount`, or overflow gets counted twice.
        presenter.setActivities(display, overflow: queue.overflowCount)
    }
}
