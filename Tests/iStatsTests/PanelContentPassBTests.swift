import XCTest
import SwiftUI
import AppKit
@testable import iStatsCore
@testable import iStats

/// Task 9.6: Fans, Network, Disk and Power content pass (one value once, hero/chart unit agreement).
@MainActor
final class PanelContentPassBTests: XCTestCase {

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ name: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent("iStats/UI/Panels/\(name)"), encoding: .utf8)
    }

    private func makeContext() -> (UserDefaults, PreferencesStore, MetricsCoordinator, String) {
        let suiteName = "test.istats.panel.passb.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = PreferencesStore(userDefaults: defaults)
        return (defaults, prefs, MetricsCoordinator(preferencesStore: prefs), suiteName)
    }

    private func assertRenders(_ view: some View, file: StaticString = #filePath, line: UInt = #line) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 560)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(hosting.fittingSize.width, Instrument.Size.panelWidth, accuracy: 2.0, file: file, line: line)
        XCTAssertGreaterThan(hosting.fittingSize.height, 100, file: file, line: line)
    }

    // MARK: - Fans

    func testFanCopyHasNoADRReferenceAndOneLineFootnote() throws {
        XCTAssertEqual(FanPanelCopy.footnote, "macOS manages fan speed automatically.")
        let text = try source("FanPanel.swift")
        let codeLines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        XCTAssertFalse(codeLines.contains { $0.contains("ADR 0004") }, "ADR references must not reach UI copy")
        XCTAssertFalse(text.contains("System-managed"), "Constant target row removed")
        XCTAssertFalse(text.contains("Read-Only Policy"))
        XCTAssertFalse(text.contains("readOnlyExplanation"))
    }

    func testFanControlShownOncePerDetailsPage() throws {
        let text = try source("FanPanel.swift")
        XCTAssertEqual(text.components(separatedBy: "label: \"Control").count - 1, 1)
        XCTAssertFalse(text.contains("Control Mode"))
    }

    func testFanPagesRender() {
        let (defaults, prefs, coord, suite) = makeContext()
        defer { defaults.removePersistentDomain(forName: suite) }
        coord.handleReading(.fan(Sample(value: FanSample(fans: [
            FanReading(name: "Left", rpm: 1500, minRPM: 1200, maxRPM: 5800),
            FanReading(name: "Right", rpm: 1600, minRPM: 1200, maxRPM: 6000),
            FanReading(name: "Aux", rpm: 1400, minRPM: 1000, maxRPM: 5000)
        ]))))
        for tab in [PopoverTab.overview, .detail] {
            assertRenders(FanPanel(initialTab: tab, rememberLastTab: false, coordinator: coord, preferences: prefs))
        }
    }

    func testFanlessUsesFanSlash() {
        XCTAssertEqual(CategoryIdentity(.fan).liveSymbol(LiveSymbolState(isFanless: true)), "fan.slash")
        let (defaults, prefs, coord, suite) = makeContext()
        defer { defaults.removePersistentDomain(forName: suite) }
        coord.handleReading(.fan(Sample(value: FanSample(fans: []))))
        for tab in [PopoverTab.overview, .detail] {
            assertRenders(FanPanel(initialTab: tab, rememberLastTab: false, coordinator: coord, preferences: prefs))
        }
    }

    // MARK: - Network

    func testNetworkNowHasNoDuplicatePillOrLooseSpacing() throws {
        let text = try source("NetworkPanel.swift")
        XCTAssertFalse(text.contains("pillLabel"), "Connectivity pill duplicates the status chip")
        XCTAssertFalse(text.contains("Instrument.Space.l)"), "Use Space.sectionGap between sections")
        XCTAssertFalse(text.contains("(\"SSID\""), "Wi-Fi telemetry must not repeat the SSID shown on Now")
    }

    func testNetworkDetailsAndNowRender() {
        let (defaults, prefs, coord, suite) = makeContext()
        defer { defaults.removePersistentDomain(forName: suite) }
        coord.handleReading(.network(Sample(value: NetworkSample(
            interfaces: [InterfaceThroughput(interfaceName: "en0", bytesInPerSec: 1_250_000, bytesOutPerSec: 180_000, totalBytesIn: 12_400_000, totalBytesOut: 2_100_000, ipv4Address: "192.168.1.104", type: .wifi)],
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.104",
            gatewayIPv4: "192.168.1.1",
            primaryDNS: "1.1.1.1",
            wifiDetails: WiFiLinkTelemetry(ssid: "Studio-5G", rssi: -58, noise: -92, txRate: 650, channel: 44, band: "5 GHz")
        ))))
        for tab in [PopoverTab.overview, .detail] {
            assertRenders(NetworkPanel(initialTab: tab, rememberLastTab: false, coordinator: coord, preferences: prefs))
        }
    }

    // MARK: - Disk

    func testDiskHeroFormatterUsesUnits() throws {
        let si = Units.byteComponents(214_000_000_000, standard: .si)
        XCTAssertEqual(si.unit, "GB")
        XCTAssertEqual(si.value, 214.0, accuracy: 0.001)
        XCTAssertEqual(si.format, "%.0f")

        let iec = Units.byteComponents(214_000_000_000, standard: .iec)
        XCTAssertEqual(iec.unit, "GiB")
        XCTAssertEqual(iec.value, 199.30, accuracy: 0.01)

        let small = Units.byteComponents(5_500_000_000, standard: .si)
        XCTAssertEqual(small.unit, "GB")
        XCTAssertEqual(small.format, "%.1f")

        XCTAssertEqual(Units.byteComponents(512, standard: .si).unit, "B")
        let text = try source("DiskPanel.swift")
        XCTAssertFalse(text.contains("formatFreeSpace"), "Bespoke hero formatter removed")
    }

    func testDiskThroughputRowShowsRateAndIOPS() {
        let text = DiskPanel.throughputText(bytesPerSec: 14_500_000, opsPerSec: 1240, standard: .si)
        XCTAssertTrue(text.contains("MB/s"), text)
        XCTAssertTrue(text.contains("1,240 IOPS"), text)
        XCTAssertFalse(text.contains("ops/s"))
    }

    func testDiskPagesRenderWithManyVolumes() {
        let (defaults, prefs, coord, suite) = makeContext()
        defer { defaults.removePersistentDomain(forName: suite) }
        var volumes = [VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 494_000_000_000, used: 280_000_000_000, free: 214_000_000_000)]
        for i in 1...6 {
            volumes.append(VolumeCapacity(name: "Ext \(i)", mountPoint: "/Volumes/Ext\(i)", total: 1_000_000_000_000, used: 450_000_000_000, free: 550_000_000_000))
        }
        coord.handleReading(.disk(Sample(value: DiskSample(
            volumes: volumes,
            io: DiskIO(bytesReadPerSec: 80_000_000, bytesWrittenPerSec: 45_000_000, readOpsPerSec: 1200, writeOpsPerSec: 650)
        ))))
        for tab in [PopoverTab.overview, .detail] {
            assertRenders(DiskPanel(initialTab: tab, rememberLastTab: false, coordinator: coord, preferences: prefs))
        }
    }

    // MARK: - Power

    func testBatteryGlanceHeroAndScrubShareUnit() {
        let glance = PowerPanel.makeGlance(hasBattery: true, heroValue: 87, headline: "", insight: nil, chartMode: nil)
        XCTAssertEqual(glance.unit, "%")
        XCTAssertEqual(glance.scrubFormat?(64.4), "64%")
    }

    func testDesktopGlanceHeroAndScrubShareUnit() {
        let glance = PowerPanel.makeGlance(hasBattery: false, heroValue: 31.25, headline: "", insight: nil, chartMode: nil)
        XCTAssertEqual(glance.unit, "W")
        XCTAssertEqual(glance.format, "%.1f")
        XCTAssertEqual(glance.scrubFormat?(12.44), "12.4 W")
    }

    func testMissingHeroValueShowsDash() {
        let glance = PowerPanel.makeGlance(hasBattery: true, heroValue: nil, headline: "", insight: nil, chartMode: nil)
        XCTAssertEqual(glance.formattedValue, "—")
        XCTAssertEqual(glance.unit, "")
    }

    func testBatteryHeadlineCarriesWattsAndTime() {
        let s = PowerSample(hasBattery: true, charge: 72, state: .discharging, timeRemaining: 3 * 3600 + 40 * 60, powerDrawWatts: 12.4)
        XCTAssertEqual(PowerPanel.headline(sample: s), "Discharging 12.4 W · 3h 40m left")
        XCTAssertEqual(PowerPanel.headline(sample: nil), "Power telemetry unavailable")
    }

    func testPowerHasNoRedundantChargeOrMaxCapacityRows() throws {
        let text = try source("PowerPanel.swift")
        XCTAssertFalse(text.contains("label: \"Charge\""))
        XCTAssertFalse(text.contains("label: \"Max Capacity\""))
        XCTAssertFalse(text.contains("Charge & Time Remaining"))
    }

    func testBatteryAndDesktopPagesRender() {
        let (defaults, prefs, coord, suite) = makeContext()
        defer { defaults.removePersistentDomain(forName: suite) }
        coord.handleReading(.power(Sample(value: PowerSample(
            hasBattery: true, charge: 72, state: .discharging, timeRemaining: 13_200,
            cycleCount: 210, condition: "Normal", designCapacity: 6000, currentMaxCapacity: 5500,
            powerDrawWatts: 12.4, voltageVolts: 12.1, amperageMilliAmps: -1020
        ))))
        for tab in [PopoverTab.overview, .detail] {
            assertRenders(PowerPanel(initialTab: tab, rememberLastTab: false, coordinator: coord, preferences: prefs))
        }

        let (d2, p2, c2, s2) = makeContext()
        defer { d2.removePersistentDomain(forName: s2) }
        c2.handleReading(.power(Sample(value: PowerSample(hasBattery: false, powerDrawWatts: 31.2, adapterWatts: 150))))
        assertRenders(PowerPanel(initialTab: .overview, rememberLastTab: false, coordinator: c2, preferences: p2))
    }
}
