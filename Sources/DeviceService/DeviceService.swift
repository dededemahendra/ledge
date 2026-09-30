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
                guard self.deriver.outputChanged(uid: route.uid, name: route.name, transport: route.transport, battery: nil) != nil
                else { return }
                guard route.transport == .bluetooth else {
                    self.continuation?.yield(.outputChanged(name: route.name, transport: route.transport, battery: nil))
                    return
                }
                // Apple and Beats: the HID service, at once. Anything else:
                // the profiler, off the main actor, capped at three seconds
                // so the blip is never held hostage by a slow child process.
                if let levels = PeripheralBattery.levels(forDeviceNamed: route.name) {
                    self.continuation?.yield(.outputChanged(name: route.name, transport: .bluetooth, battery: levels))
                    return
                }
                let name = route.name
                Task { @MainActor [weak self] in
                    let levels = await Self.profiledLevels(forDeviceNamed: name)
                    self?.continuation?.yield(.outputChanged(name: name, transport: .bluetooth, battery: levels))
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

    /// The profiler's levels for `name`, or `nil` after three seconds.
    static func profiledLevels(forDeviceNamed name: String) async -> PeripheralLevels? {
        await withTaskGroup(of: PeripheralLevels?.self) { group in
            group.addTask {
                let devices = await BluetoothProfile.run()
                let wanted = name.lowercased()
                return devices.first { $0.name.lowercased() == wanted && $0.levels != nil }?.levels
                    ?? devices.first { PeripheralBattery.matches(candidate: $0.name.lowercased(), wanted: wanted) && $0.levels != nil }?.levels
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
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
