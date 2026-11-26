import XCTest
@testable import iStatsCore

final class MetricGlossaryTests: XCTestCase {
    func testEveryRequiredKeyResolvesWithNonEmptyFields() {
        XCTAssertFalse(MetricGlossary.requiredKeys.isEmpty)

        for key in MetricGlossary.requiredKeys {
            let entry = MetricGlossary.entry(for: key)
            XCTAssertEqual(entry.key, key)
            XCTAssertFalse(entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty title for \(key)")
            XCTAssertFalse(entry.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty summary for \(key)")
            XCTAssertFalse(entry.typical.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty typical for \(key)")
            XCTAssertFalse(entry.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(entry.learnMore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            let byString = MetricGlossary.entry(forKey: key.rawValue)
            XCTAssertEqual(byString, entry)
        }

        XCTAssertNil(MetricGlossary.entry(forKey: "unknown_metric_key"))
    }

    func testAllGlossaryTitlesAreUnique() {
        let titles = MetricGlossary.allEntries.map(\.title)
        XCTAssertEqual(titles.count, Set(titles).count, "Duplicate glossary titles found")
        XCTAssertEqual(MetricGlossary.allEntries.count, MetricGlossary.requiredKeys.count)
    }

    func testEveryCategoryHasGlossaryEntriesAndDestinationLookupMatches() {
        for category in MetricCategory.allCases {
            let categoryEntries = MetricGlossary.entries(for: category)
            XCTAssertFalse(categoryEntries.isEmpty, "Category \(category) has no glossary entries")
            XCTAssertTrue(categoryEntries.allSatisfy { $0.category == category })
            XCTAssertEqual(MetricGlossary.entries(for: .category(category)), categoryEntries)
        }

        let subset: Set<MetricCategory> = [.cpu, .memory]
        let overviewEntries = MetricGlossary.entries(for: .overview, enabledCategories: subset)
        XCTAssertTrue(overviewEntries.allSatisfy { subset.contains($0.category) })
        XCTAssertEqual(
            overviewEntries.count,
            MetricGlossary.entries(for: .cpu).count + MetricGlossary.entries(for: .memory).count
        )
    }

    func testExpectedCoreTermsArePresent() {
        let expected: [MetricTerm] = [
            .memoryPressure, .swap, .compressed, .wired,
            .loadAverage, .peCores, .cycleCount, .maxCapacity,
            .iops, .rssi, .snr, .throttling, .thermalState,
            .gpuEngines, .fanRpmRange
        ]
        for term in expected {
            XCTAssertTrue(MetricGlossary.requiredKeys.contains(term))
        }
    }
}
