import XCTest
import UIKit
import PDFKit
@testable import YetAnotherEBookReader

/// Characterization tests for YabrPDF single-page margin cropping and viewport fitting.
///
/// Pages are synthetic: a white page with one solid black "text block" at a known
/// PDF-space rect (bottom-left origin), so the expected crop and viewport are exact.
@MainActor
final class YabrPDFMarginCropTests: XCTestCase {
    private static let pageSize = CGSize(width: 612, height: 792)
    /// Portrait phone: a width-fitted page is shorter than the view, so PDFKit
    /// centers it vertically and only horizontal placement is under our control.
    private static let portrait = CGSize(width: 390, height: 844)
    /// Landscape phone: a width-fitted page is taller than the view, so both the
    /// horizontal placement and the top margin are under our control.
    private static let landscape = CGSize(width: 844, height: 390)

    /// Detection works on a thumbnail, so allow a few PDF points of slack.
    private let detectTolerance: CGFloat = 3
    /// Viewport assertions are in view points.
    private let viewTolerance: CGFloat = 2


    private static let knownShortFirstLine = "Pages that open on a short paragraph tail: that line's row density is below the detect threshold, so the detected top skips to the next line and the text sits one line higher than on other pages."
    private static let knownScanLimit = "blankBorderWidth only scans the outer quarter of each axis (lineNumMax / 4); a margin wider than 25% of the page is not found and the page falls back to uncropped."

    private var tempURLs: [URL] = []
    private var window: UIWindow?

    override func tearDownWithError() throws {
        tearDownWindow()
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        tempURLs.removeAll()
        PDFPageWithBackground.fillColor = nil
    }

    // MARK: - Detection (PDFMarginCropController.visibleBounds)

    func testDetectsCenteredContent() throws {
        try assertDetection(content: CGRect(x: 81, y: 96, width: 450, height: 600))
    }

    func testDetectsContentLeaningLeft() throws {
        try assertDetection(content: CGRect(x: 60, y: 90, width: 420, height: 610))
    }

    func testDetectsContentLeaningRight() throws {
        try assertDetection(content: CGRect(x: 140, y: 150, width: 400, height: 500))
    }

    func testDetectsContentInsideNonZeroCropBox() throws {
        try assertDetection(
            content: CGRect(x: 120, y: 140, width: 360, height: 520),
            cropBox: CGRect(x: 40, y: 60, width: 500, height: 700)
        )
    }

    func testDetectsVerticalTextContent() throws {
        try assertDetection(
            content: CGRect(x: 100, y: 80, width: 420, height: 620),
            readingDirection: .TtB_RtL
        )
    }

    /// Side margins just over 25% of the page width (short lines, verse, centered figures).
    func testDetectsNarrowContentWithWideSideMargins() throws {
        XCTExpectFailure(Self.knownScanLimit)
        try assertDetection(content: CGRect(x: 156, y: 96, width: 300, height: 600))
    }

    /// Chapter-opening page: text starts well below the usual top margin.
    func testDetectsChapterOpeningWithTallTopMargin() throws {
        XCTExpectFailure(Self.knownScanLimit)
        try assertDetection(content: CGRect(x: 81, y: 96, width: 450, height: 350))
    }

    func testThemesDoNotAffectDetection() throws {
        for theme in PDFThemeMode.allCases {
            try assertDetection(content: CGRect(x: 81, y: 96, width: 450, height: 600), themeMode: theme)
            tearDownWindow()
        }
    }

    // MARK: - Horizontal fit (Width auto scaler)

    func testPortraitFitWidthCentersCenteredContent() throws {
        let harness = try makeHarness(
            pages: [PageSpec(content: CGRect(x: 81, y: 96, width: 450, height: 600))],
            viewSize: Self.portrait
        )
        assertHorizontalWidthFit(harness, pageIndex: 0)
    }

    func testPortraitFitWidthCentersContentLeaningLeft() throws {
        let harness = try makeHarness(
            pages: [PageSpec(content: CGRect(x: 60, y: 90, width: 420, height: 610))],
            viewSize: Self.portrait
        )
        assertHorizontalWidthFit(harness, pageIndex: 0)
    }

    func testPortraitFitWidthCentersContentInsideNonZeroCropBox() throws {
        let harness = try makeHarness(
            pages: [PageSpec(
                content: CGRect(x: 120, y: 140, width: 360, height: 520),
                cropBox: CGRect(x: 40, y: 60, width: 500, height: 700)
            )],
            viewSize: Self.portrait
        )
        assertHorizontalWidthFit(harness, pageIndex: 0)
    }

