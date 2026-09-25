# Private API notes

Every private symbol Ledge touches, why, and what breaks if Apple removes it.

## DisplayServices (`/System/Library/PrivateFrameworks/DisplayServices.framework`)

Loaded with `dlopen` + `dlsym`. Never linked. Note: on this OS release the
framework has no standalone file on disk (`nm`/`otool` on the path both fail
with "No such file or directory" — it lives only in the dyld shared cache),
but `dlopen` still resolves it through the shared-cache shim, exactly as the
task brief's verified facts said.

| Symbol | Signature | Verified | Used for |
| --- | --- | --- | --- |
| `DisplayServicesGetBrightness` | `(CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32` | ✅ 2026-09-25, rc=0, value 0…1 (confirmed again via `bridgeLoadsAndReadsARealBrightnessValue`, and repeatedly during the Step 5 spike below) | reading brightness |
| `DisplayServicesRegisterForBrightnessChangeNotifications` | undocumented | ⚠️ 2026-09-25 — registers cleanly (rc=0) and the callback reliably fires, but see **Step 5 spike** below: not adopted | change notifications |
| `DisplayServicesCanChangeBrightness` | undocumented | resolves only, not used |  |
| `DisplayServicesSetBrightness` | `(CGDirectDisplayID, Float) -> Int32` | ✅ resolves and works (used only in the throwaway Step 5 probe, never shipped — Ledge never *sets* brightness) | not used in shipped code |

**If removed:** `DisplayServicesBridge.init?` returns nil, `BrightnessObserver`
reports `.unavailable`, the brightness HUD disappears, and everything else
keeps working. No crash, no alert.

**Backend actually in use: polling**, at `BrightnessObserver.pollInterval`
(0.1s / 10 Hz), one C call per tick.

### Step 5 spike — notification callback signature

The task brief gives this candidate signature to try:

```swift
typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UInt32, CFString?, Double) -> Void
typealias Register = @convention(c) (CGDirectDisplayID, UnsafeMutableRawPointer?, Callback) -> Int32
```

This environment has no physical key-press access (unattended CLI agent, no
Accessibility/Input Monitoring grant, no GUI automation) to drive brightness
keys the way the brief's manual procedure assumes. Substituted: drive
brightness changes programmatically via `DisplayServicesSetBrightness`
(resolves via `dlsym`; confirmed working), oscillating around the original
value and restoring it afterward, while a registered callback listens. This
tests exactly the thing Step 5 needs — does the notification path fire and
with what payload — without needing hardware input.

**Run 1 — brief's literal signature.** `register` returned `rc=0`. The
callback **fired reliably, 1:1 with every `SetBrightness` call** (6/6, plus
one more delivered asynchronously after the run loop's explicit wait window
closed — delivery is not strictly synchronous with the call that triggered
it). But the payload was not usable:
- `value: Double` read as denormalized garbage (`~2.5e-312`), not a
  brightness in `0...1`.
- `display: UInt32` read as `0` — CGMainDisplayID() on this machine is
  actually `1`.

**Run 2 — corrected minimal-assumption signature**, after the garbage/zero
readings suggested a 4-parameter guess was wrong:

```swift
typealias Callback2 = @convention(c) (CGDirectDisplayID, UnsafeMutableRawPointer?) -> Void
```

i.e. no pushed name or value at all — just an identifier and the context
pointer, requiring the caller to re-read brightness itself on any fire. This
run:
- `register` again returned `rc=0`; the callback fired 1:1 with every
  `SetBrightness` call (4/4, plus one more delivered async after the wait
  window, same pattern as run 1).
- The context pointer **round-trips correctly** — a live object reference
  passed in survived through the C trampoline and read back valid on every
  call. This is a real positive signal: it means at least this parameter's
  position/type in the real ABI matches the hypothesis.
- The first parameter still printed `0`, and `CGMainDisplayID()` on this
  machine is `1` — calling `DisplayServicesGetBrightness` with the callback's
  reported "display" value (`0`) failed (no valid value written). So `0` is
  either a different internal display-indexing scheme than `CGDirectDisplayID`
  (plausible — Apple's private display APIs sometimes use a zero-based
  ordinal internally), or this parameter isn't a display identifier in that
  position at all. No way to tell which without disassembly, which is out of
  scope for a spike.

**Decision — per the brief's rule, applied by its spirit and not just its
letter:** the rule requires "`CALLBACK FIRED` lines appear with plausible
values" to proceed to Step 6. Run 1, using the brief's own suggested
signature, produced values that were not plausible (garbage double, a display
id that doesn't match the real one under the obvious interpretation). Run 2
firmed up confidence that the dispatch mechanism and context handling are
correct, but left the meaning of the leading identifier genuinely ambiguous —
and, per the task's own instruction ("the polling fallback ... is a correct
and acceptable permanent answer; do not contort the code to avoid it"),
ambiguity here is not worth resolving further by guessing at more candidate
signatures. **Skipped Step 6.** `BrightnessObserver` never attempts
registration (`start()` calls `Self.backend(canRegister: false, canRead:)`
unconditionally) and polls at 10 Hz instead, which is correct, simple, and
costs one C call per 100ms.

If a future task wants to revisit this: the promising thread is the 2-arg
`(identifier, context)` hypothesis, worth confirming by comparing the
"identifier" value across a real multi-display setup rather than guessing
further on a single-display machine, or by disassembling
`DisplayServicesRegisterForBrightnessChangeNotifications`'s call site inside
`OSDUIHelper` or `ControlCenter` to read the real trampoline shape.

## OSDUIHelper

See `Sources/HUDService/OSDSuppressor.swift`. Bundle id `com.apple.OSDUIHelper`,
a `gui/<uid>` LaunchAgent, **not resident** — launches on demand.

## MediaRemote

Not touched directly. Reached only through the vendored `mediaremote-adapter`,
which loads it inside `/usr/bin/perl` (bundle id `com.apple.perl`).
