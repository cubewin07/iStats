import XCTest
import Foundation
import iStatsCore
@testable import iStats

final class Phase3ValidationTests: XCTestCase {

    func testLiveValidationNetworkAndDisk() throws {
        print("\n=======================================================")
        print("PHASE 3 LIVE METRIC VALIDATION")
        print("=======================================================")

        // 1. DISK VOLUMES & CAPACITY VALIDATION
        print("\n--- 1. DISK VOLUME CAPACITY VALIDATION ---")
        let diskProvider = HostDiskInfoProvider()
        let diskSampler = DiskSampler(provider: diskProvider)
        let diskSample1 = try diskSampler.sample()

        print("\(pad("Mount Point", 30)) | \(pad("Total (IEC)", 12)) | \(pad("Used (IEC)", 12)) | \(pad("Free (IEC)", 12)) | Used %")
        print(String(repeating: "-", count: 85))
        for vol in diskSample1.volumes {
            let totalStr = Units.formatBytes(vol.total, standard: .iec)
            let usedStr = Units.formatBytes(vol.used, standard: .iec)
            let freeStr = Units.formatBytes(vol.free, standard: .iec)
            let usedPct = vol.total > 0 ? (Double(vol.used) / Double(vol.total)) * 100.0 : 0.0
            let percentStr = String(format: "%.1f%%", usedPct)
            print("\(pad(vol.mountPoint, 30)) | \(pad(totalStr, 12)) | \(pad(usedStr, 12)) | \(pad(freeStr, 12)) | \(percentStr)")
        }

        // 2. DISK I/O SAMPLING & WRITE LOAD VALIDATION
        print("\n--- 2. DISK I/O THROUGHPUT VALIDATION ---")
        // Warm up / sample 1
        _ = try diskSampler.sample()
        Thread.sleep(forTimeInterval: 0.5)

        // Sample 2 (baseline idle)
        let diskSampleIdle = try diskSampler.sample()
        if let io = diskSampleIdle.io {
            let rStr = Units.formatDiskRate(io.bytesReadPerSec)
            let wStr = Units.formatDiskRate(io.bytesWrittenPerSec)
            print("Idle Disk I/O: Read: \(rStr), Write: \(wStr), Read IOPS: \(String(format: "%.1f", io.readOpsPerSec)), Write IOPS: \(String(format: "%.1f", io.writeOpsPerSec))")
        } else {
            print("Disk I/O counters unavailable on this host.")
        }

        // Apply a synthetic disk write load (50 MB)
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("istats_disk_test_\(UUID().uuidString).bin")
        let testData = Data(repeating: 0xAB, count: 50 * 1024 * 1024) // 50 MB
        let writeStart = Date()
        try testData.write(to: tempFile, options: .atomic)
        let writeDuration = Date().timeIntervalSince(writeStart)

        let diskSampleUnderLoad = try diskSampler.sample()
        if let io = diskSampleUnderLoad.io {
            let rStr = Units.formatDiskRate(io.bytesReadPerSec)
            let wStr = Units.formatDiskRate(io.bytesWrittenPerSec)
            print("Under 50MB Write Load: Read: \(rStr), Write: \(wStr), Read IOPS: \(String(format: "%.1f", io.readOpsPerSec)), Write IOPS: \(String(format: "%.1f", io.writeOpsPerSec)) (write took \(String(format: "%.3f", writeDuration))s)")
        }
        try? FileManager.default.removeItem(at: tempFile)

        // 3. NETWORK SAMPLING & TRANSFER VALIDATION
        print("\n--- 3. NETWORK THROUGHPUT VALIDATION ---")
        let netProvider = HostNetworkInfoProvider()
        let netSampler = NetworkSampler(provider: netProvider)

        // Sample 1: Baseline (cold start, rates 0)
        let netSample1 = try netSampler.sample()
        let in1Str = Units.formatNetworkRate(netSample1.totalBytesInPerSec, unit: .bytesPerSecond, standard: .iec)
        let out1Str = Units.formatNetworkRate(netSample1.totalBytesOutPerSec, unit: .bytesPerSecond, standard: .iec)
        print("Sample 1 (Cold Start): In: \(in1Str), Out: \(out1Str), Active Interfaces: \(netSample1.interfaces.count)")

        // Sample 2: Idle 1s
        Thread.sleep(forTimeInterval: 1.0)
        let netSample2 = try netSampler.sample()
        let in2Str = Units.formatNetworkRate(netSample2.totalBytesInPerSec, unit: .bytesPerSecond, standard: .iec)
        let out2Str = Units.formatNetworkRate(netSample2.totalBytesOutPerSec, unit: .bytesPerSecond, standard: .iec)
        print("Sample 2 (Idle 1s): In: \(in2Str), Out: \(out2Str)")
        for iface in netSample2.interfaces where iface.bytesInPerSec > 0 || iface.bytesOutPerSec > 0 {
            let inRate = Units.formatNetworkRate(iface.bytesInPerSec, unit: .bytesPerSecond, standard: .iec)
            let outRate = Units.formatNetworkRate(iface.bytesOutPerSec, unit: .bytesPerSecond, standard: .iec)
            let inTotal = Units.formatBytes(iface.totalBytesIn, standard: .iec)
            let outTotal = Units.formatBytes(iface.totalBytesOut, standard: .iec)
            print("  - Interface \(iface.interfaceName): In \(inRate), Out \(outRate) (Session total in: \(inTotal), out: \(outTotal))")
        }

        // Sample 3: Apply Network Download Load via URLSession (e.g. 1-2MB download)
        let exp = expectation(description: "Network Download Load")
        if let url = URL(string: "https://www.apple.com") {
            let task = URLSession.shared.dataTask(with: url) { _, _, _ in
                exp.fulfill()
            }
            task.resume()
        } else {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)

        let netSample3 = try netSampler.sample()
        let in3Str = Units.formatNetworkRate(netSample3.totalBytesInPerSec, unit: .bytesPerSecond, standard: .iec)
        let out3Str = Units.formatNetworkRate(netSample3.totalBytesOutPerSec, unit: .bytesPerSecond, standard: .iec)
        print("Sample 3 (Under HTTP Load): In: \(in3Str), Out: \(out3Str)")
        for iface in netSample3.interfaces where iface.bytesInPerSec > 0 || iface.bytesOutPerSec > 0 {
            let inRate = Units.formatNetworkRate(iface.bytesInPerSec, unit: .bytesPerSecond, standard: .iec)
            let outRate = Units.formatNetworkRate(iface.bytesOutPerSec, unit: .bytesPerSecond, standard: .iec)
            print("  - Interface \(iface.interfaceName): In \(inRate), Out \(outRate)")
        }

        print("\n=======================================================\n")
    }

    private func pad(_ text: String, _ length: Int) -> String {
        if text.count >= length {
            return String(text.prefix(length))
        }
        return text + String(repeating: " ", count: length - text.count)
    }
}
