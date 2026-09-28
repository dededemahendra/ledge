import Foundation
import ActivityKit
import OSLog

/// Output-route changes as one stream of `DeviceEvent`s. Thin, like every
/// other service: the judgement is in `DeviceEventDeriver`. No permission.
@MainActor
public final class DeviceService {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "device")

    public private(set) var availability: ServiceAvailability = .available

    private var deriver = DeviceEventDeriver()
    private var route: OutputRouteObserver?
    private var continuation: AsyncStream<DeviceEvent>.Continuation?

    public init() {}

    public func start() -> AsyncStream<DeviceEvent> {
        stop()   // idempotent, same shape as the other services

        return AsyncStream { continuation in
            self.continuation = continuation

            let route = OutputRouteObserver { [weak self] route in
                guard let self else { return }
                let battery = route.transport == .bluetooth
                    ? PeripheralBattery.percent(forDeviceNamed: route.name) : nil
                if let event = self.deriver.outputChanged(
                    uid: route.uid, name: route.name, transport: route.transport, batteryPercent: battery
                ) {
                    self.continuation?.yield(event)
                }
            }
            route.start()
            self.route = route
            Self.log.info("device service ready")

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
        }
    }

    public func stop() {
        route?.stop()
        route = nil
        continuation?.onTermination = nil
        continuation?.finish()
        continuation = nil
    }
}
