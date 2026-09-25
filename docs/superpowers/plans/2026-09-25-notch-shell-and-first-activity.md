# Notch Shell and First Activity — Implementation Plan (Phases 0–2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A launchable macOS agent app whose notch island morphs open and closed on a spring, claims no clicks it does not own, and displays a real charging activity driven by live IOKit power events.

**Architecture:** A fixed oversized transparent `NSPanel` hosts a SwiftUI island that animates *inside* it; the window itself never resizes. All logic lives in pure, AppKit-free modules (`NotchGeometry`, `NotchShape`, `NotchController`, `ActivityQueue`, `PowerEventDeriver`) that are unit-tested in isolation, with thin platform shells around them. Data flows one way: service → queue → controller → view.

**Tech Stack:** Swift 6.4 (language mode 6, strict concurrency), SwiftPM, SwiftUI + AppKit, Swift Testing, IOKit `IOPowerSources`, GNU make. No third-party dependencies in this plan.

**Spec:** `docs/superpowers/specs/2026-09-25-notch-companion-design.md`

## Global Constraints

- Platform floor: `.macOS("27.0")` in `Package.swift`; `LSMinimumSystemVersion` `27.0` in Info.plist.
- Swift language mode 6, strict concurrency. All cross-actor types `Sendable`.
- Toolchain: the **active Command Line Tools** Swift (verified: builds SwiftUI, runs Swift Testing). Do **not** add `DEVELOPER_DIR` or require `xcodebuild`; the Xcode licence has not been accepted and is not needed.
- App name `Ledge`; bundle id `com.dedemahendra.ledge`; agent app (`LSUIElement = true`, `.accessory` activation policy).
- Notch geometry is **never hardcoded** outside test fixtures. Production code reads it from the screen. Measured reference values for fixtures: notch `179 × 32` pt at origin x `645.5`; screen `1470 × 956` pt @2x; `safeAreaInsets.top` `32`.
- Motion: expand `response 0.35, dampingFraction 0.72`; collapse `response 0.30, dampingFraction 0.92`. Content opacity ramps over animation progress `0.45 → 0.83`.
- Shape parameters: width `179 → 390`, height `32 → 118`, bottom radius `9 → 26`, outer fillet `0 → 13`.
- **No content may be drawn inside the notch rect** (it has no pixels). Debug builds assert this.
- No modal alerts on any failure path, ever.
- `OSLog` per module. Nothing user-content-bearing logged above `.debug`.
- No network access. No telemetry.
- Signing: every build signs with the self-signed identity `Ledge Dev` so TCC grants survive rebuilds. Never `codesign -s -`.

## Review Focus

Input classes the spec implies that no task's happy path exercises. Each has its test assigned to the task owning the code.

1. **Display scaling changes while the island is expanded** — geometry recomputes mid-animation; the hit-test path must not be left stale, or the app silently swallows clicks across the top of the screen. → Task 5.
2. **Main screen has no notch** (external display, or a future non-notch Mac) — `NotchGeometry` must return `nil` and the island must hide, never draw a guessed rect. → Task 2, Task 6.
3. **Built-in display absent from `NSScreen.screens`** (clamshell) — must hide without crashing or positioning a window offscreen. → Task 2, Task 6.
4. **State is `.hidden` / window ordered out** — hit testing must claim *nothing*. A hidden agent app that eats clicks is the worst failure this app can have. → Task 5.
5. **Two activities expiring on the same prune tick while hovered** — hover suppresses both; un-hovering must then expire both with no lost update and no partial state. → Task 7.

## File Structure

```
ledge/
  Package.swift                          targets; each task appends its own
  Makefile                               cert / dev / release / bundle / sign / install / run / test
  Info.plist.in                          templated: @APP_NAME@, @BUNDLE_ID@
  scripts/make-cert.sh                   one-time self-signed code-signing identity
  Sources/
    Ledge/
      main.swift                         top-level entry, .accessory policy
      AppDelegate.swift                  lifecycle, owns AppModel
      AppModel.swift                     wires services → queue → controller (from Task 8)
      StatusItemController.swift         menu bar item: status rows + Quit
    NotchKit/
      ScreenDescribing.swift             protocol + NSScreen conformance
      NotchGeometry.swift                PURE: screen description → notch rect
      NotchMetrics.swift                 PURE: spec constants, layout maths
      NotchShape.swift                   PURE: animatable Path
      NotchController.swift              @MainActor @Observable state machine
      NotchWindow.swift                  NSPanel subclass
      NotchHostingView.swift             NSHostingView subclass, path hit-testing
      NotchRootView.swift                SwiftUI root, drives the morph
    ActivityKit/
      ActivityKind.swift                 PURE: kinds, priorities, default TTLs
      ActivityRecord.swift               PURE: value type
      ActivityQueue.swift                PURE: insert / coalesce / prune / visible / overflow
    PowerService/
      PowerSnapshot.swift                PURE: IOKit dictionary → snapshot
      PowerEventDeriver.swift            PURE: snapshot transitions → domain events
      PowerService.swift                 IOKit run-loop shell → AsyncStream
  Tests/
    NotchKitTests/                       geometry, metrics, shape, controller
    ActivityKitTests/                    queue behaviour
    PowerServiceTests/                   snapshot parsing, event derivation
    NotchWindowTests/                    real NSPanel: level, behaviour, hit testing
```

Pure modules carry the logic and all the tests. Platform shells are kept deliberately thin so that what cannot be unit-tested is also nearly trivial.

---

### Task 1: Project skeleton that launches, signs, and quits

**Files:**
- Create: `Package.swift`
- Create: `Makefile`
- Create: `Info.plist.in`
- Create: `scripts/make-cert.sh`
- Create: `Sources/Ledge/main.swift`
- Create: `Sources/Ledge/AppDelegate.swift`
- Create: `Sources/Ledge/StatusItemController.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `AppDelegate` (class, `NSApplicationDelegate`); `StatusItemController` with `init()` and `func addItem(title: String, action: @escaping () -> Void)`; a `make dev` target that builds, bundles, signs and relaunches; identity name `Ledge Dev`.

TDD does not apply to build scaffolding. This task's deliverable is verified by running it: a signed agent app appears in the menu bar and quits cleanly.

- [ ] **Step 1: Create `Package.swift` with only the executable target**

Later tasks append their own targets. An SwiftPM target with no sources fails to build, so targets arrive with their files.

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ledge",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(name: "Ledge", path: "Sources/Ledge")
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 2: Create `Info.plist.in`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>@APP_NAME@</string>
    <key>CFBundleExecutable</key><string>@APP_NAME@</string>
    <key>CFBundleIdentifier</key><string>@BUNDLE_ID@</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>27.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
```

- [ ] **Step 3: Create `scripts/make-cert.sh`**

`security find-identity -v -p codesigning` currently reports `0 valid identities found`, so this must run once before any signed build. The `openssl` portion is verified working on this machine.

```bash
#!/usr/bin/env bash
# One-time: create a self-signed code-signing identity so TCC grants survive rebuilds.
set -euo pipefail

IDENTITY="${1:-Ledge Dev}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# `security import` needs BOTH of these to be true, independently — verified
# matrix, 2026-09-25:
#
#   openssl                    password    security import
#   -------------------------  ----------  -----------------------------
#   Homebrew 3.6.4 default     empty       FAIL (MAC verification failed)
#   Homebrew 3.6.4 default     non-empty   FAIL (MAC verification failed)
#   Homebrew 3.6.4 -legacy     empty       FAIL (MAC verification failed)
#   Homebrew 3.6.4 -legacy     non-empty   OK
#   LibreSSL 3.3.6 default     empty       FAIL (MAC verification failed)
#   LibreSSL 3.3.6 default     non-empty   OK
#
# 1. A non-empty PKCS#12 transport password. It protects nothing — the file
#    lives in a temp dir for one command — it only has to be non-empty.
# 2. A legacy-format p12. OpenSSL 3.x defaults to AES/SHA-256 which
#    `security import` cannot read; LibreSSL's default is already compatible.
#
# Hence /usr/bin/openssl is pinned below rather than passing `-legacy`:
# LibreSSL rejects `-legacy` outright ("unknown option"), so a single code path
# is only possible by pinning the system binary, which macOS always ships.
P12PASS="ledge-transport"

# NOT `-v`: a self-signed certificate is legitimately untrusted, and
# `find-identity -v` lists only trusted identities, so it reports 0 even after a
# successful import. `codesign` signs happily with an untrusted identity.
if security find-identity -p codesigning | grep -q "$IDENTITY"; then
    echo "Identity '$IDENTITY' already exists — nothing to do."
    exit 0
fi

echo "Minting self-signed code-signing certificate '$IDENTITY'..."
/usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$IDENTITY" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# Pinned: see the matrix above. A Homebrew openssl earlier in PATH produces a
# p12 that `security import` cannot read.
/usr/bin/openssl pkcs12 -export -out "$WORK/identity.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -passout "pass:$P12PASS" -name "$IDENTITY"

echo "Importing into the login keychain."
echo "macOS may ask you to allow keychain access — click Allow."
security import "$WORK/identity.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$P12PASS" -T /usr/bin/codesign -A

echo
echo "Result:"
security find-identity -p codesigning | grep "$IDENTITY" \
    || { echo "FAILED: identity not found after import." >&2
         echo "Fallback: Keychain Access → Certificate Assistant →" >&2
         echo "  Create a Certificate: name '$IDENTITY', type 'Code Signing', self-signed." >&2
         exit 1; }
echo "Done. 'make dev' will now sign with '$IDENTITY'."
```

- [ ] **Step 4: Create `Makefile`**

Recursive `$(MAKE) CONF=...` rather than target-specific variables, which leak into prerequisites confusingly. No `--options runtime`: the hardened runtime blocks private-framework loading that later phases need, and this app is never distributed. No `--deep` (deprecated).

```make
APP      := Ledge
BUNDLE   := com.dedemahendra.ledge
IDENTITY := Ledge Dev
CONF     ?= debug
BUILDDIR := .build/$(CONF)
DIST     := dist
APPDIR   := $(DIST)/$(APP).app

.PHONY: all dev release test build bundle sign install run stop cert clean

all: release

cert:
	@bash scripts/make-cert.sh "$(IDENTITY)"

test:
	swift test

build:
	swift build -c $(CONF)

bundle: build
	rm -rf "$(APPDIR)"
	mkdir -p "$(APPDIR)/Contents/MacOS" "$(APPDIR)/Contents/Resources"
	cp "$(BUILDDIR)/$(APP)" "$(APPDIR)/Contents/MacOS/$(APP)"
	sed -e 's/@APP_NAME@/$(APP)/g' -e 's/@BUNDLE_ID@/$(BUNDLE)/g' \
	    Info.plist.in > "$(APPDIR)/Contents/Info.plist"
	printf 'APPL????' > "$(APPDIR)/Contents/PkgInfo"

sign: bundle
	codesign --force --sign "$(IDENTITY)" "$(APPDIR)"
	@codesign -dv --verbose=2 "$(APPDIR)" 2>&1 | grep -E 'Identifier|Authority' || true

stop:
	-@pkill -x $(APP) 2>/dev/null || true

run: stop
	open "$(APPDIR)"

dev:
	$(MAKE) CONF=debug sign
	$(MAKE) run

release:
	$(MAKE) CONF=release sign

install: release
	rm -rf "/Applications/$(APP).app"
	cp -R "$(APPDIR)" /Applications/

clean:
	rm -rf .build "$(DIST)"
```

