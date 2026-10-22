import Darwin
import Testing
@testable import CallService

private let zoom = CallAppInfo(bundleID: "us.zoom.xos", name: "zoom.us", pid: 100)
private let safari = CallAppInfo(bundleID: "com.apple.Safari", name: "Safari", pid: 150)
private let chrome = CallAppInfo(bundleID: "com.google.Chrome", name: "Google Chrome", pid: 302)

/// A process table as dictionaries: who is a regular app, who is
/// responsible for whom, and who is whose parent.
@MainActor
private func lookup(regular: [pid_t: CallAppInfo] = [:], responsible: [pid_t: pid_t] = [:],
                    parent: [pid_t: pid_t] = [:], unbundled: Set<pid_t> = [], names: [pid_t: String] = [:],
                    running: [String: CallAppInfo] = [:]) -> ProcessLookup {
    ProcessLookup(regularApp: { regular[$0] }, responsiblePID: { responsible[$0] }, parentPID: { parent[$0] },
                  isBundled: { !unbundled.contains($0) }, executableName: { names[$0] }, runningApp: { running[$0] })
}

@MainActor @Test func aRegularAppIsItself() {
    #expect(CallApp.resolve(100, ownPID: 9, lookup: lookup(regular: [100: zoom])) == zoom)
}

/// Safari's WebKit processes are launchd's children, so only the
/// responsible process leads back to Safari.
@MainActor @Test func aWebKitHelperResolvesThroughItsResponsibleProcess() {
    let table = lookup(regular: [150: safari], responsible: [200: 150], parent: [200: 1])
    #expect(CallApp.resolve(200, ownPID: 9, lookup: table) == safari)
}

@MainActor @Test func aHelperResolvesToItsRegularParent() {
    let table = lookup(regular: [302: chrome], parent: [300: 301, 301: 302])
    #expect(CallApp.resolve(300, ownPID: 9, lookup: table) == chrome)
}

@MainActor @Test func aDaemonWithNoRegularAncestorIsNil() {
    #expect(CallApp.resolve(400, ownPID: 9, lookup: lookup(parent: [400: 1])) == nil)
}

@MainActor @Test func ledgeItselfIsNil() {
    let ledge = CallAppInfo(bundleID: "com.dedemahendra.ledge", name: "Ledge", pid: 9)
    #expect(CallApp.resolve(9, ownPID: 9, lookup: lookup(regular: [9: ledge])) == nil)
}

@MainActor @Test func theWalkStopsAfterTenHops() {
    #expect(CallApp.resolve(500, ownPID: 9, lookup: lookup(parent: [500: 501, 501: 500])) == nil)
}

/// A command-line recorder started from a terminal is no call, though the
/// terminal app is responsible for it (review, 2026-10-22).
@MainActor @Test func aCommandLineToolIsNilEvenFromATerminal() {
    let terminal = CallAppInfo(bundleID: "com.apple.Terminal", name: "Terminal", pid: 601)
    let table = lookup(regular: [601: terminal], responsible: [600: 601], parent: [600: 601], unbundled: [600])
    #expect(CallApp.resolve(600, ownPID: 9, lookup: table) == nil)
}

/// FaceTime's audio runs in a system daemon of its own.
@MainActor @Test func theCallDaemonIsFaceTime() {
    let facetime = CallAppInfo(bundleID: "com.apple.FaceTime", name: "FaceTime", pid: 710)
    let table = lookup(responsible: [700: 700], parent: [700: 1], unbundled: [700], names: [700: "avconferenced"],
                       running: ["com.apple.FaceTime": facetime])
    #expect(CallApp.resolve(700, ownPID: 9, lookup: table) == facetime)
}

@MainActor @Test func theCallDaemonIsFaceTimeWhenItIsNotRunning() {
    let table = lookup(parent: [700: 1], unbundled: [700], names: [700: "avconferenced"])
    #expect(CallApp.resolve(700, ownPID: 9, lookup: table)
            == CallAppInfo(bundleID: "com.apple.FaceTime", name: "FaceTime", pid: 700))
}
