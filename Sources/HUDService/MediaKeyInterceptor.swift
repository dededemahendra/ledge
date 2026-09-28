import AppKit
import ApplicationServices
import CoreAudio
import AudioToolbox
import ActivityKit
import OSLog

/// Reads and writes the default output device's level and mute — the
/// write-side twin of `VolumeObserver`, which only ever reads.
///
/// Prefers `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`, which
/// is what the system's own volume keys drive and which every device
/// exposes (Bluetooth and aggregate devices included); falls back to the
/// per-channel scalar on the main element. Looks the device up on every
/// call rather than caching it: a key press is rare, the lookup is one
/// property read, and it means an output-device switch can never leave
/// this writing to a device nobody hears.
@MainActor
final class VolumeControl {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "volume-control")

    struct Reading: Equatable {
        let level: Double
        let muted: Bool
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func defaultOutputDevice() -> AudioDeviceID? {
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }

    /// The one volume property this device lets us write, or `nil`.
    private func settableVolumeAddress(on device: AudioDeviceID) -> AudioObjectPropertyAddress? {
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar] {
            var addr = Self.address(selector)
            var settable = DarwinBoolean(false)
            if AudioObjectHasProperty(device, &addr),
               AudioObjectIsPropertySettable(device, &addr, &settable) == noErr, settable.boolValue {
                return addr
            }
        }
        return nil
    }

    func read() -> Reading? {
        guard let device = defaultOutputDevice(), var addr = settableVolumeAddress(on: device) else { return nil }
        var level = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &level) == noErr else { return nil }

        var muteAddr = Self.address(kAudioDevicePropertyMute)
        var muted = UInt32(0)
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &muteAddr) {
            _ = AudioObjectGetPropertyData(device, &muteAddr, 0, nil, &muteSize, &muted)
        }
        return Reading(level: Double(min(1, max(0, level))), muted: muted == 1)
    }

    @discardableResult
    func setLevel(_ level: Double) -> Bool {
        guard let device = defaultOutputDevice(), var addr = settableVolumeAddress(on: device) else { return false }
        var value = Float32(min(1, max(0, level)))
        let status = AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        if status != noErr { Self.log.error("set volume failed: \(status)") }
        return status == noErr
    }

    @discardableResult
    func setMuted(_ muted: Bool) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var addr = Self.address(kAudioDevicePropertyMute)
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &addr),
              AudioObjectIsPropertySettable(device, &addr, &settable) == noErr, settable.boolValue
        else { return false }
        var value = UInt32(muted ? 1 : 0)
        let status = AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        if status != noErr { Self.log.error("set mute failed: \(status)") }
        return status == noErr
    }
}

