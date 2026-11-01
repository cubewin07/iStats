import Foundation
import Darwin
import AppKit
import iStatsCore

/// Background process rusage sampler using proc_listpids and proc_pid_rusage (ADR 0009 / Task 8.9).
/// Runs on the background queue only when demand is active; skips unprivileged processes silently.
public final class ProcessSampler: @unchecked Sendable {
    private var previousRecords: [Int32: ProcessCPURecord] = [:]
    private let lock = NSLock()

    public init() {}

    /// Samples current process CPU and memory utilization. Runs off the main thread.
    public func sample() -> ProcessSample {
        lock.lock()
        defer { lock.unlock() }

        var pids = [pid_t](repeating: 0, count: 2048)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<pid_t>.stride * pids.count))
        guard bytes > 0 else {
            return ProcessSample(topCPU: [], topMemory: [], skippedCount: 0)
        }

        let count = min(pids.count, Int(bytes) / MemoryLayout<pid_t>.stride)
        var snapshots: [RawProcessSnapshot] = []
        var skippedCount = 0
        let now = Date()

        // Lookup map of running GUI applications to get bundleIDs and friendly display names
        let runningApps = NSWorkspace.shared.runningApplications
        var appMap: [pid_t: (name: String, bundleID: String?)] = [:]
        for app in runningApps {
            if let name = app.localizedName {
                appMap[app.processIdentifier] = (name, app.bundleIdentifier)
            }
        }

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var rusage = rusage_info_v4()
            let res = withUnsafeMutablePointer(to: &rusage) { ptr in
                ptr.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) { reboundPtr in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, reboundPtr)
                }
            }

            if res == 0 {
                let name: String
                let bundleID: String?

                if let appInfo = appMap[pid] {
                    name = appInfo.name
                    bundleID = appInfo.bundleID
                } else {
                    var nameBuf = [CChar](repeating: 0, count: 256)
                    let nameLen = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
                    if nameLen > 0 {
                        name = String(cString: nameBuf).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        name = "Process \(pid)"
                    }
                    bundleID = nil
                }

                let totalCpuNs = rusage.ri_user_time + rusage.ri_system_time
                let memBytes = rusage.ri_phys_footprint

                snapshots.append(
                    RawProcessSnapshot(
                        pid: pid,
                        name: name,
                        bundleID: bundleID,
                        totalCpuTimeNs: totalCpuNs,
                        physicalFootprintBytes: memBytes,
                        timestamp: now
                    )
                )
            } else {
                skippedCount += 1
            }
        }

        let (sample, newRecords) = ProcessRanking.rankProcesses(
            currentSnapshots: snapshots,
            previousRecords: previousRecords,
            limit: 5,
            groupChildren: true,
            skippedCount: skippedCount
        )
        self.previousRecords = newRecords
        return sample
    }
}
