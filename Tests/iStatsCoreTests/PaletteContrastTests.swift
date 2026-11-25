import XCTest
import iStatsCore

final class PaletteContrastTests: XCTestCase {

    func testRGBColorParsing() {
        let white = RGBColor(hex: "#FFFFFF")
        XCTAssertNotNil(white)
        XCTAssertEqual(white?.red, 1.0)
        XCTAssertEqual(white?.green, 1.0)
        XCTAssertEqual(white?.blue, 1.0)

        let black = RGBColor(hex: "000000")
        XCTAssertNotNil(black)
        XCTAssertEqual(black?.red, 0.0)
        XCTAssertEqual(black?.green, 0.0)
        XCTAssertEqual(black?.blue, 0.0)

        let invalid = RGBColor(hex: "invalid")
        XCTAssertNil(invalid)
    }

    func testRelativeLuminanceKnownValues() {
        let white = RGBColor(hex: "#FFFFFF")!
        let black = RGBColor(hex: "#000000")!

        XCTAssertEqual(white.relativeLuminance, 1.0, accuracy: 0.001)
        XCTAssertEqual(black.relativeLuminance, 0.0, accuracy: 0.001)

        // Contrast ratio between pure white and pure black must be 21:1
        XCTAssertEqual(white.contrastRatio(with: black), 21.0, accuracy: 0.01)
    }

    func testTextOnSurfacesContrast() {
        let white = PaletteContrast.white
        let black = PaletteContrast.black
        let darkBg = PaletteContrast.darkBackground
        let lightBg = PaletteContrast.lightBackground

        // White text on dark surface (≥ 4.5:1)
        let whiteOnDark = white.contrastRatio(with: darkBg)
        XCTAssertGreaterThanOrEqual(whiteOnDark, 4.5)
        XCTAssertTrue(PaletteContrast.meetsWcagAA(text: white, background: darkBg))

        // Black text on light surface (≥ 4.5:1)
        let blackOnLight = black.contrastRatio(with: lightBg)
        XCTAssertGreaterThanOrEqual(blackOnLight, 4.5)
        XCTAssertTrue(PaletteContrast.meetsWcagAA(text: black, background: lightBg))
    }

    func testDarkCategoryTintsContrastOnDarkBackground() {
        // All 8 category dark tints on dark surface (#1C1C1E) must satisfy WCAG AA (≥ 4.5:1)
        let darkBackground = PaletteContrast.darkBackground

        for category in MetricCategory.allCases {
            let hex = PaletteContrast.Hex.categoryTint(for: category).dark
            guard let color = RGBColor(hex: hex) else {
                XCTFail("Failed to parse hex \(hex) for \(category)")
                continue
            }
            let ratio = color.contrastRatio(with: darkBackground)
            XCTAssertGreaterThanOrEqual(
                ratio,
                4.5,
                "\(category) dark tint (\(hex)) contrast ratio \(ratio) is below 4.5:1 on dark background"
            )
        }
    }

    func testStatusColorsContrastOnDarkBackground() {
        let darkBackground = PaletteContrast.darkBackground

        for status in StatusLevel.allCases {
            let hex = PaletteContrast.Hex.status(for: status).dark
            guard let color = RGBColor(hex: hex) else {
                XCTFail("Failed to parse hex \(hex) for status \(status)")
                continue
            }
            let ratio = color.contrastRatio(with: darkBackground)
            XCTAssertGreaterThanOrEqual(
                ratio,
                4.5,
                "\(status) status color (\(hex)) contrast ratio \(ratio) is below 4.5:1 on dark background"
            )
        }
    }