    func testLandscapeFitWidthCentersContent() throws {
        let harness = try makeHarness(
            pages: [PageSpec(content: CGRect(x: 81, y: 96, width: 450, height: 600))],
            viewSize: Self.landscape
        )
        assertHorizontalWidthFit(harness, pageIndex: 0)
    }

    // MARK: - Top alignment

    func testLandscapeFitWidthAlignsContentTopMargin() throws {
        let harness = try makeHarness(
            pages: [PageSpec(content: CGRect(x: 81, y: 96, width: 450, height: 600))],
            viewSize: Self.landscape
        )
        assertTopMargin(harness, pageIndex: 0)
    }

    func testLandscapeFitWidthAlignsTopMarginInsideNonZeroCropBox() throws {
        let harness = try makeHarness(
            pages: [PageSpec(
                content: CGRect(x: 120, y: 140, width: 360, height: 520),
                cropBox: CGRect(x: 40, y: 60, width: 500, height: 700)
            )],
            viewSize: Self.landscape
        )
        assertTopMargin(harness, pageIndex: 0)
    }

    /// A width-fitted portrait page is shorter than the view; PDFKit would center
    /// it, but the text should still start at the top margin.
    func testPortraitFitWidthTopAlignsPageShorterThanView() throws {
        let harness = try makeHarness(
            pages: [PageSpec(content: CGRect(x: 81, y: 96, width: 450, height: 600))],
            viewSize: Self.portrait,
            inNavigationController: true
        )
        let pageInView = harness.pdfView.convert(harness.page(0).bounds(for: .cropBox), from: harness.page(0))

        XCTAssertLessThan(pageInView.height, harness.pdfView.bounds.height)
        assertTopMargin(harness, pageIndex: 0)
        assertHorizontalWidthFit(harness, pageIndex: 0)
    }

    // MARK: - Page turns

    func testLandscapePageTurnsKeepFitIndependentOfPreviousViewport() throws {
        // Book-like alternating margins: odd pages lean left, even pages lean right.
        let left = CGRect(x: 60, y: 90, width: 420, height: 610)
        let right = CGRect(x: 132, y: 90, width: 420, height: 610)
        let harness = try makeHarness(
            pages: [left, right, left, right, left].map { PageSpec(content: $0) },
            viewSize: Self.landscape
        )

        for pageIndex in 1..<5 {
            // Simulate the reader having scrolled down within the previous page.
            if let current = harness.pdfView.currentPage {
                let visible = harness.pdfView.convert(harness.pdfView.bounds, to: current)
                harness.pdfView.go(to: PDFDestination(page: current, at: CGPoint(x: visible.minX, y: visible.maxY - 150)))
                settle()
            }
            harness.pdfView.go(to: harness.page(pageIndex))
            settle()

            assertHorizontalWidthFit(harness, pageIndex: pageIndex, label: "page \(pageIndex + 1)")
            assertTopMargin(harness, pageIndex: pageIndex, label: "page \(pageIndex + 1)")
        }
    }

    func testRevisitingPageRestoresSavedViewport() throws {
        let content = CGRect(x: 81, y: 96, width: 450, height: 600)
        let harness = try makeHarness(
            pages: [PageSpec(content: content), PageSpec(content: content)],
            viewSize: Self.landscape
        )
        let firstVisit = visibleRect(harness, pageIndex: 0)

        harness.pdfView.go(to: harness.page(1))
        settle()
        harness.pdfView.go(to: harness.page(0))
        settle()

        let secondVisit = visibleRect(harness, pageIndex: 0)
        let message = "first=\(firstVisit) second=\(secondVisit)"
        XCTAssertEqual(secondVisit.minX, firstVisit.minX, accuracy: 1, "restored x drifted \(message)")
        XCTAssertEqual(secondVisit.maxY, firstVisit.maxY, accuracy: 1, "restored top drifted \(message)")
        XCTAssertEqual(secondVisit.width, firstVisit.width, accuracy: 1, "restored scale drifted \(message)")
    }

    // MARK: - Page turn top consistency (reported: top margin varies after page turns)

