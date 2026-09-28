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
    private var catalog: OutputDeviceCatalog?
    private var continuation: AsyncStream<DeviceEvent>.Continuation?

    /// Every output-capable device, the default flagged — for the panel's
    /// output picker. Kept current by `OutputDeviceCatalog`.
    public private(set) var outputs: [OutputDevice] = []
    /// Fired on the main actor whenever `outputs` changes.
    public var onOutputsChange: (([OutputDevice]) -> Void)?

    /// Switches the default output. Fire-and-forget: the route observer
    /// reports the result the same way it reports any other change.
    public func setDefaultOutput(uid: String) {
        OutputDeviceCatalog.setDefaultOutput(uid: uid)
    }

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

            let catalog = OutputDeviceCatalog { [weak self] outputs in
                guard let self else { return }
                self.outputs = outputs
                self.onOutputsChange?(outputs)
            }
            catalog.start()
            self.catalog = catalog
            Self.log.info("device service ready")

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
        }
    }

    public func stop() {
        catalog?.stop()
        catalog = nil
        route?.stop()
        route = nil
        continuation?.onTermination = nil
        continuation?.finish()
        continuation = nil
    }
}
