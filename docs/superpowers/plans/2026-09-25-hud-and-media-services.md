# HUD and Media Services — Implementation Plan (Phases 3–4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the stock macOS volume and brightness overlays with notch HUDs, and show live now-playing metadata with working playback controls — turning the island from a demo into the app that is actually used every day.

**Architecture:** Same one-directional flow as Phases 0–2. Every platform integration is split into a **pure deriver** (all the judgement, fully unit-tested) and a **thin shell** (CoreAudio listeners, `dlopen`'d private symbols, a supervised subprocess). Volume and brightness are observed *by value*, not by tapping keys, so no permission is ever requested.

**Tech Stack:** Swift 6.4, SwiftPM, CoreAudio (`AudioObjectAddPropertyListenerBlock`), `DisplayServices` private framework via `dlopen`/`dlsym`, `NSRunningApplication` + POSIX signals, `Foundation.Process` + NDJSON, `mediaremote-adapter` (BSD-3-Clause, vendored), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-25-notch-companion-design.md`

**Prerequisite:** `docs/superpowers/plans/2026-09-25-notch-shell-and-first-activity.md` complete — `NotchKit`, `ActivityKit`, `PowerService`, `AppModel` and the `Makefile` all exist and `swift test` passes.

## Global Constraints

Everything in the Phases 0–2 plan's Global Constraints still applies — including this one, which is easy to miss and affects every step below:

- **Run tests through `make test`, never bare `swift test`.** Where a step says `swift test --filter SomeTests`, run `make test FILTER=SomeTests`; where it says `swift test`, run `make test`. Bare `swift test` fails intermittently (measured: 5/12 runs) because swift-testing's macro plugin lives in a `plugins/testing/` subdirectory that is not on the compiler's default plugin search path. The Makefile's `TESTFLAGS` supplies it and makes runs deterministic (12/12).

Additionally:

- **No permission is requested by any task in this plan.** Volume and brightness are observed by value. If an implementation finds itself needing Accessibility or Input Monitoring, stop and report rather than adding a prompt.
- Verified on this machine, use as given:
  - `DisplayServicesGetBrightness` has signature `(CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32`, returns `0` on success and writes `0...1`. Confirmed working via `dlopen` of `/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices`.
  - `DisplayServicesRegisterForBrightnessChangeNotifications` and `DisplayServicesCanChangeBrightness` both resolve via `dlsym`. **Their signatures are not verified** — Task 3 verifies before relying on them.
  - `OSDUIHelper` bundle id is `com.apple.OSDUIHelper`; it is a `gui/<uid>` LaunchAgent that is **not resident** (`active count = 0`) and launches on demand. A one-shot `SIGSTOP` at startup would silently do nothing.
  - `/usr/bin/perl` reports `Identifier=com.apple.perl`, which is what makes the media adapter work.
- Media adapter invocation is exactly:
  `/usr/bin/perl <abs path>/mediaremote-adapter.pl <abs path>/MediaRemoteAdapter.framework COMMAND`
  Paths **must be absolute**. The framework is **bundled but never linked against**.
- `stream` emits diffs **by default**: `{"type":"data","diff":Bool,"payload":{…}}`. When `diff` is true the payload holds only changed keys, and `null` means *that key vanished*.
- Adapter restart policy, from its README: clean exit or signal → restart with backoff; **non-zero exit is fatal, do not reinvoke.**
- Mandatory non-null payload keys: `bundleIdentifier`, `playing`, `title`. A `null` line means no media.
- Never log track titles, artists, or album names above `.debug`.

## Review Focus

Input classes the spec implies that no happy path exercises. Each has its test assigned to the owning task.

1. **The default audio device changes while the island is showing a volume HUD** (AirPods connect mid-adjustment) — the CoreAudio listener is bound to the *old* device and silently stops reporting. Volume changes must keep working. → Task 2.
2. **A device that exposes no per-channel volume scalar** (many Bluetooth and all aggregate devices) — reading `kAudioDevicePropertyVolumeScalar` fails, so the HUD must fall back to `VirtualMainVolume` rather than showing 0% or nothing. → Task 2.
3. **Ledge crashes or is force-quit while the stock OSD is suppressed** — `OSDUIHelper` stays `SIGSTOP`ped and the user's system HUD is dead until they reboot. Recovery must not depend on clean shutdown. → Task 4.
4. **The adapter emits a diff whose key is `null`** (track ends, artwork unloads, artist vanishes) — merging must *remove* the key, not store a literal null or keep the stale previous value. A stale title that never clears is the visible symptom. → Task 6.
5. **The adapter exits non-zero, or is missing from the bundle entirely** — the app must fall back cleanly and keep every other feature working, never retry-loop a fatal failure or block launch. → Task 7.

## File Structure

```
Sources/
  HUDService/
    HUDEvent.swift              PURE: event type + display formatting
    HUDEventDeriver.swift       PURE: readings → events, dedupe, coalesce
    VolumeObserver.swift        CoreAudio shell, rebinds on device change
    BrightnessObserver.swift    DisplayServices shell via dlopen
    OSDSuppressor.swift         NSRunningApplication + SIGSTOP/SIGCONT + recovery
    HUDService.swift            composes the three, exposes AsyncStream
  MediaService/
    MediaPayload.swift          PURE: adapter JSON keys → value type
    MediaStateMerger.swift      PURE: diff merging (Review Focus 4)
    MediaPosition.swift         PURE: local extrapolation from elapsed+timestamp
    RestartPolicy.swift         PURE: backoff + fatal-vs-transient decision
    AdapterLocator.swift        resolves bundled absolute paths, probes `test`
    MediaRemoteSource.swift     Process + NDJSON shell
    MediaCommand.swift          PURE: command → adapter argument
    MediaService.swift          composes, exposes AsyncStream + command sink
Resources/mediaremote-adapter/  vendored: mediaremote-adapter.pl,
                                MediaRemoteAdapter.framework,
                                MediaRemoteAdapterTestClient, LICENSE
Tests/
  HUDServiceTests/
  MediaServiceTests/
  MediaServiceTests/Fixtures/   real captured NDJSON
```

---

### Task 1: `HUDEvent` and `HUDEventDeriver`

**Files:**
- Create: `Sources/HUDService/HUDEvent.swift`
- Create: `Sources/HUDService/HUDEventDeriver.swift`
- Create: `Tests/HUDServiceTests/HUDEventDeriverTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `ActivityKit` (`ServiceAvailability`).
- Produces:
  - `enum HUDEvent: Sendable, Equatable` — `volume(level: Double, muted: Bool)`, `brightness(level: Double)`; `var activityTitle: String`; `var barFill: Double`; `var symbolName: String`; `var compactText: String`

`compactText` is **required, not decorative.** At one activity the island stays exactly
notch-height, so `detailRow` is gated off and `activityTitle` has nowhere to render —
the trailing ear is the only place a value can appear. A volume HUD that shows a
speaker glyph and no number fails at the one thing a volume HUD exists for. Plan A hit
this exact defect with power activities and it was invisible to all 81 tests, because
no test renders a view. Add to `HUDEvent`:

```swift
    /// Glanceable form for the trailing ear, which is the only place text can appear
    /// while a single activity holds the island at notch height. The ear is ~38pt
    /// wide, so this stays to a few characters.
    public var compactText: String {
        switch self {
        case .volume(_, true):            return "Muted"
        case .volume(let level, false):   return "\(Int((level * 100).rounded()))%"
        case .brightness(let level):      return "\(Int((level * 100).rounded()))%"
        }
    }
```

and pin all three cases in `HUDEventDeriverTests`, including that muted yields `"Muted"`
rather than a percentage.
  - `struct HUDEventDeriver: Sendable` — `static let minimumDelta: Double`; `mutating func volumeChanged(level: Double, muted: Bool) -> HUDEvent?`; `mutating func brightnessChanged(level: Double) -> HUDEvent?`; `mutating func reset()`

- [ ] **Step 1: Add the `HUDService` targets to `Package.swift`**

```swift
        .target(name: "HUDService", dependencies: ["ActivityKit"]),
        .testTarget(name: "HUDServiceTests", dependencies: ["HUDService"]),
```

Add `"HUDService"` to the `Ledge` executable target's `dependencies`.

- [ ] **Step 2: Write the failing tests**

Create `Tests/HUDServiceTests/HUDEventDeriverTests.swift`.

```swift
import Testing
@testable import HUDService

@Test func firstReadingEstablishesBaselineWithoutFiring() {
    var d = HUDEventDeriver()
    #expect(d.volumeChanged(level: 0.4, muted: false) == nil,
            "launching must not throw a HUD on screen")
    #expect(d.brightnessChanged(level: 0.6) == nil)
}

@Test func aRealChangeFires() {
    var d = HUDEventDeriver()
    _ = d.volumeChanged(level: 0.4, muted: false)
    #expect(d.volumeChanged(level: 0.5, muted: false) == .volume(level: 0.5, muted: false))
}

@Test func anIdenticalReadingDoesNotFire() {
    var d = HUDEventDeriver()
    _ = d.volumeChanged(level: 0.4, muted: false)
    #expect(d.volumeChanged(level: 0.4, muted: false) == nil)
}

@Test func imperceptibleJitterIsIgnored() {
    // CoreAudio reports floats; a device can report 0.400001 repeatedly.
    var d = HUDEventDeriver()
    _ = d.volumeChanged(level: 0.4, muted: false)
    #expect(d.volumeChanged(level: 0.4001, muted: false) == nil)
    #expect(d.volumeChanged(level: 0.4 + HUDEventDeriver.minimumDelta * 2, muted: false) != nil)
}

@Test func muteTogglingFiresEvenAtTheSameLevel() {
    var d = HUDEventDeriver()
    _ = d.volumeChanged(level: 0.4, muted: false)
    #expect(d.volumeChanged(level: 0.4, muted: true) == .volume(level: 0.4, muted: true))
    #expect(d.volumeChanged(level: 0.4, muted: false) == .volume(level: 0.4, muted: false))
}

@Test func brightnessAndVolumeTrackIndependently() {
    var d = HUDEventDeriver()
    _ = d.volumeChanged(level: 0.4, muted: false)
    _ = d.brightnessChanged(level: 0.6)
    #expect(d.brightnessChanged(level: 0.7) == .brightness(level: 0.7))
    #expect(d.volumeChanged(level: 0.4, muted: false) == nil)
}

@Test func levelsAreClampedToUnitRange() {
    var d = HUDEventDeriver()
    _ = d.volumeChanged(level: 0.5, muted: false)
    #expect(d.volumeChanged(level: 1.8, muted: false) == .volume(level: 1.0, muted: false))
    #expect(d.volumeChanged(level: -0.3, muted: false) == .volume(level: 0.0, muted: false))
}

// Review Focus 1: rebinding to a new device must not suppress the next real change.
@Test func resetForcesTheNextReadingToBeTreatedAsFresh() {
    var d = HUDEventDeriver()
    _ = d.volumeChanged(level: 0.4, muted: false)
    d.reset()
    #expect(d.volumeChanged(level: 0.4, muted: false) == nil,
            "reset re-baselines; the first post-reset reading is a baseline")
    #expect(d.volumeChanged(level: 0.55, muted: false) != nil)
}

@Test func displayPropertiesAreUseful() {
    #expect(HUDEvent.volume(level: 0.5, muted: false).barFill == 0.5)
    #expect(HUDEvent.volume(level: 0.5, muted: true).barFill == 0,
            "a muted bar must read as empty even at level 0.5")
    #expect(HUDEvent.volume(level: 0.5, muted: true).symbolName == "speaker.slash.fill")
    #expect(HUDEvent.volume(level: 0.0, muted: false).symbolName == "speaker.fill")
    #expect(HUDEvent.volume(level: 0.8, muted: false).symbolName == "speaker.wave.3.fill")
    #expect(HUDEvent.brightness(level: 0.25).barFill == 0.25)
    #expect(HUDEvent.brightness(level: 0.25).symbolName == "sun.max.fill")
    #expect(HUDEvent.volume(level: 0.5, muted: false).activityTitle == "Volume 50%")
    #expect(HUDEvent.volume(level: 0.5, muted: true).activityTitle == "Muted")
    #expect(HUDEvent.brightness(level: 0.06).activityTitle == "Brightness 6%")
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter HUDEventDeriverTests`
Expected: FAIL — `cannot find 'HUDEventDeriver' in scope`.

- [ ] **Step 4: Write `Sources/HUDService/HUDEvent.swift`**

```swift
import Foundation

public enum HUDEvent: Sendable, Equatable {
    case volume(level: Double, muted: Bool)
    case brightness(level: Double)

    /// Proportion of the bar to fill. Muted reads as empty regardless of level.
    public var barFill: Double {
        switch self {
        case .volume(let level, let muted): return muted ? 0 : level
        case .brightness(let level):        return level
        }
    }

    public var symbolName: String {
        switch self {
        case .volume(_, true):
            return "speaker.slash.fill"
        case .volume(let level, false):
            if level <= 0.001 { return "speaker.fill" }
            if level < 0.34 { return "speaker.wave.1.fill" }
            if level < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return "sun.max.fill"
        }
    }

    public var activityTitle: String {
        switch self {
        case .volume(_, true):
            return "Muted"
        case .volume(let level, false):
            return "Volume \(Int((level * 100).rounded()))%"
        case .brightness(let level):
            return "Brightness \(Int((level * 100).rounded()))%"
        }
    }
}
```

- [ ] **Step 5: Write `Sources/HUDService/HUDEventDeriver.swift`**

```swift
import Foundation

/// Turns raw volume and brightness readings into the changes worth showing.
///
/// Pure and deterministic. The CoreAudio and DisplayServices shells do nothing
/// but feed this and forward what comes back.
public struct HUDEventDeriver: Sendable {
    /// Below this, a change is imperceptible and almost certainly float jitter.
    public static let minimumDelta: Double = 0.005

    private var lastVolume: Double?
    private var lastMuted: Bool?
    private var lastBrightness: Double?

    public init() {}

    /// Discards the baseline so the next reading re-establishes it.
    /// Used when rebinding to a different audio device (Review Focus 1).
    public mutating func reset() {
        lastVolume = nil
        lastMuted = nil
        lastBrightness = nil
    }

    public mutating func volumeChanged(level: Double, muted: Bool) -> HUDEvent? {
        let clamped = min(1, max(0, level))
        defer { lastVolume = clamped; lastMuted = muted }

        guard let lastVolume, let lastMuted else { return nil }   // baseline
        let levelMoved = abs(clamped - lastVolume) >= Self.minimumDelta
        let muteToggled = muted != lastMuted
        guard levelMoved || muteToggled else { return nil }
        return .volume(level: clamped, muted: muted)
    }

    public mutating func brightnessChanged(level: Double) -> HUDEvent? {
        let clamped = min(1, max(0, level))
        defer { lastBrightness = clamped }

        guard let lastBrightness else { return nil }              // baseline
        guard abs(clamped - lastBrightness) >= Self.minimumDelta else { return nil }
        return .brightness(level: clamped)
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter HUDEventDeriverTests`
Expected: PASS — 9 tests.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/HUDService Tests/HUDServiceTests
git commit -m "feat: derive HUD events from volume and brightness readings"
```

---

### Task 2: `VolumeObserver` — CoreAudio by value, with device rebinding

**Files:**
- Create: `Sources/HUDService/VolumeObserver.swift`
- Create: `Tests/HUDServiceTests/VolumeReaderTests.swift`

**Interfaces:**
- Consumes: `HUDEventDeriver` (Task 1).
- Produces:
  - `struct VolumeReading: Sendable, Equatable` — `level: Double`, `muted: Bool`
  - `enum VolumeStrategy: Sendable, Equatable { case perChannelScalar, virtualMainVolume, unavailable }`
  - `static func VolumeObserver.strategy(hasScalar: Bool, hasVirtualMain: Bool) -> VolumeStrategy` (pure, tested)
  - `static func VolumeObserver.availability(for: VolumeStrategy) -> ServiceAvailability` (pure, tested)
  - `@MainActor final class VolumeObserver` — `init(onChange: @escaping (VolumeReading) -> Void)`, `func start()`, `func stop()`, `var availability: ServiceAvailability`

Review Focus 1 and 2 are pinned here. The device-selection logic is pure and tested; the listener plumbing is shell.

- [ ] **Step 1: Write the failing tests for the pure parts**

Create `Tests/HUDServiceTests/VolumeReaderTests.swift`.

```swift
import Testing
import CoreAudio
@testable import HUDService

// Review Focus 2: not every device exposes a per-channel scalar.
@Test func strategyPrefersPerChannelScalarWhenAvailable() {
    #expect(VolumeObserver.strategy(hasScalar: true, hasVirtualMain: true) == .perChannelScalar)
    #expect(VolumeObserver.strategy(hasScalar: true, hasVirtualMain: false) == .perChannelScalar)
}

@Test func strategyFallsBackToVirtualMainVolume() {
    #expect(VolumeObserver.strategy(hasScalar: false, hasVirtualMain: true) == .virtualMainVolume,
            "Bluetooth and aggregate devices commonly expose only this")
}

@Test func strategyReportsUnavailableWhenNeitherExists() {
    #expect(VolumeObserver.strategy(hasScalar: false, hasVirtualMain: false) == .unavailable)
}

@Test func readingsAreClampedAndComparable() {
    #expect(VolumeReading(level: 1.4, muted: false).level == 1.0)
    #expect(VolumeReading(level: -1, muted: false).level == 0.0)
    #expect(VolumeReading(level: 0.5, muted: false) != VolumeReading(level: 0.5, muted: true))
}

@Test func unavailableStrategyMapsToAnUnavailableService() {
    #expect(VolumeObserver.availability(for: .unavailable)
            == .unavailable(reason: "output device reports no volume control"))
    #expect(VolumeObserver.availability(for: .perChannelScalar) == .available)
    #expect(VolumeObserver.availability(for: .virtualMainVolume) == .available)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter VolumeReaderTests`
Expected: FAIL — `cannot find 'VolumeObserver' in scope`.

- [ ] **Step 3: Write `Sources/HUDService/VolumeObserver.swift`**

```swift
import Foundation
import CoreAudio
import ActivityKit
import OSLog

public struct VolumeReading: Sendable, Equatable {
    public let level: Double
    public let muted: Bool

    public init(level: Double, muted: Bool) {
        self.level = min(1, max(0, level))
        self.muted = muted
    }
}

/// Which CoreAudio property actually carries this device's volume.
public enum VolumeStrategy: Sendable, Equatable {
    case perChannelScalar
    case virtualMainVolume
    case unavailable
}

/// Observes the default output device's volume *by value*, so no permission is
/// needed and menu bar / Control Centre changes are caught as well as key presses.
///
/// Rebinds when the default output device changes — otherwise the listener stays
/// attached to a device nobody is using any more (Review Focus 1).
@MainActor
public final class VolumeObserver {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "volume")

    public private(set) var availability: ServiceAvailability = .available

    private let onChange: (VolumeReading) -> Void
    private var device = AudioDeviceID(kAudioObjectUnknown)
    private var strategy: VolumeStrategy = .unavailable
    private var deviceListenerInstalled = false
    private var volumeListenerInstalled = false

    public init(onChange: @escaping (VolumeReading) -> Void) {
        self.onChange = onChange
    }

    // MARK: - pure decisions

    public static func strategy(hasScalar: Bool, hasVirtualMain: Bool) -> VolumeStrategy {
        if hasScalar { return .perChannelScalar }
        if hasVirtualMain { return .virtualMainVolume }
        return .unavailable
    }

    public static func availability(for strategy: VolumeStrategy) -> ServiceAvailability {
        strategy == .unavailable
            ? .unavailable(reason: "output device reports no volume control")
            : .available
    }

    // MARK: - lifecycle

    public func start() {
        installDefaultDeviceListener()
        rebind()
    }

    public func stop() {
        removeVolumeListener()
        removeDefaultDeviceListener()
    }

    // MARK: - binding

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func installDefaultDeviceListener() {
        guard !deviceListenerInstalled else { return }
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main
        ) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.rebind() }
        }
        deviceListenerInstalled = (status == noErr)
        if status != noErr {
            Self.log.error("default-device listener failed: \(status)")
        }
    }

    private func removeDefaultDeviceListener() {
        deviceListenerInstalled = false
    }

    private func currentDefaultOutputDevice() -> AudioDeviceID? {
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id
        )
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }

    /// Re-points every listener at whatever the current default output device is.
    private func rebind() {
        removeVolumeListener()

        guard let id = currentDefaultOutputDevice() else {
            availability = .unavailable(reason: "no default output device")
            return
        }
        device = id

        var scalar = Self.address(
            kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput
        )
        var virtualMain = Self.address(
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: kAudioDevicePropertyScopeOutput
        )

        strategy = Self.strategy(
            hasScalar: AudioObjectHasProperty(device, &scalar),
            hasVirtualMain: AudioObjectHasProperty(device, &virtualMain)
        )
        availability = Self.availability(for: strategy)

        guard strategy != .unavailable else {
            Self.log.info("device \(self.device) exposes no volume control")
            return
        }

        var volumeAddress = strategy == .perChannelScalar ? scalar : virtualMain
        var muteAddress = Self.address(
            kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput
        )

        let handler: (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.emit() }
        }
        let volumeStatus = AudioObjectAddPropertyListenerBlock(
            device, &volumeAddress, DispatchQueue.main, handler
        )
        _ = AudioObjectAddPropertyListenerBlock(device, &muteAddress, DispatchQueue.main, handler)
        volumeListenerInstalled = (volumeStatus == noErr)

        // Re-baseline: the new device's level is not a change the user made.
        emit(isBaseline: true)
    }

    private func removeVolumeListener() {
        volumeListenerInstalled = false
    }

    // MARK: - reading

    private func read() -> VolumeReading? {
        guard strategy != .unavailable else { return nil }

        var addr = strategy == .perChannelScalar
            ? Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)
            : Self.address(
                kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                scope: kAudioDevicePropertyScopeOutput
              )

        var level = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &level) == noErr else {
            return nil
        }

        var muteAddr = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        var muted = UInt32(0)
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &muteAddr) {
            _ = AudioObjectGetPropertyData(device, &muteAddr, 0, nil, &muteSize, &muted)
        }

        return VolumeReading(level: Double(level), muted: muted == 1)
    }

    /// `isBaseline` readings still go through: the deriver decides whether the
    /// first reading after a rebind counts as a change.
    private func emit(isBaseline: Bool = false) {
        guard let reading = read() else { return }
        onChange(reading)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter VolumeReaderTests`
Expected: PASS — 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/HUDService/VolumeObserver.swift Tests/HUDServiceTests/VolumeReaderTests.swift
git commit -m "feat: observe output volume by value with device rebinding"
```

---

### Task 3: `BrightnessObserver` — private API with a verified fallback

**Files:**
- Create: `Sources/HUDService/BrightnessObserver.swift`
- Create: `Tests/HUDServiceTests/BrightnessObserverTests.swift`
- Create: `docs/private-api-notes.md`

**Interfaces:**
- Consumes: `HUDEventDeriver` (Task 1).
- Produces:
  - `enum BrightnessBackend: Sendable, Equatable { case notifications, polling, unavailable }`
  - `@MainActor final class BrightnessObserver` — `init(onChange: @escaping (Double) -> Void)`, `func start()`, `func stop()`, `var availability: ServiceAvailability`, `var backend: BrightnessBackend`
  - `struct DisplayServicesBridge: ~Copyable` — `init?()`, `func brightness(for: CGDirectDisplayID) -> Double?`, `var canRegisterForNotifications: Bool`

Verified already: `dlopen` of the framework succeeds, and
`DisplayServicesGetBrightness` has signature `(CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32`
returning `0` with a `0...1` value. The *notification callback* signature is
undocumented, so this task verifies it empirically before depending on it.

- [ ] **Step 1: Write the failing tests for the pure parts**

Create `Tests/HUDServiceTests/BrightnessObserverTests.swift`.

```swift
import Testing
import CoreGraphics
@testable import HUDService

@Test func bridgeLoadsAndReadsARealBrightnessValue() throws {
    // Verified working on the target machine: rc=0, value in 0...1.
    let bridge = try #require(DisplayServicesBridge(), "DisplayServices must dlopen")
    let level = try #require(bridge.brightness(for: CGMainDisplayID()))
    #expect(level >= 0 && level <= 1)
}

@Test func backendPrefersNotificationsWhenRegistrationWorks() {
    #expect(BrightnessObserver.backend(canRegister: true, canRead: true) == .notifications)
}

@Test func backendFallsBackToPollingWhenRegistrationIsUnusable() {
    #expect(BrightnessObserver.backend(canRegister: false, canRead: true) == .polling)
}

@Test func backendIsUnavailableWhenBrightnessCannotEvenBeRead() {
    #expect(BrightnessObserver.backend(canRegister: false, canRead: false) == .unavailable)
    #expect(BrightnessObserver.backend(canRegister: true, canRead: false) == .unavailable,
            "registration is worthless if the value cannot be read")
}

@Test func availabilityReflectsTheBackend() {
    #expect(BrightnessObserver.availability(for: .notifications) == .available)
    #expect(BrightnessObserver.availability(for: .polling) == .available)
    #expect(BrightnessObserver.availability(for: .unavailable)
            == .unavailable(reason: "DisplayServices brightness unavailable"))
}

