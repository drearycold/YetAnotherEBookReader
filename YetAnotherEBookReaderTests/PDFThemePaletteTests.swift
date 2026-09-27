import XCTest
@testable import YetAnotherEBookReader

final class PDFThemePaletteTests: XCTestCase {
    private func rgb(_ color: CGColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let c = color.components ?? []
        return (c[0], c[1], c[2])
    }

    func testLightTintOverlayMapsWhiteExactlyToBackgroundAndKeepsBlackDark() throws {
        for theme in [PDFThemeMode.serpia, .forest] {
            let palette = PDFThemePalette(themeMode: theme)
            let overlay = try XCTUnwrap(palette.overlay, "\(theme)")
            let background = rgb(palette.background)

            let white = overlay.composite(over: (1, 1, 1))
            XCTAssertEqual(white.red, background.red, accuracy: 0.5 / 255, "\(theme)")
            XCTAssertEqual(white.green, background.green, accuracy: 0.5 / 255, "\(theme)")
            XCTAssertEqual(white.blue, background.blue, accuracy: 0.5 / 255, "\(theme)")

            let black = overlay.composite(over: (0, 0, 0))
            XCTAssertLessThanOrEqual(max(black.red, black.green, black.blue), 0.14, "\(theme) black=\(black)")

            XCTAssertFalse(palette.drawsInverted)
            XCTAssertEqual(palette.canvas, CGColor(gray: 1, alpha: 1), "canvas must be white so the overlay turns it into the background")
        }
    }

    func testDarkIsDrawnInvertedWithoutOverlay() {
        let palette = PDFThemePalette(themeMode: .dark)

        XCTAssertNil(palette.overlay)
        XCTAssertTrue(palette.drawsInverted)
        XCTAssertEqual(palette.canvas, palette.background)
    }

    func testNoneHasNoTint() {
        let palette = PDFThemePalette(themeMode: .none)

        XCTAssertNil(palette.overlay)
        XCTAssertFalse(palette.drawsInverted)
    }

    func testFillColorIsPaletteBackground() {
        for theme in PDFThemeMode.allCases {
            let value = PDFPreferenceValue(themeMode: theme)
            XCTAssertEqual(value.fillColor, PDFThemePalette(themeMode: theme).background, "\(theme)")
        }
    }
}
