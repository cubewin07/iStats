import Foundation

/// Internal record of a process's CPU consumption at a specific timestamp.
public struct ProcessCPURecord: Sendable, Equatable {
    public let totalCpuTimeNs: UInt64
    public let timestamp: Date

    public init(totalCpuTimeNs: UInt64, timestamp: Date) {
        self.totalCpuTimeNs = totalCpuTimeNs
        self.timestamp = timestamp
    }
}

/// Raw unsorted process measurement taken from background libproc.
public struct RawProcessSnapshot: Sendable, Equatable {
    public let pid: Int32
    public let name: String
    public let bundleID: String?
    public let totalCpuTimeNs: UInt64
    public let physicalFootprintBytes: UInt64
    public let timestamp: Date

    public init(
        pid: Int32,
        name: String,
        bundleID: String? = nil,
        totalCpuTimeNs: UInt64,
        physicalFootprintBytes: UInt64,
        timestamp: Date = Date()
    ) {
        self.pid = pid
        self.name = name
        self.bundleID = bundleID
        self.totalCpuTimeNs = totalCpuTimeNs
        self.physicalFootprintBytes = physicalFootprintBytes
        self.timestamp = timestamp
    }
}

/// Sorting criterion for process rankings.
public enum ProcessSortCriterion: Sendable {
    case cpu
    case memory
}

/// Pure mathematical calculation and ranking of top processes (ADR 0009 / Task 8.9).
public enum ProcessRanking {

    /// Pure calculation of CPU percentage and top N rankings from raw process snapshots.
    public static func rankProcesses(
        currentSnapshots: [RawProcessSnapshot],
        previousRecords: [Int32: ProcessCPURecord],
        limit: Int = 5,
        groupChildren: Bool = true,
        skippedCount: Int = 0
    ) -> (sample: ProcessSample, newRecords: [Int32: ProcessCPURecord]) {
        var newRecords: [Int32: ProcessCPURecord] = [:]
        var items: [ProcessInfoItem] = []

        for snap in currentSnapshots {
            newRecords[snap.pid] = ProcessCPURecord(totalCpuTimeNs: snap.totalCpuTimeNs, timestamp: snap.timestamp)

            let cpuPercent: Double
            if let prev = previousRecords[snap.pid] {
                let deltaWallSec = snap.timestamp.timeIntervalSince(prev.timestamp)
                if deltaWallSec > 0 && snap.totalCpuTimeNs >= prev.totalCpuTimeNs {
                    let deltaCpuNs = snap.totalCpuTimeNs - prev.totalCpuTimeNs
                    let deltaWallNs = deltaWallSec * 1_000_000_000.0
                    // RateMath semantics: percentage = (deltaCpuNs / deltaWallNs) * 100.0
                    cpuPercent = max(0.0, (Double(deltaCpuNs) / deltaWallNs) * 100.0)
                } else {
                    // Counter reset or PID reuse -> 0.0, never negative
                    cpuPercent = 0.0
                }
            } else {
                // New PID seen for first time -> 0.0
                cpuPercent = 0.0
            }

            items.append(
                ProcessInfoItem(
                    pid: snap.pid,
                    name: snap.name,
                    bundleID: snap.bundleID,
                    cpuPercent: cpuPercent,
                    memoryBytes: snap.physicalFootprintBytes
                )
            )
        }

        let processedItems: [ProcessInfoItem]
        if groupChildren {
            // Group helpers/XPC children under parent app bundle when bundleID is present
            var grouped: [String: (pid: Int32, name: String, bundleID: String, cpu: Double, mem: UInt64)] = [:]
            var ungrouped: [ProcessInfoItem] = []

            for item in items {
                if let bundle = item.bundleID, !bundle.isEmpty {
                    if let existing = grouped[bundle] {
                        grouped[bundle] = (
                            pid: min(existing.pid, item.pid),
                            name: existing.name,
                            bundleID: bundle,
                            cpu: existing.cpu + item.cpuPercent,
                            mem: existing.mem + item.memoryBytes
                        )
                    } else {
                        grouped[bundle] = (item.pid, item.name, bundle, item.cpuPercent, item.memoryBytes)
                    }
                } else {
                    ungrouped.append(item)
                }
            }

            let groupedItems = grouped.values.map {
                ProcessInfoItem(
                    pid: $0.pid,
                    name: $0.name,
                    bundleID: $0.bundleID,
                    cpuPercent: $0.cpu,
                    memoryBytes: $0.mem
                )
            }
            processedItems = groupedItems + ungrouped
        } else {
            processedItems = items
        }

        let topCPU = topN(items: processedItems, by: .cpu, limit: limit)
        let topMemory = topN(items: processedItems, by: .memory, limit: limit)

        return (
            ProcessSample(topCPU: topCPU, topMemory: topMemory, skippedCount: skippedCount),
            newRecords
        )
    }

    /// Sorts and takes the top N items by the specified criterion.
    public static func topN(
        items: [ProcessInfoItem],
        by criterion: ProcessSortCriterion,
        limit: Int = 5
    ) -> [ProcessInfoItem] {
        let sorted = items.sorted { a, b in
            switch criterion {
            case .cpu:
                if a.cpuPercent != b.cpuPercent {
                    return a.cpuPercent > b.cpuPercent
                }
                return a.pid < b.pid // deterministic tie breaker
            case .memory:
                if a.memoryBytes != b.memoryBytes {
                    return a.memoryBytes > b.memoryBytes
                }
                return a.pid < b.pid // deterministic tie breaker
            }
        }
        return Array(sorted.prefix(max(0, limit)))
    }
}