@Test func pollIntervalIsCheapEnoughToJustify() {
    #expect(BrightnessObserver.pollInterval == 0.1)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter BrightnessObserverTests`
Expected: FAIL — `cannot find 'DisplayServicesBridge' in scope`.

- [ ] **Step 3: Write `Sources/HUDService/BrightnessObserver.swift`**

```swift
import Foundation
import CoreGraphics
import ActivityKit
import OSLog

/// Thin wrapper over the private `DisplayServices` framework.
///
/// Verified on macOS 27.0: the framework `dlopen`s and
/// `DisplayServicesGetBrightness(CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32`
/// returns 0 and writes a value in `0...1`.
public final class DisplayServicesBridge {
    private typealias GetBrightness =
        @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    private let handle: UnsafeMutableRawPointer
    private let getBrightness: GetBrightness
    public let canRegisterForNotifications: Bool

    public init?() {
        guard let handle = dlopen(Self.frameworkPath, RTLD_LAZY) else { return nil }
        guard let symbol = dlsym(handle, "DisplayServicesGetBrightness") else {
            dlclose(handle)
            return nil
        }
        self.handle = handle
        self.getBrightness = unsafeBitCast(symbol, to: GetBrightness.self)
        self.canRegisterForNotifications =
            dlsym(handle, "DisplayServicesRegisterForBrightnessChangeNotifications") != nil
    }

    public func brightness(for display: CGDirectDisplayID) -> Double? {
        var value: Float = 0
        guard getBrightness(display, &value) == 0 else { return nil }
        guard value >= 0, value <= 1 else { return nil }
        return Double(value)
    }
}

public enum BrightnessBackend: Sendable, Equatable {
    case notifications
    case polling
    case unavailable
}

/// Observes display brightness by value.
///
/// Prefers change notifications. Falls back to a cheap poll if the undocumented
/// callback signature turns out not to fire — a single C call at 10 Hz, which is
/// a deliberate, documented deviation from the spec's no-polling rule.
@MainActor
public final class BrightnessObserver {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "brightness")

    public static let pollInterval: TimeInterval = 0.1

    public private(set) var availability: ServiceAvailability = .available
    public private(set) var backend: BrightnessBackend = .unavailable

    private let onChange: (Double) -> Void
    private let bridge: DisplayServicesBridge?
    private var timer: Timer?
    private var lastSeen: Double?

    public init(onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        self.bridge = DisplayServicesBridge()
    }

    // MARK: - pure decisions

    public static func backend(canRegister: Bool, canRead: Bool) -> BrightnessBackend {
        guard canRead else { return .unavailable }
        return canRegister ? .notifications : .polling
    }

    public static func availability(for backend: BrightnessBackend) -> ServiceAvailability {
        backend == .unavailable
            ? .unavailable(reason: "DisplayServices brightness unavailable")
            : .available
    }

    // MARK: - lifecycle

    public func start() {
        let canRead = bridge?.brightness(for: CGMainDisplayID()) != nil
        // Registration is treated as unusable until Step 5 proves the signature.
        backend = Self.backend(canRegister: false, canRead: canRead)
        availability = Self.availability(for: backend)

        guard backend == .polling else {
            Self.log.info("brightness unavailable")
            return
        }
        startPolling()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.pollInterval, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = Self.pollInterval / 2   // let the OS coalesce wakeups
        tick()
    }

    private func tick() {
        guard let level = bridge?.brightness(for: CGMainDisplayID()) else { return }
        guard lastSeen != level else { return }
        lastSeen = level
        onChange(level)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter BrightnessObserverTests`
Expected: PASS — 6 tests.

- [ ] **Step 5: Empirically verify the notification callback signature**

The polling fallback is already correct and shipping. This step decides whether
notifications can replace it. Write a throwaway probe **outside the package**:

```bash
mkdir -p /tmp/ledge-probe && cat > /tmp/ledge-probe/probe.swift <<'EOF'
import Foundation
import CoreGraphics

let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)!
typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UInt32, CFString?, Double) -> Void
typealias Register = @convention(c) (CGDirectDisplayID, UnsafeMutableRawPointer?, Callback) -> Int32
let register = unsafeBitCast(
    dlsym(h, "DisplayServicesRegisterForBrightnessChangeNotifications")!, to: Register.self)

let cb: Callback = { _, display, name, value in
    print("CALLBACK FIRED display=\(display) value=\(value)")
}
let rc = register(CGMainDisplayID(), nil, cb)
print("register rc=\(rc) — now press the brightness keys for 15 seconds")
RunLoop.main.run(until: Date().addingTimeInterval(15))
print("done")
EOF
swift /tmp/ledge-probe/probe.swift
```

While it runs, press F1/F2 several times.

**Decision rule:**
- `rc == 0` **and** `CALLBACK FIRED` lines appear with plausible values → notifications work. Proceed to Step 6.
- Anything else (non-zero rc, no output, or a crash) → notifications are unusable. **Skip Step 6**, keep polling, and record the result. Polling at 10 Hz is one C call per tick and is an acceptable permanent answer.

- [ ] **Step 6: Only if Step 5 fired — switch to notifications**

Add to `DisplayServicesBridge`:

```swift
    public typealias BrightnessCallback =
        @convention(c) (UnsafeMutableRawPointer?, UInt32, CFString?, Double) -> Void

    private typealias RegisterFn =
        @convention(c) (CGDirectDisplayID, UnsafeMutableRawPointer?, BrightnessCallback) -> Int32
    private typealias UnregisterFn =
        @convention(c) (CGDirectDisplayID, BrightnessCallback) -> Int32

    /// Returns true when registration succeeded.
    public func register(
        display: CGDirectDisplayID,
        context: UnsafeMutableRawPointer?,
        callback: BrightnessCallback
    ) -> Bool {
        guard let symbol = dlsym(handle, "DisplayServicesRegisterForBrightnessChangeNotifications")
        else { return false }
        return unsafeBitCast(symbol, to: RegisterFn.self)(display, context, callback) == 0
    }

    public func unregister(display: CGDirectDisplayID, callback: BrightnessCallback) {
        guard let symbol = dlsym(handle, "DisplayServicesUnregisterForBrightnessChangeNotifications")
        else { return }
        _ = unsafeBitCast(symbol, to: UnregisterFn.self)(display, callback)
    }
```

In `BrightnessObserver.start()`, replace the hardcoded `canRegister: false` with a real
attempt, and fall through to `startPolling()` if registration returns false. The
callback must not capture context (C function pointers cannot), so route through a
file-private `nonisolated(unsafe)` weak box holding the live observer, and hop to the
main actor inside the callback before calling `onChange`.

- [ ] **Step 7: Record findings in `docs/private-api-notes.md`**

```markdown
# Private API notes

Every private symbol Ledge touches, why, and what breaks if Apple removes it.

## DisplayServices (`/System/Library/PrivateFrameworks/DisplayServices.framework`)

Loaded with `dlopen` + `dlsym`. Never linked.

| Symbol | Signature | Verified | Used for |
| --- | --- | --- | --- |
| `DisplayServicesGetBrightness` | `(CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32` | ✅ 2026-09-25, rc=0, value 0…1 | reading brightness |
| `DisplayServicesRegisterForBrightnessChangeNotifications` | undocumented | *record Step 5 result here* | change notifications |
| `DisplayServicesCanChangeBrightness` | undocumented | resolves only | not used |

**If removed:** `DisplayServicesBridge.init?` returns nil, `BrightnessObserver`
reports `.unavailable`, the brightness HUD disappears, and everything else keeps
working. No crash, no alert.

**Backend actually in use:** *record: notifications or polling*

## OSDUIHelper

See `Sources/HUDService/OSDSuppressor.swift`. Bundle id `com.apple.OSDUIHelper`,
a `gui/<uid>` LaunchAgent, **not resident** — launches on demand.

## MediaRemote

Not touched directly. Reached only through the vendored `mediaremote-adapter`,
which loads it inside `/usr/bin/perl` (bundle id `com.apple.perl`).
```

- [ ] **Step 8: Commit**

```bash
git add Sources/HUDService/BrightnessObserver.swift Tests/HUDServiceTests/BrightnessObserverTests.swift docs/private-api-notes.md
git commit -m "feat: observe display brightness via DisplayServices with polling fallback"
```

---

### Task 4: `OSDSuppressor` — suppress the stock HUD, and always restore it

**Files:**
- Create: `Sources/HUDService/OSDSuppressor.swift`
- Create: `Tests/HUDServiceTests/OSDSuppressorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum OSDAction: Sendable, Equatable { case stop(pid_t), resume(pid_t), nothing }`
  - `struct OSDSuppressionPolicy: Sendable` — `static func actions(pids: [pid_t], suppressing: Bool) -> [OSDAction]`; `static let sweepInterval: TimeInterval`
  - `@MainActor final class OSDSuppressor` — `init()`, `var isSuppressing: Bool`, `func setSuppressing(_:)`, `func recoverAtLaunch()`, `func shutdown()`

The stock HUD is drawn by `OSDUIHelper`, which is **not resident** and launches on
demand — so suppression is a repeating sweep, not a one-shot signal. `SIGSTOP` is
idempotent, so the sweep needs no process-state inspection.

Review Focus 3 is the important one: the user's system HUD must never stay dead.

- [ ] **Step 1: Write the failing tests**

Create `Tests/HUDServiceTests/OSDSuppressorTests.swift`.

```swift
import Testing
import Foundation
@testable import HUDService

@Test func suppressingStopsEveryHelperFound() {
    #expect(OSDSuppressionPolicy.actions(pids: [42], suppressing: true) == [.stop(42)])
    #expect(OSDSuppressionPolicy.actions(pids: [42, 77], suppressing: true)
            == [.stop(42), .stop(77)],
            "more than one helper can exist across sessions")
}

@Test func notSuppressingResumesEveryHelperFound() {
    #expect(OSDSuppressionPolicy.actions(pids: [42], suppressing: false) == [.resume(42)])
}

// The helper is not resident: most sweeps find nothing, and that is normal.
@Test func noHelperRunningIsNotAnError() {
    #expect(OSDSuppressionPolicy.actions(pids: [], suppressing: true) == [])
    #expect(OSDSuppressionPolicy.actions(pids: [], suppressing: false) == [])
}

@Test func sweepIntervalIsFrequentEnoughToCatchAnOnDemandLaunch() {
    // The helper launches, draws, and lingers briefly. A 1s sweep catches it
    // before the second HUD of a key-repeat burst.
    #expect(OSDSuppressionPolicy.sweepInterval <= 1.0)
    #expect(OSDSuppressionPolicy.sweepInterval > 0)
}

@Test func bundleIdentifierIsTheVerifiedOne() {
    #expect(OSDSuppressor.helperBundleIdentifier == "com.apple.OSDUIHelper")
}

// Review Focus 3: recovery must not depend on a clean shutdown.
@Test func launchRecoveryResumesUnconditionallyWhenNotSuppressing() {
    let actions = OSDSuppressionPolicy.launchRecoveryActions(pids: [42], willSuppress: false)
    #expect(actions == [.resume(42)],
            "a previous crash may have left the helper stopped")
}

@Test func launchRecoveryStillResumesFirstEvenWhenAboutToSuppress() {
    let actions = OSDSuppressionPolicy.launchRecoveryActions(pids: [42], willSuppress: true)
    #expect(actions == [.resume(42)],
            "always hand the system back a working helper, then re-suppress on the next sweep")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter OSDSuppressorTests`
Expected: FAIL — `cannot find 'OSDSuppressionPolicy' in scope`.

- [ ] **Step 3: Write `Sources/HUDService/OSDSuppressor.swift`**

```swift
import AppKit
import Foundation
import OSLog

public enum OSDAction: Sendable, Equatable {
    case stop(pid_t)
    case resume(pid_t)
    case nothing
}

/// Pure decisions about which signals to send. Tested exhaustively; the shell
/// below does nothing but enumerate pids and call `kill`.
public struct OSDSuppressionPolicy: Sendable {
    /// The helper is launched on demand, lingers briefly, then exits — so the
    /// sweep has to be frequent enough to catch it mid-burst.
    public static let sweepInterval: TimeInterval = 0.75

    public static func actions(pids: [pid_t], suppressing: Bool) -> [OSDAction] {
        pids.map { suppressing ? .stop($0) : .resume($0) }
    }

    /// At launch, always resume first. A previous crash may have left the helper
    /// `SIGSTOP`ped, and the user's system HUD would be dead until reboot.
    public static func launchRecoveryActions(pids: [pid_t], willSuppress: Bool) -> [OSDAction] {
        pids.map { .resume($0) }
    }
}

/// Suppresses the stock volume/brightness overlay by pausing `OSDUIHelper`.
///
/// The least clean thing in the app, so restoration is belt-and-braces:
/// on disable, on terminate, via `atexit`, and unconditionally at next launch.
@MainActor
public final class OSDSuppressor {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "osd")

    public static let helperBundleIdentifier = "com.apple.OSDUIHelper"

    /// Set so the `atexit` handler — which cannot touch the actor — can still
    /// hand the helper back.
    private nonisolated(unsafe) static var atexitInstalled = false

    public private(set) var isSuppressing = false
    private var sweepTimer: Timer?

    public init() {}

    private static func helperPIDs() -> [pid_t] {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: helperBundleIdentifier)
            .map(\.processIdentifier)
            .filter { $0 > 0 }
    }

    private static func apply(_ actions: [OSDAction]) {
        for action in actions {
            switch action {
            case .stop(let pid):
                if kill(pid, SIGSTOP) != 0 { log.debug("SIGSTOP \(pid) failed") }
            case .resume(let pid):
                if kill(pid, SIGCONT) != 0 { log.debug("SIGCONT \(pid) failed") }
            case .nothing:
                break
            }
        }
    }

    /// Review Focus 3, part one: undo a previous run's suppression regardless of
    /// how that run ended, before deciding what this run wants.
    public func recoverAtLaunch(willSuppress: Bool) {
        let pids = Self.helperPIDs()
        Self.apply(OSDSuppressionPolicy.launchRecoveryActions(pids: pids, willSuppress: willSuppress))
        if !pids.isEmpty {
            Self.log.info("launch recovery resumed \(pids.count) helper process(es)")
        }
    }

    public func setSuppressing(_ suppressing: Bool) {
        guard suppressing != isSuppressing else { return }
        isSuppressing = suppressing

        if suppressing {
            installAtexitHandler()
            sweepTimer = Timer.scheduledTimer(
                withTimeInterval: OSDSuppressionPolicy.sweepInterval, repeats: true
            ) { _ in
                MainActor.assumeIsolated {
                    Self.apply(OSDSuppressionPolicy.actions(pids: Self.helperPIDs(), suppressing: true))
                }
            }
            sweepTimer?.tolerance = OSDSuppressionPolicy.sweepInterval / 2
            Self.apply(OSDSuppressionPolicy.actions(pids: Self.helperPIDs(), suppressing: true))
        } else {
            sweepTimer?.invalidate()
            sweepTimer = nil
            Self.apply(OSDSuppressionPolicy.actions(pids: Self.helperPIDs(), suppressing: false))
        }
    }

    /// Called from `applicationWillTerminate`.
    public func shutdown() {
        setSuppressing(false)
    }

    /// Review Focus 3, part two: a signal-kill skips `applicationWillTerminate`,
    /// but `atexit` still runs for most terminations.
    private func installAtexitHandler() {
        guard !Self.atexitInstalled else { return }
        Self.atexitInstalled = true
        atexit {
            // No actor access here; re-enumerate and resume directly.
            for app in NSRunningApplication.runningApplications(
                withBundleIdentifier: OSDSuppressor.helperBundleIdentifier
            ) {
                kill(app.processIdentifier, SIGCONT)
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter OSDSuppressorTests`
Expected: PASS — 7 tests.

- [ ] **Step 5: Verify suppression and recovery by hand**

```bash
# Before: confirm the stock HUD appears
# (press volume keys — you should see Apple's overlay)

make dev
# press volume keys — Apple's overlay must NOT appear

# Now the important one: simulate a crash.
pkill -9 -x Ledge
pgrep -x OSDUIHelper | while read -r p; do ps -o stat= -p "$p"; done
# A 'T' state means stopped. Relaunch and confirm recovery:
make dev
# press volume keys — behaviour must be sane again, and after quitting Ledge
# entirely the stock overlay must come back.
pkill -x Ledge
# press volume keys — Apple's overlay MUST appear again
```

Record the outcome in `docs/manual-checks.md`. If the stock overlay does not
return after `pkill -9`, launch recovery is broken — fix before continuing, as
this is the one failure that damages the user's system rather than the app.

- [ ] **Step 6: Commit**

```bash
git add Sources/HUDService/OSDSuppressor.swift Tests/HUDServiceTests/OSDSuppressorTests.swift docs/manual-checks.md
git commit -m "feat: suppress stock OSD via sweep with unconditional launch recovery"
```

---

### Task 5: `HUDService` and the HUD island view

**Files:**
- Create: `Sources/HUDService/HUDService.swift`
- Modify: `Sources/Ledge/AppModel.swift`
- Modify: `Sources/Ledge/AppDelegate.swift`
- Modify: `Sources/NotchKit/NotchController.swift`
- Modify: `Sources/NotchKit/NotchRootView.swift`
- Create: `Tests/HUDServiceTests/HUDServiceTests.swift`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - `@MainActor final class HUDService` — `init(suppressStockOSD: Bool = true)`, `func start() -> AsyncStream<HUDEvent>`, `func stop()`, `var availability: ServiceAvailability`, `var isSuppressingStockOSD: Bool`, `func setSuppressStockOSD(_:)`
  - `NotchController.ActivityDisplay` gains `symbolName: String?` and `barFill: Double?`

- [ ] **Step 1: Write the failing test for composed availability**

Create `Tests/HUDServiceTests/HUDServiceTests.swift`.

```swift
import Testing
import ActivityKit
@testable import HUDService

@Test func availabilityIsAvailableWhenEitherChannelWorks() {
    #expect(HUDService.composedAvailability(volume: .available, brightness: .available)
            == .available)
    #expect(HUDService.composedAvailability(
        volume: .available, brightness: .unavailable(reason: "x")) == .available,
        "a working volume HUD is still worth having")
    #expect(HUDService.composedAvailability(
        volume: .unavailable(reason: "y"), brightness: .available) == .available)
}

@Test func availabilityIsUnavailableOnlyWhenBothFail() {
    #expect(HUDService.composedAvailability(
        volume: .unavailable(reason: "no device"),
        brightness: .unavailable(reason: "no DisplayServices"))
        == .unavailable(reason: "no volume or brightness source"))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter HUDServiceTests`
Expected: FAIL — `cannot find 'HUDService' in scope`.

- [ ] **Step 3: Write `Sources/HUDService/HUDService.swift`**

```swift
import Foundation
import ActivityKit
import OSLog

/// Composes volume and brightness observation with stock-OSD suppression.
@MainActor
public final class HUDService {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "hud")

    public private(set) var availability: ServiceAvailability = .available

    private var deriver = HUDEventDeriver()
    private var volume: VolumeObserver?
    private var brightness: BrightnessObserver?
    private let suppressor = OSDSuppressor()
    private var continuation: AsyncStream<HUDEvent>.Continuation?
    private var wantsSuppression: Bool

    public init(suppressStockOSD: Bool = true) {
        self.wantsSuppression = suppressStockOSD
    }

    public var isSuppressingStockOSD: Bool { suppressor.isSuppressing }

    public static func composedAvailability(
        volume: ServiceAvailability,
        brightness: ServiceAvailability
    ) -> ServiceAvailability {
        if volume.isAvailable || brightness.isAvailable { return .available }
        return .unavailable(reason: "no volume or brightness source")
    }

    public func start() -> AsyncStream<HUDEvent> {
        AsyncStream { continuation in
            self.continuation = continuation

            // Always hand the system back a working helper before doing anything.
            suppressor.recoverAtLaunch(willSuppress: wantsSuppression)

            let volume = VolumeObserver { [weak self] reading in
                guard let self else { return }
                if let event = self.deriver.volumeChanged(
                    level: reading.level, muted: reading.muted
                ) {
                    self.continuation?.yield(event)
                }
            }
            let brightness = BrightnessObserver { [weak self] level in
                guard let self else { return }
                if let event = self.deriver.brightnessChanged(level: level) {
                    self.continuation?.yield(event)
                }
            }

            volume.start()
            brightness.start()
            self.volume = volume
            self.brightness = brightness

            availability = Self.composedAvailability(
                volume: volume.availability, brightness: brightness.availability
            )
            Self.log.info("hud \(self.availability.statusText, privacy: .public), brightness backend \(String(describing: brightness.backend), privacy: .public)")

            if wantsSuppression, availability.isAvailable {
                suppressor.setSuppressing(true)
            }

            continuation.onTermination = { _ in
                Task { @MainActor [weak self] in self?.stop() }
            }
        }
    }

    public func setSuppressStockOSD(_ suppress: Bool) {
        wantsSuppression = suppress
        suppressor.setSuppressing(suppress && availability.isAvailable)
    }

    public func stop() {
        suppressor.shutdown()
        volume?.stop()
        brightness?.stop()
        volume = nil
        brightness = nil
        continuation?.finish()
        continuation = nil
    }
}
```

- [ ] **Step 4: Extend `ActivityDisplay` for HUD rendering**

In `Sources/NotchKit/NotchController.swift`, replace the `ActivityDisplay` struct with:

```swift
    public struct ActivityDisplay: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let detail: String?
        /// SF Symbol shown in the leading ear.
        public let symbolName: String?
        /// `0...1` progress bar, or `nil` for activities without one.
        public let barFill: Double?
        /// Short glanceable form for the trailing ear — "50%", "6%".
        ///
        /// **Required for every HUD event.** At one activity the island stays
        /// exactly notch-height, so `detailRow` is gated off and `title` has
        /// nowhere to render. A volume HUD without this shows a speaker glyph and
        /// no number — which is the one thing a volume HUD exists to show. Use
        /// `HUDEvent.compactText`, added in Task 1 of this plan:
        /// `"\(Int((level * 100).rounded()))%"`, or `"Muted"` when muted.
        public let compactText: String?

        public init(
            id: String,
            title: String,
            detail: String? = nil,
            symbolName: String? = nil,
            barFill: Double? = nil,
            compactText: String? = nil
        ) {
            self.id = id
            self.title = title
            self.detail = detail
            self.symbolName = symbolName
            self.barFill = barFill.map { min(1, max(0, $0)) }
            self.compactText = compactText
        }
    }
```

- [ ] **Step 5: Render symbol and bar in `Sources/NotchKit/NotchRootView.swift`**

Replace `leadingEar` and `detailRow`:

```swift
    @ViewBuilder private var leadingEar: some View {
        if let symbol = controller.activities.first?.symbolName {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .transition(.blurReplace)
        } else if controller.activityCount > 0 {
            Circle().fill(.white.opacity(0.28)).padding(6)
        }
    }

    @ViewBuilder private var detailRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(controller.activities) { activity in
                Text(activity.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .transition(.blurReplace)
                if let fill = activity.barFill {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.22))
                            Capsule()
                                .fill(.white)
                                .frame(width: geometry.size.width * fill)
                        }
                    }
                    .frame(height: 4)
                }
                if let detail = activity.detail {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
```

- [ ] **Step 6: Wire `HUDService` into `AppModel`**

In `Sources/Ledge/AppModel.swift`, add the service, a handler, and include it in `publish()`:

```swift
    private let hud = HUDService()

    var hudStatus: String { hud.availability.statusText }
    var isSuppressingStockOSD: Bool { hud.isSuppressingStockOSD }

    func toggleStockOSDSuppression() {
        hud.setSuppressStockOSD(!hud.isSuppressingStockOSD)
    }
```

In `start()`, alongside the power stream:

```swift
        let hudStream = hud.start()
        tasks.append(Task { [weak self] in
            for await event in hudStream {
                self?.handle(event)
            }
        })
```

**First extend `ActivityRecord`, rather than keeping a side-table in `AppModel`.**
Plan A settled this: `compactText` already lives on `ActivityRecord`, because the
value has to survive the queue between `handle()` and `publish()`. Add
`symbolName: String?` and `barFill: Double?` alongside it, defaulted to `nil` in the
memberwise init, and clamp `barFill` to `0...1` there.

There is a real objection — these are presentation concerns on a domain type — but
`ActivityRecord` already carries `title` and `detail`, which are equally presentation
strings ("Charging · 87% · 24 min to full"). A side-table keyed by activity id would
be the inconsistent choice, and it would need hand-maintained synchronisation with
`insert` and `prune` that no test covers. One object riding the one tested lifecycle
is simpler and has fewer failure modes. `ActivityKit` still declares no dependency on
`NotchKit`, so the module boundary the spec cares about is untouched.

Then the handler carries everything in the record:

```swift
    private func handle(_ event: HUDEvent) {
        queue.insert(
            ActivityRecord(
                id: ActivityKind.hud.rawValue,
                kind: .hud,
                insertedAt: Date(),
                ttl: ActivityKind.hud.defaultTTL,
                title: event.activityTitle,
                compactText: event.compactText,
                symbolName: event.symbolName,
                barFill: event.barFill
            )
        )
        publish()
    }
```

and `publish()` is a straight projection with no side-table and no lookup that can
miss:

```swift
    private func publish() {
        let display = queue.visible.map { record in
            NotchController.ActivityDisplay(
                id: record.id,
                title: record.title,
                detail: record.detail,
                symbolName: record.symbolName,
                barFill: record.barFill,
                compactText: record.compactText
            )
        }
        presenter.setActivities(display, overflow: queue.overflowCount)
    }
```

This also replaces Plan A's `publish()`, which had the same shape without the three
new fields — update it in place rather than adding a second projection.

In `stop()`, add `hud.stop()` before `power.stop()`.

- [ ] **Step 7: Add the menu toggle in `AppDelegate`**

```swift
        item.setStatus(key: "hud", text: "HUD — \(model.hudStatus)")
        item.addItem(title: "Toggle Stock OSD Suppression") { [weak model] in
            model?.toggleStockOSDSuppression()
        }
```

- [ ] **Step 8: Run the full suite**

Run: `swift test`
Expected: PASS — all targets including `HUDServiceTests`.

- [ ] **Step 9: Verify the HUD by hand**

Run: `make dev`, then record in `docs/manual-checks.md`:
1. Press volume up/down → island shows `Volume NN%` with a filling bar and a speaker symbol; Apple's overlay does **not** appear.
2. Press mute → shows `Muted`, bar empty, slashed speaker.
3. Press brightness up/down → shows `Brightness NN%` with a sun symbol.
4. Drag the Control Centre volume slider → HUD fires too (proof it is value-observed, not key-tapped).
5. Connect AirPods, then change volume → **the HUD still fires** (Review Focus 1).
6. Spin volume up and down rapidly → **one** activity that updates, never a queue of them.
7. Menu bar shows `HUD — ready`; the toggle restores Apple's overlay when off.
8. Quit Ledge → Apple's overlay returns.

- [ ] **Step 10: Commit**

```bash
git add Sources/HUDService/HUDService.swift Sources/Ledge Sources/NotchKit Tests/HUDServiceTests docs/manual-checks.md
git commit -m "feat: notch HUD replacing the stock volume and brightness overlays"
```

---

### Task 6: Vendor the media adapter and parse its output

**Files:**
- Create: `Sources/MediaService/MediaPayload.swift`
- Create: `Sources/MediaService/MediaStateMerger.swift`
- Create: `Sources/MediaService/MediaPosition.swift`
- Create: `Resources/mediaremote-adapter/` (vendored artefacts)
- Create: `Tests/MediaServiceTests/Fixtures/*.ndjson`
- Create: `Tests/MediaServiceTests/MediaPayloadTests.swift`
- Create: `Tests/MediaServiceTests/MediaStateMergerTests.swift`
- Create: `Tests/MediaServiceTests/MediaPositionTests.swift`
- Modify: `Package.swift`, `Makefile`

**Interfaces:**
- Consumes: `ActivityKit`.
- Produces:
  - `struct MediaPayload: Sendable, Equatable` — `bundleIdentifier: String?`, `playing: Bool?`, `title: String?`, `artist: String?`, `album: String?`, `duration: Double?`, `elapsedTime: Double?`, `timestamp: Date?`, `playbackRate: Double?`, `artworkData: Data?`, `artworkMimeType: String?`; `static func decode(_ json: [String: Any]) -> MediaPayload`
  - `struct MediaStreamLine: Sendable, Equatable` — `isDiff: Bool`, `payload: [String: Any]?` (a present `NSNull` value means "this key vanished"; a `nil` dictionary means the line was literal `null`); `static func parse(_ line: String) -> MediaStreamLine?` — non-throwing, returns `nil` for blank or unparseable lines
  - `struct MediaStateMerger: Sendable` — `mutating func apply(_ line: MediaStreamLine) -> MediaPayload?`; `mutating func reset()`
  - `struct MediaPosition: Sendable, Equatable` — `static func elapsed(at now: Date, elapsedTime: Double, timestamp: Date, rate: Double, duration: Double?) -> Double`

- [ ] **Step 1: Vendor and build the adapter**

```bash
mkdir -p /tmp/mra-build && cd /tmp/mra-build
git clone --depth 1 https://github.com/ungive/mediaremote-adapter.git
cd mediaremote-adapter
mkdir -p build && cd build
cmake .. && cmake --build .
cd ..

DEST="$OLDPWD"   # adjust: must resolve to <repo>/Resources/mediaremote-adapter
mkdir -p ~/Developer/ledge/Resources/mediaremote-adapter
cp bin/mediaremote-adapter.pl  ~/Developer/ledge/Resources/mediaremote-adapter/
cp -R build/MediaRemoteAdapter.framework ~/Developer/ledge/Resources/mediaremote-adapter/
cp build/MediaRemoteAdapterTestClient ~/Developer/ledge/Resources/mediaremote-adapter/
cp LICENSE ~/Developer/ledge/Resources/mediaremote-adapter/LICENSE-mediaremote-adapter
```

Then confirm it actually works, using **absolute** paths as the README requires:

```bash
cd ~/Developer/ledge/Resources/mediaremote-adapter
FW=$(realpath MediaRemoteAdapter.framework)
TC=$(realpath MediaRemoteAdapterTestClient)
PL=$(realpath mediaremote-adapter.pl)
/usr/bin/perl "$PL" "$FW" "$TC" test; echo "test exit: $?"
```

Expected: exit `0`. Anything else means MediaRemote access is broken on this
machine — stop and report; Phase 4 would need the ScriptingBridge fallback first.

- [ ] **Step 2: Capture real fixtures**

With music playing in Music.app or Spotify:

```bash
cd ~/Developer/ledge/Resources/mediaremote-adapter
FW=$(realpath MediaRemoteAdapter.framework); PL=$(realpath mediaremote-adapter.pl)
OUT=~/Developer/ledge/Tests/MediaServiceTests/Fixtures
mkdir -p "$OUT"

# Diffing stream (the default, and what we actually consume). Play/pause and
# skip a track while this runs so the capture contains diffs and vanishing keys.
/usr/bin/perl "$PL" "$FW" stream --no-artwork > "$OUT/stream-diff.ndjson" &
sleep 25; kill %1

# Non-diff stream, for the merger's baseline tests.
/usr/bin/perl "$PL" "$FW" stream --no-diff --no-artwork > "$OUT/stream-full.ndjson" &
sleep 10; kill %1

# One-shot with artwork, to exercise base64 decoding.
/usr/bin/perl "$PL" "$FW" get > "$OUT/get-with-artwork.json"

wc -l "$OUT"/*.ndjson
head -c 400 "$OUT/stream-diff.ndjson"
```

Then hand-author a fixture for the cases a live capture may not contain. Create
`Tests/MediaServiceTests/Fixtures/edge-cases.ndjson` with exactly these lines:

```
{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.Music","playing":true,"title":"First","artist":"A","album":"Album","duration":210.0,"elapsedTime":12.0,"timestamp":"2026-09-25T04:00:00Z","playbackRate":1.0}}
{"type":"data","diff":true,"payload":{"elapsedTime":45.0}}
{"type":"data","diff":true,"payload":{"artist":null}}
{"type":"data","diff":true,"payload":{"playing":false}}
{"type":"data","diff":true,"payload":{"title":"Second","artist":"B","elapsedTime":0.0}}
{"type":"data","diff":false,"payload":{}}
null
not json at all
{"type":"data","diff":true,"payload":{"duration":"nonsense"}}
```

- [ ] **Step 3: Write the failing payload tests**

Create `Tests/MediaServiceTests/MediaPayloadTests.swift`.

```swift
import Testing
import Foundation
@testable import MediaService

@Test func decodesTheMandatoryKeys() {
    let p = MediaPayload.decode([
        "bundleIdentifier": "com.apple.Music",
        "playing": true,
        "title": "Song",
        "artist": "Artist",
        "album": "Album",
        "duration": 210.0,
        "elapsedTime": 12.5,
        "playbackRate": 1.0,
    ])
    #expect(p.bundleIdentifier == "com.apple.Music")
    #expect(p.playing == true)
    #expect(p.title == "Song")
    #expect(p.artist == "Artist")
    #expect(p.duration == 210.0)
    #expect(p.elapsedTime == 12.5)
    #expect(p.playbackRate == 1.0)
}

@Test func integerNumbersDecodeAsDoubles() {
    // JSON may deliver these as Int rather than Double.
    let p = MediaPayload.decode(["duration": 210, "elapsedTime": 12])
    #expect(p.duration == 210.0)
    #expect(p.elapsedTime == 12.0)
}

@Test func wrongTypesAreIgnoredRatherThanCrashing() {
    let p = MediaPayload.decode(["duration": "nonsense", "playing": "yes", "title": 42])
    #expect(p.duration == nil)
    #expect(p.playing == nil)
    #expect(p.title == nil)
}

@Test func base64ArtworkDecodes() {
    let raw = Data("hello".utf8)
    let p = MediaPayload.decode([
        "artworkData": raw.base64EncodedString(),
        "artworkMimeType": "image/jpeg",
    ])
    #expect(p.artworkData == raw)
    #expect(p.artworkMimeType == "image/jpeg")
}

@Test func malformedArtworkIsDroppedNotFatal() {
    let p = MediaPayload.decode(["artworkData": "!!!not base64!!!"])
    #expect(p.artworkData == nil)
}

@Test func timestampParsesISO8601() {
    let p = MediaPayload.decode(["timestamp": "2026-09-25T04:00:00Z"])
    #expect(p.timestamp == Date(timeIntervalSince1970: 1_790_308_800))
}

@Test func emptyPayloadMeansNoMediaNotAnError() {
    let p = MediaPayload.decode([:])
    #expect(p.title == nil)
    #expect(p.hasMedia == false)
}

@Test func hasMediaRequiresTheMandatoryTrio() {
    #expect(MediaPayload.decode([
        "bundleIdentifier": "x", "playing": true, "title": "t",
    ]).hasMedia)
    #expect(MediaPayload.decode(["playing": true, "title": "t"]).hasMedia == false)
    #expect(MediaPayload.decode(["bundleIdentifier": "x", "title": "t"]).hasMedia == false)
    #expect(MediaPayload.decode(["bundleIdentifier": "x", "playing": true]).hasMedia == false)
}

// --- line parsing ---

@Test func parsesAStreamLine() throws {
    let line = #"{"type":"data","diff":true,"payload":{"elapsedTime":45.0}}"#
    let parsed = try #require(MediaStreamLine.parse(line))
    #expect(parsed.isDiff)
    #expect(parsed.payload?["elapsedTime"] as? Double == 45.0)
}

@Test func nullLineMeansNoMedia() throws {
    let parsed = try #require(MediaStreamLine.parse("null"))
    #expect(parsed.payload == nil)
    #expect(parsed.isDiff == false)
}

@Test func blankAndGarbageLinesAreSkipped() {
    #expect(MediaStreamLine.parse("") == nil)
    #expect(MediaStreamLine.parse("   ") == nil)
    #expect(MediaStreamLine.parse("not json at all") == nil)
    #expect(MediaStreamLine.parse("{unterminated") == nil)
}

@Test func everyLineOfTheCapturedFixtureParsesOrIsSkipped() throws {
    let url = try #require(Bundle.module.url(
        forResource: "stream-diff", withExtension: "ndjson"
    ))
    let text = try String(contentsOf: url, encoding: .utf8)
    var parsedCount = 0
    for line in text.split(separator: "\n") {
        if MediaStreamLine.parse(String(line)) != nil { parsedCount += 1 }
    }
    #expect(parsedCount > 0, "the real capture must yield at least one usable line")
}
```

- [ ] **Step 4: Write the failing merger tests** (Review Focus 4)

Create `Tests/MediaServiceTests/MediaStateMergerTests.swift`.

```swift
import Testing
import Foundation
@testable import MediaService

private func line(_ json: String) -> MediaStreamLine {
    MediaStreamLine.parse(json)!
}

@Test func aFullPayloadBecomesTheBaseline() {
    var m = MediaStateMerger()
    let state = m.apply(line(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.Music","playing":true,"title":"First","artist":"A"}}"#))
    #expect(state?.title == "First")
    #expect(state?.artist == "A")
}

@Test func aDiffUpdatesOnlyTheKeysItCarries() {
    var m = MediaStateMerger()
    _ = m.apply(line(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"b","playing":true,"title":"First","artist":"A","elapsedTime":12.0}}"#))
    let state = m.apply(line(#"{"type":"data","diff":true,"payload":{"elapsedTime":45.0}}"#))
    #expect(state?.elapsedTime == 45.0)
    #expect(state?.title == "First", "untouched keys must survive")
    #expect(state?.artist == "A")
}

// Review Focus 4: the whole point.
@Test func aNullInADiffRemovesTheKeyRatherThanKeepingTheOldValue() {
    var m = MediaStateMerger()
    _ = m.apply(line(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"b","playing":true,"title":"First","artist":"A"}}"#))
    let state = m.apply(line(#"{"type":"data","diff":true,"payload":{"artist":null}}"#))
    #expect(state?.artist == nil, "a stale artist that never clears is the bug this prevents")
    #expect(state?.title == "First")
}

@Test func aNullLineClearsEverything() {
    var m = MediaStateMerger()
    _ = m.apply(line(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"b","playing":true,"title":"First"}}"#))
    let state = m.apply(line("null"))
    #expect(state?.hasMedia == false)
    #expect(state?.title == nil)
}

@Test func anEmptyFullPayloadMeansNoMediaPlayerAtAll() {
    var m = MediaStateMerger()
    _ = m.apply(line(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"b","playing":true,"title":"First"}}"#))
    let state = m.apply(line(#"{"type":"data","diff":false,"payload":{}}"#))
    #expect(state?.hasMedia == false)
}

@Test func aDiffArrivingBeforeAnyBaselineIsStillUsable() {
    var m = MediaStateMerger()
    let state = m.apply(line(#"{"type":"data","diff":true,"payload":{"title":"Orphan"}}"#))
    #expect(state?.title == "Orphan", "never drop data waiting for a baseline that may not come")
}

@Test func aTrackChangeReplacesTheFieldsItCarries() {
    var m = MediaStateMerger()
    _ = m.apply(line(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"b","playing":true,"title":"First","artist":"A","elapsedTime":180.0}}"#))
    let state = m.apply(line(#"{"type":"data","diff":true,"payload":{"title":"Second","artist":"B","elapsedTime":0.0}}"#))
    #expect(state?.title == "Second")
    #expect(state?.artist == "B")
    #expect(state?.elapsedTime == 0.0)
}

@Test func artworkIsRetainedAcrossDiffsThatOmitIt() {
    var m = MediaStateMerger()
    let art = Data("art".utf8).base64EncodedString()
    _ = m.apply(line(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"b","playing":true,"title":"First","artworkData":"\#(art)"}}"#))
    let state = m.apply(line(#"{"type":"data","diff":true,"payload":{"elapsedTime":5.0}}"#))
    #expect(state?.artworkData == Data("art".utf8), "omitted is not the same as null")
}

@Test func resetDropsTheAccumulatedState() {
    var m = MediaStateMerger()
    _ = m.apply(line(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"b","playing":true,"title":"First"}}"#))
    m.reset()
    let state = m.apply(line(#"{"type":"data","diff":true,"payload":{"elapsedTime":1.0}}"#))
    #expect(state?.title == nil, "after a restart nothing from the old process may leak through")
}

@Test func theHandAuthoredEdgeCaseFixtureReplaysWithoutLosingState() throws {
    let url = try #require(Bundle.module.url(
        forResource: "edge-cases", withExtension: "ndjson"
    ))
    let text = try String(contentsOf: url, encoding: .utf8)
    var m = MediaStateMerger()
    var lastGoodTitle: String?
    for raw in text.split(separator: "\n") {
        guard let parsed = MediaStreamLine.parse(String(raw)) else { continue }
        if let state = m.apply(parsed), let title = state.title { lastGoodTitle = title }
    }
    // The fixture ends with an empty full payload and garbage, so the last real
    // title seen must have been "Second".
    #expect(lastGoodTitle == "Second")
}
```

- [ ] **Step 5: Write the failing position tests**

Create `Tests/MediaServiceTests/MediaPositionTests.swift`.

```swift
import Testing
import Foundation
@testable import MediaService

private let t0 = Date(timeIntervalSince1970: 1_790_308_800)

@Test func positionAdvancesWithWallClockWhilePlaying() {
    let p = MediaPosition.elapsed(
        at: t0.addingTimeInterval(10), elapsedTime: 30, timestamp: t0, rate: 1, duration: 210
    )
    #expect(p == 40)
}

@Test func positionIsFrozenWhenPaused() {
    let p = MediaPosition.elapsed(
        at: t0.addingTimeInterval(60), elapsedTime: 30, timestamp: t0, rate: 0, duration: 210
    )
    #expect(p == 30)
}

@Test func positionRespectsPlaybackRate() {
    let p = MediaPosition.elapsed(
        at: t0.addingTimeInterval(10), elapsedTime: 0, timestamp: t0, rate: 1.5, duration: 210
    )
    #expect(p == 15)
}

@Test func positionNeverExceedsDuration() {
    let p = MediaPosition.elapsed(
        at: t0.addingTimeInterval(9999), elapsedTime: 200, timestamp: t0, rate: 1, duration: 210
    )
    #expect(p == 210, "a scrubber past the end looks broken")
}

@Test func positionNeverGoesNegative() {
    let p = MediaPosition.elapsed(
        at: t0.addingTimeInterval(-50), elapsedTime: 10, timestamp: t0, rate: 1, duration: 210
    )
    #expect(p == 0, "clock skew must not produce a negative position")
}

@Test func unknownDurationStillExtrapolates() {
    let p = MediaPosition.elapsed(
        at: t0.addingTimeInterval(10), elapsedTime: 5, timestamp: t0, rate: 1, duration: nil
    )
    #expect(p == 15)
}
```

- [ ] **Step 6: Run all three test files to verify they fail**

Run: `swift test --filter MediaServiceTests`
Expected: FAIL — `no such module 'MediaService'`.

- [ ] **Step 7: Add the `MediaService` targets with fixture resources to `Package.swift`**

```swift
        .target(name: "MediaService", dependencies: ["ActivityKit"]),
        .testTarget(
            name: "MediaServiceTests",
            dependencies: ["MediaService"],
            resources: [.copy("Fixtures")]
        ),
```

Note: `.copy("Fixtures")` makes `Bundle.module.url(forResource:withExtension:)`
resolve the files. Add `"MediaService"` to the `Ledge` executable's dependencies.

- [ ] **Step 8: Write `Sources/MediaService/MediaPayload.swift`**

```swift
import Foundation

/// Now-playing state, decoded from the adapter's JSON.
/// Keys mirror the adapter README exactly.
public struct MediaPayload: Sendable, Equatable {
    public var bundleIdentifier: String?
    public var playing: Bool?
    public var title: String?
    public var artist: String?
    public var album: String?
    public var duration: Double?
    public var elapsedTime: Double?
    public var timestamp: Date?
    public var playbackRate: Double?
    public var artworkData: Data?
    public var artworkMimeType: String?

    public init() {}

    /// The adapter guarantees these three are non-null when media exists.
    public var hasMedia: Bool {
        bundleIdentifier != nil && playing != nil && title != nil
    }

    public var isPlaying: Bool { playing == true }

    /// Tolerant by design: a wrong type is treated as absent, never fatal.
    public static func decode(_ json: [String: Any]) -> MediaPayload {
        var p = MediaPayload()
        p.bundleIdentifier = json["bundleIdentifier"] as? String
        p.playing = json["playing"] as? Bool
        p.title = json["title"] as? String
        p.artist = json["artist"] as? String
        p.album = json["album"] as? String
        p.duration = number(json["duration"])
        p.elapsedTime = number(json["elapsedTime"])
        p.playbackRate = number(json["playbackRate"])
        p.artworkMimeType = json["artworkMimeType"] as? String

        if let encoded = json["artworkData"] as? String {
            p.artworkData = Data(base64Encoded: encoded)
        }
        if let stamp = json["timestamp"] as? String {
            p.timestamp = ISO8601DateFormatter().date(from: stamp)
        } else if let seconds = number(json["timestamp"]) {
            p.timestamp = Date(timeIntervalSince1970: seconds)
        }
        return p
    }

    /// JSON delivers numbers as `Int` or `Double` depending on the value.
    private static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }
}
```

- [ ] **Step 9: Write `Sources/MediaService/MediaStateMerger.swift`**

```swift
import Foundation

/// One line of the adapter's `stream` output.
public struct MediaStreamLine: Sendable {
    public let isDiff: Bool
    /// `nil` means the line was literal `null`: no media at all.
    /// A present dictionary may hold `NSNull` values, meaning "this key vanished".
    public let payload: [String: Any]?

    public init(isDiff: Bool, payload: [String: Any]?) {
        self.isDiff = isDiff
        self.payload = payload
    }

    /// Returns `nil` for blank or unparseable lines — they are skipped, never fatal.
    public static func parse(_ line: String) -> MediaStreamLine? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "null" { return MediaStreamLine(isDiff: false, payload: nil) }

        guard
            let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any]
        else { return nil }

        // A bare `get` payload has no envelope.
        guard let payload = root["payload"] as? [String: Any] else {
            return MediaStreamLine(isDiff: false, payload: root)
        }
        return MediaStreamLine(isDiff: root["diff"] as? Bool ?? false, payload: payload)
    }
}

extension MediaStreamLine: Equatable {
    public static func == (lhs: MediaStreamLine, rhs: MediaStreamLine) -> Bool {
        lhs.isDiff == rhs.isDiff
            && NSDictionary(dictionary: lhs.payload ?? [:])
                .isEqual(to: rhs.payload ?? [:])
    }
}

/// Accumulates the adapter's diff stream into a complete picture.
///
/// The adapter diffs by default. A key present with a `null` value means the key
/// *vanished* and must be removed; a key simply absent from a diff is unchanged.
/// Conflating those two is what produces titles that never clear.
public struct MediaStateMerger: Sendable {
    private var raw: [String: Any] = [:]

    public init() {}

    public mutating func reset() {
        raw = [:]
    }

    public mutating func apply(_ line: MediaStreamLine) -> MediaPayload? {
        guard let payload = line.payload else {
            raw = [:]                       // literal null: nothing is playing
            return MediaPayload.decode(raw)
        }

        if line.isDiff {
            for (key, value) in payload {
                if value is NSNull {
                    raw.removeValue(forKey: key)     // vanished
                } else {
                    raw[key] = value
                }
            }
        } else {
            raw = payload.filter { !($0.value is NSNull) }
        }

        return MediaPayload.decode(raw)
    }
}
```

- [ ] **Step 10: Write `Sources/MediaService/MediaPosition.swift`**

```swift
import Foundation

/// Extrapolates playback position locally, so the adapter is never polled.
///
/// The adapter reports `elapsedTime` as it was at `timestamp`; everything after
/// that is arithmetic.
public enum MediaPosition {
    public static func elapsed(
        at now: Date,
        elapsedTime: Double,
        timestamp: Date,
        rate: Double,
        duration: Double?
    ) -> Double {
        let advanced = elapsedTime + now.timeIntervalSince(timestamp) * rate
        let floored = max(0, advanced)
        guard let duration, duration > 0 else { return floored }
        return min(floored, duration)
    }
}
```

- [ ] **Step 11: Run the tests to verify they pass**

Run: `swift test --filter MediaServiceTests`
Expected: PASS — 12 payload/line tests, 10 merger tests, 6 position tests.

If `everyLineOfTheCapturedFixtureParsesOrIsSkipped` fails because the fixture is
empty, Step 2's capture caught no media — replay it with something actually playing.

- [ ] **Step 12: Bundle the adapter in the app and commit**

In the `Makefile`'s `bundle` target, after the `cp` of the binary:

```make
	cp -R Resources/mediaremote-adapter "$(APPDIR)/Contents/Resources/"
	chmod +x "$(APPDIR)/Contents/Resources/mediaremote-adapter/MediaRemoteAdapterTestClient"
```

The framework is copied, **never linked** — the README is explicit about this.

```bash
git add Package.swift Makefile Resources/mediaremote-adapter Sources/MediaService Tests/MediaServiceTests
git commit -m "feat: vendor media adapter and parse its diffing NDJSON stream"
```

---

### Task 7: `MediaService` — supervision, fatal-vs-transient, commands

**Files:**
- Create: `Sources/MediaService/RestartPolicy.swift`
- Create: `Sources/MediaService/MediaCommand.swift`
- Create: `Sources/MediaService/AdapterLocator.swift`
- Create: `Sources/MediaService/MediaRemoteSource.swift`
- Create: `Sources/MediaService/MediaService.swift`
- Create: `Tests/MediaServiceTests/RestartPolicyTests.swift`
- Create: `Tests/MediaServiceTests/MediaCommandTests.swift`

**Interfaces:**
- Consumes: Task 6.
- Produces:
  - `enum ExitReason: Sendable, Equatable { case clean, signalled(Int32), nonZero(Int32) }`
  - `struct RestartPolicy: Sendable` — `static let maximumRapidFailures: Int`, `static let backoffCap: TimeInterval`; `static func backoff(attempt: Int) -> TimeInterval`; `mutating func decide(_ reason: ExitReason) -> RestartDecision`
  - `enum RestartDecision: Sendable, Equatable { case restart(after: TimeInterval), giveUp(reason: String) }`
  - `enum MediaCommand: Sendable, Equatable` — `play`, `pause`, `togglePlayPause`, `nextTrack`, `previousTrack`, `seek(seconds: Double)`; `var adapterArguments: [String]`
  - `struct AdapterLocator: Sendable` — `init(resourceRoot: URL)`, `var scriptPath: URL`, `var frameworkPath: URL`, `var testClientPath: URL`, `func validate() -> ServiceAvailability`, `func streamArguments() -> [String]`
  - `@MainActor final class MediaService` — `init(locator: AdapterLocator?)`, `func start() -> AsyncStream<MediaPayload>`, `func send(_: MediaCommand)`, `func stop()`, `var availability: ServiceAvailability`

Review Focus 5 lives here: a fatal adapter failure must never become a retry loop.

- [ ] **Step 1: Write the failing restart-policy tests**

Create `Tests/MediaServiceTests/RestartPolicyTests.swift`.

```swift
import Testing
import Foundation
@testable import MediaService

@Test func backoffDoublesAndThenCaps() {
    #expect(RestartPolicy.backoff(attempt: 1) == 0.5)
    #expect(RestartPolicy.backoff(attempt: 2) == 1.0)
    #expect(RestartPolicy.backoff(attempt: 3) == 2.0)
    #expect(RestartPolicy.backoff(attempt: 4) == 4.0)
    #expect(RestartPolicy.backoff(attempt: 50) == RestartPolicy.backoffCap)
    #expect(RestartPolicy.backoffCap == 30)
}

@Test func aCleanExitIsTransientAndRestarts() {
    var p = RestartPolicy()
    #expect(p.decide(.clean) == .restart(after: 0.5))
}

@Test func aSignalledExitIsTransientAndRestarts() {
    var p = RestartPolicy()
    #expect(p.decide(.signalled(SIGTERM)) == .restart(after: 0.5))
}

// Review Focus 5: upstream says explicitly not to reinvoke on a fatal error.
@Test func aNonZeroExitIsFatalAndNeverRetried() {
    var p = RestartPolicy()
    #expect(p.decide(.nonZero(1))
            == .giveUp(reason: "adapter exited with status 1; not reinvoking"))
}

@Test func aFatalExitStaysFatalOnSubsequentQueries() {
    var p = RestartPolicy()
    _ = p.decide(.nonZero(2))
    #expect(p.decide(.clean) != .restart(after: 0.5),
            "once fatal, a later clean exit must not resurrect the retry loop")
}

@Test func repeatedTransientFailuresEventuallyGiveUp() {
    var p = RestartPolicy()
    for attempt in 1...RestartPolicy.maximumRapidFailures {
        #expect(p.decide(.clean) == .restart(after: RestartPolicy.backoff(attempt: attempt)))
    }
    #expect(p.decide(.clean)
            == .giveUp(reason: "adapter restarted 5 times without settling"))
    #expect(RestartPolicy.maximumRapidFailures == 5)
}

@Test func successResetsTheAttemptCounter() {
    var p = RestartPolicy()
    _ = p.decide(.clean)
    _ = p.decide(.clean)
    p.noteHealthy()
    #expect(p.decide(.clean) == .restart(after: 0.5), "backoff starts over after a good run")
}
```

- [ ] **Step 2: Write the failing command tests**

Create `Tests/MediaServiceTests/MediaCommandTests.swift`.

```swift
import Testing
@testable import MediaService

// IDs come verbatim from the adapter README's command table.
@Test func commandIdsMatchTheAdapterTable() {
    #expect(MediaCommand.play.adapterArguments == ["send", "0"])
    #expect(MediaCommand.pause.adapterArguments == ["send", "1"])
    #expect(MediaCommand.togglePlayPause.adapterArguments == ["send", "2"])
    #expect(MediaCommand.nextTrack.adapterArguments == ["send", "4"])
    #expect(MediaCommand.previousTrack.adapterArguments == ["send", "5"])
}

@Test func seekConvertsSecondsToMicroseconds() {
    // The README: "The unit is microseconds", positive integer.
    #expect(MediaCommand.seek(seconds: 1).adapterArguments == ["seek", "1000000"])
    #expect(MediaCommand.seek(seconds: 12.5).adapterArguments == ["seek", "12500000"])
    #expect(MediaCommand.seek(seconds: 0).adapterArguments == ["seek", "0"])
}

@Test func seekClampsNegativesToZero() {
    #expect(MediaCommand.seek(seconds: -5).adapterArguments == ["seek", "0"],
            "a negative position is not a valid positive integer")
}

@Test func seekRoundsRatherThanTruncatingOddly() {
    #expect(MediaCommand.seek(seconds: 0.0000004).adapterArguments == ["seek", "0"])
    #expect(MediaCommand.seek(seconds: 0.0000006).adapterArguments == ["seek", "1"])
}
```

- [ ] **Step 3: Run both to verify they fail**

Run: `swift test --filter "RestartPolicyTests|MediaCommandTests"`
Expected: FAIL — `cannot find 'RestartPolicy' in scope`.

- [ ] **Step 4: Write `Sources/MediaService/RestartPolicy.swift`**

```swift
import Foundation

public enum ExitReason: Sendable, Equatable {
    case clean
    case signalled(Int32)
    case nonZero(Int32)
}

public enum RestartDecision: Sendable, Equatable {
    case restart(after: TimeInterval)
    case giveUp(reason: String)
}

/// Decides whether a dead adapter process should be revived.
///
/// The adapter's README is explicit: *"You should not reinvoke the script when a
/// fatal error occurs (non-zero exit code)"*. So exit reason, not just count,
/// determines the outcome.
public struct RestartPolicy: Sendable {
    public static let maximumRapidFailures = 5
    public static let backoffCap: TimeInterval = 30

    private var attempts = 0
    private var fatal = false

    public init() {}

    public static func backoff(attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        let delay = 0.5 * pow(2, Double(attempt - 1))
        return min(delay, backoffCap)
    }

    /// Call after the adapter has produced usable output, so a long healthy run
    /// does not count earlier stumbles against it.
    public mutating func noteHealthy() {
        attempts = 0
    }

    public mutating func decide(_ reason: ExitReason) -> RestartDecision {
        if fatal {
            return .giveUp(reason: "adapter previously failed fatally; not reinvoking")
        }

        switch reason {
        case .nonZero(let status):
            fatal = true
            return .giveUp(reason: "adapter exited with status \(status); not reinvoking")

        case .clean, .signalled:
            attempts += 1
            guard attempts <= Self.maximumRapidFailures else {
                return .giveUp(
                    reason: "adapter restarted \(Self.maximumRapidFailures) times without settling"
                )
            }
            return .restart(after: Self.backoff(attempt: attempts))
        }
    }
}
```

- [ ] **Step 5: Write `Sources/MediaService/MediaCommand.swift`**

```swift
import Foundation

/// Playback commands. IDs are from the adapter README's `send COMMAND` table.
public enum MediaCommand: Sendable, Equatable {
    case play
    case pause
    case togglePlayPause
    case nextTrack
    case previousTrack
    case seek(seconds: Double)

    public var adapterArguments: [String] {
        switch self {
        case .play:            return ["send", "0"]
        case .pause:           return ["send", "1"]
        case .togglePlayPause: return ["send", "2"]
        case .nextTrack:       return ["send", "4"]
        case .previousTrack:   return ["send", "5"]
        case .seek(let seconds):
            let micros = Int((max(0, seconds) * 1_000_000).rounded())
            return ["seek", String(micros)]
        }
    }
}
```

- [ ] **Step 6: Write `Sources/MediaService/AdapterLocator.swift`**

```swift
import Foundation
import ActivityKit

/// Resolves the bundled adapter's absolute paths. The README requires absolute
/// paths and forbids linking the framework.
public struct AdapterLocator: Sendable {
    public let resourceRoot: URL

    public init(resourceRoot: URL) {
        self.resourceRoot = resourceRoot
    }

    /// The adapter as bundled by the Makefile.
    public static func inMainBundle() -> AdapterLocator? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        return AdapterLocator(
            resourceRoot: resources.appendingPathComponent("mediaremote-adapter", isDirectory: true)
        )
    }

    public var scriptPath: URL {
        resourceRoot.appendingPathComponent("mediaremote-adapter.pl")
    }
    public var frameworkPath: URL {
        resourceRoot.appendingPathComponent("MediaRemoteAdapter.framework")
    }
    public var testClientPath: URL {
        resourceRoot.appendingPathComponent("MediaRemoteAdapterTestClient")
    }

    /// Review Focus 5: a missing adapter is a clean `unavailable`, not a crash.
    public func validate() -> ServiceAvailability {
        let fm = FileManager.default
        guard fm.fileExists(atPath: scriptPath.path) else {
            return .unavailable(reason: "adapter script missing from bundle")
        }
        guard fm.fileExists(atPath: frameworkPath.path) else {
            return .unavailable(reason: "adapter framework missing from bundle")
        }
        guard fm.isExecutableFile(atPath: "/usr/bin/perl") else {
            return .unavailable(reason: "/usr/bin/perl unavailable")
        }
        return .available
    }

    /// `--no-diff` is deliberately NOT passed: diffs are cheaper, and
    /// `MediaStateMerger` handles them.
    public func streamArguments() -> [String] {
        [scriptPath.path, frameworkPath.path, "stream"]
    }

    public func commandArguments(_ command: MediaCommand) -> [String] {
        [scriptPath.path, frameworkPath.path] + command.adapterArguments
    }

    public func testArguments() -> [String] {
        [scriptPath.path, frameworkPath.path, testClientPath.path, "test"]
    }
}
```

- [ ] **Step 7: Write `Sources/MediaService/MediaRemoteSource.swift`**

```swift
import Foundation
import OSLog

/// Runs the adapter and turns its stdout into lines.
/// Knows nothing about merging or restarting.
final class MediaRemoteSource {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "media.proc")

    private let locator: AdapterLocator
    private var process: Process?

    init(locator: AdapterLocator) {
        self.locator = locator
    }

    /// Emits each stdout line, then exactly one terminal `ExitReason`.
    func run(
        onLine: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (ExitReason) -> Void
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = locator.streamArguments()

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        // Every stderr line is an error message, non-fatal unless the exit code
        // is non-zero — per the adapter README.
        err.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Self.log.debug("adapter stderr: \(text, privacy: .public)")
        }

        var buffer = Data()
        out.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if let line = String(data: lineData, encoding: .utf8) {
                    onLine(line)
                }
            }
        }

        process.terminationHandler = { finished in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            let reason: ExitReason
            if finished.terminationReason == .uncaughtSignal {
                reason = .signalled(finished.terminationStatus)
            } else if finished.terminationStatus == 0 {
                reason = .clean
            } else {
                reason = .nonZero(finished.terminationStatus)
            }
            onExit(reason)
        }

        do {
            try process.run()
            self.process = process
        } catch {
            Self.log.error("could not launch adapter: \(error.localizedDescription, privacy: .public)")
            onExit(.nonZero(-1))
        }
    }

    /// The adapter streams until SIGTERM, per its README.
    func terminate() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    /// One-shot invocation for `send` / `seek`.
    static func fire(locator: AdapterLocator, command: MediaCommand) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = locator.commandArguments(command)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// Capability probe. Exit 0 means MediaRemote access still works.
    static func probe(locator: AdapterLocator) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = locator.testArguments()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
```

- [ ] **Step 8: Write `Sources/MediaService/MediaService.swift`**

```swift
import Foundation
import ActivityKit
import OSLog

/// Live now-playing state and playback control.
@MainActor
public final class MediaService {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "media")

    public private(set) var availability: ServiceAvailability = .available
    public private(set) var current = MediaPayload()

    private let locator: AdapterLocator?
    private var source: MediaRemoteSource?
    private var merger = MediaStateMerger()
    private var policy = RestartPolicy()
    private var continuation: AsyncStream<MediaPayload>.Continuation?
    private var restartTask: Task<Void, Never>?
    private var sawUsableOutput = false

    public init(locator: AdapterLocator? = AdapterLocator.inMainBundle()) {
        self.locator = locator
    }

    public func start() -> AsyncStream<MediaPayload> {
        AsyncStream { continuation in
            self.continuation = continuation

            guard let locator else {
                availability = .unavailable(reason: "adapter not bundled")
                continuation.finish()
                return
            }

            let validation = locator.validate()
            guard validation.isAvailable else {
                availability = validation
                Self.log.info("media unavailable: \(validation.statusText, privacy: .public)")
                continuation.finish()
                return
            }

            // Probe before streaming, so a broken MediaRemote is a clean
            // `unavailable` rather than a dead stream nobody notices.
            guard MediaRemoteSource.probe(locator: locator) else {
                availability = .unavailable(reason: "MediaRemote access blocked")
                Self.log.info("adapter test command failed; media disabled")
                continuation.finish()
                return
            }

            availability = .available
            launch()

            continuation.onTermination = { _ in
                Task { @MainActor [weak self] in self?.stop() }
            }
        }
    }

    public func send(_ command: MediaCommand) {
        guard let locator, availability.isAvailable else { return }
        MediaRemoteSource.fire(locator: locator, command: command)
    }

    public func stop() {
        restartTask?.cancel()
        restartTask = nil
        source?.terminate()
        source = nil
        continuation?.finish()
        continuation = nil
    }

    private func launch() {
        guard let locator else { return }
        merger.reset()          // never let a dead process's state leak forward
        sawUsableOutput = false

        let source = MediaRemoteSource(locator: locator)
        self.source = source

        source.run(
            onLine: { [weak self] line in
                Task { @MainActor [weak self] in self?.ingest(line) }
            },
            onExit: { [weak self] reason in
                Task { @MainActor [weak self] in self?.handleExit(reason) }
            }
        )
    }

    private func ingest(_ line: String) {
        guard let parsed = MediaStreamLine.parse(line) else { return }
        guard let payload = merger.apply(parsed) else { return }

        if !sawUsableOutput {
            sawUsableOutput = true
            policy.noteHealthy()
        }
        current = payload
        continuation?.yield(payload)
    }

    private func handleExit(_ reason: ExitReason) {
        source = nil
        switch policy.decide(reason) {
        case .restart(let delay):
            Self.log.info("adapter exited (\(String(describing: reason), privacy: .public)); retrying in \(delay)s")
            restartTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.launch()
            }
        case .giveUp(let reason):
            availability = .unavailable(reason: reason)
            Self.log.error("media given up: \(reason, privacy: .public)")
            continuation?.finish()
        }
    }
}
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `swift test --filter MediaServiceTests`
Expected: PASS — 7 restart-policy tests, 4 command tests, plus Task 6's.

- [ ] **Step 10: Commit**

```bash
git add Sources/MediaService Tests/MediaServiceTests
git commit -m "feat: supervised media adapter with fatal-vs-transient restart policy"
```

---

### Task 8: Media in the island — compact ear, expanded panel, controls

**Files:**
- Modify: `Sources/NotchKit/NotchController.swift`
- Modify: `Sources/NotchKit/NotchRootView.swift`
- Create: `Sources/NotchKit/MediaPanelView.swift`
- Modify: `Sources/Ledge/AppModel.swift`
- Modify: `Sources/Ledge/AppDelegate.swift`
- Create: `Tests/NotchKitTests/MediaPresentationTests.swift`

**Interfaces:**
- Consumes: Tasks 6–7, and `NotchKit` from the previous plan.
- Produces:
  - `struct MediaPresentation: Sendable, Equatable` — `title`, `artist: String?`, `artwork: Data?`, `isPlaying: Bool`, `elapsed: Double`, `duration: Double?`; `var progress: Double`; `var elapsedText: String`; `var remainingText: String?`
  - `NotchController` gains `var media: MediaPresentation?` and `func setMedia(_:)`
  - `enum NotchIntent: Sendable, Equatable { case togglePlayPause, next, previous, seek(fraction: Double) }` and `NotchController.onIntent: ((NotchIntent) -> Void)?`
  - `struct MediaPanelView: View`

- [ ] **Step 1: Write the failing presentation tests**

Create `Tests/NotchKitTests/MediaPresentationTests.swift`.

```swift
import Testing
import Foundation
@testable import NotchKit

private func presentation(elapsed: Double, duration: Double?) -> MediaPresentation {
    MediaPresentation(
        title: "Song", artist: "Artist", artwork: nil,
        isPlaying: true, elapsed: elapsed, duration: duration
    )
}

@Test func progressIsTheFractionPlayed() {
    #expect(presentation(elapsed: 105, duration: 210).progress == 0.5)
    #expect(presentation(elapsed: 0, duration: 210).progress == 0)
    #expect(presentation(elapsed: 210, duration: 210).progress == 1)
}

@Test func progressIsZeroWhenDurationIsUnknownOrZero() {
    #expect(presentation(elapsed: 50, duration: nil).progress == 0,
            "a live stream must not render a meaningless full bar")
    #expect(presentation(elapsed: 50, duration: 0).progress == 0)
}

@Test func progressIsClampedToUnitRange() {
    #expect(presentation(elapsed: 500, duration: 210).progress == 1)
    #expect(presentation(elapsed: -20, duration: 210).progress == 0)
}

@Test func timesFormatAsMinutesAndSeconds() {
    #expect(presentation(elapsed: 0, duration: 210).elapsedText == "0:00")
    #expect(presentation(elapsed: 9, duration: 210).elapsedText == "0:09")
    #expect(presentation(elapsed: 65, duration: 210).elapsedText == "1:05")
    #expect(presentation(elapsed: 3661, duration: 7200).elapsedText == "61:01")
}

@Test func remainingTimeIsNegativeAndAbsentWithoutDuration() {
    #expect(presentation(elapsed: 105, duration: 210).remainingText == "-1:45")
    #expect(presentation(elapsed: 210, duration: 210).remainingText == "-0:00")
    #expect(presentation(elapsed: 50, duration: nil).remainingText == nil)
}

@Test func seekIntentCarriesAFractionNotSeconds() {
    // The view knows the bar's width; only the model knows the duration.
    #expect(NotchIntent.seek(fraction: 0.5) == .seek(fraction: 0.5))
}

@MainActor
@Test func settingMediaMakesTheIslandTreatItAsAStickyActivity() {
    let controller = NotchController(
        metrics: NotchMetrics(notchRect: CGRect(x: 645.5, y: 0, width: 179, height: 32))
    )
    #expect(controller.media == nil)
    controller.setMedia(presentation(elapsed: 10, duration: 210))
    #expect(controller.media?.title == "Song")
    controller.setMedia(nil)
    #expect(controller.media == nil)
}

@MainActor
@Test func intentsAreForwardedToTheHandler() {
    let controller = NotchController(
        metrics: NotchMetrics(notchRect: CGRect(x: 645.5, y: 0, width: 179, height: 32))
    )
    var received: [NotchIntent] = []
    controller.onIntent = { received.append($0) }
    controller.emit(.togglePlayPause)
    controller.emit(.seek(fraction: 0.25))
    #expect(received == [.togglePlayPause, .seek(fraction: 0.25)])
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter MediaPresentationTests`
Expected: FAIL — `cannot find 'MediaPresentation' in scope`.

- [ ] **Step 3: Add `MediaPresentation` and intents to `NotchController.swift`**

```swift
public struct MediaPresentation: Sendable, Equatable {
    public let title: String
    public let artist: String?
    public let artwork: Data?
    public let isPlaying: Bool
    public let elapsed: Double
    public let duration: Double?

    public init(
        title: String, artist: String?, artwork: Data?,
        isPlaying: Bool, elapsed: Double, duration: Double?
    ) {
        self.title = title
        self.artist = artist
        self.artwork = artwork
        self.isPlaying = isPlaying
        self.elapsed = elapsed
        self.duration = duration
    }

    public var progress: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    public var elapsedText: String { Self.clock(max(0, elapsed)) }

    public var remainingText: String? {
        guard let duration, duration > 0 else { return nil }
        return "-" + Self.clock(max(0, duration - min(elapsed, duration)))
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

public enum NotchIntent: Sendable, Equatable {
    case togglePlayPause
    case next
    case previous
    case seek(fraction: Double)
}
```

Inside `NotchController`, add:

```swift
    public private(set) var media: MediaPresentation?
    public var onIntent: ((NotchIntent) -> Void)?

    public func setMedia(_ media: MediaPresentation?) {
        self.media = media
    }

    public func emit(_ intent: NotchIntent) {
        onIntent?(intent)
    }
```

- [ ] **Step 4: Write `Sources/NotchKit/MediaPanelView.swift`**

```swift
import SwiftUI

/// The expanded media panel. Lives entirely **below** the notch cutout.
struct MediaPanelView: View {
    let media: MediaPresentation
    let notchHeight: CGFloat
    let emit: (NotchIntent) -> Void

    @Namespace private var artworkNamespace

    var body: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .matchedGeometryEffect(id: "artwork", in: artworkNamespace)

            VStack(alignment: .leading, spacing: 4) {
                Text(media.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .transition(.blurReplace)

                if let artist = media.artist {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .transition(.blurReplace)
                }

                scrubber

                HStack(spacing: 22) {
                    button("backward.fill", .previous)
                    button(media.isPlaying ? "pause.fill" : "play.fill", .togglePlayPause)
                    button("forward.fill", .next)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .foregroundStyle(.white)
    }

    @ViewBuilder private var artwork: some View {
        if let data = media.artwork, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.18))
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.5))
                }
        }
    }

    private var scrubber: some View {
        VStack(spacing: 2) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule()
                        .fill(.white)
                        .frame(width: geometry.size.width * media.progress)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onEnded { value in
                        let fraction = min(1, max(0, value.location.x / geometry.size.width))
                        emit(.seek(fraction: fraction))
                    }
                )
            }
            .frame(height: 4)

            HStack {
                Text(media.elapsedText)
                Spacer()
                if let remaining = media.remainingText { Text(remaining) }
            }
            .font(.system(size: 9))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func button(_ symbol: String, _ intent: NotchIntent) -> some View {
        Button {
            emit(intent)
        } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol.replacingOccurrences(of: ".fill", with: ""))
    }
}
```

- [ ] **Step 5: Show media in `NotchRootView`**

Replace `leadingEar` and `detailRow` so media takes the leading ear when present,
and the expanded state shows the panel:

```swift
    @ViewBuilder private var leadingEar: some View {
        if let symbol = controller.activities.first?.symbolName {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .transition(.blurReplace)
        } else if let media = controller.media {
            Group {
                if let data = media.artwork, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.white.opacity(0.25))
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .padding(.horizontal, 6)
        } else if controller.activityCount > 0 {
            Circle().fill(.white.opacity(0.28)).padding(6)
        }
    }

    @ViewBuilder private var detailRow: some View {
        if controller.state == .expanded, let media = controller.media {
            MediaPanelView(
                media: media,
                notchHeight: controller.metrics.notchRect.height,
                emit: { controller.emit($0) }
            )
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(controller.activities) { activity in
                    Text(activity.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .transition(.blurReplace)
                    if let fill = activity.barFill {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.22))
                                Capsule().fill(.white)
                                    .frame(width: geometry.size.width * fill)
                            }
                        }
                        .frame(height: 4)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
```

- [ ] **Step 6: Wire media into `AppModel`**

```swift
    private let media = MediaService()
    private var mediaPayload = MediaPayload()
    private var positionTimer: Timer?

    var mediaStatus: String { media.availability.statusText }
```

In `start()`:

```swift
        let mediaStream = media.start()
        tasks.append(Task { [weak self] in
            for await payload in mediaStream {
                self?.handle(payload)
            }
        })

        presenter.controller.onIntent = { [weak self] intent in
            self?.handle(intent)
        }
```

Add handlers:

```swift
    private func handle(_ payload: MediaPayload) {
        mediaPayload = payload

        guard payload.hasMedia, let title = payload.title else {
            queue.remove(kind: .media)
            presenter.controller.setMedia(nil)
            stopPositionTicking()
            publish()
            return
        }

        queue.insert(
            ActivityRecord(
                id: ActivityKind.media.rawValue,
                kind: .media,
                insertedAt: Date(),
                ttl: nil,                     // sticky
                title: title,
                detail: payload.artist
            )
        )
        refreshMediaPresentation()
        payload.isPlaying ? startPositionTicking() : stopPositionTicking()
        publish()
    }

    private func handle(_ intent: NotchIntent) {
        switch intent {
        case .togglePlayPause: media.send(.togglePlayPause)
        case .next:            media.send(.nextTrack)
        case .previous:        media.send(.previousTrack)
        case .seek(let fraction):
            guard let duration = mediaPayload.duration, duration > 0 else { return }
            media.send(.seek(seconds: duration * fraction))
        }
    }

    /// 1 Hz, and only while something is playing — the adapter is never polled.
    private func startPositionTicking() {
        guard positionTimer == nil else { return }
        positionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMediaPresentation() }
        }
    }

    private func stopPositionTicking() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func refreshMediaPresentation() {
        guard mediaPayload.hasMedia, let title = mediaPayload.title else { return }
        let elapsed = MediaPosition.elapsed(
            at: Date(),
            elapsedTime: mediaPayload.elapsedTime ?? 0,
            timestamp: mediaPayload.timestamp ?? Date(),
            rate: mediaPayload.isPlaying ? (mediaPayload.playbackRate ?? 1) : 0,
            duration: mediaPayload.duration
        )
        presenter.controller.setMedia(
            MediaPresentation(
                title: title,
                artist: mediaPayload.artist,
                artwork: mediaPayload.artworkData,
                isPlaying: mediaPayload.isPlaying,
                elapsed: elapsed,
                duration: mediaPayload.duration
            )
        )
    }