    /// Turning to an unvisited page (fit path) should give the same top margin no
    /// matter where the reader had scrolled on the previous page.
    func testNextPageTopIsIndependentOfPreviousPageScroll() throws {
        let content = CGRect(x: 81, y: 96, width: 450, height: 600)
        var topGaps: [String: CGFloat] = [:]

        for scrolled in [0.0, 0.5, 1.0] {
            let harness = try makeHarness(
                pages: [PageSpec(content: content), PageSpec(content: content)],
                viewSize: Self.landscape
            )
            scrollCurrentPage(harness, toFraction: scrolled)
            pressNext(harness)

            topGaps["prev scrolled \(scrolled)"] = topGap(harness, pageIndex: 1)
            tearDownWindow()
        }
        record("PDFTURN fit-path topGaps=\(topGaps.sorted { $0.key < $1.key })")

        let values = Array(topGaps.values)
        XCTAssertLessThanOrEqual((values.max() ?? 0) - (values.min() ?? 0), viewTolerance, "topGaps=\(topGaps)")
    }

    /// Paging forward then back (restore path) should show the page exactly as the
    /// reader left it, i.e. with the same top margin as the first visit.
    func testPageTopIsStableAcrossForwardAndBackTurns() throws {
        let content = CGRect(x: 81, y: 96, width: 450, height: 600)
        let harness = try makeHarness(
            pages: Array(repeating: PageSpec(content: content), count: 4),
            viewSize: Self.landscape
        )

        var sequence: [(page: Int, topGap: CGFloat)] = []
        func sample() {
            let index = harness.pdfView.currentPage.flatMap { harness.pdfView.document?.index(for: $0) } ?? -1
            sequence.append((index + 1, topGap(harness, pageIndex: index)))
        }

        sample()
        for press in [pressNext, pressNext, pressPrev, pressPrev, pressNext, pressNext, pressNext, pressPrev] {
            press(harness)
            sample()
        }
        record("PDFTURN forward/back sequence=\(sequence.map { "p\($0.page):\(String(format: "%.1f", $0.topGap))" })")

        let gaps = sequence.map(\.topGap)
        XCTAssertLessThanOrEqual((gaps.max() ?? 0) - (gaps.min() ?? 0), viewTolerance, "sequence=\(sequence)")
    }

    /// Pressing "next" repeatedly (no scrolling) through pages whose text blocks share
    /// the same top but differ in width, as real books do (short lines, figures,
    /// chapter openings). Each page gets its own width-fit scale.
    func testLandscapeForwardPagingTopWithVaryingContentWidth() throws {
        let sequence = try forwardPagingTopGaps(viewSize: Self.landscape)
        let gaps = sequence.map(\.topGap)
        XCTAssertLessThanOrEqual((gaps.max() ?? 0) - (gaps.min() ?? 0), viewTolerance, "sequence=\(sequence)")
    }

    func testPortraitForwardPagingTopWithVaryingContentWidth() throws {
        let sequence = try forwardPagingTopGaps(viewSize: Self.portrait)
        let gaps = sequence.map(\.topGap)
        XCTAssertLessThanOrEqual((gaps.max() ?? 0) - (gaps.min() ?? 0), viewTolerance, "sequence=\(sequence)")
    }

    private func forwardPagingTopGaps(viewSize: CGSize) throws -> [(page: Int, width: CGFloat, scale: CGFloat, topGap: CGFloat)] {
        let widths: [CGFloat] = [450, 450, 300, 450, 380, 450, 260, 300, 450]
        let pages = widths.map { width in
            PageSpec(content: CGRect(x: (Self.pageSize.width - width) / 2, y: 96, width: width, height: 600))
        }
        let harness = try makeHarness(pages: pages, viewSize: viewSize)

        var sequence: [(page: Int, width: CGFloat, scale: CGFloat, topGap: CGFloat)] = []
        for index in pages.indices {
            if index > 0 {
                pressNext(harness)
            }
            let current = harness.pdfView.currentPage.flatMap { harness.pdfView.document?.index(for: $0) } ?? -1
            XCTAssertEqual(current, index)
            sequence.append((index + 1, widths[index], harness.pdfView.scaleFactor, topGap(harness, pageIndex: index)))
        }
        record("PDFFWD view=\(viewSize) " + sequence.map {
            String(format: "p%d(w%.0f s%.2f):%.1f", $0.page, $0.width, $0.scale, $0.topGap)
        }.joined(separator: " "))
        return sequence
    }

    /// Reported case: ordinary book pages, pressing "next" repeatedly, reader hosted
    /// in a navigation controller with bars visible (as YabrEBookReader does).
    func testLandscapeForwardPagingRealisticBookPages() throws {
        try assertForwardPagingRealisticBookPages(
            viewSize: Self.landscape,
            knownIssue: Self.knownShortFirstLine
        )
    }