- [ ] **Step 5: Create `Sources/Ledge/main.swift`**

Top-level code in `main.swift`, not `@main`, so AppKit setup order is explicit.

```swift
import AppKit

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 6: Create `Sources/Ledge/StatusItemController.swift`**

```swift
import AppKit

/// The app's only chrome: a menu bar item carrying status rows and Quit.
@MainActor
final class StatusItemController {
    private let item: NSStatusItem
    private let menu = NSMenu()

    init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "Ledge"
        )
        item.menu = menu
        addSeparator()
        addItem(title: "Quit Ledge") { NSApp.terminate(nil) }
    }

    func addSeparator() {
        menu.addItem(.separator())
    }

    /// Inserts an item above the trailing separator + Quit pair.
    func addItem(title: String, action: @escaping () -> Void) {
        let entry = NSMenuItem(title: title, action: #selector(Trampoline.fire), keyEquivalent: "")
        let trampoline = Trampoline(action)
        entry.target = trampoline
        // `target` is weak in AppKit's target-action pattern, so this strong
        // `representedObject` reference is what keeps the trampoline alive for
        // as long as the item is in the menu. Without it the closure would be
        // deallocated the moment this method returns.
        entry.representedObject = trampoline
        menu.addItem(entry)
    }

    /// Updates (or creates) a status row identified by `key`, e.g. "power".
    func setStatus(key: String, text: String) {
        if let existing = menu.items.first(where: { $0.identifier?.rawValue == key }) {
            existing.title = text
            return
        }
        let entry = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        entry.identifier = NSUserInterfaceItemIdentifier(key)
        entry.isEnabled = false
        menu.insertItem(entry, at: 0)
    }

    private final class Trampoline: NSObject {
        private let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }
}
```

- [ ] **Step 7: Create `Sources/Ledge/AppDelegate.swift`**

```swift
import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "app")

    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController()
        statusItem?.setStatus(key: "app", text: "Ledge — running")
        Self.log.info("launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.log.info("terminating")
    }
}
```

- [ ] **Step 8: Create the signing identity (once)**

Run: `make cert`
Expected: `1 identity imported.` followed by a line containing `Ledge Dev`. A keychain access prompt is normal — allow it. If import fails, the script prints the Keychain Access fallback; follow it, then re-run `make cert` to confirm.

Note: `security find-identity -v -p codesigning` will still report **0 valid identities** afterwards, and that is correct — `-v` counts only *trusted* identities, and a self-signed certificate is untrusted by design. Use `security find-identity -p codesigning` (no `-v`) to see it. Trust is deliberately not configured: `codesign` signs fine without it, and adding trust would need `sudo` for no benefit.

- [ ] **Step 9: Build, sign and launch**

Run: `make dev`
Expected: `Build complete!`, `codesign -dv` output containing `Identifier=com.dedemahendra.ledge` and `Authority=Ledge Dev`, and a new icon in the menu bar with rows `Ledge — running` and `Quit Ledge`. No Dock icon, no window.

- [ ] **Step 10: Verify it is a real agent app and quits cleanly**

Run:
```bash
pgrep -x Ledge && echo "running"
codesign -dv --verbose=2 dist/Ledge.app 2>&1 | grep -E 'Identifier|Authority|Signature'
pkill -x Ledge; sleep 1; pgrep -x Ledge || echo "exited cleanly"
```
Expected: `running`, an `Authority=Ledge Dev` line, then `exited cleanly`.

- [ ] **Step 11: Commit**

```bash
git add Package.swift Makefile Info.plist.in scripts/make-cert.sh Sources/Ledge
git commit -m "feat: agent app skeleton with signed bundle and menu bar item"
```

---

### Task 2: `NotchGeometry` — screen description to notch rect

**Files:**
- Create: `Sources/NotchKit/ScreenDescribing.swift`
- Create: `Sources/NotchKit/NotchGeometry.swift`
- Create: `Tests/NotchKitTests/NotchGeometryTests.swift`
- Modify: `Package.swift` (add `NotchKit` target and `NotchKitTests` test target)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `protocol ScreenDescribing: Sendable` with `var frame: CGRect`, `var safeAreaTopInset: CGFloat`, `var auxiliaryTopLeftMaxX: CGFloat?`, `var auxiliaryTopRightMinX: CGFloat?`, `var isBuiltIn: Bool`
  - `struct FakeScreen: ScreenDescribing` (test support, in the test target)
  - `enum NotchGeometry { static func notchRect(for screen: some ScreenDescribing) -> CGRect? }` — returns a rect in **top-left-origin island space**: `x` in screen points from the screen's left edge, `y = 0` at the screen's top edge. Returns `nil` when the screen has no notch.

- [ ] **Step 1: Add the `NotchKit` targets to `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ledge",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(name: "Ledge", dependencies: ["NotchKit"], path: "Sources/Ledge"),
        .target(name: "NotchKit"),
        .testTarget(name: "NotchKitTests", dependencies: ["NotchKit"]),
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/NotchKitTests/NotchGeometryTests.swift`. These cover Review Focus items 2 and 3 as well as the happy path.

```swift
import Testing
import CoreGraphics
@testable import NotchKit

struct FakeScreen: ScreenDescribing {
    var frame: CGRect
    var safeAreaTopInset: CGFloat
    var auxiliaryTopLeftMaxX: CGFloat?
    var auxiliaryTopRightMinX: CGFloat?
    var isBuiltIn: Bool = true

    /// The measured built-in display of the target machine.
    static let measured = FakeScreen(
        frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        safeAreaTopInset: 32,
        auxiliaryTopLeftMaxX: 645.5,
        auxiliaryTopRightMinX: 824.5
    )
}

@Test func measuredScreenYieldsTheMeasuredNotch() throws {
    let rect = try #require(NotchGeometry.notchRect(for: FakeScreen.measured))
    #expect(rect.width == 179)
    #expect(rect.height == 32)
    #expect(rect.minX == 645.5)
    #expect(rect.minY == 0)
}

@Test func notchIsHorizontallyCentred() throws {
    let screen = FakeScreen.measured
    let rect = try #require(NotchGeometry.notchRect(for: screen))
    #expect(abs(rect.midX - screen.frame.midX) < 0.01)
}

// Review Focus 2: no notch must mean no island, never a guessed rect.
@Test func screenWithoutAuxiliaryAreasHasNoNotch() {
    var screen = FakeScreen.measured
    screen.auxiliaryTopLeftMaxX = nil
    screen.auxiliaryTopRightMinX = nil
    #expect(NotchGeometry.notchRect(for: screen) == nil)
}

@Test func screenWithoutTopSafeAreaHasNoNotch() {
    var screen = FakeScreen.measured
    screen.safeAreaTopInset = 0
    #expect(NotchGeometry.notchRect(for: screen) == nil)
}

// Review Focus 3: an external display is not a host, even if it reports oddities.
@Test func externalScreenHasNoNotch() {
    var screen = FakeScreen.measured
    screen.isBuiltIn = false
    #expect(NotchGeometry.notchRect(for: screen) == nil)
}

@Test func degenerateAuxiliaryOrderingHasNoNotch() {
    var screen = FakeScreen.measured
    screen.auxiliaryTopLeftMaxX = 824.5
    screen.auxiliaryTopRightMinX = 645.5   // inverted
    #expect(NotchGeometry.notchRect(for: screen) == nil)
}

@Test func scaledModeYieldsDifferentButValidGeometry() throws {
    // A "more space" scaling mode: wider logical screen, proportionally narrower notch.
    let screen = FakeScreen(
        frame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
        safeAreaTopInset: 37,
        auxiliaryTopLeftMaxX: 751,
        auxiliaryTopRightMinX: 959
    )
    let rect = try #require(NotchGeometry.notchRect(for: screen))
    #expect(rect.width == 208)
    #expect(rect.height == 37)
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter NotchGeometryTests`
Expected: FAIL — `cannot find 'NotchGeometry' in scope` and `cannot find type 'ScreenDescribing' in scope`.

- [ ] **Step 4: Write `Sources/NotchKit/ScreenDescribing.swift`**

```swift
import AppKit
import CoreGraphics

/// The subset of a display Ledge needs. Abstracted so geometry is testable
/// without a real `NSScreen`.
public protocol ScreenDescribing: Sendable {
    var frame: CGRect { get }
    var safeAreaTopInset: CGFloat { get }
    /// Right edge of the menu bar area to the left of the notch.
    var auxiliaryTopLeftMaxX: CGFloat? { get }
    /// Left edge of the menu bar area to the right of the notch.
    var auxiliaryTopRightMinX: CGFloat? { get }
    var isBuiltIn: Bool { get }
}

/// Snapshot of an `NSScreen`, taken on the main actor and safe to pass around.
public struct ScreenSnapshot: ScreenDescribing {
    public let frame: CGRect
    public let safeAreaTopInset: CGFloat
    public let auxiliaryTopLeftMaxX: CGFloat?
    public let auxiliaryTopRightMinX: CGFloat?
    public let isBuiltIn: Bool

    public init(
        frame: CGRect,
        safeAreaTopInset: CGFloat,
        auxiliaryTopLeftMaxX: CGFloat?,
        auxiliaryTopRightMinX: CGFloat?,
        isBuiltIn: Bool
    ) {
        self.frame = frame
        self.safeAreaTopInset = safeAreaTopInset
        self.auxiliaryTopLeftMaxX = auxiliaryTopLeftMaxX
        self.auxiliaryTopRightMinX = auxiliaryTopRightMinX
        self.isBuiltIn = isBuiltIn
    }
}

@MainActor
extension NSScreen {
    /// The display carrying the notch, or `nil` in clamshell mode.
    /// Review Focus 3: `NSScreen.screens` omits the built-in display when the lid is shut.
    public static var builtIn: NSScreen? {
        screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }
    }

    public func snapshot() -> ScreenSnapshot {
        ScreenSnapshot(
            frame: frame,
            safeAreaTopInset: safeAreaInsets.top,
            auxiliaryTopLeftMaxX: auxiliaryTopLeftArea?.maxX,
            auxiliaryTopRightMinX: auxiliaryTopRightArea?.minX,
            isBuiltIn: safeAreaInsets.top > 0 && auxiliaryTopLeftArea != nil
        )
    }
}
```

- [ ] **Step 5: Write `Sources/NotchKit/NotchGeometry.swift`**

```swift
import CoreGraphics