```

In `stop()`, add `stopPositionTicking()` and `media.stop()`.

- [ ] **Step 7: Add the media status row in `AppDelegate`**

```swift
        item.setStatus(key: "media", text: "Media — \(model.mediaStatus)")
```

- [ ] **Step 8: Run the full suite**

Run: `swift test`
Expected: PASS — every target.

- [ ] **Step 9: Verify media by hand**

Run: `make install && open /Applications/Ledge.app`

(Install rather than `make dev` here, because the adapter resolves paths from the
bundle and `/Applications` is where it will really live.)

Record in `docs/manual-checks.md`:
1. Start playing in Music.app → artwork appears in the leading ear, island stays compact.
2. Click the island → panel opens with title, artist, artwork, scrubber and controls.
3. Play/pause, next, previous all work and the icon flips correctly.
4. Drag the scrubber → playback jumps there.
5. Elapsed time advances once a second while playing and freezes when paused.
6. Switch to Spotify or a YouTube tab → metadata follows the new source.
7. Stop all playback → the media activity disappears and the island goes quiet.
8. Change the volume while music plays → HUD takes the leading slot (priority 100 over 10), then the island returns to showing media.
9. Menu bar shows `Media — ready`.
10. Delete `Contents/Resources/mediaremote-adapter` from the installed bundle and relaunch → app still launches, `Media — unavailable`, and the HUD and power features keep working (Review Focus 5).

- [ ] **Step 10: Commit**

```bash
git add Sources/NotchKit Sources/Ledge Tests/NotchKitTests/MediaPresentationTests.swift docs/manual-checks.md
git commit -m "feat: now-playing in the island with panel controls and local position ticking"
```

---

## Done when

- `swift test` passes across `NotchKitTests`, `NotchWindowTests`, `ActivityKitTests`, `PowerServiceTests`, `HUDServiceTests` and `MediaServiceTests`.
- Volume, mute and brightness changes show notch HUDs and the stock overlay never appears — and **returns reliably** after `pkill -9`.
- Now-playing works with controls, scrubbing and a 1 Hz local position tick.
- Removing the vendored adapter degrades to `Media — unavailable` with everything else intact.
- `docs/private-api-notes.md` records every private symbol used, its verification status, and what breaks if Apple removes it.
- `docs/manual-checks.md` records all 8 HUD checks and all 10 media checks.
- Remaining phases: 5 (`DeviceService`), 6 (Settings UI), 7 (`NotificationService`), 8 (`LockScreenService`) — each needs its own plan against the same spec.