/// Takes the five volume/brightness keys away from the system so it never
/// draws its own overlay for them, and applies each press itself.
///
/// **Why this exists (2026-09-28).** On this macOS the stock volume and
/// brightness pill is no longer drawn by `OSDUIHelper` — it is a popover
/// owned by `MenuBarAgent`, the process that draws the entire menu bar
/// (verified with a window-list diff while pressing a volume key: the new
/// window's owner was `MenuBarAgent`, pid of `com.apple.MenuBarAgent`,
/// and that process owns exactly one other window, the 1470×33 menu bar
/// itself). `OSDSuppressor`'s SIGSTOP trick therefore no longer reaches
/// the overlay, and applying it to `MenuBarAgent` would freeze the whole
/// menu bar. The overlay is driven by the media-key HID event, not by the
/// value changing (a scripted `set volume` never shows it), so the one
/// reliable way to keep it off screen is to consume the key before the
/// system sees it — which is exactly why BetterDisplay, which intercepts
/// volume keys for DDC, hides the Tahoe volume pill as a side effect.
///
/// **Cost: Accessibility.** A filtering event tap on keyboard-class events
/// requires the process to be trusted for Accessibility. The spec's
/// `HUDService` was designed permission-free and observes VALUES, which
/// still holds — the observers stay the source of every HUD event, and
/// this class only changes who applies the key. Without the grant the tap
/// cannot be created; the keys then keep working through the system as
/// before, `availability` reports `.needsPermission`, and this retries
/// every couple of seconds so a grant made in System Settings takes
/// effect without a relaunch.
@MainActor
public final class MediaKeyInterceptor {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "media-keys")

    public private(set) var availability: ServiceAvailability = .unavailable(reason: "off")
    /// The level this interceptor just wrote for a brightness key. While
    /// the tap is active this is the ONLY source of brightness HUD events:
    /// it is instant (no 100ms poll), and it is certain — the display's own
    /// adjustments never come through here.
    public var onBrightnessApplied: ((Double) -> Void)?
    /// Called on the main actor whenever `availability` changes, so the
    /// menu bar row can follow a grant made while the app is running.
    public var onAvailabilityChange: ((ServiceAvailability) -> Void)?

    private let volume = VolumeControl()
    private let bridge = DisplayServicesBridge()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryTimer: Timer?

    public init() {}

    public var isActive: Bool { tap != nil }

    /// `prompt`: show the system's Accessibility prompt if not yet trusted.
    /// Shown once per `start`, never on the retry path — a user who said no
    /// should not be nagged every two seconds.
    public func start(prompt: Bool) {
        guard tap == nil else { return }
        if !AXIsProcessTrusted(), prompt {
            // The literal key, not `kAXTrustedCheckOptionPrompt`: that global
            // is a `var` in the SDK and Swift 6 refuses it as shared mutable
            // state. Its value is this string.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if !installTap() {
            setAvailability(.needsPermission("Accessibility"))
            retryTimer?.invalidate()
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, AXIsProcessTrusted(), self.installTap() else { return }
                    self.retryTimer?.invalidate()
                    self.retryTimer = nil
                }
            }
            // `.common`, like every other timer in this app that must keep
            // ticking while a menu is open — the exact moment a user is
            // likely to be granting the permission from the menu bar.
            RunLoop.main.add(timer, forMode: .common)
            retryTimer = timer
        }
    }

    public func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        source = nil
        tap = nil
        setAvailability(.unavailable(reason: "off"))
    }

    private func setAvailability(_ new: ServiceAvailability) {
        guard new != availability else { return }
        availability = new
        onAvailabilityChange?(new)
    }

    private func installTap() -> Bool {
        let mask = CGEventMask(1) << CGEventMask(MediaKeyDecoder.systemDefinedEventType)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
            // Decode BEFORE hopping onto the actor: `CGEvent` is not
            // `Sendable`, so only plain values cross into the closure.
            var decoded: (press: MediaKeyPress, fine: Bool)?
            if type.rawValue == MediaKeyDecoder.systemDefinedEventType,
               let nsEvent = NSEvent(cgEvent: event),
               let press = MediaKeyDecoder.decode(subtype: nsEvent.subtype.rawValue, data1: nsEvent.data1) {
                decoded = (press, nsEvent.modifierFlags.isSuperset(of: [.shift, .option]))
            }
            // The tap's run loop source lives on the main run loop (below),
            // so this callback is always delivered on the main thread.
            let consumed = MainActor.assumeIsolated {
                interceptor.handle(type: type, decoded: decoded)
            }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Self.log.info("media-key tap unavailable (Accessibility not granted)")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        setAvailability(.available)
        Self.log.info("media-key tap installed; system HUD replaced")
        return true
    }

    /// Returns `true` when the event was consumed.
    private func handle(type: CGEventType, decoded: (press: MediaKeyPress, fine: Bool)?) -> Bool {
        // The system disables a tap that stalls; re-arm and let the event go.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard let (press, fine) = decoded else { return false }

        // Key-up of a key whose key-down we consumed must be consumed too,
        // or the system sees an orphaned release.
        guard press.isDown else { return true }
        return apply(press.key, fine: fine)
    }

    /// `false` hands the key back to the system (which will then show its
    /// own overlay) — better than a dead key when a device has no volume
    /// control or brightness cannot be written.
    private func apply(_ key: MediaKey, fine: Bool) -> Bool {
        switch key {
        case .volumeUp, .volumeDown:
            guard let current = volume.read() else { return false }
            let next = MediaKeyStepper.step(current.level, up: key == .volumeUp, fine: fine)
            guard volume.setLevel(next) else { return false }
            // The system's keys un-mute on volume-up; mirror that.
            if key == .volumeUp, current.muted { volume.setMuted(false) }
            return true
        case .mute:
            guard let current = volume.read() else { return false }
            return volume.setMuted(!current.muted)
        case .brightnessUp, .brightnessDown:
            let display = CGMainDisplayID()
            guard let bridge, let current = bridge.brightness(for: display) else { return false }
            let next = MediaKeyStepper.step(current, up: key == .brightnessUp, fine: fine)
            guard bridge.setBrightness(next, for: display) else { return false }
            onBrightnessApplied?(next)
            return true
        }
    }
}