    func testPortraitForwardPagingRealisticBookPages() throws {
        try assertForwardPagingRealisticBookPages(
            viewSize: Self.portrait,
            knownIssue: Self.knownShortFirstLine
        )
    }

    private func assertForwardPagingRealisticBookPages(viewSize: CGSize, knownIssue: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let book = try BookPageGenerator.make(pageCount: 12, pageSize: Self.pageSize, in: directory)
        tempURLs.append(book.url)
        let pages = book.bodyRects.map { PageSpec(content: $0) }
        let harness = try makeHarness(pages: pages, viewSize: viewSize, pdfURL: book.url, inNavigationController: true)

        var rows: [String] = []
        var bodyTops: [CGFloat] = []
        for index in pages.indices {
            if index > 0 { pressNext(harness) }
            let options = harness.controller.pdfOptions
            let key = PageVisibleContentKey(
                pageNumber: index + 1,
                readingDirection: options.readingDirection,
                hMarginDetectStrength: options.hMarginDetectStrength,
                vMarginDetectStrength: options.vMarginDetectStrength
            )
            let detected = harness.controller.marginCropController.cachedValue(for: key)?.bounds ?? .null
            let bodyTop = topGap(harness, pageIndex: index)
            bodyTops.append(bodyTop)
            rows.append(String(
                format: "p%d%@ detTop=%.0f detH=%.0f s=%.2f bodyTopInView=%.1f",
                index + 1, book.opensOnShortLine[index] ? "*" : " ", detected.minY, detected.height, harness.pdfView.scaleFactor, bodyTop
            ))
        }
        record("PDFBOOK view=\(viewSize) safeTop=\(harness.pdfView.safeAreaInsets.top) (* = page opens on a short paragraph tail)\n" + rows.joined(separator: "\n"))

        XCTExpectFailure(knownIssue)
        XCTAssertLessThanOrEqual((bodyTops.max() ?? 0) - (bodyTops.min() ?? 0), viewTolerance, "bodyTops=\(bodyTops)", file: file, line: line)
    }

    // MARK: - Options

    func testDarkThemeFitMatchesDefaultThemeFit() throws {
        let content = CGRect(x: 81, y: 96, width: 450, height: 600)
        let light = try makeHarness(pages: [PageSpec(content: content)], viewSize: Self.landscape, themeMode: .none)
        let lightRect = visibleRect(light, pageIndex: 0)
        tearDownWindow()

        let dark = try makeHarness(pages: [PageSpec(content: content)], viewSize: Self.landscape, themeMode: .dark)
        let darkRect = visibleRect(dark, pageIndex: 0)

        let message = "light=\(lightRect) dark=\(darkRect)"
        XCTAssertEqual(darkRect.minX, lightRect.minX, accuracy: 1, message)
        XCTAssertEqual(darkRect.maxY, lightRect.maxY, accuracy: 1, message)
        XCTAssertEqual(darkRect.width, lightRect.width, accuracy: 1, message)
    }

    func testMarginOffsetShiftsViewportHorizontally() throws {
        let harness = try makeHarness(
            pages: [PageSpec(content: CGRect(x: 81, y: 96, width: 450, height: 600))],
            viewSize: Self.landscape
        )
        let before = contentInView(harness, pageIndex: 0)

        var options = harness.controller.pdfOptions
        options.marginOffset = 5
        harness.controller.handleOptionsChange(pdfOptions: options)
        settle()
        let after = contentInView(harness, pageIndex: 0)

        XCTAssertGreaterThan(abs(after.minX - before.minX), viewTolerance, "marginOffset had no visible effect before=\(before) after=\(after)")
    }

    // MARK: - PDFKit probes
    //
    // These document the PDFKit single-page behavior that handlePageChange and
    // getPagePoint rely on. Expected failures record PDFKit quirks; if one starts
    // passing after an OS update, revisit the viewport code.

    func testProbeCurrentDestinationIsVisibleBottomLeft() throws {
        let (pdfView, page) = try makeBarePDFView(viewSize: Self.portrait)
        pdfView.scaleFactor = 2.0
        settle()
        pdfView.go(to: PDFDestination(page: page, at: CGPoint(x: 100, y: 650)))
        settle()

        let visible = pdfView.convert(pdfView.bounds, to: page)
        let current = try XCTUnwrap(pdfView.currentDestination?.point)
        record("PDFPROBE currentDestination=\(current) visible=\(visible)")

        XCTAssertEqual(current.x, visible.minX, accuracy: 1)
        XCTAssertEqual(current.y, visible.minY, accuracy: 1)
    }

