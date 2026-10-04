import XCTest
@testable import YetAnotherEBookReader

/// Column detection (#19) on synthetic ink maps of a page's content box.
final class PDFColumnDetectorTests: XCTestCase {
    private let width = 600
    private let height = 800

    /// A text block: 7 px lines on an 11 px pitch, broken by 3 px word gaps that
    /// fall in different places on consecutive lines, as in set text. `lineEnd`
    /// gives a line's right end (ragged text).
    private struct TextBlock {
        var rect: CGRect
        var lineEnd: ((Int) -> CGFloat)?

        func isInked(_ x: Int, _ y: Int) -> Bool {
            guard rect.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) else { return false }
            let line = (y - Int(rect.minY)) / 11
            guard (y - Int(rect.minY)) % 11 < 7 else { return false }
            if let lineEnd, CGFloat(x) >= lineEnd(line) { return false }
            return (x - Int(rect.minX) + line * 13) % 23 >= 3
        }
    }

    /// Vertical text: 7 px lines on an 11 px pitch from the right edge leftward,
    /// broken by 3 px gaps between characters.
    private struct VerticalTextBlock {
        var rect: CGRect

        func isInked(_ x: Int, _ y: Int) -> Bool {
            guard rect.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) else { return false }
            let fromRight = Int(rect.maxX) - 1 - x
            let line = fromRight / 11
            guard fromRight % 11 < 7 else { return false }
            return (y - Int(rect.minY) + line * 13) % 23 >= 3
        }
    }

    private func vertical(_ x: ClosedRange<CGFloat>, _ y: ClosedRange<CGFloat>) -> VerticalTextBlock {
        VerticalTextBlock(rect: CGRect(x: x.lowerBound, y: y.lowerBound, width: x.upperBound - x.lowerBound, height: y.upperBound - y.lowerBound))
    }

    private func map(vertical blocks: [VerticalTextBlock]) -> PDFInkMap {
        PDFInkMap(width: width, height: height) { x, y in
            blocks.contains { $0.isInked(x, y) }
        }
    }

    private func map(text: [TextBlock], solid: [CGRect] = [], specks: [CGPoint] = []) -> PDFInkMap {
        PDFInkMap(width: width, height: height) { x, y in
            let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
            return text.contains { $0.isInked(x, y) }
                || solid.contains { $0.contains(point) }
                || specks.contains { CGRect(origin: $0, size: CGSize(width: 2, height: 2)).contains(point) }
        }
    }

    private func text(_ x: ClosedRange<CGFloat>, _ y: ClosedRange<CGFloat>, lineEnd: ((Int) -> CGFloat)? = nil) -> TextBlock {
        TextBlock(rect: CGRect(x: x.lowerBound, y: y.lowerBound, width: x.upperBound - x.lowerBound, height: y.upperBound - y.lowerBound), lineEnd: lineEnd)
    }

    private func assertRegion(
        _ region: PDFColumnDetector.Region?,
        _ kind: PDFReadingRegion.Kind,
        x: ClosedRange<CGFloat>,
        y: ClosedRange<CGFloat>,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let region else { return XCTFail("\(label): missing", file: file, line: line) }
        XCTAssertEqual(region.kind, kind, label, file: file, line: line)
        XCTAssertEqual(region.rect.minX, x.lowerBound, accuracy: 4, "\(label) \(region.rect)", file: file, line: line)
        XCTAssertEqual(region.rect.maxX, x.upperBound, accuracy: 4, "\(label) \(region.rect)", file: file, line: line)
        XCTAssertEqual(region.rect.minY, y.lowerBound, accuracy: 12, "\(label) \(region.rect)", file: file, line: line)
        XCTAssertEqual(region.rect.maxY, y.upperBound, accuracy: 12, "\(label) \(region.rect)", file: file, line: line)
    }

    func testTwoColumns() {
        let regions = PDFColumnDetector.regions(in: map(text: [text(0...285, 0...800), text(315...600, 0...800)]))
        XCTAssertEqual(regions.count, 2, "\(regions)")
        assertRegion(regions.first, .column, x: 0...285, y: 0...800, "left")
        assertRegion(regions.last, .column, x: 315...600, y: 0...800, "right")
    }

    /// A paper's first page: title and abstract across the top, then columns.
    func testTitleAndAbstractAboveTwoColumns() {
        let regions = PDFColumnDetector.regions(in: map(text: [
            text(0...600, 0...160),
            text(0...285, 200...800),
            text(315...600, 200...800),
        ]))
        XCTAssertEqual(regions.map(\.kind), [.spanning, .column, .column], "\(regions)")
        guard regions.count == 3 else { return }
        assertRegion(regions[0], .spanning, x: 0...600, y: 0...160, "abstract")
        assertRegion(regions[1], .column, x: 0...285, y: 200...800, "left")
        assertRegion(regions[2], .column, x: 315...600, y: 200...800, "right")
    }

    /// A full-width figure mid-page: the columns above it are read first, then
    /// the figure, then the columns below.
    func testFullWidthFigureBetweenColumnBands() {
        let regions = PDFColumnDetector.regions(in: map(
            text: [text(0...285, 0...330), text(315...600, 0...330), text(0...285, 470...800), text(315...600, 470...800)],
            solid: [CGRect(x: 40, y: 360, width: 520, height: 80)]
        ))
        XCTAssertEqual(regions.map(\.kind), [.column, .column, .spanning, .column, .column], "\(regions)")
        guard regions.count == 5 else { return }
        assertRegion(regions[0], .column, x: 0...285, y: 0...330, "L1")
        assertRegion(regions[1], .column, x: 315...600, y: 0...330, "R1")
        assertRegion(regions[2], .spanning, x: 40...560, y: 360...440, "figure")
        assertRegion(regions[3], .column, x: 0...285, y: 470...800, "L2")
        assertRegion(regions[4], .column, x: 315...600, y: 470...800, "R2")
    }

    func testThreeColumns() {
        let regions = PDFColumnDetector.regions(in: map(text: [text(0...180, 0...800), text(210...390, 0...800), text(420...600, 0...800)]))
        XCTAssertEqual(regions.count, 3, "\(regions)")
        XCTAssertEqual(regions.map(\.rect.minX).sorted(), regions.map(\.rect.minX), "left to right")
    }

    /// The left column's lines end raggedly short of the gutter.
    func testRaggedRightColumn() {
        let ragged = text(0...285, 0...800) { line in 200 + CGFloat((line * 7) % 10) * 9.5 }
        let regions = PDFColumnDetector.regions(in: map(text: [ragged, text(315...600, 0...800)]))
        XCTAssertEqual(regions.count, 2, "\(regions)")
        XCTAssertLessThanOrEqual(regions.first?.rect.maxX ?? .infinity, 290)
    }

    /// Scan specks in the gutter do not close it.
    func testSpecksInTheGutter() {
        let specks = stride(from: 37, to: 800, by: 97).map { CGPoint(x: 299, y: $0) }
        let regions = PDFColumnDetector.regions(in: map(text: [text(0...285, 0...800), text(315...600, 0...800)], specks: specks))
        XCTAssertEqual(regions.count, 2, "\(regions)")
    }

    func testSingleColumnIsNotSplit() {
        XCTAssertTrue(PDFColumnDetector.regions(in: map(text: [text(0...600, 0...800)])).isEmpty)
    }

    /// A two-column table over less than 40% of the content.
    func testShortTwoColumnBlockIsNotSplit() {
        let regions = PDFColumnDetector.regions(in: map(text: [
            text(0...285, 0...250),
            text(315...600, 0...250),
            text(0...600, 280...800),
        ]))
        XCTAssertTrue(regions.isEmpty, "\(regions)")
    }

    /// A label column beside a body: too unequal to be text columns.
    func testUnequalColumnsAreNotSplit() {
        let regions = PDFColumnDetector.regions(in: map(text: [text(0...120, 0...800), text(160...600, 0...800)]))
        XCTAssertTrue(regions.isEmpty, "\(regions)")
    }

    // MARK: - Vertical text

    /// The ink map turned a quarter: (x, y) of the turned map is
    /// (width - 1 - y, x) of the page's.
    func testTurnedMapReadsVerticalLinesAsRows() {
        let page = map(vertical: [vertical(560...600, 100...300)])
        let turned = page.turnedForVerticalText()
        XCTAssertEqual(turned.width, height)
        XCTAssertEqual(turned.height, width)
        for (x, y) in [(150, 0), (150, 6), (150, 7), (10, 3), (299, 40)] {
            XCTAssertEqual(turned.isInked(x: x, y: y), page.isInked(x: width - 1 - y, y: x), "(\(x), \(y))")
        }
    }

    /// Two tiers (段) of vertical text: the top one, then the bottom one.
    func testTwoTiersOfVerticalText() {
        let regions = PDFColumnDetector.regions(
            in: map(vertical: [vertical(0...600, 0...380), vertical(0...600, 420...800)]),
            readingDirection: .TtB_RtL
        )
        XCTAssertEqual(regions.map(\.kind), [.column, .column], "\(regions)")
        guard regions.count == 2 else { return }
        assertTier(regions[0], .column, x: 0...600, y: 0...380, "top tier")
        assertTier(regions[1], .column, x: 0...600, y: 420...800, "bottom tier")
    }

    /// A title the height of the page at the right is read first, then the
    /// tiers beside it.
    func testFullHeightTitleBesideTiers() {
        let regions = PDFColumnDetector.regions(
            in: map(vertical: [vertical(560...600, 0...800), vertical(0...520, 0...380), vertical(0...520, 420...800)]),
            readingDirection: .TtB_RtL
        )
        XCTAssertEqual(regions.map(\.kind), [.spanning, .column, .column], "\(regions)")
        guard regions.count == 3 else { return }
        assertTier(regions[0], .spanning, x: 560...600, y: 0...800, "title")
        assertTier(regions[1], .column, x: 0...520, y: 0...380, "top tier")
        assertTier(regions[2], .column, x: 0...520, y: 420...800, "bottom tier")
    }

    func testThreeTiersTopToBottom() {
        let regions = PDFColumnDetector.regions(
            in: map(vertical: [vertical(0...600, 0...250), vertical(0...600, 275...525), vertical(0...600, 550...800)]),
            readingDirection: .TtB_RtL
        )
        XCTAssertEqual(regions.count, 3, "\(regions)")
        XCTAssertEqual(regions.map(\.rect.minY).sorted(), regions.map(\.rect.minY), "top to bottom")
    }

    func testSingleTierIsNotSplit() {
        XCTAssertTrue(PDFColumnDetector.regions(in: map(vertical: [vertical(0...600, 0...800)]), readingDirection: .TtB_RtL).isEmpty)
    }

    /// Vertical lines end at a character pitch, not a pixel: the line ends of
    /// a tier are found within one pitch, its sides within a few pixels.
    private func assertTier(
        _ region: PDFColumnDetector.Region,
        _ kind: PDFReadingRegion.Kind,
        x: ClosedRange<CGFloat>,
        y: ClosedRange<CGFloat>,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(region.kind, kind, label, file: file, line: line)
        XCTAssertEqual(region.rect.minX, x.lowerBound, accuracy: 12, "\(label) \(region.rect)", file: file, line: line)
        XCTAssertEqual(region.rect.maxX, x.upperBound, accuracy: 12, "\(label) \(region.rect)", file: file, line: line)
        XCTAssertEqual(region.rect.minY, y.lowerBound, accuracy: 4, "\(label) \(region.rect)", file: file, line: line)
        XCTAssertEqual(region.rect.maxY, y.upperBound, accuracy: 4, "\(label) \(region.rect)", file: file, line: line)
    }

    /// Word spaces lining up over a few lines (a river) are not a gutter.
    func testShortRiverIsNotAGutter() {
        let regions = PDFColumnDetector.regions(in: map(
            text: [text(0...600, 0...800)],
            solid: []
        ).withBlank(x: 296..<304, y: 300..<333))
        XCTAssertTrue(regions.isEmpty, "\(regions)")
    }
}

private extension PDFInkMap {
    /// This map with `x` × `y` cleared.
    func withBlank(x: Range<Int>, y: Range<Int>) -> PDFInkMap {
        PDFInkMap(width: width, height: height) { column, row in
            x.contains(column) && y.contains(row) ? false : isInked(x: column, y: row)
        }
    }
}
