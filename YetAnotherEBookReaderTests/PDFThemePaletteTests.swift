import XCTest
@testable import YetAnotherEBookReader

final class PDFThemePaletteTests: XCTestCase {
    private func rgb(_ color: CGColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let c = color.components ?? []
        return (c[0], c[1], c[2])
    }

    /// The lists use FolioReader's menu colours (`FolioReaderConfig`), except the
    /// dark sheet, which is raised off the black page; text stays readable.
    func testListStyleUsesFolioReaderColours() {
        let expectedText: [PDFThemeMode: UInt32] = [.none: 0x000000, .serpia: 0x5F4B32, .forest: 0x37453F, .dark: 0xB6B6B6]
        for theme in PDFThemeMode.allCases {
            let palette = PDFThemePalette(themeMode: theme)
            let style = palette.listStyle
            XCTAssertEqual(hex(style.text), expectedText[theme], "\(theme)")
            XCTAssertEqual(hex(style.accent), 0x6ACC50, "\(theme)")
            XCTAssertEqual(style.background, palette.sheetBackground, "\(theme)")
            XCTAssertGreaterThanOrEqual(contrast(style.text, style.background), 4.5, "\(theme)")
            XCTAssertGreaterThanOrEqual(contrast(style.secondaryText, style.background), 4.5, "\(theme)")
            XCTAssertEqual(style.userInterfaceStyle, theme == .dark ? .dark : .light)
        }
        XCTAssertNotEqual(hex(PDFThemePalette(themeMode: .dark).listStyle.background), 0x000000, "not the black page")
        XCTAssertEqual(PDFThemePalette(themeMode: .none).listStyle.titleFont(level: 2).pointSize, 14, "FolioReader: 1.5 pt smaller per level")
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

    /// `CGColor(red:green:blue:)` is Generic RGB (gamma 1.8); bars built from it
    /// render visibly lighter than the page, so theme colours must be sRGB.
    func testTintBackgroundsAreSRGB() {
        for theme in [PDFThemeMode.serpia, .forest] {
            let palette = PDFThemePalette(themeMode: theme)
            XCTAssertEqual(palette.background.colorSpace?.name, CGColorSpace.sRGB, "\(theme)")
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

    private func hex(_ color: UIColor) -> UInt32 {
        let c = components(color)
        return UInt32((c.0 * 255).rounded()) << 16 | UInt32((c.1 * 255).rounded()) << 8 | UInt32((c.2 * 255).rounded())
    }
}

/// RGBA in sRGB, resolved for a theme's interface style.
func components(_ color: UIColor, style: UIUserInterfaceStyle = .light) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
    return (r, g, b, a)
}

/// WCAG contrast ratio of `foreground` (composited over `background`) against it.
func contrast(_ foreground: UIColor, _ background: UIColor, style: UIUserInterfaceStyle = .light) -> CGFloat {
    let bg = components(background, style: style)
    let fg = components(foreground, style: style)
    let mixed = (fg.0 * fg.3 + bg.0 * (1 - fg.3), fg.1 * fg.3 + bg.1 * (1 - fg.3), fg.2 * fg.3 + bg.2 * (1 - fg.3))
    func luminance(_ c: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
        func channel(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.0) + 0.7152 * channel(c.1) + 0.0722 * channel(c.2)
    }
    let l1 = luminance(mixed), l2 = luminance((bg.0, bg.1, bg.2))
    return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
}
