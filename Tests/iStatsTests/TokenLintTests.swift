import XCTest

/// Source-level design-system lint (ADR 0011): panels and the Kit read type and spacing from `Instrument` tokens.
final class TokenLintTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // iStatsTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo
    }

    private func swiftFiles(under relative: String, excluding: Set<String> = []) throws -> [(name: String, text: String)] {
        let dir = repoRoot.appendingPathComponent(relative)
        let urls = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && !excluding.contains($0.lastPathComponent) } ?? []
        XCTAssertFalse(urls.isEmpty, "No sources found under \(dir.path)")
        return try urls.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    private func offenders(_ files: [(name: String, text: String)], matching pattern: String) -> [String] {
        var hits: [String] = []
        for file in files {
            for (i, line) in file.text.components(separatedBy: "\n").enumerated()
            where line.range(of: pattern, options: .regularExpression) != nil
                && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                hits.append("\(file.name):\(i + 1)")
            }
        }
        return hits
    }

    func testNoLiteralFontSizesInPanelsAndKit() throws {
        let panels = try swiftFiles(under: "iStats/UI/Panels")
        let instrument = try swiftFiles(under: "iStats/UI/Instrument", excluding: ["InstrumentTokens.swift"])
        let hits = offenders(panels + instrument, matching: #"\.system\(size:"#)
        XCTAssertTrue(hits.isEmpty, "Use Instrument.Typography tokens instead of literal sizes: \(hits)")
    }

    func testNoStatusThresholdLiteralsInPanels() throws {
        let panels = try swiftFiles(under: "iStats/UI/Panels")
        let hits = offenders(panels, matching: #"(>=|>) ?(90|75|65)(\.0)?\b.*(\.critical|\.warning|\.elevated)"#)
        XCTAssertTrue(hits.isEmpty, "Use StatusThresholds instead of literal cutoffs: \(hits)")
    }

    func testDeletedLegacyTokensStayDeleted() {
        let legacy = repoRoot.appendingPathComponent("iStats/UI/Design/Tokens.swift")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }
}