    func testLightCategoryTintsContrastOnLightSurfaces() {
        let whiteBg = PaletteContrast.lightBackground
        let glassBg = PaletteContrast.lightGlassBackground

        for category in MetricCategory.allCases {
            let hex = PaletteContrast.Hex.categoryTint(for: category).light
            guard let color = RGBColor(hex: hex) else {
                XCTFail("Failed to parse hex \(hex) for \(category)")
                continue
            }
            let whiteRatio = color.contrastRatio(with: whiteBg)
            let glassRatio = color.contrastRatio(with: glassBg)

            XCTAssertGreaterThanOrEqual(
                whiteRatio,
                4.5,
                "\(category) light tint (\(hex)) contrast ratio \(whiteRatio) is below 4.5:1 on white background"
            )
            XCTAssertGreaterThanOrEqual(
                glassRatio,
                4.5,
                "\(category) light tint (\(hex)) contrast ratio \(glassRatio) is below 4.5:1 on light glass background"
            )
        }
    }

    func testLightStatusAndSeriesColorsContrastOnLightSurfaces() {
        let whiteBg = PaletteContrast.lightBackground
        let glassBg = PaletteContrast.lightGlassBackground

        var colors: [(String, String)] = StatusLevel.allCases.map {
            ("\($0)", PaletteContrast.Hex.status(for: $0).light)
        }
        colors.append(contentsOf: [
            ("CPUSystem", PaletteContrast.Hex.cpuSystem.light),
            ("CPUEfficiency", PaletteContrast.Hex.cpuEfficiency.light),
            ("NetUpload", PaletteContrast.Hex.networkUpload.light),
            ("DiskWrite", PaletteContrast.Hex.diskWrite.light),
            ("MemoryApp", PaletteContrast.Hex.memoryApp.light),
            ("MemoryWired", PaletteContrast.Hex.memoryWired.light),
            ("MemoryCompressed", PaletteContrast.Hex.memoryCompressed.light),
            ("MemoryCached", PaletteContrast.Hex.memoryCached.light)
        ])

        for (name, hex) in colors {
            guard let color = RGBColor(hex: hex) else {
                XCTFail("Failed to parse hex \(hex) for \(name)")
                continue
            }
            let whiteRatio = color.contrastRatio(with: whiteBg)
            let glassRatio = color.contrastRatio(with: glassBg)

            XCTAssertGreaterThanOrEqual(
                whiteRatio,
                4.5,
                "\(name) light color (\(hex)) contrast ratio \(whiteRatio) is below 4.5:1 on white background"
            )
            XCTAssertGreaterThanOrEqual(
                glassRatio,
                4.5,
                "\(name) light color (\(hex)) contrast ratio \(glassRatio) is below 4.5:1 on light glass background"
            )
        }
    }

    func testDarkSeriesColorsContrastOnDarkBackground() {
        let darkBackground = PaletteContrast.darkBackground
        let colors: [(String, String)] = [
            ("CPUSystem", PaletteContrast.Hex.cpuSystem.dark),
            ("CPUEfficiency", PaletteContrast.Hex.cpuEfficiency.dark),
            ("NetUpload", PaletteContrast.Hex.networkUpload.dark),
            ("DiskWrite", PaletteContrast.Hex.diskWrite.dark),
            ("MemoryApp", PaletteContrast.Hex.memoryApp.dark),
            ("MemoryWired", PaletteContrast.Hex.memoryWired.dark),
            ("MemoryCompressed", PaletteContrast.Hex.memoryCompressed.dark),
            ("MemoryCached", PaletteContrast.Hex.memoryCached.dark)
        ]

        for (name, hex) in colors {
            guard let color = RGBColor(hex: hex) else {
                XCTFail("Failed to parse hex \(hex) for \(name)")
                continue
            }
            let ratio = color.contrastRatio(with: darkBackground)
            XCTAssertGreaterThanOrEqual(
                ratio,
                4.5,
                "\(name) dark color (\(hex)) contrast ratio \(ratio) is below 4.5:1 on dark background"
            )
        }
    }

    // MARK: - Hue identity (ADR 0011)

    private func hue(_ hex: String) -> Double { RGBColor(hex: hex)!.hueDegrees }

    /// Fans are a desaturated steel and are separated from the hue wheel by saturation.
    private let saturatedCategories = MetricCategory.allCases.filter { $0 != .fan }

