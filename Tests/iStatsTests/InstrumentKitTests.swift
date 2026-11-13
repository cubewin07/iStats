import XCTest
import SwiftUI
import AppKit
@testable import iStatsCore
@testable import iStats

@MainActor
final class InstrumentKitTests: XCTestCase {

    // MARK: - 1. Secondary Series Hues

    func testSecondarySeriesColorsResolveInLightAndDark() {
        let seriesColors: [Color] = [
            CategoryPalette.Series.cpuUser,
            CategoryPalette.Series.cpuSystem,
            CategoryPalette.Series.cpuEfficiency,
            CategoryPalette.Series.memoryApp,
            CategoryPalette.Series.memoryWired,
            CategoryPalette.Series.memoryCompressed,
            CategoryPalette.Series.memoryCached,
            CategoryPalette.Series.networkDownload,
            CategoryPalette.Series.networkUpload,
            CategoryPalette.Series.diskRead,
            CategoryPalette.Series.diskWrite
        ]

        XCTAssertEqual(seriesColors.count, 11)
        for color in seriesColors {
            let nsColor = NSColor(color)
            XCTAssertNotNil(nsColor.usingColorSpace(.displayP3))
        }
    }

    // MARK: - 2. Section / Module v2 Integrated Header

    func testSectionAndModuleSourceCompatibilityAndLayout() {
        let section = Section("Processor Overview", trailing: {
            Text("Load 2.31")
                .font(Instrument.Typography.caption)
        }) {
            Text("Body row")
                .font(Instrument.Typography.body)
        }

        let titled = iStats.Section("Cores") {
            Text("Body row")
                .font(Instrument.Typography.body)
        }

        let legacyModule = Module(eyebrow: "Memory Composition") {
            Text("Legacy caller")
                .font(Instrument.Typography.body)
        }

        let headerless = iStats.Section {
            Text("No header")
        }

        for view in [AnyView(section), AnyView(titled), AnyView(legacyModule), AnyView(headerless)] {
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(x: 0, y: 0, width: 320, height: 100)
            hosting.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(hosting.fittingSize.width, 50)
            XCTAssertGreaterThan(hosting.fittingSize.height, 20)
        }

        XCTAssertEqual(legacyModule.eyebrow, "Memory Composition")
        XCTAssertEqual(section.title, "Processor Overview")
    }

    // MARK: - 3. MetricRow Table Style & B11 Default

    func testMetricRowDefaultsIsCopyableFalseAndHairlineHeight() {
        let defaultRow = MetricRow(label: "Mode", valueText: "Read-only (ADR 0004)")
        XCTAssertFalse(defaultRow.isCopyable, "B11: MetricRow.isCopyable must default to false")
        XCTAssertFalse(defaultRow.showHairline)

        let copyableHairlineRow = MetricRow(
            label: "Local IPv4",
            valueText: "192.168.1.42",
            statusLevel: .fine,
            isCopyable: true,
            showHairline: true
        )
        XCTAssertTrue(copyableHairlineRow.isCopyable)
        XCTAssertTrue(copyableHairlineRow.showHairline)

        let hosting = NSHostingView(rootView: copyableHairlineRow)
        hosting.frame = CGRect(x: 0, y: 0, width: 320, height: 40)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(hosting.fittingSize.height, 26.0)
    }

    // MARK: - 4. SegmentedControl & FilterChip

    func testSegmentedControlAndFilterChipRenderAcrossMotionPolicies() {
        for policy in [MotionPolicy.full, .reduced, .frozen] {
            let segmented = SegmentedControl(
                options: ["1m", "5m", "15m"],
                selection: .constant("5m")
            ) { $0 }
            .motionPolicy(policy)

            let segHost = NSHostingView(rootView: segmented)
            segHost.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
            segHost.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(segHost.fittingSize.width, 60)
            XCTAssertGreaterThan(segHost.fittingSize.height, 16)

            let chip = FilterChip(
                title: "Upload",
                isSelected: true,
                isDimmed: false,
                dotColor: CategoryPalette.Series.networkUpload,
                tint: CategoryPalette.Series.networkUpload
            ) {}
            .motionPolicy(policy)

            let chipHost = NSHostingView(rootView: chip)
            chipHost.frame = CGRect(x: 0, y: 0, width: 120, height: 40)
            chipHost.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(chipHost.fittingSize.width, 30)
            XCTAssertGreaterThan(chipHost.fittingSize.height, 14)
        }
    }

