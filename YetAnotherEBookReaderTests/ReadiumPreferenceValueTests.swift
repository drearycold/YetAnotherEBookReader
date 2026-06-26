import XCTest
import UIKit
import ReadiumNavigator
@testable import YetAnotherEBookReader

final class ReadiumPreferenceValueTests: XCTestCase {
    func testRealmRoundTripPreservesAllFields() {
        let value = ReadiumPreferenceValue(
            id: "pref-1",
            themeMode: 2,
            fontSizePercentage: 135,
            fontFamily: "Palatino",
            lineHeight: 1.45,
            pageMargins: 1.8,
            publisherStyles: false,
            scroll: true,
            textAlign: 4,
            columnCount: 2,
            fontWeight: 1.2,
            letterSpacing: 0.15,
            wordSpacing: 0.2,
            hyphens: true,
            imageFilter: 2,
            textNormalization: true,
            typeScale: 1.3,
            paragraphIndent: 0.4,
            paragraphSpacing: 0.5,
            volumeKeyPaging: true,
            verticalMargin: 28,
            readingProgression: 1,
            fit: 2,
            ligatures: true,
            offsetFirstPage: true,
            spread: 2,
            verticalText: true,
            pageSpacing: 12,
            scrollAxis: 1,
            visibleScrollbar: false
        )

        let realmValue = ReadiumPreferenceRealm(id: value.id, value: value)
        XCTAssertEqual(realmValue.toValue(), value)

        var updated = value
        updated.themeMode = 1
        updated.verticalMargin = 14
        updated.visibleScrollbar = true
        realmValue.apply(updated)

        XCTAssertEqual(realmValue.toValue(), updated)
    }

    func testToEPUBAndPDFPreferencesMapsFields() {
        let value = ReadiumPreferenceValue(
            id: "pref-2",
            themeMode: 1,
            fontSizePercentage: 125,
            fontFamily: "Palatino",
            lineHeight: 1.5,
            pageMargins: 1.6,
            publisherStyles: false,
            scroll: true,
            textAlign: 4,
            columnCount: 2,
            fontWeight: 1.3,
            letterSpacing: 0.12,
            wordSpacing: 0.18,
            hyphens: true,
            imageFilter: 1,
            textNormalization: true,
            typeScale: 1.25,
            paragraphIndent: 0.35,
            paragraphSpacing: 0.4,
            volumeKeyPaging: true,
            verticalMargin: 0,
            readingProgression: 1,
            fit: 2,
            ligatures: true,
            offsetFirstPage: false,
            spread: 1,
            verticalText: true,
            pageSpacing: 10,
            scrollAxis: 1,
            visibleScrollbar: false
        )

        let epub = value.toEPUBPreferences()
        XCTAssertEqual(epub.theme, .sepia)
        XCTAssertEqual(epub.fontSize, 1.25)
        XCTAssertEqual(epub.fontFamily, .palatino)
        XCTAssertEqual(epub.lineHeight, 1.5)
        XCTAssertEqual(epub.pageMargins, 1.6)
        XCTAssertEqual(epub.publisherStyles, false)
        XCTAssertEqual(epub.scroll, true)
        XCTAssertEqual(epub.textAlign, .justify)
        XCTAssertEqual(epub.columnCount, .two)
        XCTAssertEqual(epub.fontWeight, 1.3)
        XCTAssertEqual(epub.letterSpacing, 0.12)
        XCTAssertEqual(epub.wordSpacing, 0.18)
        XCTAssertEqual(epub.hyphens, true)
        XCTAssertEqual(epub.imageFilter, .darken)
        XCTAssertEqual(epub.textNormalization, true)
        XCTAssertEqual(epub.typeScale, 1.25)
        XCTAssertEqual(epub.paragraphIndent, 0.35)
        XCTAssertEqual(epub.paragraphSpacing, 0.4)
        XCTAssertEqual(epub.readingProgression, .rtl)
        XCTAssertEqual(epub.fit, .width)
        XCTAssertEqual(epub.ligatures, true)
        XCTAssertEqual(epub.offsetFirstPage, false)
        XCTAssertEqual(epub.spread, .never)
        XCTAssertEqual(epub.verticalText, true)

        let pdf = value.toPDFPreferences()
        XCTAssertEqual(pdf.fit, .width)
        XCTAssertEqual(pdf.offsetFirstPage, false)
        XCTAssertEqual(pdf.pageSpacing, 10)
        XCTAssertEqual(pdf.readingProgression, .rtl)
        XCTAssertEqual(pdf.scroll, true)
        XCTAssertEqual(pdf.scrollAxis, .horizontal)
        XCTAssertEqual(pdf.spread, .never)
        XCTAssertEqual(pdf.visibleScrollbar, false)
    }

