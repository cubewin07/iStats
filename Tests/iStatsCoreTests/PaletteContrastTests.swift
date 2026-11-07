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
            ("NetUpload", PaletteContrast.Hex.networkUpload.light),
            ("DiskWrite", PaletteContrast.Hex.diskWrite.light),
            ("MemoryApp", PaletteContrast.Hex.memoryApp.light)
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
}