/// Derives the notch rectangle from a display description.
///
/// Result is in **island space**: x measured from the screen's left edge,
/// `y = 0` at the screen's top edge, growing downward.
///
/// Returns `nil` whenever a notch cannot be established. Never guesses:
/// a wrong rect would put the island over live pixels or over the camera.
public enum NotchGeometry {
    public static func notchRect(for screen: some ScreenDescribing) -> CGRect? {
        guard screen.isBuiltIn else { return nil }

        let height = screen.safeAreaTopInset
        guard height > 0 else { return nil }

        guard
            let leadingEdge = screen.auxiliaryTopLeftMaxX,
            let trailingEdge = screen.auxiliaryTopRightMinX
        else { return nil }

        let width = trailingEdge - leadingEdge
        guard width > 0 else { return nil }

        return CGRect(x: leadingEdge, y: 0, width: width, height: height)
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter NotchGeometryTests`
Expected: PASS — 7 tests.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/NotchKit Tests/NotchKitTests
git commit -m "feat: derive notch geometry from display description"
```

---

### Task 3: `NotchMetrics` and `NotchShape` — the animatable island path

**Files:**
- Create: `Sources/NotchKit/NotchMetrics.swift`
- Create: `Sources/NotchKit/NotchShape.swift`
- Create: `Tests/NotchKitTests/NotchShapeTests.swift`

**Interfaces:**
- Consumes: `NotchGeometry` (Task 2).
- Produces:
  - `struct NotchMetrics: Sendable` — `notchRect`, plus `collapsed`, `peek`, `oneActivity`, `twoActivities`, `expanded` each a `NotchShapeParameters`; plus `static let canvasSize = CGSize(width: 640, height: 320)` and `func contentOpacity(progress:) -> Double`
  - `struct NotchShapeParameters: Sendable, Equatable, Animatable` — `width`, `height`, `bottomRadius`, `outerFillet`, with `static func lerp(_:_:_:)`
  - `struct NotchShape: Shape` — `init(_ parameters: NotchShapeParameters)`, `func path(in:) -> Path`

- [ ] **Step 1: Write the failing tests**

Create `Tests/NotchKitTests/NotchShapeTests.swift`.

```swift
import Testing
import CoreGraphics
import SwiftUI
@testable import NotchKit

private let measuredNotch = CGRect(x: 645.5, y: 0, width: 179, height: 32)

@Test func collapsedParametersMatchTheMeasuredNotch() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    #expect(metrics.collapsed.width == 179)
    #expect(metrics.collapsed.height == 32)
    #expect(metrics.collapsed.bottomRadius == 9)
    #expect(metrics.collapsed.outerFillet == 0)
}

@Test func specifiedTargetGeometryIsHonoured() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    #expect(metrics.peek.height == 38)                  // notch + 6
    #expect(metrics.oneActivity.width == 255)
    #expect(metrics.oneActivity.height == 32)
    #expect(metrics.twoActivities.width == 342)
    #expect(metrics.twoActivities.height == 62)
    #expect(metrics.expanded.width == 390)
    #expect(metrics.expanded.height == 118)
    #expect(metrics.expanded.bottomRadius == 26)
    #expect(metrics.expanded.outerFillet == 13)
}

@Test func earWidthLeavesRoomBesideTheHole() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    #expect((metrics.oneActivity.width - 179) / 2 == 38)
    #expect((metrics.twoActivities.width - 179) / 2 == 81.5)
}

@Test func interpolationIsMonotonicAndBounded() {
    let a = NotchShapeParameters(width: 179, height: 32, bottomRadius: 9, outerFillet: 0)
    let b = NotchShapeParameters(width: 390, height: 118, bottomRadius: 26, outerFillet: 13)
    var previousWidth = a.width
    var previousHeight = a.height
    for step in 0...10 {
        let p = Double(step) / 10
        let mid = NotchShapeParameters.lerp(a, b, p)
        #expect(mid.width >= previousWidth)
        #expect(mid.height >= previousHeight)
        #expect(mid.outerFillet >= 0)          // never negative — the seam would invert
        #expect(mid.bottomRadius >= 0)
        previousWidth = mid.width
        previousHeight = mid.height
    }
    #expect(NotchShapeParameters.lerp(a, b, 0) == a)
    #expect(NotchShapeParameters.lerp(a, b, 1) == b)
}

@Test func animatableDataRoundTrips() {
    var p = NotchShapeParameters(width: 200, height: 40, bottomRadius: 12, outerFillet: 4)
    let captured = p.animatableData
    p.width = 0; p.height = 0; p.bottomRadius = 0; p.outerFillet = 0
    p.animatableData = captured
    #expect(p.width == 200)
    #expect(p.height == 40)
    #expect(p.bottomRadius == 12)
    #expect(p.outerFillet == 4)
}

@Test func collapsedPathBoundsEqualTheNotch() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    let bounds = NotchShape(metrics.collapsed).path(in: canvas).boundingRect
    // Fillet is 0 when collapsed, so bounds are exactly the island body.
    #expect(abs(bounds.width - 179) < 0.5)
    #expect(abs(bounds.height - 32) < 0.5)
    #expect(abs(bounds.midX - canvas.midX) < 0.5)
    #expect(abs(bounds.minY - canvas.minY) < 0.5)
}

@Test func expandedPathIsWiderByExactlyTwoFillets() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    let bounds = NotchShape(metrics.expanded).path(in: canvas).boundingRect
    #expect(abs(bounds.width - (390 + 2 * 13)) < 0.5)
    #expect(abs(bounds.height - 118) < 0.5)
}

@Test func pathIsAlwaysWeldedToTheTopEdge() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    for p in [metrics.collapsed, metrics.peek, metrics.oneActivity, metrics.expanded] {
        let bounds = NotchShape(p).path(in: canvas).boundingRect
        #expect(abs(bounds.minY - canvas.minY) < 0.5, "island must stay welded to the bezel")
    }
}

@Test func contentOpacityRampsOverTheSpecifiedWindow() {
    let metrics = NotchMetrics(notchRect: measuredNotch)
    #expect(metrics.contentOpacity(progress: 0.0) == 0)
    #expect(metrics.contentOpacity(progress: 0.45) == 0)
    #expect(metrics.contentOpacity(progress: 0.83) == 1)
    #expect(metrics.contentOpacity(progress: 1.0) == 1)
    let mid = metrics.contentOpacity(progress: 0.64)
    #expect(mid > 0.4 && mid < 0.6)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NotchShapeTests`
Expected: FAIL — `cannot find 'NotchMetrics' in scope`.

- [ ] **Step 3: Write `Sources/NotchKit/NotchMetrics.swift`**

```swift
import CoreGraphics

/// Geometry of the island at each resting size, derived from the live notch.
/// Target sizes come from the spec; the collapsed size comes from the hardware.
public struct NotchMetrics: Sendable, Equatable {
    /// Transparent canvas the island animates inside. The window is this size
    /// and never resizes — see spec §5.
    public static let canvasSize = CGSize(width: 640, height: 320)

    /// Progress window over which content fades in.
    public static let contentFadeIn: ClosedRange<Double> = 0.45...0.83

    public let notchRect: CGRect

    public init(notchRect: CGRect) {
        self.notchRect = notchRect
    }

    public var collapsed: NotchShapeParameters {
        NotchShapeParameters(
            width: notchRect.width,
            height: notchRect.height,
            bottomRadius: 9,
            outerFillet: 0
        )
    }

    public var peek: NotchShapeParameters {
        NotchShapeParameters(
            width: notchRect.width,
            height: notchRect.height + 6,
            bottomRadius: 11,
            outerFillet: 4
        )
    }

    public var oneActivity: NotchShapeParameters {
        NotchShapeParameters(width: 255, height: 32, bottomRadius: 12, outerFillet: 6)
    }

    public var twoActivities: NotchShapeParameters {
        NotchShapeParameters(width: 342, height: 62, bottomRadius: 20, outerFillet: 10)
    }

    public var expanded: NotchShapeParameters {
        NotchShapeParameters(width: 390, height: 118, bottomRadius: 26, outerFillet: 13)
    }

    /// Ear width available beside the hole at a given island width.
    public func earWidth(forIslandWidth width: CGFloat) -> CGFloat {
        max(0, (width - notchRect.width) / 2)
    }

    public func contentOpacity(progress: Double) -> Double {
        let range = Self.contentFadeIn
        if progress <= range.lowerBound { return 0 }
        if progress >= range.upperBound { return 1 }
        return (progress - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}
```

- [ ] **Step 4: Write `Sources/NotchKit/NotchShape.swift`**

```swift
import SwiftUI

/// The four animated dimensions of the island.
public struct NotchShapeParameters: Sendable, Equatable, Animatable {
    public var width: CGFloat
    public var height: CGFloat
    public var bottomRadius: CGFloat
    public var outerFillet: CGFloat

    public init(width: CGFloat, height: CGFloat, bottomRadius: CGFloat, outerFillet: CGFloat) {
        self.width = width
        self.height = height
        self.bottomRadius = bottomRadius
        self.outerFillet = outerFillet
    }

    public var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, CGFloat>
    > {
        get {
            AnimatablePair(
                AnimatablePair(width, height),
                AnimatablePair(bottomRadius, outerFillet)
            )
        }
        set {
            width = newValue.first.first
            height = newValue.first.second
            bottomRadius = newValue.second.first
            outerFillet = newValue.second.second
        }
    }

    public static func lerp(
        _ a: NotchShapeParameters,
        _ b: NotchShapeParameters,
        _ t: Double
    ) -> NotchShapeParameters {
        let t = CGFloat(min(max(t, 0), 1))
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
        return NotchShapeParameters(
            width: mix(a.width, b.width),
            height: mix(a.height, b.height),
            bottomRadius: mix(a.bottomRadius, b.bottomRadius),
            outerFillet: mix(a.outerFillet, b.outerFillet)
        )
    }
}

/// The island: square top welded to the bezel, rounded bottom corners, and
/// concave outer fillets blending the sides into the menu bar.
///
/// Hand-rolled because `UnevenRoundedRectangle` cannot produce concave corners.
public struct NotchShape: Shape {
    public var parameters: NotchShapeParameters

    public init(_ parameters: NotchShapeParameters) {
        self.parameters = parameters
    }

    public var animatableData: NotchShapeParameters.AnimatableData {
        get { parameters.animatableData }
        set { parameters.animatableData = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        let centreX = rect.midX
        let top = rect.minY
        let height = max(0, parameters.height)
        let halfWidth = max(0, parameters.width) / 2
        // Radii cannot exceed the box they round, or the path self-intersects.
        let bottomRadius = min(parameters.bottomRadius, halfWidth, height)
        let fillet = max(0, min(parameters.outerFillet, height - bottomRadius))

        let left = centreX - halfWidth
        let right = centreX + halfWidth
        let bottom = top + height

        var path = Path()
        path.move(to: CGPoint(x: left - fillet, y: top))

        if fillet > 0 {
            // Concave top-left: curves away from the island, into the menu bar.
            path.addArc(
                center: CGPoint(x: left - fillet, y: top + fillet),
                radius: fillet,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: left, y: bottom - bottomRadius))

        if bottomRadius > 0 {
            path.addArc(
                center: CGPoint(x: left + bottomRadius, y: bottom - bottomRadius),
                radius: bottomRadius,
                startAngle: .degrees(180),
                endAngle: .degrees(90),
                clockwise: true
            )
        }

        path.addLine(to: CGPoint(x: right - bottomRadius, y: bottom))

        if bottomRadius > 0 {
            path.addArc(
                center: CGPoint(x: right - bottomRadius, y: bottom - bottomRadius),
                radius: bottomRadius,
                startAngle: .degrees(90),
                endAngle: .degrees(0),
                clockwise: true
            )
        }

        path.addLine(to: CGPoint(x: right, y: top + fillet))

        if fillet > 0 {
            // Concave top-right.
            path.addArc(
                center: CGPoint(x: right + fillet, y: top + fillet),
                radius: fillet,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        }

        path.closeSubpath()
        return path
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter NotchShapeTests`
Expected: PASS — 9 tests. If `collapsedPathBoundsEqualTheNotch` or `expandedPathIsWiderByExactlyTwoFillets` fails on bounding width, the arc sweep direction is inverted: check that both fillet arcs use `clockwise: false` and both bottom arcs use `clockwise: true`.

- [ ] **Step 6: Commit**

```bash
git add Sources/NotchKit/NotchMetrics.swift Sources/NotchKit/NotchShape.swift Tests/NotchKitTests/NotchShapeTests.swift
git commit -m "feat: animatable notch shape with concave outer fillets"
```

---

### Task 4: `NotchController` — the state machine

**Files:**
- Create: `Sources/NotchKit/NotchController.swift`
- Create: `Tests/NotchKitTests/NotchControllerTests.swift`

**Interfaces:**
- Consumes: `NotchMetrics` (Task 3).
- Produces:
  - `enum NotchState: Sendable, Equatable { case hidden, peek, activity, expanded }`
  - `@MainActor @Observable final class NotchController` with:
    - `init(metrics: NotchMetrics, reduceMotion: Bool = false)`
    - `var state: NotchState { get }`
    - `var metrics: NotchMetrics` (settable — geometry can change at runtime)
    - `var isHovered: Bool { get }`
    - `var activityCount: Int { get }`
    - `func setHovered(_:)`, `func click()`, `func dismiss()`, `func setActivityCount(_:)`
    - `var parameters: NotchShapeParameters { get }`
    - `var isVisible: Bool { get }`

- [ ] **Step 1: Write the failing tests**

Create `Tests/NotchKitTests/NotchControllerTests.swift`.

```swift
import Testing
import CoreGraphics
@testable import NotchKit

@MainActor
private func makeController(reduceMotion: Bool = false) -> NotchController {
    NotchController(
        metrics: NotchMetrics(notchRect: CGRect(x: 645.5, y: 0, width: 179, height: 32)),
        reduceMotion: reduceMotion
    )
}

@MainActor
@Test func startsHiddenAndInvisible() {
    let c = makeController()
    #expect(c.state == .hidden)
    #expect(c.isVisible == false)
}

@MainActor
@Test func hoverPeeksAndUnhoverHides() {
    let c = makeController()
    c.setHovered(true)
    #expect(c.state == .peek)
    #expect(c.isVisible)
    c.setHovered(false)
    #expect(c.state == .hidden)
}

@MainActor
@Test func clickExpandsAndDismissCollapses() {
    let c = makeController()
    c.setHovered(true)
    c.click()
    #expect(c.state == .expanded)
    c.dismiss()
    #expect(c.state == .peek, "cursor is still over the island after dismissing")
    c.setHovered(false)
    #expect(c.state == .hidden)
}

@MainActor
@Test func expandedSurvivesTheCursorLeaving() {
    let c = makeController()
    c.setHovered(true)
    c.click()
    c.setHovered(false)
    #expect(c.state == .expanded, "an opened panel must not close just because the cursor left")
}

@MainActor
@Test func activityShowsWithoutHoverAndRestsOnActivityState() {
    let c = makeController()
    c.setActivityCount(1)
    #expect(c.state == .activity)
    #expect(c.isVisible)
    c.setActivityCount(0)
    #expect(c.state == .hidden)
}

@MainActor
@Test func activityArrivingWhileExpandedDoesNotCollapseThePanel() {
    let c = makeController()
    c.setHovered(true)
    c.click()
    c.setActivityCount(2)
    #expect(c.state == .expanded)
}

@MainActor
@Test func hoverOverAnActivityPeeksButKeepsTheActivityVisible() {
    let c = makeController()
    c.setActivityCount(1)
    c.setHovered(true)
    #expect(c.state == .activity, "hover must not shrink a live activity to peek size")
    #expect(c.isVisible)
}

@MainActor
@Test func lastActivityDisappearingWhileHoveredFallsBackToPeek() {
    let c = makeController()
    c.setActivityCount(1)
    c.setHovered(true)
    c.setActivityCount(0)
    #expect(c.state == .peek)
}

@MainActor
@Test func parametersTrackTheState() {
    let c = makeController()
    #expect(c.parameters == c.metrics.collapsed)
    c.setHovered(true)
    #expect(c.parameters == c.metrics.peek)
    c.setActivityCount(1)
    #expect(c.parameters == c.metrics.oneActivity)
    c.setActivityCount(2)
    #expect(c.parameters == c.metrics.twoActivities)
    c.setActivityCount(5)
    #expect(c.parameters == c.metrics.twoActivities, "three or more still uses the two-slot size")
    c.click()
    #expect(c.parameters == c.metrics.expanded)
}

// Review Focus 1: geometry can change under a live island.
@MainActor
@Test func changingMetricsUpdatesParametersImmediately() {
    let c = makeController()
    c.setHovered(true)
    c.click()
    #expect(c.parameters == c.metrics.expanded)
    c.metrics = NotchMetrics(notchRect: CGRect(x: 751, y: 0, width: 208, height: 37))
    #expect(c.parameters.height == 118, "expanded target is fixed by the spec")
    #expect(c.metrics.collapsed.width == 208, "collapsed follows the new hardware geometry")
}

@MainActor
@Test func reduceMotionIsReportedSoTheViewCanSwapTheAnimation() {
    #expect(makeController(reduceMotion: false).reduceMotion == false)
    #expect(makeController(reduceMotion: true).reduceMotion)
}

@MainActor
@Test func dismissFromHiddenIsANoOp() {
    let c = makeController()
    c.dismiss()
    #expect(c.state == .hidden)
}

@MainActor
@Test func clickWithoutHoverStillExpands() {
    // A click can arrive from a hit test without a preceding hover event.
    let c = makeController()
    c.click()
    #expect(c.state == .expanded)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NotchControllerTests`
Expected: FAIL — `cannot find 'NotchController' in scope`.

- [ ] **Step 3: Write `Sources/NotchKit/NotchController.swift`**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter NotchControllerTests`
Expected: PASS — 13 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchKit/NotchController.swift Tests/NotchKitTests/NotchControllerTests.swift
git commit -m "feat: notch state machine with hover, activity and panel precedence"
```

---

### Task 5: `NotchWindow` and path hit-testing

**Files:**
- Create: `Sources/NotchKit/NotchWindow.swift`
- Create: `Sources/NotchKit/NotchHostingView.swift`
- Create: `Tests/NotchWindowTests/NotchWindowTests.swift`
- Modify: `Package.swift` (add `NotchWindowTests` test target)

**Interfaces:**
- Consumes: `NotchGeometry`, `NotchMetrics`, `NotchShape`, `NotchController`.
- Produces:
  - `@MainActor final class NotchWindow: NSPanel` — `init(screen: NSScreen)`, `func reposition(for screen: NSScreen)`, `var interactivePath: CGPath?` (settable), `func setLocked(_ locked: Bool)`
  - `@MainActor final class NotchHostingView<Content: View>: NSHostingView<Content>` — `var interactivePath: CGPath?`, overridden `hitTest(_:)`

This is where Review Focus 1 and 4 are pinned. A hidden window that claims clicks is the worst possible failure, so it is asserted directly.

- [ ] **Step 1: Add the `NotchWindowTests` target to `Package.swift`**

Append inside `targets:`:

```swift
        .testTarget(name: "NotchWindowTests", dependencies: ["NotchKit"]),
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/NotchWindowTests/NotchWindowTests.swift`.

```swift
import Testing
import AppKit
import CoreGraphics
@testable import NotchKit

@MainActor
private func makeWindow() throws -> NotchWindow {
    let screen = try #require(NSScreen.main, "tests need a display")
    return NotchWindow(screen: screen)
}

@MainActor
@Test func windowIsAnInvisibleNonActivatingOverlay() throws {
    let w = try makeWindow()
    #expect(w.level.rawValue == NSWindow.Level.statusBar.rawValue + 1)
    #expect(w.isOpaque == false)
    #expect(w.hasShadow == false)
    #expect(w.backgroundColor == .clear)
    #expect(w.isMovable == false)
    #expect(w.hidesOnDeactivate == false)
    #expect(w.isFloatingPanel)
    #expect(w.styleMask.contains(.borderless))
    #expect(w.styleMask.contains(.nonactivatingPanel))
}

@MainActor
@Test func windowFollowsSpacesAndSurvivesFullscreen() throws {
    let w = try makeWindow()
    #expect(w.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(w.collectionBehavior.contains(.stationary))
    #expect(w.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(w.collectionBehavior.contains(.ignoresCycle))
}

@MainActor
@Test func canvasIsTheFixedOversizedSize() throws {
    let w = try makeWindow()
    #expect(w.frame.width == NotchMetrics.canvasSize.width)
    #expect(w.frame.height == NotchMetrics.canvasSize.height)
}

@MainActor
@Test func canvasIsAnchoredToTheTopCentreOfItsScreen() throws {
    let screen = try #require(NSScreen.main)
    let w = NotchWindow(screen: screen)
    #expect(abs(w.frame.midX - screen.frame.midX) < 1)
    #expect(abs(w.frame.maxY - screen.frame.maxY) < 1)
}

@MainActor
@Test func lockedStateRaisesAboveTheShield() throws {
    let w = try makeWindow()
    w.setLocked(true)
    #expect(w.level.rawValue == Int(CGShieldingWindowLevel()) + 1)
    w.setLocked(false)
    #expect(w.level.rawValue == NSWindow.Level.statusBar.rawValue + 1)
}

// --- hit testing: Review Focus 4 ---

@MainActor
@Test func noPathMeansTheWindowClaimsNothing() throws {
    let w = try makeWindow()
    w.interactivePath = nil
    let centre = CGPoint(x: w.frame.width / 2, y: w.frame.height / 2)
    #expect(w.hostingView.hitTest(centre) == nil,
            "a hidden island must never swallow a click")
}

@MainActor
@Test func pointsInsideThePathAreClaimedAndOutsideAreNot() throws {
    let w = try makeWindow()
    let box = CGRect(x: 100, y: 100, width: 200, height: 40)
    w.interactivePath = CGPath(rect: box, transform: nil)
    #expect(w.hostingView.hitTest(CGPoint(x: 200, y: 120)) != nil)
    #expect(w.hostingView.hitTest(CGPoint(x: 10, y: 10)) == nil)
    #expect(w.hostingView.hitTest(CGPoint(x: 200, y: 300)) == nil)
}

// Review Focus 1: repositioning must not leave a stale claim.
@MainActor
@Test func repositioningClearsTheStaleInteractivePath() throws {
    let screen = try #require(NSScreen.main)
    let w = NotchWindow(screen: screen)
    w.interactivePath = CGPath(rect: CGRect(x: 0, y: 0, width: 600, height: 300), transform: nil)
    w.reposition(for: screen)
    #expect(w.interactivePath == nil,
            "a path from the previous geometry would claim clicks in the wrong place")
    #expect(w.hostingView.hitTest(CGPoint(x: 300, y: 150)) == nil)
}

@MainActor
@Test func notchShapePathClaimsTheIslandAndNotTheMenuBarBesideIt() throws {
    let w = try makeWindow()
    let metrics = NotchMetrics(notchRect: CGRect(x: 645.5, y: 0, width: 179, height: 32))
    let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
    w.setInteractiveShape(NotchShape(metrics.collapsed), in: canvas)

    // In view coordinates the island hangs from the top edge of the canvas.
    let insideIsland = CGPoint(x: canvas.midX, y: canvas.maxY - 16)
    let besideIsland = CGPoint(x: canvas.midX - 200, y: canvas.maxY - 16)
    #expect(w.hostingView.hitTest(insideIsland) != nil)
    #expect(w.hostingView.hitTest(besideIsland) == nil,
            "menu bar clicks beside the notch must pass through")
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter NotchWindowTests`
Expected: FAIL — `cannot find 'NotchWindow' in scope`.

- [ ] **Step 4: Write `Sources/NotchKit/NotchHostingView.swift`**

```swift
import AppKit
import SwiftUI

/// Hosting view that claims only the points inside `interactivePath`.
///
/// The window is a large transparent canvas; without this, it would swallow
/// every click across the top of the screen. Returning `nil` lets the event
/// fall through to whatever is underneath.
@MainActor
public final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// Interactive region in this view's own coordinate space.
    /// `nil` means claim nothing.
    public var interactivePath: CGPath?

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard let interactivePath else { return nil }
        // `point` arrives in the superview's coordinates.
        let local = convert(point, from: superview)
        guard interactivePath.contains(local) else { return nil }
        return super.hitTest(point)
    }

    public override var allowsVibrancy: Bool { false }
}
```

- [ ] **Step 5: Write `Sources/NotchKit/NotchWindow.swift`**

```swift
import AppKit
import SwiftUI
import CoreGraphics

/// The island's host: a borderless, non-activating panel of fixed oversized
/// size, anchored to the top centre of the built-in display.
///
/// The window never animates or resizes — the island animates inside it.
@MainActor
public final class NotchWindow: NSPanel {
    private static var normalLevel: NSWindow.Level {
        NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    }

    private static var lockedLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
    }

    /// Exposed so hit testing can be asserted directly in tests.
    public let hostingView: NotchHostingView<AnyView>

    public var interactivePath: CGPath? {
        get { hostingView.interactivePath }
        set { hostingView.interactivePath = newValue }
    }

    public init(screen: NSScreen, content: AnyView = AnyView(EmptyView())) {
        hostingView = NotchHostingView(rootView: content)

        super.init(
            contentRect: CGRect(origin: .zero, size: NotchMetrics.canvasSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = Self.normalLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = false      // hit testing decides, not a blanket flag
        contentView = hostingView

        reposition(for: screen)
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public func setContent(_ content: AnyView) {
        hostingView.rootView = content
    }

    /// Anchors the canvas to the top centre of `screen`.
    /// Always clears `interactivePath`: a path computed for the previous
    /// geometry would claim clicks in the wrong place.
    public func reposition(for screen: NSScreen) {
        interactivePath = nil
        let size = NotchMetrics.canvasSize
        let origin = CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height
        )
        setFrame(CGRect(origin: origin, size: size), display: false)
    }

    /// Replaces the interactive region with a shape's path.
    /// `rect` is in the hosting view's coordinate space.
    public func setInteractiveShape(_ shape: some Shape, in rect: CGRect) {
        // SwiftUI shapes are drawn with y growing downward; AppKit views with y
        // growing upward. Flip so the island hangs from the top of the canvas.
        let flip = CGAffineTransform(translationX: 0, y: rect.height)
            .scaledBy(x: 1, y: -1)
        interactivePath = shape.path(in: rect).cgPath.copy(using: &{ var t = flip; return t }())
            ?? shape.path(in: rect).cgPath
    }

    public func setLocked(_ locked: Bool) {
        level = locked ? Self.lockedLevel : Self.normalLevel
    }
}
```

- [ ] **Step 6: Run tests; fix the transform helper if it does not compile**

Run: `swift test --filter NotchWindowTests`

The inline `&{ ... }()` construction in `setInteractiveShape` is not valid Swift. Replace that method body with:

```swift
    public func setInteractiveShape(_ shape: some Shape, in rect: CGRect) {
        let base = shape.path(in: rect).cgPath
        var flip = CGAffineTransform(translationX: 0, y: rect.height)
            .scaledBy(x: 1, y: -1)
        interactivePath = base.copy(using: &flip) ?? base
    }
```

Expected after the fix: PASS — 9 tests.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/NotchKit/NotchWindow.swift Sources/NotchKit/NotchHostingView.swift Tests/NotchWindowTests
git commit -m "feat: notch panel with path-based click-through hit testing"
```

---

### Task 6: `NotchRootView` — a morphing island on screen

**Files:**
- Create: `Sources/NotchKit/NotchRootView.swift`
- Create: `Sources/NotchKit/NotchPresenter.swift`
- Modify: `Sources/Ledge/AppDelegate.swift`
- Create: `Tests/NotchKitTests/NotchAnimationTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 2–5.
- Produces:
  - `enum NotchAnimation { static let expand: Animation; static let collapse: Animation; static let reduced: Animation; static func animation(expanding: Bool, reduceMotion: Bool) -> Animation }`
  - `struct NotchRootView: View` — `init(controller: NotchController)`
  - `@MainActor final class NotchPresenter` — `init()`, `func start()`, `func stop()`, `var controller: NotchController { get }`

- [ ] **Step 1: Write the failing test for the animation constants**

Create `Tests/NotchKitTests/NotchAnimationTests.swift`. The springs are two numbers from the spec and must not drift.

```swift
import Testing
import SwiftUI
@testable import NotchKit

@Test func springParametersMatchTheSpec() {
    #expect(NotchAnimation.expandResponse == 0.35)
    #expect(NotchAnimation.expandDamping == 0.72)
    #expect(NotchAnimation.collapseResponse == 0.30)
    #expect(NotchAnimation.collapseDamping == 0.92)
    #expect(NotchAnimation.reducedDuration == 0.15)
}

@Test func reduceMotionAlwaysYieldsTheCrossfade() {
    #expect(NotchAnimation.animation(expanding: true, reduceMotion: true) == NotchAnimation.reduced)
    #expect(NotchAnimation.animation(expanding: false, reduceMotion: true) == NotchAnimation.reduced)
}

@Test func normalMotionPicksDirectionSpecificSprings() {
    #expect(NotchAnimation.animation(expanding: true, reduceMotion: false) == NotchAnimation.expand)
    #expect(NotchAnimation.animation(expanding: false, reduceMotion: false) == NotchAnimation.collapse)
}

@Test func expandOvershootsAndCollapseBarelyDoes() {
    // overshoot = exp(-zeta * pi / sqrt(1 - zeta^2))
    func overshoot(_ zeta: Double) -> Double {
        guard zeta < 1 else { return 0 }
        return exp(-zeta * .pi / (1 - zeta * zeta).squareRoot())
    }
    let expand = overshoot(NotchAnimation.expandDamping)
    let collapse = overshoot(NotchAnimation.collapseDamping)
    #expect(expand > 0.03 && expand < 0.05, "one small confident overshoot, ~3.8%")
    #expect(collapse < 0.005, "closing must not draw attention")
    #expect(expand > collapse)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter NotchAnimationTests`
Expected: FAIL — `cannot find 'NotchAnimation' in scope`.

- [ ] **Step 3: Write `Sources/NotchKit/NotchRootView.swift`**

```swift
import SwiftUI

/// Motion constants. Chosen by comparing candidates against "which would you
/// still tolerate on the fiftieth repeat" — see spec §5.
public enum NotchAnimation {
    public static let expandResponse: Double = 0.35
    public static let expandDamping: Double = 0.72
    public static let collapseResponse: Double = 0.30
    public static let collapseDamping: Double = 0.92
    public static let reducedDuration: Double = 0.15

    public static let expand = Animation.spring(
        response: expandResponse, dampingFraction: expandDamping
    )
    public static let collapse = Animation.spring(
        response: collapseResponse, dampingFraction: collapseDamping
    )
    public static let reduced = Animation.easeInOut(duration: reducedDuration)

    public static func animation(expanding: Bool, reduceMotion: Bool) -> Animation {
        if reduceMotion { return reduced }
        return expanding ? expand : collapse
    }
}

/// The island itself. Content is clipped to the same shape that defines the
/// silhouette, so nothing can bleed outside during a morph.
public struct NotchRootView: View {
    private let controller: NotchController

    public init(controller: NotchController) {
        self.controller = controller
    }

    public var body: some View {
        let parameters = controller.parameters
        let shape = NotchShape(parameters)

        ZStack(alignment: .top) {
            shape
                .fill(.black)
                .overlay {
                    islandContent(parameters: parameters)
                        .clipShape(shape)
                }
        }
        .frame(
            width: NotchMetrics.canvasSize.width,
            height: NotchMetrics.canvasSize.height,
            alignment: .top
        )
        .animation(
            NotchAnimation.animation(
                expanding: controller.state == .expanded || controller.state == .activity,
                reduceMotion: controller.reduceMotion
            ),
            value: parameters
        )
        .opacity(controller.isVisible ? 1 : 0)
        .allowsHitTesting(controller.isVisible)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ledge notch island")
    }

    /// Content lives in the ears and below the hole. Nothing may be drawn
    /// inside `controller.metrics.notchRect` — there are no pixels there.
    @ViewBuilder
    private func islandContent(parameters: NotchShapeParameters) -> some View {
        let notch = controller.metrics.notchRect
        let ear = controller.metrics.earWidth(forIslandWidth: parameters.width)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leadingEar.frame(width: ear, height: notch.height)
                Color.clear.frame(width: notch.width, height: notch.height)   // the hole
                trailingEar.frame(width: ear, height: notch.height)
            }
            if parameters.height > notch.height + 8 {
                detailRow
                    .frame(maxWidth: .infinity)
                    .frame(height: parameters.height - notch.height)
            }
        }
        .frame(width: parameters.width, alignment: .top)
        .foregroundStyle(.white)
    }

    @ViewBuilder private var leadingEar: some View {
        if controller.activityCount > 0 {
            Circle().fill(.white.opacity(0.28)).padding(6)
        }
    }

    @ViewBuilder private var trailingEar: some View {
        if controller.activityCount > 2 {
            Text("+\(controller.activityCount - 2)")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
        }
    }

    @ViewBuilder private var detailRow: some View {
        EmptyView()
    }
}
```

- [ ] **Step 4: Write `Sources/NotchKit/NotchPresenter.swift`**

```swift
import AppKit
import SwiftUI
import OSLog

/// Owns the window and keeps it in step with the display and the controller.
@MainActor
public final class NotchPresenter {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "notch")

    public let controller: NotchController
    private var window: NotchWindow?
    private var observers: [NSObjectProtocol] = []
    private var trackingMonitor: Any?

    public init() {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let rect = NSScreen.builtIn.flatMap { NotchGeometry.notchRect(for: $0.snapshot()) }
        controller = NotchController(
            metrics: NotchMetrics(notchRect: rect ?? .zero),
            reduceMotion: reduceMotion
        )
    }

    public func start() {
        rebuildForCurrentScreen()

        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildForCurrentScreen() }
            }
        )

        // Mouse tracking: the window is click-through, so hover is observed globally
        // and filtered against the island rect. Mouse-moved monitors need no permission.
        trackingMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }
    }

    public func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if let trackingMonitor { NSEvent.removeMonitor(trackingMonitor) }
        trackingMonitor = nil
        window?.orderOut(nil)
        window = nil
    }

    /// Review Focus 2 and 3: no notch, or no built-in screen, means no island.
    private func rebuildForCurrentScreen() {
        guard
            let screen = NSScreen.builtIn,
            let rect = NotchGeometry.notchRect(for: screen.snapshot())
        else {
            Self.log.info("no notched built-in display; island hidden")
            window?.orderOut(nil)
            window = nil
            return
        }

        controller.metrics = NotchMetrics(notchRect: rect)

        if let window {
            window.reposition(for: screen)
        } else {
            let created = NotchWindow(
                screen: screen,
                content: AnyView(NotchRootView(controller: controller))
            )
            window = created
        }
        refreshInteractiveRegion()
        window?.orderFrontRegardless()
    }

    /// Keeps the claimed region in step with what is actually drawn.
    private func refreshInteractiveRegion() {
        guard let window else { return }
        guard controller.isVisible else {
            window.interactivePath = nil     // Review Focus 4
            return
        }
        let canvas = CGRect(origin: .zero, size: NotchMetrics.canvasSize)
        // Claim a little more than is drawn when collapsed, for hover forgiveness.
        var parameters = controller.parameters
        if controller.state == .hidden || controller.state == .peek {
            parameters.width += 8
            parameters.height += 4
        }
        window.setInteractiveShape(NotchShape(parameters), in: canvas)
    }

    private func updateHover() {
        guard let window, let screen = NSScreen.builtIn else { return }
        let mouse = NSEvent.mouseLocation
        let notch = controller.metrics.notchRect

        // Island hit region in global screen coordinates.
        let parameters = controller.parameters
        let islandTop = screen.frame.maxY
        let region = CGRect(
            x: screen.frame.midX - parameters.width / 2 - 4,
            y: islandTop - parameters.height - 4,
            width: parameters.width + 8,
            height: parameters.height + 4
        )
        _ = notch
        let wasVisible = controller.isVisible
        controller.setHovered(region.contains(mouse))
        if wasVisible != controller.isVisible || controller.isVisible {
            refreshInteractiveRegion()
            if controller.isVisible {
                window.orderFrontRegardless()
            } else {
                window.orderOut(nil)
            }
        }
    }
}
```

- [ ] **Step 5: Wire the presenter into `Sources/Ledge/AppDelegate.swift`**

Replace the file with:

```swift
import AppKit
import NotchKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "app")

    private var statusItem: StatusItemController?
    private var presenter: NotchPresenter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let presenter = NotchPresenter()
        presenter.start()
        self.presenter = presenter

        let item = StatusItemController()
        item.setStatus(key: "app", text: "Ledge — running")
        item.addItem(title: "Toggle Panel") { [weak presenter] in
            guard let presenter else { return }
            if presenter.controller.state == .expanded {
                presenter.controller.dismiss()
            } else {
                presenter.controller.click()
            }
        }
        statusItem = item

        Self.log.info("launched; notch \(String(describing: presenter.controller.metrics.notchRect))")
    }

    func applicationWillTerminate(_ notification: Notification) {
        presenter?.stop()
        Self.log.info("terminating")
    }
}
```

- [ ] **Step 6: Run the animation tests and the whole suite**

Run: `swift test`
Expected: PASS — all tests across `NotchKitTests`, `NotchWindowTests`.

- [ ] **Step 7: Verify the island on screen by hand**

Run: `make dev`

Check, and record results in `docs/manual-checks.md` (create it):
1. Move the cursor onto the notch → island grows slightly (peek) with a spring.
2. Move away → it collapses and disappears.
3. Menu bar → **Toggle Panel** → island expands to the full panel size; again → collapses.
4. Click the menu bar just left of the notch (e.g. the Finder menu) → **it opens normally**. This is the click-through check; if the menu does not open, hit testing is claiming too much.
5. System Settings → Displays → change scaling → island repositions and still behaves.
6. Nothing is ever drawn inside the notch cutout itself.

- [ ] **Step 8: Commit**

```bash
git add Sources/NotchKit/NotchRootView.swift Sources/NotchKit/NotchPresenter.swift Sources/Ledge/AppDelegate.swift Tests/NotchKitTests/NotchAnimationTests.swift docs/manual-checks.md
git commit -m "feat: render and animate the island, wired to display changes and hover"
```

---

### Task 7: `ActivityKit` — priority, coalescing, TTL

**Files:**
- Create: `Sources/ActivityKit/ActivityKind.swift`
- Create: `Sources/ActivityKit/ActivityRecord.swift`
- Create: `Sources/ActivityKit/ActivityQueue.swift`
- Create: `Tests/ActivityKitTests/ActivityQueueTests.swift`
- Modify: `Package.swift` (add `ActivityKit` target and tests)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum ActivityKind: String, Sendable, CaseIterable, Comparable` — cases `hud`, `power`, `device`, `notification`, `media`; `var priority: Int`; `var defaultTTL: TimeInterval?`
  - `struct ActivityRecord: Sendable, Equatable, Identifiable` — `id: String`, `kind`, `insertedAt: Date`, `ttl: TimeInterval?`, `title: String`, `detail: String?`
  - `struct ActivityQueue: Sendable, Equatable` — `static let visibleSlots = 2`; `mutating func insert(_:)`; `mutating func prune(at:hovered:)`; `var visible: [ActivityRecord]`; `var overflowCount: Int`; `var count: Int`; `var isEmpty: Bool`

- [ ] **Step 1: Add the `ActivityKit` targets to `Package.swift`**

Add to `targets:` and add `"ActivityKit"` to the `Ledge` executable's dependencies:

```swift
        .target(name: "ActivityKit"),
        .testTarget(name: "ActivityKitTests", dependencies: ["ActivityKit"]),
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/ActivityKitTests/ActivityQueueTests.swift`.

```swift
import Testing
import Foundation
@testable import ActivityKit

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func record(
    _ kind: ActivityKind,
    id: String? = nil,
    at: Date = t0,
    ttl: TimeInterval? = nil,
    title: String = "x"
) -> ActivityRecord {
    ActivityRecord(
        id: id ?? kind.rawValue,
        kind: kind,
        insertedAt: at,
        ttl: ttl ?? kind.defaultTTL,
        title: title,
        detail: nil
    )
}

@Test func prioritiesAndTTLsMatchTheSpec() {
    #expect(ActivityKind.hud.priority == 100)
    #expect(ActivityKind.power.priority == 60)
    #expect(ActivityKind.device.priority == 50)
    #expect(ActivityKind.notification.priority == 40)
    #expect(ActivityKind.media.priority == 10)

    #expect(ActivityKind.hud.defaultTTL == 1.5)
    #expect(ActivityKind.power.defaultTTL == 3)
    #expect(ActivityKind.device.defaultTTL == 3)
    #expect(ActivityKind.notification.defaultTTL == 5)
    #expect(ActivityKind.media.defaultTTL == nil, "media is sticky")
}

@Test func emptyQueueShowsNothing() {
    let q = ActivityQueue()
    #expect(q.isEmpty)
    #expect(q.visible.isEmpty)
    #expect(q.overflowCount == 0)
}

@Test func insertionOrdersByPriorityNotArrival() {
    var q = ActivityQueue()
    q.insert(record(.media))
    q.insert(record(.hud))
    #expect(q.visible.map(\.kind) == [.hud, .media])
}

@Test func sameKindCoalescesInsteadOfStacking() {
    var q = ActivityQueue()
    q.insert(record(.hud, title: "volume 40"))
    q.insert(record(.hud, title: "volume 45"))
    q.insert(record(.hud, title: "volume 50"))
    #expect(q.count == 1, "spinning the volume wheel must not queue twenty activities")
    #expect(q.visible.first?.title == "volume 50")
}

@Test func coalescingResetsTheTTLClock() {
    var q = ActivityQueue()
    q.insert(record(.hud, at: t0))
    q.insert(record(.hud, at: t0.addingTimeInterval(1.4)))
    q.prune(at: t0.addingTimeInterval(2.0), hovered: false)
    #expect(q.count == 1, "the second insert restarted the 1.5s window")
    q.prune(at: t0.addingTimeInterval(3.0), hovered: false)
    #expect(q.isEmpty)
}

@Test func onlyTwoSlotsAreVisibleAndTheRestOverflow() {
    var q = ActivityQueue()
    q.insert(record(.hud))
    q.insert(record(.power))
    q.insert(record(.device))
    q.insert(record(.notification))
    #expect(q.count == 4)
    #expect(q.visible.map(\.kind) == [.hud, .power])
    #expect(q.overflowCount == 2)
}

@Test func expiredActivitiesArePruned() {
    var q = ActivityQueue()
    q.insert(record(.power, at: t0))
    q.prune(at: t0.addingTimeInterval(2.9), hovered: false)
    #expect(q.count == 1)
    q.prune(at: t0.addingTimeInterval(3.1), hovered: false)
    #expect(q.isEmpty)
}

@Test func stickyMediaNeverExpires() {
    var q = ActivityQueue()
    q.insert(record(.media, at: t0))
    q.prune(at: t0.addingTimeInterval(86_400), hovered: false)
    #expect(q.count == 1)
}

// Review Focus 5.
@Test func hoverSuppressesExpiryAndUnhoverThenExpiresEverythingDue() {
    var q = ActivityQueue()
    q.insert(record(.power, at: t0))
    q.insert(record(.device, at: t0))
    #expect(q.count == 2)

    let wellPastBoth = t0.addingTimeInterval(10)
    q.prune(at: wellPastBoth, hovered: true)
    #expect(q.count == 2, "never yank the island out from under the cursor")

    q.prune(at: wellPastBoth, hovered: false)
    #expect(q.isEmpty, "both must go, in one pass, with no lost update")
}

@Test func hoverDoesNotExtendTheDeadlineAfterRelease() {
    // Hovering pauses expiry; it must not silently renew the TTL.
    var q = ActivityQueue()
    q.insert(record(.hud, at: t0))
    q.prune(at: t0.addingTimeInterval(1.0), hovered: true)
    q.prune(at: t0.addingTimeInterval(1.6), hovered: false)
    #expect(q.isEmpty)
}

@Test func removingAKindByHand() {
    var q = ActivityQueue()
    q.insert(record(.media))
    q.insert(record(.power))
    q.remove(kind: .media)
    #expect(q.visible.map(\.kind) == [.power])
}

@Test func equalPrioritiesBreakTiesDeterministically() {
    var q = ActivityQueue()
    q.insert(record(.device, id: "b", at: t0.addingTimeInterval(1)))
    q.insert(record(.notification, id: "a", at: t0))
    // device (50) outranks notification (40) regardless of arrival order
    #expect(q.visible.map(\.id) == ["b", "a"])
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter ActivityQueueTests`
Expected: FAIL — `cannot find 'ActivityQueue' in scope`.

- [ ] **Step 4: Write `Sources/ActivityKit/ActivityKind.swift`**

```swift
import Foundation

/// What an activity is about. Priority and lifetime come from the kind.
public enum ActivityKind: String, Sendable, CaseIterable, Comparable {
    case hud
    case power
    case device
    case notification
    case media

    /// Higher wins a visible slot. Values fixed by spec §7.
    public var priority: Int {
        switch self {
        case .hud:          return 100
        case .power:        return 60
        case .device:       return 50
        case .notification: return 40
        case .media:        return 10
        }
    }

    /// Seconds before the activity expires. `nil` means sticky.
    public var defaultTTL: TimeInterval? {
        switch self {
        case .hud:          return 1.5
        case .power:        return 3
        case .device:       return 3
        case .notification: return 5
        case .media:        return nil
        }
    }

    public static func < (lhs: ActivityKind, rhs: ActivityKind) -> Bool {
        lhs.priority < rhs.priority
    }
}
```

- [ ] **Step 5: Write `Sources/ActivityKit/ActivityRecord.swift`**

```swift
import Foundation

/// One thing the island is currently saying.
public struct ActivityRecord: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: ActivityKind
    public let insertedAt: Date
    /// `nil` means sticky.
    public let ttl: TimeInterval?
    public let title: String
    public let detail: String?

    public init(
        id: String,
        kind: ActivityKind,
        insertedAt: Date,
        ttl: TimeInterval?,
        title: String,
        detail: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.insertedAt = insertedAt
        self.ttl = ttl
        self.title = title
        self.detail = detail
    }

    public var isSticky: Bool { ttl == nil }

    public func hasExpired(at now: Date) -> Bool {
        guard let ttl else { return false }
        return now.timeIntervalSince(insertedAt) >= ttl
    }
}
```

- [ ] **Step 6: Write `Sources/ActivityKit/ActivityQueue.swift`**

```swift
import Foundation

/// Holds what the island is showing. Pure value type: no timers, no clock of
/// its own. Whoever owns it calls `prune(at:hovered:)`.
public struct ActivityQueue: Sendable, Equatable {
    /// Compact slots available — matches the chosen layout (spec §6).
    public static let visibleSlots = 2

    /// One record per kind: inserting the same kind replaces it.
    private var records: [ActivityKind: ActivityRecord] = [:]

    public init() {}

    public var count: Int { records.count }
    public var isEmpty: Bool { records.isEmpty }

    /// Highest priority first. Stable, because at most one record exists per kind.
    public var ordered: [ActivityRecord] {
        records.values.sorted { $0.kind.priority > $1.kind.priority }
    }

    public var visible: [ActivityRecord] {
        Array(ordered.prefix(Self.visibleSlots))
    }

    public var overflowCount: Int {
        max(0, count - Self.visibleSlots)
    }

    /// Coalesces by kind, restarting that kind's TTL window.
    public mutating func insert(_ record: ActivityRecord) {
        records[record.kind] = record
    }

    public mutating func remove(kind: ActivityKind) {
        records[kind] = nil
    }

    /// Drops everything whose TTL has elapsed.
    ///
    /// While hovered, nothing is dropped — but nothing is renewed either, so
    /// releasing the cursor expires everything already due in a single pass.
    public mutating func prune(at now: Date, hovered: Bool) {
        guard !hovered else { return }
        records = records.filter { !$0.value.hasExpired(at: now) }
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `swift test --filter ActivityQueueTests`
Expected: PASS — 12 tests.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/ActivityKit Tests/ActivityKitTests
git commit -m "feat: activity queue with priority, coalescing and hover-safe expiry"
```

---

### Task 8: `PowerService` — a real charging activity end to end

**Files:**
- Create: `Sources/PowerService/PowerSnapshot.swift`
- Create: `Sources/PowerService/PowerEventDeriver.swift`
- Create: `Sources/PowerService/PowerService.swift`
- Create: `Sources/Ledge/AppModel.swift`
- Modify: `Sources/Ledge/AppDelegate.swift`
- Modify: `Sources/NotchKit/NotchRootView.swift` (render activity titles)
- Create: `Tests/PowerServiceTests/PowerSnapshotTests.swift`
- Create: `Tests/PowerServiceTests/PowerEventDeriverTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `ActivityKit` (Task 7), `NotchKit` (Tasks 2–6).
- Produces:
  - `struct PowerSnapshot: Sendable, Equatable` — `percent: Int`, `isPluggedIn: Bool`, `isCharging: Bool`, `isCharged: Bool`, `timeToFullMinutes: Int?`; `static func parse(_ description: [String: Any]) -> PowerSnapshot?`
  - `enum PowerEvent: Sendable, Equatable` — `pluggedIn(percent:timeToFullMinutes:)`, `unplugged(percent:)`, `fullyCharged`, `lowBattery(percent:)`; `var activityTitle: String`
  - `struct PowerEventDeriver: Sendable` — `static let lowThresholds: [Int]`; `mutating func events(for: PowerSnapshot) -> [PowerEvent]`
  - `@MainActor final class PowerService` — `init()`, `var availability: ServiceAvailability`, `func start() -> AsyncStream<PowerEvent>`, `func stop()`
  - `enum ServiceAvailability: Sendable, Equatable` in `ActivityKit`
  - `@MainActor final class AppModel` — `init(presenter:)`, `func start()`, `func stop()`

- [ ] **Step 1: Add `ServiceAvailability` to `ActivityKit`**

Create `Sources/ActivityKit/ServiceAvailability.swift`:

```swift
import Foundation

/// Every service reports this. The app must be correct with any subset available.
public enum ServiceAvailability: Sendable, Equatable {
    case available
    case needsPermission(String)
    case unavailable(reason: String)

    public var isAvailable: Bool { self == .available }

    public var statusText: String {
        switch self {
        case .available:                 return "ready"
        case .needsPermission(let what): return "needs \(what)"
        case .unavailable(let reason):   return "unavailable — \(reason)"
        }
    }
}
```

- [ ] **Step 2: Add the `PowerService` targets to `Package.swift`**

```swift
        .target(name: "PowerService", dependencies: ["ActivityKit"]),
        .testTarget(name: "PowerServiceTests", dependencies: ["PowerService"]),
```

Add `"PowerService"` to the `Ledge` executable's dependencies.

- [ ] **Step 3: Write the failing snapshot-parsing tests**

Create `Tests/PowerServiceTests/PowerSnapshotTests.swift`. Keys are IOKit's real
`IOPSKeys` string values, so fixtures mirror what the system actually returns.

```swift
import Testing
import Foundation
@testable import PowerService

private func description(
    percent: Int = 87,
    state: String = "AC Power",
    charging: Bool = true,
    charged: Bool = false,
    timeToFull: Int = 24
) -> [String: Any] {
    [
        "Current Capacity": percent,
        "Max Capacity": 100,
        "Power Source State": state,
        "Is Charging": charging,
        "Is Charged": charged,
        "Time to Full Charge": timeToFull,
    ]
}

@Test func parsesAChargingSource() throws {
    let s = try #require(PowerSnapshot.parse(description()))
    #expect(s.percent == 87)
    #expect(s.isPluggedIn)
    #expect(s.isCharging)
    #expect(s.isCharged == false)
    #expect(s.timeToFullMinutes == 24)
}

@Test func parsesABatterySource() throws {
    let s = try #require(PowerSnapshot.parse(
        description(percent: 41, state: "Battery Power", charging: false, timeToFull: -1)
    ))
    #expect(s.percent == 41)
    #expect(s.isPluggedIn == false)
    #expect(s.isCharging == false)
    #expect(s.timeToFullMinutes == nil, "a negative estimate means unknown, not -1 minutes")
}

@Test func parsesAFullyChargedSource() throws {
    let s = try #require(PowerSnapshot.parse(
        description(percent: 100, charging: false, charged: true, timeToFull: 0)
    ))
    #expect(s.isCharged)
    #expect(s.percent == 100)
}

@Test func percentIsScaledAgainstMaxCapacity() throws {
    var d = description(percent: 40)
    d["Max Capacity"] = 80
    let s = try #require(PowerSnapshot.parse(d))
    #expect(s.percent == 50)
}

@Test func percentIsClampedToZeroAndOneHundred() throws {
    var d = description(percent: 140)
    d["Max Capacity"] = 100
    #expect(try #require(PowerSnapshot.parse(d)).percent == 100)
    d["Current Capacity"] = -5
    #expect(try #require(PowerSnapshot.parse(d)).percent == 0)
}

@Test func missingKeysYieldNilRatherThanGuesses() {
    #expect(PowerSnapshot.parse([:]) == nil)
    #expect(PowerSnapshot.parse(["Current Capacity": 50]) == nil)
    #expect(PowerSnapshot.parse(["Max Capacity": 100]) == nil)
}

@Test func zeroMaxCapacityDoesNotDivideByZero() {
    var d = description()
    d["Max Capacity"] = 0
    #expect(PowerSnapshot.parse(d) == nil)
}

@Test func unexpectedTypesDoNotCrash() {
    var d = description()
    d["Current Capacity"] = "eighty-seven"
    #expect(PowerSnapshot.parse(d) == nil)
}
```

- [ ] **Step 4: Write the failing deriver tests**

Create `Tests/PowerServiceTests/PowerEventDeriverTests.swift`.

```swift
import Testing
import Foundation
@testable import PowerService

private func snapshot(
    _ percent: Int,
    plugged: Bool,
    charging: Bool = false,
    charged: Bool = false,
    toFull: Int? = nil
) -> PowerSnapshot {
    PowerSnapshot(
        percent: percent,
        isPluggedIn: plugged,
        isCharging: charging,
        isCharged: charged,
        timeToFullMinutes: toFull
    )
}

@Test func firstReadingEmitsNothing() {
    var d = PowerEventDeriver()
    #expect(d.events(for: snapshot(87, plugged: true, charging: true)).isEmpty,
            "launching while already plugged in must not fire a spurious activity")
}

@Test func plugInIsReported() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(50, plugged: false))
    let events = d.events(for: snapshot(50, plugged: true, charging: true, toFull: 42))
    #expect(events == [.pluggedIn(percent: 50, timeToFullMinutes: 42)])
}

@Test func unplugIsReported() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(50, plugged: true, charging: true))
    #expect(d.events(for: snapshot(50, plugged: false)) == [.unplugged(percent: 50)])
}

@Test func steadyStateEmitsNothing() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(50, plugged: true, charging: true))
    #expect(d.events(for: snapshot(51, plugged: true, charging: true)).isEmpty)
    #expect(d.events(for: snapshot(52, plugged: true, charging: true)).isEmpty)
}

@Test func fullyChargedFiresOnceOnly() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(99, plugged: true, charging: true))
    #expect(d.events(for: snapshot(100, plugged: true, charged: true)) == [.fullyCharged])
    #expect(d.events(for: snapshot(100, plugged: true, charged: true)).isEmpty)
}

@Test func lowBatteryFiresOncePerThresholdCrossed() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(30, plugged: false))
    #expect(d.events(for: snapshot(19, plugged: false)) == [.lowBattery(percent: 19)])
    #expect(d.events(for: snapshot(18, plugged: false)).isEmpty, "no nagging every percent")
    #expect(d.events(for: snapshot(9, plugged: false)) == [.lowBattery(percent: 9)])
    #expect(d.events(for: snapshot(4, plugged: false)) == [.lowBattery(percent: 4)])
}

@Test func thresholdsRearmAfterCharging() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(30, plugged: false))
    #expect(d.events(for: snapshot(19, plugged: false)) == [.lowBattery(percent: 19)])
    _ = d.events(for: snapshot(60, plugged: true, charging: true))
    _ = d.events(for: snapshot(60, plugged: false))
    #expect(d.events(for: snapshot(19, plugged: false)) == [.lowBattery(percent: 19)],
            "after a charge cycle the warning must be able to fire again")
}

@Test func lowBatteryDoesNotFireWhilePluggedIn() {
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(30, plugged: true, charging: true))
    #expect(d.events(for: snapshot(8, plugged: true, charging: true)).isEmpty)
}

@Test func plungeThroughSeveralThresholdsAtOnceReportsOnlyTheLowest() {
    // Waking from sleep can jump several thresholds in one reading.
    var d = PowerEventDeriver()
    _ = d.events(for: snapshot(40, plugged: false))
    #expect(d.events(for: snapshot(3, plugged: false)) == [.lowBattery(percent: 3)])
}

@Test func eventTitlesAreHumanReadable() {
    #expect(PowerEvent.pluggedIn(percent: 87, timeToFullMinutes: 24).activityTitle
            == "Charging · 87% · 24 min to full")
    #expect(PowerEvent.pluggedIn(percent: 87, timeToFullMinutes: nil).activityTitle
            == "Charging · 87%")
    #expect(PowerEvent.unplugged(percent: 87).activityTitle == "On battery · 87%")
    #expect(PowerEvent.fullyCharged.activityTitle == "Fully charged")
    #expect(PowerEvent.lowBattery(percent: 9).activityTitle == "Low battery · 9%")
}
```

- [ ] **Step 5: Run both test files to verify they fail**

Run: `swift test --filter PowerServiceTests`
Expected: FAIL — `cannot find 'PowerSnapshot' in scope`.

- [ ] **Step 6: Write `Sources/PowerService/PowerSnapshot.swift`**

```swift
import Foundation

/// One reading of the system's power state.
public struct PowerSnapshot: Sendable, Equatable {
    public let percent: Int
    public let isPluggedIn: Bool
    public let isCharging: Bool
    public let isCharged: Bool
    public let timeToFullMinutes: Int?

    public init(
        percent: Int,
        isPluggedIn: Bool,
        isCharging: Bool,
        isCharged: Bool,
        timeToFullMinutes: Int?
    ) {
        self.percent = percent
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.timeToFullMinutes = timeToFullMinutes
    }

    /// Parses an `IOPSCopyPowerSourceDescription` dictionary.
    /// Returns `nil` rather than guessing when the shape is not what we expect.
    public static func parse(_ description: [String: Any]) -> PowerSnapshot? {
        guard
            let current = description["Current Capacity"] as? Int,
            let maximum = description["Max Capacity"] as? Int,
            maximum > 0
        else { return nil }

        let ratio = Double(current) / Double(maximum)
        let percent = min(100, max(0, Int((ratio * 100).rounded())))

        let state = description["Power Source State"] as? String
        let isPluggedIn = state == "AC Power"
        let isCharging = description["Is Charging"] as? Bool ?? false
        let isCharged = description["Is Charged"] as? Bool ?? false

        let rawTimeToFull = description["Time to Full Charge"] as? Int
        let timeToFull = (rawTimeToFull ?? -1) > 0 ? rawTimeToFull : nil

        return PowerSnapshot(
            percent: percent,
            isPluggedIn: isPluggedIn,
            isCharging: isCharging,
            isCharged: isCharged,
            timeToFullMinutes: timeToFull
        )
    }
}
```

- [ ] **Step 7: Write `Sources/PowerService/PowerEventDeriver.swift`**

```swift
import Foundation

public enum PowerEvent: Sendable, Equatable {
    case pluggedIn(percent: Int, timeToFullMinutes: Int?)
    case unplugged(percent: Int)
    case fullyCharged
    case lowBattery(percent: Int)

    public var activityTitle: String {
        switch self {
        case .pluggedIn(let percent, let minutes):
            if let minutes {
                return "Charging · \(percent)% · \(minutes) min to full"
            }
            return "Charging · \(percent)%"
        case .unplugged(let percent):
            return "On battery · \(percent)%"
        case .fullyCharged:
            return "Fully charged"
        case .lowBattery(let percent):
            return "Low battery · \(percent)%"
        }
    }
}

/// Turns a stream of snapshots into the handful of moments worth showing.
///
/// Pure and deterministic: the same snapshot sequence always yields the same
/// events, which is what makes the IOKit shell around it nearly trivial.
public struct PowerEventDeriver: Sendable {
    public static let lowThresholds = [20, 10, 5]

    private var previous: PowerSnapshot?
    private var firedThresholds: Set<Int> = []
    private var firedFullyCharged = false

    public init() {}

    public mutating func events(for snapshot: PowerSnapshot) -> [PowerEvent] {
        defer { previous = snapshot }

        // First reading establishes a baseline only — launching while plugged in
        // must not announce a plug-in that happened before we existed.
        guard let previous else { return [] }

        var events: [PowerEvent] = []

        if snapshot.isPluggedIn != previous.isPluggedIn {
            if snapshot.isPluggedIn {
                events.append(.pluggedIn(
                    percent: snapshot.percent,
                    timeToFullMinutes: snapshot.timeToFullMinutes
                ))
            } else {
                events.append(.unplugged(percent: snapshot.percent))
            }
        }

        if snapshot.isCharged, !firedFullyCharged {
            events.append(.fullyCharged)
            firedFullyCharged = true
        }
        if !snapshot.isCharged {
            firedFullyCharged = false
        }

        if snapshot.isPluggedIn {
            // Charging rearms the warnings for the next discharge cycle.
            firedThresholds.removeAll()
        } else {
            // Report only the lowest threshold newly crossed, so waking from
            // sleep at 3% announces 3%, not 20% then 10% then 5%.
            let crossed = Self.lowThresholds
                .filter { snapshot.percent < $0 && !firedThresholds.contains($0) }
            if !crossed.isEmpty {
                firedThresholds.formUnion(crossed)
                events.append(.lowBattery(percent: snapshot.percent))
            }
        }

        return events
    }
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `swift test --filter PowerServiceTests`
Expected: PASS — 18 tests.

- [ ] **Step 9: Write `Sources/PowerService/PowerService.swift`** (thin IOKit shell)

```swift
import Foundation
import IOKit.ps
import ActivityKit
import OSLog

/// Watches the system power sources and emits `PowerEvent`s.
///
/// Deliberately thin: all the judgement lives in `PowerEventDeriver`.
@MainActor
public final class PowerService {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "power")

    public private(set) var availability: ServiceAvailability = .available

    private var deriver = PowerEventDeriver()
    private var runLoopSource: CFRunLoopSource?
    private var continuation: AsyncStream<PowerEvent>.Continuation?

    public init() {}

    public func start() -> AsyncStream<PowerEvent> {
        AsyncStream { continuation in
            self.continuation = continuation

            let context = Unmanaged.passUnretained(self).toOpaque()
            guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
                guard let ctx else { return }
                let service = Unmanaged<PowerService>.fromOpaque(ctx).takeUnretainedValue()
                MainActor.assumeIsolated { service.poll() }
            }, context)?.takeRetainedValue() else {
                availability = .unavailable(reason: "IOPowerSources unavailable")
                Self.log.error("could not create power notification source")
                continuation.finish()
                return
            }

            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)

            continuation.onTermination = { _ in
                Task { @MainActor [weak self] in self?.stop() }
            }

            poll()   // establish the baseline
        }
    }

