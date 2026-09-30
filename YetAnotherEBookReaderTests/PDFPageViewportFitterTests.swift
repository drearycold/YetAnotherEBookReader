import XCTest
@testable import YetAnotherEBookReader

final class PDFPageViewportFitterTests: XCTestCase {
    private let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    private let content = CGRect(x: 81, y: 96, width: 450, height: 600)
    /// 390x844 view with a 116pt top bar and 83pt bottom toolbar.
    private let readable = CGRect(x: 0, y: 116, width: 390, height: 645)

    private func input(
        content: CGRect? = nil,
        autoScaler: PDFAutoScaler = .Width,
        customScale: CGFloat = 1,
        readingDirection: PDFReadDirection = .LtR_TtB,
        marginOffset: Double = 0
    ) -> PDFPageViewportFitter.Input {
        PDFPageViewportFitter.Input(
            contentBounds: content ?? self.content,
            pageBounds: page,
            readableRect: readable,
            autoScaler: autoScaler,
            hMarginPercent: 5,
            vMarginPercent: 5,
            customScale: customScale,
            readingDirection: readingDirection,
            marginOffsetPercent: marginOffset
        )
    }

    /// Where `rect` (page space) lands in view space under `fit`.
    private func place(_ rect: CGRect, _ fit: PDFPageViewportFit) -> CGRect {
        func viewX(_ x: CGFloat) -> CGFloat { fit.viewAnchor.x + (x - fit.pageAnchor.x) * fit.scale }
        func viewY(_ y: CGFloat) -> CGFloat { fit.viewAnchor.y - (y - fit.pageAnchor.y) * fit.scale }
        return CGRect(x: viewX(rect.minX), y: viewY(rect.maxY), width: rect.width * fit.scale, height: rect.height * fit.scale)
    }

    func testWidthFitCentersContentAndTopAlignsBelowBar() {
        let fit = PDFPageViewportFitter.fit(input())
        let placed = place(content, fit)

        XCTAssertEqual(fit.scale, 390 * 0.9 / 450, accuracy: 0.0001)
        XCTAssertEqual(placed.minX, 19.5, accuracy: 0.001)
        XCTAssertEqual(readable.maxX - placed.maxX, 19.5, accuracy: 0.001)
        XCTAssertEqual(placed.minY, 116 + 645 * 0.05, accuracy: 0.001)
    }

    func testTopPlacementIsIndependentOfContentWidth() {
        let narrow = CGRect(x: 131, y: 96, width: 350, height: 600)
        let wide = PDFPageViewportFitter.fit(input())
        let narrowFit = PDFPageViewportFitter.fit(input(content: narrow))

        XCTAssertEqual(place(content, wide).minY, place(narrow, narrowFit).minY, accuracy: 0.001)
    }

    func testHeightAndPageScalers() {
        let height = PDFPageViewportFitter.fit(input(autoScaler: .Height))
        let pageFit = PDFPageViewportFitter.fit(input(autoScaler: .Page))

        XCTAssertEqual(height.scale, 645 * 0.9 / 600, accuracy: 0.0001)
        XCTAssertEqual(pageFit.scale, min(390 * 0.9 / 450, 645 * 0.9 / 600), accuracy: 0.0001)
    }

    func testCustomScaleWiderThanViewStartsAtLeadingMargin() {
        let fit = PDFPageViewportFitter.fit(input(autoScaler: .Custom, customScale: 2))
        let placed = place(content, fit)

        XCTAssertEqual(fit.scale, 2)
        XCTAssertEqual(placed.minX, 19.5, accuracy: 0.001)
    }

    func testCustomScaleWithoutSavedScaleFallsBackToPage() {
        let fit = PDFPageViewportFitter.fit(input(autoScaler: .Custom, customScale: -1))

        XCTAssertEqual(fit.scale, min(390 * 0.9 / 450, 645 * 0.9 / 600), accuracy: 0.0001)
    }

    func testMarginOffsetShiftsHorizontallyOnly() {
        let base = place(content, PDFPageViewportFitter.fit(input()))
        let fit = PDFPageViewportFitter.fit(input(marginOffset: 5))
        let shifted = place(content, fit)

        XCTAssertEqual(shifted.minX - base.minX, -612 * 0.05 * fit.scale, accuracy: 0.001)
        XCTAssertEqual(shifted.minY, base.minY, accuracy: 0.001)
        XCTAssertEqual(shifted.width, base.width, accuracy: 0.001)
    }

    /// Wider than the view (Height on a portrait phone): the text starts at the
    /// right margin.
    func testVerticalTextWiderThanViewStartsAtRightEdge() {
        let fit = PDFPageViewportFitter.fit(input(autoScaler: .Height, readingDirection: .TtB_RtL))
        let placed = place(content, fit)

        XCTAssertGreaterThan(placed.width, readable.width * 0.9)
        XCTAssertEqual(readable.maxX - placed.maxX, 19.5, accuracy: 0.001)
        XCTAssertEqual(placed.midY, readable.midY, accuracy: 0.001)
    }

    /// Fitting the view (Page), vertical text is centered like horizontal text.
    func testVerticalTextThatFitsIsCentered() {
        let fit = PDFPageViewportFitter.fit(input(autoScaler: .Page, readingDirection: .TtB_RtL))
        let placed = place(content, fit)

        XCTAssertEqual(placed.midX, readable.midX, accuracy: 0.001)
        XCTAssertEqual(placed.midY, readable.midY, accuracy: 0.001)
    }

    func testEmptyContentFallsBackToPageBounds() {
        let fit = PDFPageViewportFitter.fit(input(content: .zero))

        XCTAssertEqual(fit.scale, 390 * 0.9 / 612, accuracy: 0.0001)
    }

    func testPageSpaceRectConvertsDetectorOutput() {
        let crop = CGRect(x: 40, y: 60, width: 500, height: 700)
        let detected = CGRect(x: 80, y: 100, width: 360, height: 520)

        XCTAssertEqual(
            PDFPageViewportFitter.pageSpaceRect(detected: detected, pageBounds: crop),
            CGRect(x: 120, y: 140, width: 360, height: 520)
        )
    }
}