    func testUpdateFromReadiumPreferencesMapsIntoValueType() {
        var epubValue = ReadiumPreferenceValue()
        epubValue.update(from: EPUBPreferences(
            columnCount: .one,
            fit: .page,
            fontFamily: .georgia,
            fontSize: 1.4,
            fontWeight: 1.1,
            hyphens: true,
            imageFilter: .invert,
            letterSpacing: 0.09,
            ligatures: true,
            lineHeight: 1.55,
            offsetFirstPage: true,
            pageMargins: 1.7,
            paragraphIndent: 0.3,
            paragraphSpacing: 0.6,
            publisherStyles: false,
            readingProgression: .rtl,
            scroll: true,
            spread: .always,
            textAlign: .right,
            textNormalization: true,
            theme: .dark,
            typeScale: 1.4,
            verticalText: true,
            wordSpacing: 0.22
        ))

        XCTAssertEqual(epubValue.themeMode, 2)
        XCTAssertEqual(epubValue.fontSizePercentage, 140)
        XCTAssertEqual(epubValue.fontFamily, "Georgia")
        XCTAssertEqual(epubValue.lineHeight, 1.55)
        XCTAssertEqual(epubValue.pageMargins, 1.7)
        XCTAssertEqual(epubValue.publisherStyles, false)
        XCTAssertEqual(epubValue.scroll, true)
        XCTAssertEqual(epubValue.textAlign, 3)
        XCTAssertEqual(epubValue.columnCount, 1)
        XCTAssertEqual(epubValue.fontWeight, 1.1)
        XCTAssertEqual(epubValue.letterSpacing, 0.09)
        XCTAssertEqual(epubValue.wordSpacing, 0.22)
        XCTAssertEqual(epubValue.hyphens, true)
        XCTAssertEqual(epubValue.imageFilter, 2)
        XCTAssertEqual(epubValue.textNormalization, true)
        XCTAssertEqual(epubValue.typeScale, 1.4)
        XCTAssertEqual(epubValue.paragraphIndent, 0.3)
        XCTAssertEqual(epubValue.paragraphSpacing, 0.6)
        XCTAssertEqual(epubValue.readingProgression, 1)
        XCTAssertEqual(epubValue.fit, 1)
        XCTAssertEqual(epubValue.ligatures, true)
        XCTAssertEqual(epubValue.offsetFirstPage, true)
        XCTAssertEqual(epubValue.spread, 2)
        XCTAssertEqual(epubValue.verticalText, true)

        var pdfValue = ReadiumPreferenceValue()
        pdfValue.update(from: PDFPreferences(
            fit: .page,
            offsetFirstPage: false,
            pageSpacing: 8,
            readingProgression: .rtl,
            scroll: true,
            scrollAxis: .horizontal,
            spread: .always,
            visibleScrollbar: false
        ))

        XCTAssertEqual(pdfValue.scroll, true)
        XCTAssertEqual(pdfValue.readingProgression, 1)
        XCTAssertEqual(pdfValue.offsetFirstPage, false)
        XCTAssertEqual(pdfValue.pageSpacing, 8)
        XCTAssertEqual(pdfValue.scrollAxis, 1)
        XCTAssertEqual(pdfValue.visibleScrollbar, false)
        XCTAssertEqual(pdfValue.fit, 1)
        XCTAssertEqual(pdfValue.spread, 2)
    }

    func testThemeColorReaderEnginePreferencesAndApply() {
        let sepia = ReadiumPreferenceValue(themeMode: 1).themeColor
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(sepia.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(red, 0.98, accuracy: 0.001)
        XCTAssertEqual(green, 0.96, accuracy: 0.001)
        XCTAssertEqual(blue, 0.91, accuracy: 0.001)
        XCTAssertEqual(alpha, 1.0, accuracy: 0.001)

        let prefs = ReadiumPreferenceValue(
            themeMode: 2,
            fontSizePercentage: 145,
            fontFamily: "Avenir",
            lineHeight: 1.35,
            pageMargins: 1.5,
            scroll: true,
            volumeKeyPaging: true,
            scrollAxis: 1
        ).toReaderEnginePreferences()

        XCTAssertEqual(prefs.themeMode, 2)
        XCTAssertEqual(prefs.fontSizePercentage, 145)
        XCTAssertEqual(prefs.fontFamily, "Avenir")
        XCTAssertEqual(prefs.lineHeight, 1.35)
        XCTAssertEqual(prefs.pageMargins, 1.5)
        XCTAssertEqual(prefs.scroll, true)
        XCTAssertEqual(prefs.scrollDirection, 1)
        XCTAssertEqual(prefs.volumeKeyPaging, true)

        var value = ReadiumPreferenceValue()
        value.apply(ReaderEnginePreferences(
            themeMode: 1,
            fontSizePercentage: 130,
            fontFamily: "Georgia",
            lineHeight: 1.42,
            pageMargins: 1.9,
            scroll: true,
            scrollDirection: 1,
            volumeKeyPaging: true
        ))

        XCTAssertEqual(value.themeMode, 1)
        XCTAssertEqual(value.fontSizePercentage, 130)
        XCTAssertEqual(value.fontFamily, "Georgia")
        XCTAssertEqual(value.lineHeight, 1.42)
        XCTAssertEqual(value.pageMargins, 1.9)
        XCTAssertEqual(value.scroll, true)
        XCTAssertEqual(value.scrollAxis, 1)
        XCTAssertEqual(value.volumeKeyPaging, true)
    }
}