    public func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
        continuation?.finish()
        continuation = nil
    }

    private func poll() {
        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            Self.log.debug("no power sources returned")
            return
        }

        for source in sources {
            guard
                let raw = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                    as? [String: Any],
                let snapshot = PowerSnapshot.parse(raw)
            else { continue }

            for event in deriver.events(for: snapshot) {
                Self.log.debug("power event: \(String(describing: event), privacy: .public)")
                continuation?.yield(event)
            }
            return   // internal battery is the first source
        }
    }
}
```

- [ ] **Step 10: Write `Sources/Ledge/AppModel.swift`** (the wiring)

> **Ordering note:** this file references `NotchController.ActivityDisplay` and
> `NotchPresenter.setActivities`, which Step 11 adds. Steps 10 and 11 compile
> together — write both before building, and Step 13 runs the suite. Do not
> expect a green build between them.

```swift
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
```

- [ ] **Step 11: Teach `NotchPresenter` and `NotchRootView` to show activity text**

In `Sources/NotchKit/NotchPresenter.swift`, add to `NotchPresenter`:

```swift
    /// Latest visible activities, rendered by `NotchRootView`.
    public func setActivities(_ activities: [ActivityDisplay], overflow: Int) {
        controller.setActivities(activities, overflow: overflow)
        refreshInteractiveRegion()
        if controller.isVisible {
            window?.orderFrontRegardless()
        } else {
            window?.orderOut(nil)
        }
    }