    func testProbeCurrentDestinationWithNonZeroCropBox() throws {
        let (pdfView, page) = try makeBarePDFView(
            viewSize: Self.portrait,
            cropBox: CGRect(x: 40, y: 60, width: 500, height: 700)
        )
        pdfView.scaleFactor = 2.0
        settle()
        pdfView.go(to: PDFDestination(page: page, at: CGPoint(x: 100, y: 650)))
        settle()

        let visible = pdfView.convert(pdfView.bounds, to: page)
        let current = try XCTUnwrap(pdfView.currentDestination?.point)
        record("PDFPROBE cropBox currentDestination=\(current) visible=\(visible)")

        XCTAssertEqual(current.x, visible.minX, accuracy: 1)
        XCTAssertEqual(current.y, visible.minY, accuracy: 1)
    }

    func testProbeGoToPlacesPointAtVisibleTopLeft() throws {
        let (pdfView, page) = try makeBarePDFView(viewSize: Self.portrait)
        pdfView.scaleFactor = 2.0
        settle()

        let target = CGPoint(x: 100, y: 650)
        pdfView.go(to: PDFDestination(page: page, at: target))
        settle()

        let visible = pdfView.convert(pdfView.bounds, to: page)
        record("PDFPROBE go(to:) target=\(target) visible=\(visible) safeArea=\(pdfView.safeAreaInsets)")

        XCTAssertEqual(visible.minX, target.x, accuracy: 1, "go(to:) x is not the visible left edge")
        XCTExpectFailure("go(to:) aligns the point below the top safe-area inset, not the view's top edge.")
        XCTAssertEqual(visible.maxY, target.y, accuracy: 1, "go(to:) y is not the visible top edge")
    }

    func testProbeGoToIsIndependentOfPreviousPosition() throws {
        let (pdfView, page) = try makeBarePDFView(viewSize: Self.portrait)
        pdfView.scaleFactor = 2.0
        settle()

        let target = CGPoint(x: 100, y: 650)
        var results: [CGRect] = []
        for start in [CGPoint(x: 0, y: 792), CGPoint(x: 400, y: 250), CGPoint(x: 0, y: 250)] {
            pdfView.go(to: PDFDestination(page: page, at: start))
            settle()
            pdfView.go(to: PDFDestination(page: page, at: target))
            settle()
            results.append(pdfView.convert(pdfView.bounds, to: page))
        }
        record("PDFPROBE repeated go(to:) visible=\(results)")

        XCTExpectFailure("The same go(to:) lands at a different top depending on the prior scroll position.")
        for result in results.dropFirst() {
            XCTAssertEqual(result.minX, results[0].minX, accuracy: 1)
            XCTAssertEqual(result.maxY, results[0].maxY, accuracy: 1)
        }
    }

    /// Validates the planned fix: after one go(to:), correcting the internal scroll
    /// view's contentOffset by the measured page-space error lands exactly.
    func testProbeScrollViewOffsetCorrectionIsExact() throws {
        let (pdfView, page) = try makeBarePDFView(viewSize: Self.portrait)
        pdfView.scaleFactor = 2.0
        settle()
        let scrollView = try XCTUnwrap(firstScrollView(in: pdfView), "PDFView has no internal UIScrollView")

        let target = CGPoint(x: 100, y: 650)
        for start in [CGPoint(x: 0, y: 792), CGPoint(x: 400, y: 250)] {
            pdfView.go(to: PDFDestination(page: page, at: start))
            settle()
            pdfView.go(to: PDFDestination(page: page, at: target))
            settle()

            let visible = pdfView.convert(pdfView.bounds, to: page)
            var offset = scrollView.contentOffset
            offset.x += (target.x - visible.minX) * pdfView.scaleFactor
            offset.y += (visible.maxY - target.y) * pdfView.scaleFactor
            scrollView.setContentOffset(offset, animated: false)
            settle()

            let corrected = pdfView.convert(pdfView.bounds, to: page)
            record("PDFPROBE correction start=\(start) before=\(visible) after=\(corrected)")
            XCTAssertEqual(corrected.minX, target.x, accuracy: 0.5)
            XCTAssertEqual(corrected.maxY, target.y, accuracy: 0.5)
        }
    }

    // MARK: - Assertions