    // MARK: - 5. LiveNumber Cadence Gate (A12)

    func testLiveNumberCadenceGateIntegerUpdatesImmediately() {
        var gate = LiveNumberCadenceGate(initialValue: 40, now: 100.0)

        let updated1 = gate.evaluate(newValue: 41, formatted: "41", now: 100.5)
        XCTAssertTrue(updated1)
        XCTAssertEqual(gate.displayedValue, 41)

        let updated2 = gate.evaluate(newValue: 42, formatted: "42", now: 101.0)
        XCTAssertTrue(updated2)
        XCTAssertEqual(gate.displayedValue, 42)
    }

    func testLiveNumberCadenceGateThrottlesSmallFractionalJitter() {
        var gate = LiveNumberCadenceGate(initialValue: 8.4, now: 10.0)

        // Sub-unit change within 2.0s is gated
        let tick1 = gate.evaluate(newValue: 8.5, formatted: "8.5", now: 11.0)
        XCTAssertFalse(tick1)
        XCTAssertEqual(gate.displayedValue, 8.4, accuracy: 0.0001)

        // Another sub-unit change at 1.9s is still gated
        let tick2 = gate.evaluate(newValue: 8.6, formatted: "8.6", now: 11.9)
        XCTAssertFalse(tick2)
        XCTAssertEqual(gate.displayedValue, 8.4, accuracy: 0.0001)

        // At 2.0s elapsed, update commits
        let tick3 = gate.evaluate(newValue: 8.7, formatted: "8.7", now: 12.0)
        XCTAssertTrue(tick3)
        XCTAssertEqual(gate.displayedValue, 8.7, accuracy: 0.0001)

        // Large jump (>= 1.0) bypasses the 2.0s gate immediately
        let jump = gate.evaluate(newValue: 9.8, formatted: "9.8", now: 12.5)
        XCTAssertTrue(jump)
        XCTAssertEqual(gate.displayedValue, 9.8, accuracy: 0.0001)
    }

    // MARK: - 6. ProcessIconCache Negative Caching (B12)

    func testProcessIconCacheCachesMissesForNonAppProcesses() {
        var lookupCount = 0
        let sampleImage = NSImage(size: NSSize(width: 16, height: 16))
        let cache = ProcessIconCache(maxEntries: 4) { pid in
            lookupCount += 1
            return pid == 42 ? sampleImage : nil
        }

        // Non-app process miss: hits resolver once, subsequent calls return nil from negative cache
        XCTAssertNil(cache.icon(for: 999, bundleID: nil))
        XCTAssertEqual(lookupCount, 1)
        XCTAssertTrue(cache.hasCachedEntry(for: 999, bundleID: nil))

        XCTAssertNil(cache.icon(for: 999, bundleID: nil))
        XCTAssertNil(cache.icon(for: 999, bundleID: nil))
        XCTAssertEqual(lookupCount, 1, "B12: cached miss must not re-query resolver")

        // App process hit: hits resolver once, subsequent calls return cached NSImage
        XCTAssertNotNil(cache.icon(for: 42, bundleID: "com.example.App"))
        XCTAssertEqual(lookupCount, 2)
        XCTAssertNotNil(cache.icon(for: 42, bundleID: "com.example.App"))
        XCTAssertEqual(lookupCount, 2)
    }

    // MARK: - 7. TopConsumersModule Layout (A13)

    func testTopConsumersModuleRendersWithRowsAndEmptyState() {
        let items = [
            ProcessInfoItem(pid: 101, name: "Xcode", bundleID: nil, cpuPercent: 45.2, memoryBytes: 2_000_000_000),
            ProcessInfoItem(pid: 102, name: "kernel_task", bundleID: nil, cpuPercent: 12.4, memoryBytes: 500_000_000)
        ]

        let cpuModule = TopConsumersModule(
            criterion: .cpu,
            processes: items,
            skippedCount: 1,
            sparklines: [101: [10, 25, 45.2]]
        )
        let memModule = TopConsumersModule(criterion: .memory, processes: [])

        for view in [AnyView(cpuModule), AnyView(memModule)] {
            let host = NSHostingView(rootView: view)
            host.frame = CGRect(x: 0, y: 0, width: 320, height: 160)
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.width, 100)
            XCTAssertGreaterThan(host.fittingSize.height, 40)
        }
    }
}
