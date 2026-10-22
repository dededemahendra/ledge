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
                    parent: [pid_t: pid_t] = [:]) -> ProcessLookup {
    ProcessLookup(regularApp: { regular[$0] }, responsiblePID: { responsible[$0] }, parentPID: { parent[$0] })
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