    func testHueDistanceWrapsAround() {
        XCTAssertEqual(RGBColor.hueDistance(350, 10), 20, accuracy: 0.001)
        XCTAssertEqual(RGBColor.hueDistance(0, 180), 180, accuracy: 0.001)
        XCTAssertEqual(RGBColor(hex: "#FF0000")!.hueDegrees, 0, accuracy: 0.5)
        XCTAssertEqual(RGBColor(hex: "#00FF00")!.hueDegrees, 120, accuracy: 0.5)
        XCTAssertEqual(RGBColor(hex: "#0000FF")!.hueDegrees, 240, accuracy: 0.5)
    }

    func testSaturatedCategoriesArePairwiseDistinctInHue() {
        for appearance in ["light", "dark"] {
            for (i, a) in saturatedCategories.enumerated() {
                for b in saturatedCategories[(i + 1)...] {
                    let ta = PaletteContrast.Hex.categoryTint(for: a)
                    let tb = PaletteContrast.Hex.categoryTint(for: b)
                    let ha = hue(appearance == "light" ? ta.light : ta.dark)
                    let hb = hue(appearance == "light" ? tb.light : tb.dark)
                    XCTAssertGreaterThanOrEqual(
                        RGBColor.hueDistance(ha, hb), 25,
                        "\(a) and \(b) are too close in \(appearance) hue (\(ha), \(hb))"
                    )
                }
            }
        }
    }

    func testFansAreDesaturatedSteel() {
        let fan = PaletteContrast.Hex.categoryTint(for: .fan)
        for hex in [fan.light, fan.dark] {
            XCTAssertLessThanOrEqual(RGBColor(hex: hex)!.saturation, 0.35, "Fan tint \(hex) must stay low saturation")
        }
        for category in saturatedCategories {
            let t = PaletteContrast.Hex.categoryTint(for: category)
            XCTAssertGreaterThanOrEqual(RGBColor(hex: t.light)!.saturation, 0.5, "\(category) light tint must be saturated")
            XCTAssertGreaterThanOrEqual(RGBColor(hex: t.dark)!.saturation, 0.45, "\(category) dark tint must be saturated")
        }
    }

    func testLightDarkHueDriftWithinFifteenDegrees() {
        for category in MetricCategory.allCases {
            for pair in [PaletteContrast.Hex.categoryTint(for: category), PaletteContrast.Hex.categoryDeep(for: category)] {
                XCTAssertLessThanOrEqual(
                    RGBColor.hueDistance(hue(pair.light), hue(pair.dark)), 15,
                    "\(category) hue flips between light (\(pair.light)) and dark (\(pair.dark))"
                )
            }
        }
    }

    func testCategoriesAreSeparatedFromStatusHues() {
        // Every saturated category stays >= 15 deg away from the "fine" green so Power cannot read as status.
        // Temperature is exempt from the warm status hues: orange is its identity and the status ramp
        // (amber, orange, red) occupies the same arc, so it is distinguished by symbol and placement.
        for category in saturatedCategories {
            let tint = PaletteContrast.Hex.categoryTint(for: category)
            for level in StatusLevel.allCases {
                if category == .thermal && level != .fine { continue }
                let status = PaletteContrast.Hex.status(for: level)
                for (c, s) in [(tint.light, status.light), (tint.dark, status.dark)] {
                    XCTAssertGreaterThanOrEqual(
                        RGBColor.hueDistance(hue(c), hue(s)), 15,
                        "\(category) tint \(c) is too close to \(level) status \(s)"
                    )
                }
            }
        }
    }

    func testDeepColorsAreDarkerThanTints() {
        for category in MetricCategory.allCases {
            let tint = PaletteContrast.Hex.categoryTint(for: category)
            let deep = PaletteContrast.Hex.categoryDeep(for: category)
            XCTAssertLessThan(RGBColor(hex: deep.light)!.relativeLuminance, RGBColor(hex: tint.light)!.relativeLuminance)
            XCTAssertLessThan(RGBColor(hex: deep.dark)!.relativeLuminance, RGBColor(hex: tint.dark)!.relativeLuminance)
        }
    }
}
