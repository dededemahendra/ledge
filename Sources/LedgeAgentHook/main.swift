import AgentWire
import Foundation

// A Claude Code hook (2026-10-23): stdin to Ledge's socket, one line, and
// exit 0 whatever happens — Claude must never see an error from Ledge.
//
// The chain seen on this Mac: this helper's parent is `claude` itself (comm
// "claude"; headless runs show args like `claude -p …`). Ledge's real hook
// command is `[ -x "<helper>" ] && "<helper>" || true`, so in practice one
// shell sits between: helper -> sh -> claude. `pids` carries the whole chain.
let input = FileHandle.standardInput.readDataToEndOfFile()
let me = getpid()
let stamp = AgentProcess.startTime(of: me) ?? Int64(Date().timeIntervalSince1970 * 1_000_000)
if let message = AgentTrim.message(hookJSON: input, environment: ProcessInfo.processInfo.environment,
                                   stamp: stamp, pids: AgentProcess.parentChain(from: me)),
   let line = AgentTrim.line(message) {
    _ = AgentSocket.send(line, to: AgentSocket.socketURL(), timeout: 0.5)
}
exit(0)
