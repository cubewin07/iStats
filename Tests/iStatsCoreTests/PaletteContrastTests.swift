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

        let darkPalette: [(String, String)] = [
            ("CPU", "#5C8DFF"),
            ("Memory", "#33D1A6"),
            ("GPU", "#A386FF"),
            ("Thermal", "#FF8A4C"),
            ("Fan", "#3CC6E8"),
            ("Network", "#8389FF"),
            ("Disk", "#FF6E9C"),
            ("Power", "#4ADE80")
        ]

        for (category, hex) in darkPalette {
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

        let statusColors: [(String, String)] = [
            ("Elevated", "#FFC53D"),
            ("Warning", "#FF9F45"),
            ("Critical", "#FF5C5C")
        ]

        for (status, hex) in statusColors {
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
        let glassBg = RGBColor(hex: "#F2F2F7")!

        let lightPalette: [(String, String)] = [
            ("CPU", "#0058D6"),
            ("Memory", "#006E80"),
            ("GPU", "#6D28D9"),
            ("Thermal", "#B54308"),
            ("Fan", "#0B6E66"),
            ("Network", "#087054"),
            ("Disk", "#364FC7"),
            ("Power", "#147530")
        ]

        for (category, hex) in lightPalette {
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
        let glassBg = RGBColor(hex: "#F2F2F7")!

        let colors: [(String, String)] = [
            ("Elevated", "#9E5800"),
            ("Warning", "#B83E00"),
            ("Critical", "#C42014"),
            ("CPUSystem", "#C23B1E"),
            ("NetUpload", "#6D28D9"),
            ("DiskWrite", "#B8470B"),
            ("MemoryApp", "#005EB8")
        ]

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