    private func assertDetection(
        content: CGRect,
        cropBox: CGRect? = nil,
        themeMode: PDFThemeMode = .none,
        readingDirection: PDFReadDirection = .LtR_TtB,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let harness = try makeHarness(
            pages: [PageSpec(content: content, cropBox: cropBox)],
            viewSize: Self.portrait,
            themeMode: themeMode,
            readingDirection: readingDirection
        )
        let detected = detectedBounds(harness, pageIndex: 0)

        // `visibleBounds` currently returns a rect relative to the crop box with a
        // top-down y axis; convert the expected PDF-space rect into that space.
        let crop = harness.page(0).bounds(for: .cropBox)
        let expected = CGRect(
            x: content.minX - crop.minX,
            y: crop.maxY - content.maxY,
            width: content.width,
            height: content.height
        )
        let message = "theme=\(themeMode) detected=\(detected) expected=\(expected)"
        record("PDFDETECT \(message)")
        XCTAssertEqual(detected.minX, expected.minX, accuracy: detectTolerance, "minX \(message)", file: file, line: line)
        XCTAssertEqual(detected.minY, expected.minY, accuracy: detectTolerance, "minY \(message)", file: file, line: line)
        XCTAssertEqual(detected.width, expected.width, accuracy: detectTolerance, "width \(message)", file: file, line: line)
        XCTAssertEqual(detected.height, expected.height, accuracy: detectTolerance, "height \(message)", file: file, line: line)
    }

    /// Width scaler with the default 5% h margin: the content block should span
    /// 90% of the readable width and be horizontally centered in it.
    private func assertHorizontalWidthFit(_ harness: Harness, pageIndex: Int, label: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let options = harness.controller.pdfOptions
        let bounds = readableRect(harness)
        let inView = contentInView(harness, pageIndex: pageIndex)
        let leftGap = inView.minX - bounds.minX
        let rightGap = bounds.maxX - inView.maxX
        let expectedWidth = bounds.width * (1 - 2 * options.hMarginAutoScaler / 100)
        let message = "\(label) view=\(bounds.size) contentInView=\(inView) leftGap=\(leftGap) rightGap=\(rightGap)"
        record("PDFFIT \(message)")

        XCTAssertEqual(inView.width, expectedWidth, accuracy: viewTolerance, "width \(message)", file: file, line: line)
        XCTAssertEqual(leftGap, rightGap, accuracy: viewTolerance, "not centered \(message)", file: file, line: line)
    }

    /// The content block should start `vMarginAutoScaler`% of the readable height
    /// below the top bar (the top safe-area inset).
    private func assertTopMargin(_ harness: Harness, pageIndex: Int, label: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let options = harness.controller.pdfOptions
        let bounds = readableRect(harness)
        let inView = contentInView(harness, pageIndex: pageIndex)
        let topGap = inView.minY - bounds.minY
        let expectedTopGap = bounds.height * options.vMarginAutoScaler / 100
        let message = "\(label) view=\(bounds.size) contentInView=\(inView) topGap=\(topGap) expected=\(expectedTopGap)"
        record("PDFTOP \(message)")

        XCTAssertEqual(topGap, expectedTopGap, accuracy: viewTolerance, "top margin \(message)", file: file, line: line)
    }

    private func record(_ message: String) {
        print(message)
        add(XCTAttachment(string: message))
    }

    // MARK: - Measurement

    private func detectedBounds(_ harness: Harness, pageIndex: Int) -> CGRect {
        let options = harness.controller.pdfOptions
        let key = PageVisibleContentKey(
            pageNumber: pageIndex + 1,
            readingDirection: options.readingDirection,
            hMarginDetectStrength: options.hMarginDetectStrength,
            vMarginDetectStrength: options.vMarginDetectStrength
        )
        harness.controller.marginCropController.clearCache()
        return harness.controller.marginCropController.visibleBounds(
            for: harness.page(pageIndex),
            key: key
        )
    }

    private func readableRect(_ harness: Harness) -> CGRect {
        harness.pdfView.bounds.inset(by: harness.pdfView.safeAreaInsets)
    }

    private func contentInView(_ harness: Harness, pageIndex: Int) -> CGRect {
        harness.pdfView.convert(harness.pages[pageIndex].content, from: harness.page(pageIndex))
    }

    private func topGap(_ harness: Harness, pageIndex: Int) -> CGFloat {
        contentInView(harness, pageIndex: pageIndex).minY - harness.pdfView.bounds.minY
    }

    /// Mirrors the tap-zone / arrow-button page turn used by the reader.
    private func pressNext(_ harness: Harness) {
        harness.controller.pageNextButton.sendActions(for: .primaryActionTriggered)
        settle()
    }