```

In `Sources/NotchKit/NotchController.swift`, add:

```swift
    /// UI-facing projection of an activity. Keeps `NotchKit` independent of
    /// `ActivityKit`'s storage types.
    public struct ActivityDisplay: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let detail: String?
        public init(id: String, title: String, detail: String? = nil) {
            self.id = id
            self.title = title
            self.detail = detail
        }
    }
```

and, inside `NotchController`:

```swift
    public private(set) var activities: [ActivityDisplay] = []
    public private(set) var overflowCount = 0

    public func setActivities(_ activities: [ActivityDisplay], overflow: Int) {
        self.activities = activities
        self.overflowCount = max(0, overflow)
        setActivityCount(activities.count + max(0, overflow))
    }
```

In `Sources/NotchKit/NotchRootView.swift`, replace `detailRow` and `trailingEar`:

```swift
    @ViewBuilder private var trailingEar: some View {
        if controller.overflowCount > 0 {
            Text("+\(controller.overflowCount)")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
        }
    }

    @ViewBuilder private var detailRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(controller.activities) { activity in
                Text(activity.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .transition(.blurReplace)
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

`AppModel.publish()` from Step 10 already produces `[ActivityDisplay]`, so nothing
in `AppModel` changes here — this step only adds the `NotchKit` side it calls into.

- [ ] **Step 12: Wire `AppModel` into `AppDelegate`**

In `Sources/Ledge/AppDelegate.swift`, after creating the presenter:

```swift
        let model = AppModel(presenter: presenter)
        model.start()
        self.model = model
        item.setStatus(key: "power", text: "Power — \(model.powerStatus)")
```

Add the stored property `private var model: AppModel?` and call `model?.stop()` in
`applicationWillTerminate` before `presenter?.stop()`.

- [ ] **Step 13: Run the full suite**

Run: `swift test`
Expected: PASS — all targets. If `NotchKit` fails to compile because `ActivityDisplay` is
referenced before declaration, confirm the nested struct sits inside
`NotchController.swift` at file scope within the class's enclosing file, not inside
another type.

- [ ] **Step 14: Verify the charging activity by hand**

Run: `make dev`

Then, recording results in `docs/manual-checks.md`:
1. Plug in the charger → island morphs out showing `Charging · NN% · NN min to full`, then collapses after ~3s.
2. Unplug → island shows `On battery · NN%`, then collapses.
3. Plug in, then hover the island as it is about to collapse → it stays until the cursor leaves.
4. Menu bar shows `Power — ready`.
5. Launch the app while already plugged in → **no** spurious charging activity.
6. Click the Finder menu while an activity is showing → the menu still opens.

- [ ] **Step 15: Commit**

```bash
git add Package.swift Sources/ActivityKit/ServiceAvailability.swift Sources/PowerService Sources/Ledge Sources/NotchKit Tests/PowerServiceTests docs/manual-checks.md
git commit -m "feat: power service driving a live charging activity end to end"
```

---

## Done when

- `swift test` passes, covering geometry, shape, controller, animation constants, window hit testing, activity queue, power parsing and event derivation.
- `make dev` yields an agent app whose island morphs on hover, opens on demand, shows real charging activities, and **does not swallow menu bar clicks**.
- `docs/manual-checks.md` records the six manual checks from Task 6 Step 7 and the six from Task 8 Step 14.
- Phases 3 (HUD) and 4 (Media) follow in `2026-09-25-hud-and-media-services.md`.
