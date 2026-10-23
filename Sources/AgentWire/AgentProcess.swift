import Foundation
import Darwin

/// Facts the kernel knows about a process (2026-10-23): when it started, who its
/// parents are, what it is called and how it was launched.
public enum AgentProcess {
    private static func info(of pid: Int32) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var proc = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &proc, &size, nil, 0) == 0, size > 0, proc.kp_proc.p_pid == pid else { return nil }
        return proc
    }

    /// The process's start time from `sysctl(KERN_PROC_PID)` (`kp_proc.p_starttime`), in microseconds.
    public static func startTime(of pid: Int32) -> Int64? {
        guard let proc = info(of: pid) else { return nil }
        let t = proc.kp_proc.p_starttime
        return Int64(t.tv_sec) * 1_000_000 + Int64(t.tv_usec)
    }

    /// `pid`'s parent, its parent, …, nearest first; stops before a pid ≤ 1, at most `limit` entries.
    public static func parentChain(from pid: Int32, limit: Int = 12) -> [Int32] {
        var chain: [Int32] = []
        var current = pid
        while chain.count < limit, let proc = info(of: current) {
            let parent = proc.kp_eproc.e_ppid
            if parent <= 1 || chain.contains(parent) { break }
            chain.append(parent)
            current = parent
        }
        return chain
    }

    /// `proc_name`, e.g. "claude".
    public static func name(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let n = proc_name(pid, &buffer, UInt32(buffer.count))
        guard n > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The process's argv from `sysctl(KERN_PROCARGS2)`; nil when unreadable.
    public static func arguments(of pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        buffer.removeLast(buffer.count - size)

        let argc = Int(buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        guard argc >= 0 else { return nil }
        var i = MemoryLayout<Int32>.size
        while i < buffer.count, buffer[i] != 0 { i += 1 }      // the executable path
        while i < buffer.count, buffer[i] == 0 { i += 1 }      // its NUL padding

        var args: [String] = []
        while args.count < argc, i < buffer.count {
            var end = i
            while end < buffer.count, buffer[end] != 0 { end += 1 }
            args.append(String(decoding: buffer[i..<end], as: UTF8.self))
            i = end + 1
        }
        return args.count == argc ? args : nil
    }
}