    private func pressPrev(_ harness: Harness) {
        harness.controller.pagePrevButton.sendActions(for: .primaryActionTriggered)
        settle()
    }

    /// Simulates a user drag within the current page: 0 = top, 1 = bottom.
    private func scrollCurrentPage(_ harness: Harness, toFraction fraction: CGFloat) {
        guard let scrollView = firstScrollView(in: harness.pdfView) else {
            XCTFail("PDFView has no internal UIScrollView")
            return
        }
        let inset = scrollView.adjustedContentInset
        let minY = -inset.top
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: minY + (maxY - minY) * fraction), animated: false)
        settle()
    }

    private func visibleRect(_ harness: Harness, pageIndex: Int) -> CGRect {
        harness.pdfView.convert(harness.pdfView.bounds, to: harness.page(pageIndex))
    }

    // MARK: - Harness

    private struct PageSpec {
        var content: CGRect
        var cropBox: CGRect?
    }

    private struct Harness {
        let controller: AppearanceTrackingPDFViewController
        let pages: [PageSpec]

        var pdfView: YabrPDFView { controller.pdfView }

        func page(_ index: Int) -> PDFPage {
            controller.pdfView.document!.page(at: index)!
        }
    }

    private func makeHarness(
        pages: [PageSpec],
        viewSize: CGSize,
        themeMode: PDFThemeMode = .none,
        readingDirection: PDFReadDirection = .LtR_TtB,
        pdfURL: URL? = nil,
        inNavigationController: Bool = false
    ) throws -> Harness {
        let url = try pdfURL ?? makePDF(pages: pages)
        let controller = AppearanceTrackingPDFViewController()
        controller.loadViewIfNeeded()

        let document = try XCTUnwrap(PDFDocument(url: url))
        document.delegate = controller
        for (index, spec) in pages.enumerated() {
            if let cropBox = spec.cropBox {
                document.page(at: index)?.setBounds(cropBox, for: .cropBox)
            }
        }
        XCTAssertTrue(document.page(at: 0) is PDFPageWithBackground)

        controller.pdfView.document = document
        controller.pdfView.displayMode = .singlePage
        controller.pdfOptions = PDFPreferenceValue(
            themeMode: themeMode,
            selectedAutoScaler: .Width,
            pageMode: .Page,
            readingDirection: readingDirection
        )

        if inNavigationController {
            // Matches YabrEBookReader: nav bar and toolbar stay visible for PDF.
            let nav = UINavigationController(rootViewController: controller)
            nav.setToolbarHidden(false, animated: false)
            installWindow(root: nav, size: viewSize)
        } else {
            installWindow(root: controller, size: viewSize)
        }
        // viewDidAppear performs the initial fit via handlePageChange.
        let deadline = Date().addingTimeInterval(3)
        while !controller.didAppear && Date() < deadline {
            settle(0.05)
        }
        XCTAssertTrue(controller.didAppear, "controller never appeared")
        settle()

        return Harness(controller: controller, pages: pages)
    }

    private func makeBarePDFView(viewSize: CGSize, cropBox: CGRect? = nil) throws -> (PDFView, PDFPage) {
        let url = try makePDF(pages: [PageSpec(content: CGRect(x: 81, y: 96, width: 450, height: 600))])
        let document = try XCTUnwrap(PDFDocument(url: url))
        if let cropBox {
            document.page(at: 0)?.setBounds(cropBox, for: .cropBox)
        }
        let pdfView = PDFView(frame: CGRect(origin: .zero, size: viewSize))
        pdfView.autoScales = false
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.document = document
        let host = UIViewController()
        host.view.addSubview(pdfView)
        installWindow(root: host, size: viewSize)
        settle()
        return (pdfView, try XCTUnwrap(pdfView.document?.page(at: 0)))
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        for subview in view.subviews {
            if let scrollView = subview as? UIScrollView { return scrollView }
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    private func installWindow(root: UIViewController, size: CGSize) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = root
        window.isHidden = false
        root.view.frame = window.bounds
        root.view.layoutIfNeeded()
        self.window = window
    }

    private func tearDownWindow() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    private func settle(_ interval: TimeInterval = 0.15) {
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
        window?.layoutIfNeeded()
    }

    private func makePDF(pages: [PageSpec]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("crop.pdf")

        let pageRect = CGRect(origin: .zero, size: Self.pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        try renderer.writePDF(to: url) { context in
            for spec in pages {
                context.beginPage()
                UIColor.white.setFill()
                context.fill(pageRect)
                // PDF space is bottom-left; the renderer context is top-left.
                let flipped = CGRect(
                    x: spec.content.minX,
                    y: pageRect.height - spec.content.maxY,
                    width: spec.content.width,
                    height: spec.content.height
                )
                UIColor.black.setFill()
                context.fill(flipped)
            }
        }
        tempURLs.append(url)
        return url
    }
}

/// Deterministic book-like pages: running head, 11pt ragged-right body text with
/// paragraphs flowing across pages, so some pages open on a short paragraph tail.
private enum BookPageGenerator {
    static let bodyRect = CGRect(x: 81, y: 96, width: 450, height: 38 * 16)   // top-left coordinates
    static let lineHeight: CGFloat = 16

    struct Generated {
        let url: URL
        /// Body text column per page, PDF space (bottom-left origin).
        let bodyRects: [CGRect]
        /// Whether each page opens on a short paragraph tail.
        let opensOnShortLine: [Bool]
    }

    static func make(pageCount: Int, pageSize: CGSize, in directory: URL) throws -> Generated {
        let url = directory.appendingPathComponent("book.pdf")
        let pageRect = CGRect(origin: .zero, size: pageSize)
        let bodyFont = UIFont(name: "TimesNewRomanPSMT", size: 11) ?? .systemFont(ofSize: 11)
        let headFont = UIFont(name: "TimesNewRomanPSMT", size: 9) ?? .systemFont(ofSize: 9)
        var rng = SplitMix64(seed: 42)
        var paragraphLinesLeft = 0
        var opensOnShortLine: [Bool] = []

        func word() -> String {
            let letters = Array("etaoinshrdlucmfwypvbgk")
            return String((0..<Int.random(in: 2...9, using: &rng)).map { _ in letters[Int.random(in: 0..<letters.count, using: &rng)] })
        }

        func line(maxWidth: CGFloat) -> String {
            var text = word()
            while true {
                let candidate = text + " " + word()
                if (candidate as NSString).size(withAttributes: [.font: bodyFont]).width > maxWidth { return text }
                text = candidate
            }
        }

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        try renderer.writePDF(to: url) { context in
            for index in 0..<pageCount {
                context.beginPage()
                UIColor.white.setFill()
                context.fill(pageRect)
                let pageNumber = index + 1
                let headAttributes: [NSAttributedString.Key: Any] = [.font: headFont, .foregroundColor: UIColor.black]
                let bodyAttributes: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: UIColor.black]

                // Running head: verso shows the short book title, recto the longer chapter title.
                let head = pageNumber.isMultiple(of: 2) ? "A LONG WAY HOME" : "CHAPTER THREE \u{00B7} THE RIVER AND THE ROAD AT NIGHT"
                let headWidth = (head as NSString).size(withAttributes: headAttributes).width
                (head as NSString).draw(at: CGPoint(x: pageRect.midX - headWidth / 2, y: 60), withAttributes: headAttributes)
                let folio = "\(pageNumber)" as NSString
                let folioX = pageNumber.isMultiple(of: 2) ? bodyRect.minX : bodyRect.maxX - folio.size(withAttributes: headAttributes).width
                folio.draw(at: CGPoint(x: folioX, y: 60), withAttributes: headAttributes)

                var opensShort = false
                for lineIndex in 0..<38 {
                    let y = bodyRect.minY + CGFloat(lineIndex) * lineHeight
                    if paragraphLinesLeft == 0 {
                        paragraphLinesLeft = Int.random(in: 3...9, using: &rng)
                    }
                    paragraphLinesLeft -= 1
                    let isLast = paragraphLinesLeft == 0
                    let isFirst = false
                    let width = isLast ? bodyRect.width * CGFloat.random(in: 0.08...0.7, using: &rng) : bodyRect.width
                    if lineIndex == 0 { opensShort = isLast }
                    let indent: CGFloat = isFirst ? 18 : 0
                    (line(maxWidth: width - indent) as NSString).draw(at: CGPoint(x: bodyRect.minX + indent, y: y), withAttributes: bodyAttributes)
                }
                opensOnShortLine.append(opensShort)
            }
        }

        let bodyInPDF = CGRect(x: bodyRect.minX, y: pageSize.height - bodyRect.maxY, width: bodyRect.width, height: bodyRect.height)
        return Generated(url: url, bodyRects: Array(repeating: bodyInPDF, count: pageCount), opensOnShortLine: opensOnShortLine)
    }

    struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
}

private final class AppearanceTrackingPDFViewController: YabrPDFViewController {
    private(set) var didAppear = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didAppear = true
    }
}
