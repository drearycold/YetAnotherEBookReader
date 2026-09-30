import XCTest
import UIKit
import PDFKit
@testable import YetAnotherEBookReader

/// Characterization tests for YabrPDF single-page margin cropping and viewport fitting.
///
/// Pages are synthetic: a white page with one solid black "text block" at a known
/// PDF-space rect (bottom-left origin), so the expected crop and viewport are exact.
@available(iOS 16.0, macCatalyst 16.0, *)
@MainActor
final class YabrPDFMarginCropTests: XCTestCase {
    private static let pageSize = CGSize(width: 612, height: 792)
    /// Portrait phone: a width-fitted page is shorter than the view, so PDFKit
    /// centers it vertically and only horizontal placement is under our control.
    private static let portrait = CGSize(width: 390, height: 844)
    /// Landscape phone: a width-fitted page is taller than the view, so both the
    /// horizontal placement and the top margin are under our control.
    private static let landscape = CGSize(width: 844, height: 390)
    private static let tabletLandscape = CGSize(width: 1000, height: 750)

    /// Detection works on a thumbnail, so allow a few PDF points of slack.
    private let detectTolerance: CGFloat = 3
    /// Viewport assertions are in view points.
    private let viewTolerance: CGFloat = 2

    private var tempURLs: [URL] = []
    private var window: UIWindow?

    override func tearDownWithError() throws {
        tearDownWindow()
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        tempURLs.removeAll()
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
        try assertDetection(content: CGRect(x: 156, y: 96, width: 300, height: 600))
    }

    /// Chapter-opening page: text starts well below the usual top margin.
    func testDetectsChapterOpeningWithTallTopMargin() throws {
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
        try assertForwardPagingRealisticBookPages(viewSize: Self.landscape)
    }

    func testPortraitForwardPagingRealisticBookPages() throws {
        try assertForwardPagingRealisticBookPages(viewSize: Self.portrait)
    }

    private func assertForwardPagingRealisticBookPages(viewSize: CGSize, file: StaticString = #filePath, line: UInt = #line) throws {
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
            // The crop starts at the body (short first lines included), not at the
            // running head 36pt above it.
            XCTAssertEqual(detected.minY, BookPageGenerator.bodyRect.minY, accuracy: 4, "p\(index + 1) detected=\(detected)", file: file, line: line)
            rows.append(String(
                format: "p%d%@ detTop=%.0f detH=%.0f s=%.2f bodyTopInView=%.1f",
                index + 1, book.opensOnShortLine[index] ? "*" : " ", detected.minY, detected.height, harness.pdfView.scaleFactor, bodyTop
            ))
        }
        record("PDFBOOK view=\(viewSize) safeTop=\(harness.pdfView.safeAreaInsets.top) (* = page opens on a short paragraph tail)\n" + rows.joined(separator: "\n"))

        XCTAssertLessThanOrEqual((bodyTops.max() ?? 0) - (bodyTops.min() ?? 0), viewTolerance, "bodyTops=\(bodyTops)", file: file, line: line)
    }

    // MARK: - Theme overlay and jump mask

    func testThemeOverlaySitsAboveDocumentAndBelowTapLabels() throws {
        let harness = try makeHarness(
            pages: [PageSpec(content: CGRect(x: 81, y: 96, width: 450, height: 600))],
            viewSize: Self.portrait,
            themeMode: .serpia
        )
        let surface = harness.surface
        let subviews = surface.subviews
        let pageIndex = try XCTUnwrap(subviews.firstIndex { $0 === harness.pdfView })
        let maskIndex = try XCTUnwrap(subviews.firstIndex { $0 === surface.jumpMaskView })
        let overlayIndex = try XCTUnwrap(subviews.firstIndex { $0 === surface.themeOverlayView })
        let labelIndex = try XCTUnwrap(subviews.firstIndex { $0 === surface.singleTapLeftLabel })

        XCTAssertLessThan(pageIndex, maskIndex)
        XCTAssertLessThan(maskIndex, overlayIndex)
        XCTAssertLessThan(overlayIndex, labelIndex)
        XCTAssertFalse(surface.themeOverlayView.isHidden)
        XCTAssertFalse(surface.themeOverlayView.isUserInteractionEnabled)
        XCTAssertEqual(surface.themeOverlayView.frame, surface.bounds)
        XCTAssertEqual(harness.pdfView.frame, surface.bounds)
    }

    func testThemeSwitchRetintsWithoutMovingViewport() throws {
        let harness = try makeHarness(
            pages: [PageSpec(content: CGRect(x: 81, y: 96, width: 450, height: 600))],
            viewSize: Self.landscape,
            themeMode: .serpia
        )
        let before = visibleRect(harness, pageIndex: 0)
        let sepiaOverlay = harness.surface.themeOverlayView.backgroundColor

        for (theme, overlayHidden, inverted) in [(PDFThemeMode.forest, false, false), (.dark, true, true), (.none, true, false)] {
            var options = harness.controller.pdfOptions
            options.themeMode = theme
            harness.controller.handleOptionsChange(pdfOptions: options)
            settle()

            XCTAssertEqual(harness.surface.themeOverlayView.isHidden, overlayHidden, "\(theme)")
            XCTAssertEqual(harness.controller.pageRenderTheme.drawsInverted, inverted, "\(theme)")
            if theme == .forest {
                XCTAssertNotEqual(harness.surface.themeOverlayView.backgroundColor, sepiaOverlay)
            }
            let after = visibleRect(harness, pageIndex: 0)
            XCTAssertEqual(after.minX, before.minX, accuracy: 0.5, "\(theme)")
            XCTAssertEqual(after.maxY, before.maxY, accuracy: 0.5, "\(theme)")
            XCTAssertEqual(after.width, before.width, accuracy: 0.5, "\(theme)")
        }
    }

    func testJumpShowsMaskButPageTurnDoesNot() throws {
        let content = CGRect(x: 81, y: 96, width: 450, height: 600)
        let harness = try makeHarness(
            pages: Array(repeating: PageSpec(content: content), count: 5),
            viewSize: Self.portrait
        )
        waitForJumpMaskToClear(harness)
        XCTAssertFalse(harness.surface.isJumpMaskVisible)

        pressNext(harness)
        XCTAssertFalse(harness.surface.isJumpMaskVisible, "next page must not show the jump mask in light themes")

        slide(harness, toPage: 5)
        XCTAssertEqual(harness.pdfView.currentPage.flatMap { harness.pdfView.document?.index(for: $0) }, 4)
        XCTAssertTrue(harness.surface.isJumpMaskVisible, "slider jump should show the jump mask")
        XCTAssertNil(harness.controller.pendingJumpMaskPage)

        settle(0.8)
        XCTAssertFalse(harness.surface.isJumpMaskVisible, "jump mask should fade out")
    }

    /// Toggling dark re-attaches the document to drop cached tiles; the reader must
    /// stay on the same page and never report another page as the reading position.
    func testDarkToggleKeepsPageAndPosition() throws {
        let harness = try makeJumpHarness()
        pressNext(harness)
        pressNext(harness)
        let before = visibleRect(harness, pageIndex: 2)
        let spy = PositionSpy()
        harness.controller.readerEngineDelegate = spy

        for theme in [PDFThemeMode.dark, .serpia] {
            var options = harness.controller.pdfOptions
            options.themeMode = theme
            harness.controller.handleOptionsChange(pdfOptions: options)
            settle()

            XCTAssertEqual(currentPageIndex(harness), 2, "\(theme)")
            let after = visibleRect(harness, pageIndex: 2)
            XCTAssertEqual(after.minX, before.minX, accuracy: 0.5, "\(theme)")
            XCTAssertEqual(after.maxY, before.maxY, accuracy: 0.5, "\(theme)")
            XCTAssertEqual(after.width, before.width, accuracy: 0.5, "\(theme)")
        }
        XCTAssertFalse(spy.pageNumbers.isEmpty)
        XCTAssertEqual(Set(spy.pageNumbers), [3], "reported pages=\(spy.pageNumbers)")
    }

    // MARK: - Jump mask entry points

    func testTOCJumpShowsMask() throws {
        let harness = try makeJumpHarness()
        let document = try XCTUnwrap(harness.pdfView.document)
        let root = PDFOutline()
        for (index, pageIndex) in [0, 3].enumerated() {
            let item = PDFOutline()
            item.label = "Chapter \(index + 1)"
            item.destination = PDFDestination(page: harness.page(pageIndex), at: CGPoint(x: 0, y: 792))
            root.insertChild(item, at: index)
        }
        document.outlineRoot = root
        harness.controller.buildTocList()
        let deadline = Date().addingTimeInterval(3)
        while (harness.controller.titleInfoButton.menu?.children.count ?? 0) < 2 && Date() < deadline {
            settle(0.05)
        }
        let chapter2 = try XCTUnwrap(harness.controller.titleInfoButton.menu?.children.last as? UIAction)

        try assertShowsJumpMask(harness, toPageIndex: 3) {
            chapter2.performWithSender(nil, target: nil)
        }
    }

    func testHistoryBackShowsMask() throws {
        let harness = try makeJumpHarness()
        harness.controller.updateHistoryMenu(curPage: harness.page(0))
        pressNext(harness)
        pressNext(harness)

        try assertShowsJumpMask(harness, toPageIndex: 0) {
            harness.controller.pageBackButton.sendActions(for: .primaryActionTriggered)
        }
    }

    func testListNavigationShowsMask() throws {
        let harness = try makeJumpHarness()
        let metaSource = YabrEBookReaderPDFMetaSource(
            book: TestFixtures.makeBook(),
            readerInfo: ReaderInfo(
                deviceName: "test-device",
                url: URL(fileURLWithPath: "/tmp/test.pdf"),
                missing: false,
                format: .PDF,
                readerType: .YabrPDF,
                position: BookDeviceReadingPosition(readerName: ReaderType.YabrPDF.id)
            ),
            preferenceRepository: StubPDFPreferenceRepository()
        )

        try assertShowsJumpMask(harness, toPageIndex: 3) {
            metaSource.yabrPDFNavigate(harness.pdfView, pageNumber: 4, offset: CGPoint(x: 0, y: 792))
        }
    }

    func testInitialRestoreShowsMask() throws {
        let harness = try makeJumpHarness(initialPage: 3)

        XCTAssertEqual(currentPageIndex(harness), 2)
        // Loading cover in viewWillAppear, then the restored page's mask.
        XCTAssertEqual(harness.surface.jumpMaskGeneration, 2)
        XCTAssertNil(harness.controller.pendingJumpMaskPage)
        XCTAssertFalse(harness.surface.isJumpMaskVisible)
    }

    func testLoadingCoverFadesAfterOpening() throws {
        let harness = try makeHarness(
            pages: [PageSpec(content: CGRect(x: 81, y: 96, width: 450, height: 600))],
            viewSize: Self.portrait,
            themeMode: .serpia
        )
        XCTAssertEqual(harness.surface.jumpMaskGeneration, 1, "cover only; opening on the first page is not a jump")
        waitForJumpMaskToClear(harness)
        XCTAssertFalse(harness.surface.isJumpMaskVisible)
    }

    /// Dark pages are drawn into PDFKit's tiles; a newly shown page is a white
    /// placeholder until they render, so dark page turns are covered too.
    func testDarkPageTurnShowsMask() throws {
        let harness = try makeJumpHarness(themeMode: .dark)
        // Without a buffered target page.
        harness.surface.discardBuffers()
        let before = harness.surface.jumpMaskGeneration

        pressNext(harness)

        // Frozen current page before PDFKit's transition, then the new page.
        XCTAssertEqual(harness.surface.jumpMaskGeneration, before + 2)
        XCTAssertTrue(harness.surface.isJumpMaskVisible)
        XCTAssertEqual(currentPageIndex(harness), 1)
    }

    /// A buffered dark page turn is covered by the buffer alone: a snapshot mask
    /// renders glyphs a little heavier than PDFKit, visible as it fades.
    func testBufferedDarkPageTurnShowsNoMask() throws {
        let harness = try makeJumpHarness(initialPage: 2, themeMode: .dark)
        try waitForRenderedBuffers(harness, pages: [3, 1])
        let before = harness.surface.jumpMaskGeneration

        let old = harness.pdfView
        harness.controller.pageNextButton.sendActions(for: .primaryActionTriggered)

        XCTAssertTrue(harness.surface.coveringView != nil || harness.pdfView !== old)
        XCTAssertEqual(harness.surface.jumpMaskGeneration, before, "no freeze, no page-change mask")
        XCTAssertEqual(currentPageIndex(harness), 2)
    }

    /// Guards the PDFKit layer structure the dark theme depends on: each page's
    /// placeholder (`PDFPageLayer` > `backgroundLayer`) must be found and inverted,
    /// or dark pages flash white before their tiles render.
    func testDarkInvertsPDFKitPagePlaceholders() throws {
        let harness = try makeJumpHarness(themeMode: .dark)
        pressNext(harness)
        settle(0.5)

        let pageViews = placeholderPageViews(harness.pdfView)
        XCTAssertFalse(pageViews.isEmpty, "PDFKit page layer structure changed: no placeholder layers found")
        XCTAssertGreaterThan(harness.pdfView.updateAllPagePlaceholders(), 0)
        for layer in pageViews.flatMap(YabrPDFView.pagePlaceholderLayers(in:)) {
            XCTAssertEqual(layer.backgroundColor?.components?.first ?? 1, 0, accuracy: 0.01, "placeholder background must be black")
            if let contents = layer.contents {
                XCTAssertTrue(layer.value(forKey: YabrPDFView.invertedPlaceholderKey) as AnyObject? === contents as AnyObject, "placeholder preview must be the inverted copy")
            }
        }
    }

    func testLightThemesLeavePDFKitPagePlaceholdersAlone() throws {
        let harness = try makeJumpHarness(themeMode: .serpia)
        pressNext(harness)
        settle(0.5)

        let layers = placeholderPageViews(harness.pdfView).flatMap(YabrPDFView.pagePlaceholderLayers(in:))
        XCTAssertFalse(layers.isEmpty)
        for layer in layers {
            XCTAssertNil(layer.value(forKey: YabrPDFView.invertedPlaceholderKey))
        }
    }

    private func placeholderPageViews(_ pdfView: YabrPDFView) -> [UIView] {
        func find(_ view: UIView) -> [UIView] {
            YabrPDFView.pagePlaceholderLayers(in: view).isEmpty ? view.subviews.flatMap(find) : [view]
        }
        return find(pdfView)
    }

    func testReturningToPageModeShowsMaskButScrollModeDoesNot() throws {
        let harness = try makeJumpHarness()
        pressNext(harness)
        pressNext(harness)
        let before = harness.surface.jumpMaskGeneration

        var options = harness.controller.pdfOptions
        options.pageMode = .Scroll
        harness.controller.handleOptionsChange(pdfOptions: options)
        settle()
        XCTAssertEqual(harness.surface.jumpMaskGeneration, before, "continuous mode shows no mask")
        XCTAssertNil(harness.controller.pendingJumpMaskPage)

        let scrollModePage = currentPageIndex(harness)
        options.pageMode = .Page
        harness.controller.handleOptionsChange(pdfOptions: options)
        settle()
        XCTAssertEqual(currentPageIndex(harness), scrollModePage)
        XCTAssertEqual(harness.surface.jumpMaskGeneration, before + 1)
        XCTAssertNil(harness.controller.pendingJumpMaskPage)
    }

    func testContinuousModeJumpShowsNoMask() throws {
        let harness = try makeJumpHarness()
        var options = harness.controller.pdfOptions
        options.pageMode = .Scroll
        harness.controller.handleOptionsChange(pdfOptions: options)
        settle()
        let before = harness.surface.jumpMaskGeneration

        slide(harness, toPage: 4)

        XCTAssertEqual(harness.surface.jumpMaskGeneration, before)
        XCTAssertNil(harness.controller.pendingJumpMaskPage)
    }

    func testJumpToCurrentPageIsNotMarked() throws {
        let harness = try makeJumpHarness()

        harness.controller.markJumpTarget(harness.pdfView.currentPage)

        XCTAssertNil(harness.controller.pendingJumpMaskPage)
    }

    func testStaleJumpTargetIsDroppedByOrdinaryTurn() throws {
        let harness = try makeJumpHarness()
        let before = harness.surface.jumpMaskGeneration

        harness.controller.markJumpTarget(harness.page(2))
        pressNext(harness)
        XCTAssertNil(harness.controller.pendingJumpMaskPage, "any page change consumes the pending jump")
        pressNext(harness)

        XCTAssertEqual(currentPageIndex(harness), 2)
        XCTAssertEqual(harness.surface.jumpMaskGeneration, before, "reaching the old target by next must not show the mask")
    }

    func testSecondQuickJumpKeepsMaskForItsOwnHold() throws {
        let harness = try makeJumpHarness()

        slide(harness, toPage: 3)
        settle(0.2)
        slide(harness, toPage: 5)
        settle(0.2)   // past the first jump's 400ms hold
        XCTAssertTrue(harness.surface.isJumpMaskVisible, "the first jump's timer must not hide the second mask")

        settle(0.6)
        XCTAssertFalse(harness.surface.isJumpMaskVisible)
    }

    // MARK: - Jump mask preview geometry

    func testJumpMaskPreviewWithNonZeroCropBox() throws {
        try assertJumpMaskPreview(
            spec: PageSpec(content: CGRect(x: 120, y: 140, width: 360, height: 520), cropBox: CGRect(x: 40, y: 60, width: 500, height: 700)),
            theme: .none, content: 0, margin: 255
        )
    }

    /// The snapshot must match what PDFView renders, independent of the crop fit:
    /// the page is laid out by PDFKit itself here.
    func testViewportSnapshotMatchesRenderedRotatedPages() throws {
        let content = CGRect(x: 81, y: 96, width: 450, height: 600)
        for rotation in [90, 180, 270] {
            let harness = try makeHarness(
                pages: [PageSpec(content: content, rotation: rotation)],
                viewSize: Self.portrait
            )
            // Plain PDFKit layout: drop the fit's padded page break margins first.
            harness.pdfView.restoreDefaultPageBreakMargins()
            harness.pdfView.autoScales = true
            settle(0.5)
            let page = harness.page(0)
            let snapshot = harness.pdfView.viewportSnapshot(of: page)
            let bounds = harness.pdfView.bounds
            let inView = contentInView(harness, pageIndex: 0)
            let pageInView = harness.pdfView.convert(page.bounds(for: .cropBox), from: page)
            let visibleContent = inView.intersection(bounds)
            let visiblePage = pageInView.intersection(bounds)
            let insideContent = CGPoint(x: visibleContent.midX, y: visibleContent.midY)
            // Inside the page but outside the text block, on whichever side has room.
            let pageMargin = visibleContent.minY - visiblePage.minY > 8
                ? CGPoint(x: visibleContent.midX, y: (visiblePage.minY + visibleContent.minY) / 2)
                : CGPoint(x: visibleContent.midX, y: (visibleContent.maxY + visiblePage.maxY) / 2)
            guard !visibleContent.isEmpty, !visiblePage.isEmpty else {
                XCTFail("rotation \(rotation): content not visible, inView=\(inView) page=\(pageInView)")
                tearDownWindow()
                continue
            }

            let snapshotContent = try gray(of: snapshot, at: insideContent)
            let snapshotMargin = try gray(of: snapshot, at: pageMargin)
            let renderedContent = try renderedColor(harness, pageIndex: 0, at: insideContent)
            let renderedMargin = try renderedColor(harness, pageIndex: 0, at: pageMargin)
            record("PDFMASK rotation=\(rotation) inView=\(inView) page=\(pageInView) snapshot=\(snapshotContent)/\(snapshotMargin) rendered=\(renderedContent)/\(renderedMargin)")

            XCTAssertEqual(snapshotContent, 0, accuracy: 6, "rotation \(rotation) content")
            XCTAssertEqual(snapshotMargin, 255, accuracy: 6, "rotation \(rotation) margin")
            XCTAssertEqual(renderedContent.0, 0, accuracy: 6, "rotation \(rotation) rendered content")
            XCTAssertEqual(renderedMargin.0, 255, accuracy: 6, "rotation \(rotation) rendered margin")
            tearDownWindow()
        }
    }

    /// Detection and the viewport fitter work in unrotated page space.
    func testRotatedPageFitShowsContent() throws {
        let harness = try makeHarness(
            pages: [PageSpec(content: CGRect(x: 81, y: 96, width: 450, height: 600), rotation: 90)],
            viewSize: Self.portrait
        )
        let inView = contentInView(harness, pageIndex: 0)
        record("PDFROTATE inView=\(inView) bounds=\(harness.pdfView.bounds)")

        XCTExpectFailure("Pre-existing: margin detection and PDFPageViewportFitter ignore page.rotation, so a rotated page is fitted as if unrotated and the text lands off screen.")
        XCTAssertTrue(harness.pdfView.bounds.insetBy(dx: -2, dy: -2).contains(inView), "inView=\(inView)")
    }

    func testOverlaysFollowViewResize() throws {
        let harness = try makeHarness(
            pages: [PageSpec(content: CGRect(x: 81, y: 96, width: 450, height: 600))],
            viewSize: Self.portrait,
            themeMode: .serpia
        )

        window?.frame = CGRect(origin: .zero, size: Self.landscape)
        harness.controller.view.frame = window?.bounds ?? .zero
        settle()

        XCTAssertEqual(harness.pdfView.bounds.size, Self.landscape)
        XCTAssertEqual(harness.surface.themeOverlayView.frame, harness.surface.bounds)
        XCTAssertEqual(harness.surface.jumpMaskView.frame, harness.surface.bounds)
    }

    // MARK: - Native edit menus

    func testSelectionContextMenuOffersReaderActionsOnlyForASelection() throws {
        let (harness, selection) = try makeTextHarness()

        XCTAssertNil(harness.pdfView.selectionContextMenu(), "no selection, no reader actions")

        harness.pdfView.setCurrentSelection(selection, animate: false)
        let menu = try XCTUnwrap(harness.pdfView.selectionContextMenu())
        XCTAssertTrue(menu.options.contains(.displayInline))
        XCTAssertEqual(menu.children.compactMap { ($0 as? UIAction)?.identifier }, [PDFMenuManager.ActionID.highlight, PDFMenuManager.ActionID.underline, PDFMenuManager.ActionID.note])

        harness.surface.highlightTapped = UUID()
        XCTAssertNil(harness.pdfView.selectionContextMenu(), "a highlight's own menu is showing")
    }

    func testHighlightAndUnderlineActionsAnnotateTheSelection() throws {
        let (harness, selection) = try makeTextHarness()

        for (identifier, subtype) in [(PDFMenuManager.ActionID.highlight, PDFAnnotationSubtype.highlight), (PDFMenuManager.ActionID.underline, .underline)] {
            harness.pdfView.setCurrentSelection(selection, animate: false)
            try perform(identifier, in: harness.controller.menuManager.selectionMenuElements())

            let annotations = harness.page(0).annotations.filter { $0.value(forAnnotationKey: .highlightId) != nil }
            XCTAssertTrue(annotations.contains { $0.type == subtype.rawValue.replacingOccurrences(of: "/", with: "") }, "\(identifier): \(annotations.map { $0.type ?? "" })")
        }
        XCTAssertEqual(harness.surface.highlights.count, 2)
    }

    func testTappingHighlightPresentsItsMenu() throws {
        let (harness, highlightId) = try makeHighlightHarness(style: .green)
        let (_, rect) = try XCTUnwrap(harness.surface.highlight(at: highlightCenter(harness, highlightId)))

        harness.surface.handleHighlightTap(at: CGPoint(x: rect.midX, y: rect.midY))
        settle()

        XCTAssertEqual(harness.surface.highlightTapped, highlightId)
        XCTAssertEqual(harness.controller.menuManager.highlightMenuRect, rect)
        let menu = try XCTUnwrap(editMenu(harness))
        let children = menu.children
        XCTAssertEqual(children.count, 5)
        XCTAssertEqual((children[0] as? UIAction)?.identifier, PDFMenuManager.ActionID.copyHighlight)
        XCTAssertEqual((children[1] as? UIAction)?.identifier, PDFMenuManager.ActionID.selectHighlight)
        XCTAssertEqual((children[2] as? UIAction)?.identifier, PDFMenuManager.ActionID.note)
        let style = try XCTUnwrap(children[3] as? UIMenu)
        XCTAssertEqual(style.title, "Style")
        XCTAssertEqual(style.children.count, BookHighlightStyle.allCases.count)
        let checked = style.children.compactMap { $0 as? UIAction }.filter { $0.state == .on }.map(\.identifier)
        XCTAssertEqual(checked, [PDFMenuManager.ActionID.style(.green)], "current style is ticked")
        let delete = try XCTUnwrap(children[4] as? UIAction)
        XCTAssertEqual(delete.identifier, PDFMenuManager.ActionID.deleteHighlight)
        XCTAssertTrue(delete.attributes.contains(.destructive))
    }

    /// A highlight spanning several lines anchors its menu on the line tapped.
    func testHighlightMenuPointsAtTappedLine() throws {
        let (harness, highlightId) = try makeHighlightHarness(style: .yellow)
        let pdfView = harness.pdfView
        let lineRects = (harness.surface.highlights[highlightId] ?? []).flatMap(\.annotations).compactMap { annotation -> CGRect? in
            annotation.page.map { pdfView.convert(annotation.bounds, from: $0) }
        }
        XCTAssertGreaterThan(lineRects.count, 1, "fixture highlight should span lines")

        for rect in lineRects {
            XCTAssertTrue(harness.surface.handleHighlightTap(at: CGPoint(x: rect.midX, y: rect.midY)))
            XCTAssertEqual(harness.controller.menuManager.highlightMenuRect, rect)
        }
    }

    func testTappingOutsideHighlightsPresentsNoMenu() throws {
        let (harness, _) = try makeHighlightHarness(style: .yellow)
        let pageInView = harness.pdfView.convert(harness.page(0).bounds(for: .cropBox), from: harness.page(0))

        harness.surface.handleHighlightTap(at: CGPoint(x: pageInView.midX, y: pageInView.maxY - 8))

        XCTAssertNil(harness.surface.highlightTapped)
    }

    func testHighlightMenuActions() throws {
        let (harness, highlightId) = try makeHighlightHarness(style: .yellow)
        let text = harness.surface.highlights[highlightId]?.compactMap { $0.selection.string }.joined(separator: " ")
        let elements = harness.controller.menuManager.highlightMenuElements(for: highlightId)

        try perform(PDFMenuManager.ActionID.copyHighlight, in: elements)
        XCTAssertEqual(UIPasteboard.general.string, text)

        try perform(PDFMenuManager.ActionID.selectHighlight, in: elements)
        XCTAssertEqual(harness.pdfView.currentSelection?.string, text)

        try perform(PDFMenuManager.ActionID.style(.underline), in: elements)
        XCTAssertEqual(harness.controller.annotationManager.style(of: highlightId), .underline)
        XCTAssertTrue(harness.surface.highlights[highlightId]?.flatMap(\.annotations).allSatisfy { $0.type == "Underline" } ?? false)

        try perform(PDFMenuManager.ActionID.deleteHighlight, in: elements)
        XCTAssertNil(harness.surface.highlights[highlightId])
        XCTAssertTrue(harness.page(0).annotations.filter { $0.value(forAnnotationKey: .highlightId) != nil }.isEmpty)
    }

    /// PDFKit shows its own markup menu (Remove / colour / Add Note, which bypass
    /// the app's storage) when a highlight annotation is tapped; its taps must wait
    /// for the app's highlight tap so the app's menu wins.
    func testPDFKitTapsWaitForHighlightMenuTap() throws {
        let (harness, _) = try makeHighlightHarness(style: .yellow)
        let pdfView = harness.pdfView
        let surface = harness.surface
        let highlightMenuTap = try XCTUnwrap(surface.highlightMenuTapGestureRecognizer)
        XCTAssertTrue(highlightMenuTap.view === surface)
        let pdfKitTap = UITapGestureRecognizer()
        let pageContent = try XCTUnwrap(pdfView.documentScrollView?.subviews.first)
        pageContent.addGestureRecognizer(pdfKitTap)
        defer { pageContent.removeGestureRecognizer(pdfKitTap) }

        XCTAssertTrue(surface.gestureRecognizer(highlightMenuTap, shouldBeRequiredToFailBy: pdfKitTap))
        XCTAssertFalse(surface.gestureRecognizer(highlightMenuTap, shouldBeRequiredToFailBy: try XCTUnwrap(surface.highlightTapGestureRecognizer)))
        // A double tap in a side zone turns the page instead of selecting a word.
        for pageTurnTap in [surface.doubleTapGestureRecognizer, surface.singleTapGestureRecognizer] {
            XCTAssertTrue(surface.gestureRecognizer(try XCTUnwrap(pageTurnTap), shouldBeRequiredToFailBy: pdfKitTap))
        }
        // PDFView declares but does not implement this delegate method: falling back
        // to super used to crash with an unrecognized selector.
        XCTAssertFalse(pdfView.gestureRecognizer(pdfKitTap, shouldBeRequiredToFailBy: highlightMenuTap))
    }

    // MARK: - Highlight notes

    func testSetNotePersistsThroughTheSameHighlight() throws {
        let (harness, highlightId) = try makeHighlightHarness(style: .yellow)
        let spy = HighlightSpy()
        harness.controller.annotationManager.delegate = spy
        let manager = harness.controller.annotationManager

        manager.setNote(uuid: highlightId, note: "  a thought \n")

        XCTAssertEqual(manager.note(of: highlightId), "a thought", "trimmed")
        XCTAssertEqual(spy.added.map(\.id), [highlightId.uuidString], "updates the highlight in place")
        XCTAssertEqual(spy.added.last?.note, "a thought")
        XCTAssertEqual(manager.style(of: highlightId), .yellow, "style kept")

        manager.setNote(uuid: highlightId, note: " \n ")
        XCTAssertNil(manager.note(of: highlightId), "blank clears the note")
        XCTAssertNil(spy.added.last?.note)
        XCTAssertEqual(spy.added.count, 2)
    }

    func testAddHighlightWithNotePersistsItAndSurvivesReapply() throws {
        let (harness, selection) = try makeTextHarness()
        let spy = HighlightSpy()
        let manager = harness.controller.annotationManager
        manager.delegate = spy

        let highlightId = try XCTUnwrap(manager.addHighlight(style: BookHighlightStyle.blue.rawValue, selection: selection, note: "why"))

        XCTAssertEqual(spy.added.last?.note, "why")
        XCTAssertEqual(manager.note(of: highlightId), "why")

        manager.applyHighlights(spy.added)
        XCTAssertEqual(manager.note(of: highlightId), "why")
        XCTAssertEqual(noteMarkers(harness).count, 1, "re-applying does not duplicate the marker")
    }

    func testNoteMarkerSitsInsideTheLastLineAndFollowsTheNote() throws {
        let (harness, highlightId) = try makeHighlightHarness(style: .green)
        let manager = harness.controller.annotationManager
        XCTAssertTrue(noteMarkers(harness).isEmpty, "no note, no marker")

        manager.setNote(uuid: highlightId, note: "marked")

        let marker = try XCTUnwrap(noteMarkers(harness).first)
        XCTAssertEqual(noteMarkers(harness).count, 1)
        let lines = try XCTUnwrap(harness.surface.highlights[highlightId]).flatMap(\.annotations).filter { !($0.isNoteMarker) }
        let lastLine = try XCTUnwrap(lines.last)
        XCTAssertTrue(lastLine.bounds.contains(marker.bounds), "marker \(marker.bounds) inside last line \(lastLine.bounds)")
        XCTAssertEqual(marker.bounds.maxX, lastLine.bounds.maxX, accuracy: 0.01, "top-right corner")
        XCTAssertEqual(marker.bounds.maxY, lastLine.bounds.maxY, accuracy: 0.01, "top-right corner")
        XCTAssertLessThanOrEqual(marker.bounds.width, PDFHighlightAnnotations.noteMarkerMaxSide + 0.01)
        XCTAssertEqual(marker.type, "Highlight", "rendered inside the page like the highlight")
        XCTAssertEqual(marker.color, lastLine.color)
        XCTAssertEqual(lines.first?.contents, "marked", "exported as the highlight's comment")

        // Tapping the marker is tapping the highlight.
        let markerInView = harness.pdfView.convert(marker.bounds, from: harness.page(0))
        XCTAssertEqual(harness.surface.highlight(at: CGPoint(x: markerInView.midX, y: markerInView.midY))?.0, highlightId)

        manager.setNote(uuid: highlightId, note: nil)
        XCTAssertTrue(noteMarkers(harness).isEmpty, "cleared note removes the marker")
        XCTAssertNil(harness.surface.highlights[highlightId]?.first?.annotations.first?.contents)

        manager.setNote(uuid: highlightId, note: "again")
        manager.removeHighlight(uuid: highlightId)
        XCTAssertTrue(noteMarkers(harness).isEmpty, "removed highlight removes the marker")
    }

    /// The fixture highlight sits on the page's first lines, so a marker that read
    /// as ink would raise the detected top edge.
    func testNoteMarkerDoesNotChangeMarginDetection() throws {
        let (harness, highlightId) = try makeHighlightHarness(style: .pink)
        let manager = harness.controller.annotationManager

        for theme in [PDFThemeMode.none, .dark] {
            setTheme(harness, theme)
            for style in BookHighlightStyle.allCases {
                manager.modifyHighlightStyle(uuid: highlightId, type: style)
                manager.setNote(uuid: highlightId, note: nil)
                let before = detectedBounds(harness, pageIndex: 0)

                manager.setNote(uuid: highlightId, note: "margin")

                XCTAssertEqual(noteMarkers(harness).count, 1)
                XCTAssertEqual(detectedBounds(harness, pageIndex: 0), before, "\(theme) \(style)")
            }
        }
    }

    func testHighlightMenuOffersNoteOrEditNote() throws {
        let (harness, highlightId) = try makeHighlightHarness(style: .yellow)
        let manager = harness.controller.menuManager

        func noteTitle() -> String? {
            manager.highlightMenuElements(for: highlightId).compactMap { $0 as? UIAction }.first { $0.identifier == PDFMenuManager.ActionID.note }?.title
        }
        XCTAssertEqual(noteTitle(), "Note")
        harness.controller.annotationManager.setNote(uuid: highlightId, note: "n")
        XCTAssertEqual(noteTitle(), "Edit Note")
    }

    func testHighlightNoteActionEditsTheNote() throws {
        let (harness, highlightId) = try makeHighlightHarness(style: .yellow)
        harness.controller.annotationManager.setNote(uuid: highlightId, note: "old")

        try perform(PDFMenuManager.ActionID.note, in: harness.controller.menuManager.highlightMenuElements(for: highlightId))
        let editor = try presentedNoteEditor(harness)
        XCTAssertEqual(editor.textView.text, "old", "prefilled")
        XCTAssertFalse(editor.quote.isEmpty)

        editor.textView.text = "new"
        editor.save()
        settle(0.5)

        XCTAssertEqual(harness.controller.annotationManager.note(of: highlightId), "new")
        waitForDismissal(harness)
        XCTAssertNil(harness.controller.presentedViewController)
    }

    func testSelectionNoteCreatesHighlightOnlyOnSave() throws {
        let (harness, selection) = try makeTextHarness()

        harness.pdfView.setCurrentSelection(selection, animate: false)
        try perform(PDFMenuManager.ActionID.note, in: harness.controller.menuManager.selectionMenuElements())
        let cancelled = try presentedNoteEditor(harness)
        XCTAssertEqual(cancelled.quote, selection.string)
        cancelled.textView.text = "never saved"
        cancelled.cancel()
        waitForDismissal(harness)
        XCTAssertTrue(harness.surface.highlights.isEmpty, "cancel creates nothing")

        harness.pdfView.setCurrentSelection(selection, animate: false)
        try perform(PDFMenuManager.ActionID.note, in: harness.controller.menuManager.selectionMenuElements())
        let editor = try presentedNoteEditor(harness)
        editor.textView.text = "kept"
        editor.save()
        waitForDismissal(harness)

        let highlightId = try XCTUnwrap(harness.surface.highlights.keys.first)
        XCTAssertEqual(harness.surface.highlights.count, 1)
        XCTAssertEqual(harness.controller.annotationManager.note(of: highlightId), "kept")
        XCTAssertEqual(harness.controller.annotationManager.style(of: highlightId), .yellow)
        XCTAssertEqual(noteMarkers(harness).count, 1)
    }

    func testAnnotatedExportCarriesNoteWithoutMarker() throws {
        let (harness, highlightId) = try makeHighlightHarness(style: .yellow)
        harness.controller.annotationManager.setNote(uuid: highlightId, note: "exported")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        tempURLs.append(url)

        XCTAssertTrue(harness.controller.writeAnnotatedPDF(to: url))

        let exported = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
        let highlightAnnotations = exported.annotations.filter { $0.type == "Highlight" }
        XCTAssertFalse(highlightAnnotations.isEmpty)
        XCTAssertTrue(highlightAnnotations.contains { $0.contents == "exported" })
        XCTAssertFalse(exported.annotations.contains { $0.isNoteMarker }, "no marker in the export")
        XCTAssertEqual(noteMarkers(harness).count, 1, "marker back on screen")
    }

    // MARK: - Dark-theme annotations

    /// PDFKit multiplies markup annotations over the already-inverted dark page,
    /// which hides their fill; dark draws highlights as translucent fills instead.
    func testDarkThemeDrawsHighlightsAsFills() throws {
        let (harness, highlightId) = try makeHighlightHarness(style: .green)
        harness.controller.annotationManager.setNote(uuid: highlightId, note: "n")
        let lightLines = lineAnnotations(harness, highlightId).map(\.bounds)

        setTheme(harness, .dark)

        let lines = lineAnnotations(harness, highlightId)
        XCTAssertEqual(lines.map(\.bounds), lightLines, "same geometry")
        for line in lines {
            XCTAssertEqual(line.type, "Square")
            let alpha = try XCTUnwrap(line.interiorColor).cgColor.alpha
            XCTAssertTrue(alpha > 0 && alpha < 1, "translucent fill: \(alpha)")
        }
        let marker = try XCTUnwrap(noteMarkers(harness).first)
        XCTAssertEqual(noteMarkers(harness).count, 1)
        XCTAssertEqual(marker.type, "Square")
        XCTAssertEqual(harness.surface.highlight(at: highlightCenter(harness, highlightId))?.0, highlightId, "still tappable")

        setTheme(harness, .none)

        XCTAssertTrue(lineAnnotations(harness, highlightId).allSatisfy { $0.type == "Highlight" })
        XCTAssertEqual(noteMarkers(harness).first?.type, "Highlight")
        XCTAssertEqual(harness.surface.highlights.count, 1)
    }

    func testDarkUnderlineIsABarAtTheBottomOfEachLine() throws {
        let (harness, highlightId) = try makeHighlightHarness(style: .underline)
        let lightLines = lineAnnotations(harness, highlightId).map(\.bounds)

        setTheme(harness, .dark)

        let bars = lineAnnotations(harness, highlightId)
        XCTAssertEqual(bars.count, lightLines.count)
        for (bar, line) in zip(bars, lightLines) {
            XCTAssertEqual(bar.type, "Square")
            XCTAssertEqual(try XCTUnwrap(bar.interiorColor).cgColor.alpha, 1, accuracy: 0.01)
            XCTAssertEqual(bar.bounds.minX, line.minX, accuracy: 0.01)
            XCTAssertEqual(bar.bounds.width, line.width, accuracy: 0.01)
            XCTAssertEqual(bar.bounds.minY, line.minY, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(bar.bounds.height, 2, "PDFKit does not fill thinner squares")
            XCTAssertLessThan(bar.bounds.height, line.height / 4)
        }
    }

    /// The marker is sized from the text line, not from the dark underline bar.
    func testDarkUnderlineNoteMarkerKeepsItsSize() throws {
        let (harness, highlightId) = try makeHighlightHarness(style: .underline)
        harness.controller.annotationManager.setNote(uuid: highlightId, note: "n")
        let lightMarker = try XCTUnwrap(noteMarkers(harness).first).bounds

        setTheme(harness, .dark)

        XCTAssertEqual(try XCTUnwrap(noteMarkers(harness).first).bounds, lightMarker)
    }

    /// Jump masks and dark page-turn covers are snapshots; they must show
    /// highlights the way PDFView composites them, not inverted with the page.
    func testDarkSnapshotShowsHighlightsAsOnScreen() throws {
        let (harness, highlightId) = try makeHighlightHarness(style: .green)
        setTheme(harness, .dark)
        waitForJumpMaskToClear(harness)
        let line = try XCTUnwrap(lineAnnotations(harness, highlightId).last)
        let rect = harness.pdfView.convert(line.bounds, from: harness.page(0))

        let image = harness.pdfView.viewportSnapshot(of: harness.page(0))
        var sum = (0, 0, 0)
        var count = 0
        for i in 1...12 {
            for j in 1...3 {
                let (r, g, b) = try rgb(of: image, at: CGPoint(x: rect.minX + rect.width * CGFloat(i) / 13, y: rect.minY + rect.height * CGFloat(j) / 4))
                sum = (sum.0 + r, sum.1 + g, sum.2 + b)
                count += 1
            }
        }
        let average = (sum.0 / count, sum.1 / count, sum.2 / count)
        record("PDFDARKSNAPSHOT highlight average=\(average)")
        XCTAssertGreaterThan(average.1, average.0 + 20, "green, not the inverted magenta: \(average)")
        XCTAssertGreaterThan(average.1, average.2)
    }

    /// PDFView multiplies an opaque highlight colour over the page; `PDFPage.draw`
    /// draws highlights paler, which showed as a colour shift when a mask faded.
    func testLightSnapshotDrawsHighlightsAtFullColour() throws {
        let (harness, highlightId) = try makeHighlightHarness(style: .green)
        let line = try XCTUnwrap(lineAnnotations(harness, highlightId).last)
        let rect = harness.pdfView.convert(line.bounds, from: harness.page(0))
        let image = harness.pdfView.viewportSnapshot(of: harness.page(0))

        var fill = [(Int, Int, Int)]()
        for i in 1...40 {
            for j in 1...3 {
                let color = try rgb(of: image, at: CGPoint(x: rect.minX + rect.width * CGFloat(i) / 41, y: rect.minY + rect.height * CGFloat(j) / 4))
                if color.1 > 140 { fill.append(color) }
            }
        }
        XCTAssertGreaterThan(fill.count, 20)
        let expected = UIColor.systemGreen.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).rgb255
        let average = (fill.map(\.0).reduce(0, +) / fill.count, fill.map(\.1).reduce(0, +) / fill.count, fill.map(\.2).reduce(0, +) / fill.count)
        record("PDFLIGHTSNAPSHOT fill=\(average) expected=\(expected)")
        XCTAssertEqual(average.0, expected.0, accuracy: 12)
        XCTAssertEqual(average.1, expected.1, accuracy: 12)
        XCTAssertEqual(average.2, expected.2, accuracy: 12)
    }

    func testDarkAnnotatedExportWritesStandardAnnotations() throws {
        let (harness, highlightId) = try makeHighlightHarness(style: .green)
        harness.controller.annotationManager.setNote(uuid: highlightId, note: "dark export")
        setTheme(harness, .dark)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        tempURLs.append(url)

        XCTAssertTrue(harness.controller.writeAnnotatedPDF(to: url))

        let exported = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
        XCTAssertTrue(exported.annotations.contains { $0.type == "Highlight" && $0.contents == "dark export" })
        XCTAssertFalse(exported.annotations.contains { $0.type == "Square" }, "\(exported.annotations.map { $0.type ?? "" })")
        XCTAssertFalse(exported.annotations.contains { $0.isNoteMarker })
        XCTAssertTrue(lineAnnotations(harness, highlightId).allSatisfy { $0.type == "Square" }, "dark form back on screen")
        XCTAssertEqual(noteMarkers(harness).count, 1)
    }

    private func lineAnnotations(_ harness: Harness, _ highlightId: UUID) -> [PDFAnnotation] {
        (harness.surface.highlights[highlightId] ?? []).flatMap(\.annotations).filter { !$0.isNoteMarker }
    }

    private func setTheme(_ harness: Harness, _ themeMode: PDFThemeMode) {
        var options = harness.controller.pdfOptions
        guard options.themeMode != themeMode else { return }
        options.themeMode = themeMode
        harness.controller.handleOptionsChange(pdfOptions: options)
        settle(0.3)
    }

    private func noteMarkers(_ harness: Harness) -> [PDFAnnotation] {
        (0..<(harness.pdfView.document?.pageCount ?? 0)).flatMap { harness.page($0).annotations.filter { $0.isNoteMarker } }
    }

    private func waitForDismissal(_ harness: Harness) {
        let deadline = Date().addingTimeInterval(3)
        while harness.controller.presentedViewController != nil && Date() < deadline {
            settle(0.1)
        }
    }

    private func presentedNoteEditor(_ harness: Harness, file: StaticString = #filePath, line: UInt = #line) throws -> YabrPDFNoteEditorViewController {
        settle(0.5)
        let nav = try XCTUnwrap(harness.controller.presentedViewController as? UINavigationController, file: file, line: line)
        return try XCTUnwrap(nav.viewControllers.first as? YabrPDFNoteEditorViewController, file: file, line: line)
    }

    /// Real-text pages (the synthetic block pages have no text to select).
    private func makeTextHarness() throws -> (Harness, PDFSelection) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let book = try BookPageGenerator.make(pageCount: 2, pageSize: Self.pageSize, in: directory)
        tempURLs.append(book.url)
        let harness = try makeHarness(
            pages: book.bodyRects.map { PageSpec(content: $0) },
            viewSize: Self.portrait,
            pdfURL: book.url
        )
        waitForJumpMaskToClear(harness)
        let document = try XCTUnwrap(harness.pdfView.document)
        let selection = try XCTUnwrap(document.selection(from: harness.page(0), atCharacterIndex: 40, to: harness.page(0), atCharacterIndex: 90))
        return (harness, selection)
    }

    private func makeHighlightHarness(style: BookHighlightStyle) throws -> (Harness, UUID) {
        let (harness, selection) = try makeTextHarness()
        harness.controller.annotationManager.addHighlight(style: style.rawValue, selection: selection)
        let highlightId = try XCTUnwrap(harness.surface.highlights.keys.first)
        return (harness, highlightId)
    }

    private func highlightCenter(_ harness: Harness, _ highlightId: UUID) -> CGPoint {
        guard let annotation = harness.surface.highlights[highlightId]?.first?.annotations.first,
              let page = annotation.page
        else { return .zero }
        let rect = harness.pdfView.convert(annotation.bounds, from: page)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    private func editMenu(_ harness: Harness) -> UIMenu? {
        let manager = harness.controller.menuManager
        guard let interaction = harness.surface.interactions.compactMap({ $0 as? UIEditMenuInteraction }).first(where: { $0.delegate === manager }) else { return nil }
        let configuration = UIEditMenuConfiguration(identifier: PDFMenuManager.highlightMenuIdentifier, sourcePoint: .zero)
        return manager.editMenuInteraction(interaction, menuFor: configuration, suggestedActions: [])
    }

    private func perform(_ identifier: UIAction.Identifier, in elements: [UIMenuElement], file: StaticString = #filePath, line: UInt = #line) throws {
        func find(_ elements: [UIMenuElement]) -> UIAction? {
            for element in elements {
                if let action = element as? UIAction, action.identifier == identifier { return action }
                if let menu = element as? UIMenu, let action = find(menu.children) { return action }
            }
            return nil
        }
        let action = try XCTUnwrap(find(elements), "no action \(identifier.rawValue)", file: file, line: line)
        action.performWithSender(nil, target: nil)
        settle(0.1)
    }

    /// Snapshots draw PDFKit's own annotations at the same place as the highlight
    /// fill, which is drawn directly, also when the crop box does not start at the
    /// page origin or the page is rotated.
    func testSnapshotAnnotationsLineUpWithHighlightsOnCroppedPages() throws {
        let target = CGRect(x: 200, y: 300, width: 100, height: 40)
        for rotation in [0, 90] {
            let url = try makePDF(pages: [PageSpec(content: CGRect(x: 0, y: 0, width: 1, height: 1))])
            let document = try XCTUnwrap(PDFDocument(url: url))
            let pageClass = PageWithBackgroundDelegate()
            document.delegate = pageClass
            let page = try XCTUnwrap(document.page(at: 0) as? PDFPageWithBackground)
            page.setBounds(CGRect(x: 40, y: 60, width: 500, height: 700), for: .cropBox)
            page.rotation = rotation

            func redBounds(_ type: PDFAnnotationSubtype) throws -> CGRect {
                for annotation in page.annotations { page.removeAnnotation(annotation) }
                let annotation = PDFAnnotation(bounds: target, forType: type, withProperties: nil)
                annotation.color = .red
                if type == .square { annotation.interiorColor = .red }
                page.addAnnotation(annotation)
                let size = page.bounds(for: .cropBox).applying(CGAffineTransform(rotationAngle: CGFloat(rotation) * .pi / 180)).size
                let width = Int(abs(size.width).rounded()), height = Int(abs(size.height).rounded())
                let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                page.drawAsDisplayed(with: .cropBox, to: context)
                let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
                var red = CGRect.null
                for y in 0..<height {
                    for x in 0..<width {
                        let offset = y * context.bytesPerRow + x * 4
                        if data[offset] > 200 && data[offset + 1] < 80 {
                            red = red.union(CGRect(x: x, y: y, width: 1, height: 1))
                        }
                    }
                }
                XCTAssertFalse(red.isNull, "\(type.rawValue) not drawn, rotation=\(rotation)")
                return red
            }

            let highlight = try redBounds(.highlight)
            let square = try redBounds(.square)
            XCTAssertEqual(square.minX, highlight.minX, accuracy: 1.5, "rotation=\(rotation)")
            XCTAssertEqual(square.minY, highlight.minY, accuracy: 1.5, "rotation=\(rotation)")
            XCTAssertEqual(square.maxX, highlight.maxX, accuracy: 1.5, "rotation=\(rotation)")
            XCTAssertEqual(square.maxY, highlight.maxY, accuracy: 1.5, "rotation=\(rotation)")
            let underline = try redBounds(.underline)
            XCTAssertTrue(highlight.insetBy(dx: -1.5, dy: -1.5).contains(underline), "underline \(underline) outside \(highlight), rotation=\(rotation)")
        }
    }

    // MARK: - Drag range

    /// A page may be dragged only between the placements where it stays inside
    /// the view (along an axis it fits) or keeps covering it (along an axis it
    /// overflows), plus where the fit put it. PDFKit applies the padded page break
    /// margins twice per side, which let a Height-fitted page leave the screen.
    /// One harness for all configurations: more window-hosted documents tip the
    /// test process's PDFKit Vision / GCD deadlock.
    func testPageCannotBeDraggedOutOfView() throws {
        let content = CGRect(x: 40, y: 50, width: 530, height: 690)
        let harness = try makeHarness(pages: [PageSpec(content: content)], viewSize: Self.tabletLandscape)
        for (scaler, direction) in [(PDFAutoScaler.Width, PDFReadDirection.LtR_TtB), (.Height, .TtB_RtL), (.Height, .LtR_TtB), (.Page, .TtB_RtL)] {
            let label = "\(scaler) \(direction)"
            var options = harness.controller.pdfOptions
            options.selectedAutoScaler = scaler
            options.readingDirection = direction
            harness.controller.handleOptionsChange(pdfOptions: options)
            settle(0.3)
            let view = harness.pdfView
            let page = try XCTUnwrap(view.currentPage)
            let scrollView = try XCTUnwrap(view.documentScrollView)
            let fitted = view.convert(page.bounds(for: .cropBox), from: page)
            let size = view.bounds.size
            if direction == .TtB_RtL {
                // Vertical text starts at the right, also after Width left a saved
                // top-left point that no longer applies once the content fits.
                let readable = view.bounds.inset(by: view.safeAreaInsets)
                let margin = readable.width * CGFloat(options.hMarginAutoScaler) / 100
                XCTAssertEqual(contentInView(harness, pageIndex: 0).maxX, readable.maxX - margin, accuracy: 2, label)
            }

            let inset = scrollView.adjustedContentInset
            let extremes = [
                CGPoint(x: -inset.left, y: -inset.top),
                CGPoint(x: scrollView.contentSize.width + inset.right - scrollView.bounds.width, y: scrollView.contentSize.height + inset.bottom - scrollView.bounds.height),
            ]
            for extreme in extremes {
                scrollView.contentOffset = extreme
                view.layoutIfNeeded()
                let placed = view.convert(page.bounds(for: .cropBox), from: page)
                func allowed(_ start: CGFloat, _ length: CGFloat, _ viewLength: CGFloat, _ fittedStart: CGFloat) -> Bool {
                    let inside = length <= viewLength
                        ? start >= -1 && start + length <= viewLength + 1
                        : start <= 1 && start + length >= viewLength - 1
                    return inside || abs(start - fittedStart) < 1
                }
                XCTAssertTrue(allowed(placed.minX, placed.width, size.width, fitted.minX), "\(label): x \(placed) fitted \(fitted)")
                XCTAssertTrue(allowed(placed.minY, placed.height, size.height, fitted.minY), "\(label): y \(placed) fitted \(fitted)")
            }
        }
    }

    // MARK: - Buffered neighbour pages (#54 / #55)

    func testForwardTurnTakesOverTheRenderedNextBuffer() throws {
        let harness = try makeJumpHarness(initialPage: 3)
        let surface = harness.surface
        try waitForRenderedBuffers(harness, pages: [4, 2])
        let old = harness.pdfView
        let next = try XCTUnwrap(surface.bufferViews.first { $0.currentPage?.pageRef?.pageNumber == 4 })
        let masksBefore = surface.jumpMaskGeneration

        harness.controller.pageNextButton.sendActions(for: .primaryActionTriggered)

        // The rendered buffer is now the page view: no PDFKit turn, no cover.
        XCTAssertTrue(harness.pdfView === next)
        XCTAssertEqual(harness.pdfView.currentPage?.pageRef?.pageNumber, 4)
        XCTAssertNil(surface.coveringView)
        XCTAssertEqual(surface.jumpMaskGeneration, masksBefore)
        XCTAssertEqual(harness.controller.pageIndicator.title(for: .normal), "4 / 5", "page change handled")
        XCTAssertTrue(next.isUserInteractionEnabled)
        XCTAssertFalse(old.isUserInteractionEnabled)
        let order = surface.subviews
        let nextIndex = try XCTUnwrap(order.firstIndex { $0 === next })
        XCTAssertGreaterThan(nextIndex, try XCTUnwrap(order.firstIndex { $0 === old }))
        XCTAssertLessThan(nextIndex, try XCTUnwrap(order.firstIndex { $0 === surface.jumpMaskView }))
        XCTAssertTrue(surface.bufferViews.contains { $0 === old }, "the old page view is a buffer")
        XCTAssertEqual(old.currentPage?.pageRef?.pageNumber, 3, "already showing the new previous page")

        // The new page view's notifications are relayed, the old one's are not.
        var relayed = 0
        let observer = NotificationCenter.default.addObserver(forName: .readerSurfaceScaleChanged, object: surface, queue: nil) { _ in relayed += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        NotificationCenter.default.post(name: .PDFViewScaleChanged, object: old)
        NotificationCenter.default.post(name: .PDFViewScaleChanged, object: next)
        XCTAssertEqual(relayed, 1)

        try waitForBuffers(harness, pages: [5, 3])
        XCTAssertTrue(surface.bufferViews.contains { $0 === old && $0.currentPage?.pageRef?.pageNumber == 3 }, "kept for page 3")
    }

    func testTakeoverClearsTheOldSelection() throws {
        let (harness, selection) = try makeTextHarness()
        try waitForRenderedBuffers(harness, pages: [2])
        let old = harness.pdfView
        old.setCurrentSelection(selection, animate: false)

        harness.controller.pageNextButton.sendActions(for: .primaryActionTriggered)

        XCTAssertTrue(harness.pdfView !== old)
        XCTAssertNil(old.currentSelection)
        XCTAssertNil(harness.pdfView.currentSelection)
    }

    /// Under dark, a buffer that has not rendered yet shows PDFKit's white
    /// placeholder, so fast turns keep the snapshot masks.
    func testDarkTurnOntoAnUnrenderedBufferKeepsTheMasks() throws {
        let harness = try makeJumpHarness(initialPage: 3, themeMode: .dark)
        try waitForBuffers(harness, pages: [4, 2])
        harness.surface.discardBuffers()
        harness.controller.refreshPageBuffers()
        let before = harness.surface.jumpMaskGeneration

        harness.controller.pageNextButton.sendActions(for: .primaryActionTriggered)

        XCTAssertNotNil(harness.surface.coveringView)
        XCTAssertEqual(harness.surface.jumpMaskGeneration, before + 2, "freeze, then the new page")
    }

    func testBackwardTurnTakesOverTheRenderedPreviousBuffer() throws {
        let harness = try makeJumpHarness(initialPage: 3)
        try waitForRenderedBuffers(harness, pages: [4, 2])
        let previous = try XCTUnwrap(harness.surface.bufferViews.first { $0.currentPage?.pageRef?.pageNumber == 2 })

        harness.controller.pagePrevButton.sendActions(for: .primaryActionTriggered)

        XCTAssertTrue(harness.pdfView === previous)
        XCTAssertEqual(harness.pdfView.currentPage?.pageRef?.pageNumber, 2)
    }

    /// A buffer that has not finished rendering does not take over; the turn is
    /// PDFKit's, covered by the buffer.
    func testTurnOntoAnUnrenderedBufferIsCovered() throws {
        let harness = try makeJumpHarness(initialPage: 3)
        try waitForBuffers(harness, pages: [4, 2])
        harness.surface.discardBuffers()
        harness.controller.refreshPageBuffers()
        let old = harness.pdfView

        harness.controller.pageNextButton.sendActions(for: .primaryActionTriggered)

        XCTAssertTrue(harness.pdfView === old, "no takeover")
        let cover = try XCTUnwrap(harness.surface.coveringView, "page 4 was buffered")
        let page = try XCTUnwrap(harness.pdfView.currentPage)
        XCTAssertEqual(page.pageRef?.pageNumber, 4)
        XCTAssertTrue(cover.currentPage === page)
        let order = harness.surface.subviews
        let coverIndex = try XCTUnwrap(order.firstIndex { $0 === cover })
        XCTAssertGreaterThan(coverIndex, try XCTUnwrap(order.firstIndex { $0 === harness.pdfView }), "in front of the page view")
        XCTAssertLessThan(coverIndex, try XCTUnwrap(order.firstIndex { $0 === harness.surface.jumpMaskView }), "below the overlays")
        assertSameViewport(cover, harness.pdfView, page: page)

        waitForCoverToEnd(harness)
        let after = harness.surface.subviews
        XCTAssertLessThan(try XCTUnwrap(after.firstIndex { $0 === cover }), try XCTUnwrap(after.firstIndex { $0 === harness.pdfView }), "back behind")
    }

    func testJumpToAnUnbufferedPageIsNotCovered() throws {
        let harness = try makeJumpHarness(initialPage: 2)
        try waitForBuffers(harness, pages: [3, 1])

        slide(harness, toPage: 5)

        XCTAssertNil(harness.surface.coveringView)
        XCTAssertEqual(currentPageIndex(harness), 4)
    }

    /// The engine is told about every page change, including a return to a page
    /// whose position was saved.
    func testTurningBackToAVisitedPageReportsIt() throws {
        let harness = try makeJumpHarness()
        pressNext(harness)
        pressNext(harness)
        let spy = PositionSpy()
        harness.controller.readerEngineDelegate = spy

        pressPrev(harness)

        XCTAssertEqual(currentPageIndex(harness), 1)
        XCTAssertEqual(spy.pageNumbers.last, 2)
    }

    /// Pages fitted at different scales: the scale of a page view that takes over
    /// becomes the reader's last scale, as when PDFKit rescales on a turn.
    func testTakeoverUpdatesTheLastScale() throws {
        let wide = PageSpec(content: CGRect(x: 81, y: 96, width: 450, height: 600))
        let narrow = PageSpec(content: CGRect(x: 156, y: 96, width: 300, height: 600))
        let harness = try makeHarness(pages: [wide, narrow, wide], viewSize: Self.portrait)
        waitForJumpMaskToClear(harness)
        try waitForRenderedBuffers(harness, pages: [2])
        let old = harness.pdfView
        let next = try XCTUnwrap(harness.surface.bufferViews.first { $0.currentPage?.pageRef?.pageNumber == 2 })
        XCTAssertNotEqual(next.scaleFactor, old.scaleFactor, accuracy: 0.01, "precondition")

        pressNext(harness)

        XCTAssertTrue(harness.pdfView === next)
        XCTAssertEqual(harness.controller.pdfOptions.lastScale, next.scaleFactor, accuracy: 0.0001)
    }

    /// Options reach the buffers only when they are next refreshed; until then a
    /// buffer laid out differently neither takes over nor covers.
    func testBufferLaidOutDifferentlyIsNotUsed() throws {
        let harness = try makeJumpHarness(initialPage: 3)
        try waitForRenderedBuffers(harness, pages: [4, 2])
        let old = harness.pdfView
        old.displaysRTL = true
        XCTAssertFalse(harness.surface.hasRenderedBuffer(showing: harness.page(3)))

        harness.controller.pageNextButton.sendActions(for: .primaryActionTriggered)

        XCTAssertTrue(harness.pdfView === old, "no takeover")
        XCTAssertNil(harness.surface.coveringView)
    }

    /// PDFKit draws the same tiles for every view at a scale and the draw log does
    /// not know which view drew; the tiles an unrendered covering buffer still
    /// draws are not taken for the page view's.
    func testCoverByAnUnrenderedBufferOwesItsTiles() throws {
        let harness = try makeJumpHarness(initialPage: 3)
        try waitForBuffers(harness, pages: [4, 2])
        harness.surface.discardBuffers()
        harness.controller.refreshPageBuffers()

        harness.controller.pageNextButton.sendActions(for: .primaryActionTriggered)

        let cover = try XCTUnwrap(harness.surface.coveringView)
        let page = try XCTUnwrap(cover.currentPage)
        let shown = harness.surface.shownTiles(of: cover, page: page)
        XCTAssertFalse(harness.surface.coverOwedTiles.isEmpty)
        XCTAssertTrue(harness.surface.coverOwedTiles.isSubset(of: shown))
    }

    func testCoverByARenderedBufferOwesNothing() throws {
        let harness = try makeJumpHarness(initialPage: 3)
        try waitForRenderedBuffers(harness, pages: [4, 2])

        let slider = harness.controller.pageSlider
        slider.maximumValue = 5
        slider.value = 4
        slider.sendActions(for: .valueChanged)

        XCTAssertNotNil(harness.surface.coveringView)
        XCTAssertEqual(harness.surface.coverOwedTiles, [])
    }

    /// Guards the PDFKit tile layout the buffers depend on (see `PDFPageTile`): a
    /// rendered page's draws must be recognised as the tiles its view shows.
    func testRenderedPageDrawsArePDFKitTiles() throws {
        let harness = try makeJumpHarness()
        settle(0.5)
        let view = harness.pdfView
        let page = try XCTUnwrap(view.currentPage)
        let pageNumber = try XCTUnwrap(page.pageRef?.pageNumber)
        let shown = harness.surface.shownTiles(of: view, page: page)
        let counts = harness.controller.pageRenderTheme.tileDrawCounts(
            ofPage: pageNumber,
            pixelsPerPoint: view.scaleFactor * view.traitCollection.displayScale,
            after: 0
        )

        XCTAssertFalse(shown.isEmpty)
        XCTAssertTrue(shown.isSubset(of: Set(counts.keys)), "PDFKit tile layout changed: shown \(shown), drawn \(counts.keys)")
    }

    func testTileGrid() {
        XCTAssertEqual(PDFPageTile(drawnWith: CGAffineTransform(a: 3, b: 0, c: 0, d: 3, tx: 1, ty: -1023)), PDFPageTile(column: 0, row: 1))
        XCTAssertEqual(PDFPageTile(drawnWith: CGAffineTransform(a: 6, b: 0, c: 0, d: 6, tx: -2047, ty: -4095)), PDFPageTile(column: 2, row: 4))
        XCTAssertNil(PDFPageTile(drawnWith: CGAffineTransform(a: 0.5, b: 0, c: 0, d: 0.5, tx: 0, ty: 0)), "a thumbnail")

        // A whole 612 x 792 page at 3 pixels per point: 1836 x 2376 pixels.
        XCTAssertEqual(PDFPageTile.tiles(covering: CGRect(x: 0, y: 0, width: 612, height: 792), pixelsPerPoint: 3).count, 6)
        // Zoomed in (as PDFKit drew it): columns 0...1, rows 1...3.
        let zoomed = PDFPageTile.tiles(covering: CGRect(x: 92, y: 229.5, width: 195, height: 422), pixelsPerPoint: 6)
        XCTAssertEqual(zoomed, Set((0...1).flatMap { column in (1...3).map { PDFPageTile(column: column, row: $0) } }))
        XCTAssertEqual(PDFPageTile.tiles(covering: .null, pixelsPerPoint: 3), [])
    }

    func testDrawLogCountsTileDraws() {
        let log = PDFPageRenderTheme()
        let tile = CGAffineTransform(a: 3, b: 0, c: 0, d: 3, tx: 1, ty: 1)
        log.noteDraw(ofPage: 1, ctm: tile)
        usleep(1000)
        let between = CACurrentMediaTime()
        usleep(1000)
        log.noteDraw(ofPage: 1, ctm: tile)
        log.noteDraw(ofPage: 1, ctm: CGAffineTransform(a: 3, b: 0, c: 0, d: 3, tx: -1023, ty: 1))
        log.noteDraw(ofPage: 1, ctm: CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 1, ty: 1))

        XCTAssertEqual(log.tileDrawCounts(ofPage: 1, pixelsPerPoint: 3, after: 0), [PDFPageTile(column: 0, row: 0): 2, PDFPageTile(column: 1, row: 0): 1])
        XCTAssertEqual(log.tileDrawCounts(ofPage: 1, pixelsPerPoint: 3, after: between), [PDFPageTile(column: 0, row: 0): 1, PDFPageTile(column: 1, row: 0): 1])
        XCTAssertEqual(log.tileDrawCounts(ofPage: 2, pixelsPerPoint: 3, after: 0), [:])
    }

    /// A viewport past PDFKit's scroll range (here the page's bottom edge at the
    /// view's top) is reached with extra inset; continuous mode must not keep it.
    func testScrollModeDropsTheViewportExtraInset() throws {
        let harness = try makeJumpHarness()
        let page = try XCTUnwrap(harness.pdfView.currentPage)
        harness.pdfView.applyViewport(
            PDFPageViewportFit(scale: harness.pdfView.scaleFactor, pageAnchor: CGPoint(x: 0, y: 0), viewAnchor: .zero),
            on: page
        )
        XCTAssertNotEqual(harness.pdfView.viewportExtraInset, .zero, "precondition")

        var options = harness.controller.pdfOptions
        options.pageMode = .Scroll
        harness.controller.handleOptionsChange(pdfOptions: options)
        settle()

        XCTAssertEqual(harness.pdfView.viewportExtraInset, .zero)
    }

    /// A page whose saved position (here, scale) differs from the buffer's is not
    /// taken over: the buffer's tiles are for the old scale.
    func testBufferAtAnotherViewportDoesNotCover() throws {
        let harness = try makeJumpHarness(initialPage: 3)
        try waitForBuffers(harness, pages: [4, 2])
        harness.controller.pageViewPositionHistory[4] = PageViewPosition(
            // Not near 1.0: PDFKit's first pass renders every page at 100% zoom.
            scaler: harness.pdfView.scaleFactor * 1.6,
            point: CGPoint(x: 100, y: 500),
            viewSize: harness.pdfView.frame.size
        )

        let old = harness.pdfView
        harness.controller.pageNextButton.sendActions(for: .primaryActionTriggered)

        XCTAssertEqual(harness.pdfView.currentPage?.pageRef?.pageNumber, 4)
        XCTAssertTrue(harness.pdfView === old, "a buffer at another scale is not taken over")
    }

    func testScrollModeReleasesTheBuffers() throws {
        let harness = try makeJumpHarness(initialPage: 3)
        try waitForBuffers(harness, pages: [4, 2])

        var options = harness.controller.pdfOptions
        options.pageMode = .Scroll
        harness.controller.handleOptionsChange(pdfOptions: options)
        settle()

        XCTAssertTrue(harness.surface.bufferedPages.isEmpty)
    }

    func testThemeReachesTheBuffers() throws {
        let harness = try makeJumpHarness(initialPage: 3)
        try waitForBuffers(harness, pages: [4, 2])

        setTheme(harness, .dark)
        waitForJumpMaskToClear(harness)
        try waitForBuffers(harness, pages: [4, 2])

        for buffer in harness.surface.bufferViews {
            XCTAssertTrue(buffer.invertsPagePlaceholders)
            XCTAssertEqual(buffer.backgroundColor, harness.pdfView.backgroundColor)
        }
        let old = harness.pdfView
        harness.controller.pageNextButton.sendActions(for: .primaryActionTriggered)
        XCTAssertTrue(harness.surface.coveringView != nil || harness.pdfView !== old, "re-rendered buffers cover or take over in dark too")
    }

    private func waitForBuffers(_ harness: Harness, pages: Set<Int>, file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(3)
        func buffered() -> Set<Int> { Set(harness.surface.bufferedPages.compactMap { $0.pageRef?.pageNumber }) }
        while buffered() != pages && Date() < deadline {
            settle(0.05)
        }
        XCTAssertEqual(buffered(), pages, "buffered pages", file: file, line: line)
    }

    private func waitForRenderedBuffers(_ harness: Harness, pages: Set<Int>, file: StaticString = #filePath, line: UInt = #line) throws {
        try waitForBuffers(harness, pages: pages, file: file, line: line)
        let deadline = Date().addingTimeInterval(3)
        func rendered() -> Bool {
            harness.surface.bufferedPages.allSatisfy { harness.surface.hasRenderedBuffer(showing: $0) }
        }
        while !rendered() && Date() < deadline {
            settle(0.05)
        }
        XCTAssertTrue(rendered(), "buffers rendered", file: file, line: line)
    }

    private func waitForCoverToEnd(_ harness: Harness) {
        let deadline = Date().addingTimeInterval(3)
        while harness.surface.coveringView != nil && Date() < deadline {
            settle(0.05)
        }
        XCTAssertNil(harness.surface.coveringView, "cover ends")
    }

    private func assertSameViewport(_ a: PDFView, _ b: PDFView, page: PDFPage, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.scaleFactor, b.scaleFactor, accuracy: 0.0005, file: file, line: line)
        let pointA = a.convert(a.bounds.origin, to: page)
        let pointB = b.convert(b.bounds.origin, to: page)
        XCTAssertEqual(pointA.x, pointB.x, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(pointA.y, pointB.y, accuracy: 0.5, file: file, line: line)
    }

    // MARK: - Jump helpers

    private func makeJumpHarness(initialPage: Int? = nil, themeMode: PDFThemeMode = .none) throws -> Harness {
        let harness = try makeHarness(
            pages: Array(repeating: PageSpec(content: CGRect(x: 81, y: 96, width: 450, height: 600)), count: 5),
            viewSize: Self.portrait,
            themeMode: themeMode,
            initialPage: initialPage
        )
        waitForJumpMaskToClear(harness)
        return harness
    }

    private func waitForJumpMaskToClear(_ harness: Harness) {
        let deadline = Date().addingTimeInterval(2)
        while harness.surface.isJumpMaskVisible && Date() < deadline {
            settle(0.05)
        }
    }

    private func currentPageIndex(_ harness: Harness) -> Int? {
        harness.pdfView.currentPage.flatMap { harness.pdfView.document?.index(for: $0) }
    }

    private func assertShowsJumpMask(_ harness: Harness, toPageIndex pageIndex: Int, file: StaticString = #filePath, line: UInt = #line, jump: () -> Void) throws {
        let before = harness.surface.jumpMaskGeneration
        jump()
        settle()
        XCTAssertEqual(currentPageIndex(harness), pageIndex, file: file, line: line)
        XCTAssertEqual(harness.surface.jumpMaskGeneration, before + 1, "jump should show the mask once", file: file, line: line)
        XCTAssertTrue(harness.surface.isJumpMaskVisible, file: file, line: line)
        XCTAssertNil(harness.controller.pendingJumpMaskPage, file: file, line: line)
    }

    /// A point inside the page's top margin, clear of the side tap-zone labels.
    private func pageMarginPoint(_ harness: Harness, pageIndex: Int) -> CGPoint {
        let inView = contentInView(harness, pageIndex: pageIndex)
        return CGPoint(x: inView.midX, y: inView.minY - 6)
    }

    /// Color of the window at a PDFView point, via drawHierarchy. It redraws the
    /// hierarchy, so it shows layout but not stale on-screen page tiles.
    private func renderedColor(_ harness: Harness, pageIndex: Int, at point: CGPoint) throws -> (Int, Int, Int) {
        let view = try XCTUnwrap(harness.pdfView.window)
        let pointInWindow = harness.pdfView.convert(point, to: view)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        return try rgb(of: image, at: pointInWindow)
    }

    func testJumpMaskPreviewMatchesFinalViewport() throws {
        try assertJumpMaskPreview(spec: PageSpec(content: CGRect(x: 81, y: 96, width: 450, height: 600)), theme: .none, content: 0, margin: 255)
    }

    func testDarkJumpMaskPreviewIsInverted() throws {
        // Dark draws the page inverted, text at 70% gray.
        try assertJumpMaskPreview(spec: PageSpec(content: CGRect(x: 81, y: 96, width: 450, height: 600)), theme: .dark, content: 178, margin: 0)
    }

    private func assertJumpMaskPreview(spec: PageSpec, theme: PDFThemeMode, content expectedContent: Int, margin expectedMargin: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        let harness = try makeHarness(
            pages: Array(repeating: spec, count: 3),
            viewSize: Self.landscape,
            themeMode: theme
        )
        slide(harness, toPage: 3)
        let image = try XCTUnwrap(harness.surface.jumpMaskView.image, file: file, line: line)

        let inView = contentInView(harness, pageIndex: 2)
        let visibleContent = inView.intersection(harness.pdfView.bounds)
        XCTAssertFalse(visibleContent.isEmpty, "content not visible: \(inView)", file: file, line: line)
        let insideContent = CGPoint(x: visibleContent.midX, y: visibleContent.midY)
        let pageMargin = CGPoint(x: inView.minX - 8, y: insideContent.y)
        let contentGray = try gray(of: image, at: insideContent)
        let marginGray = try gray(of: image, at: pageMargin)
        record("PDFMASK theme=\(theme) rotation=\(spec.rotation) crop=\(String(describing: spec.cropBox)) inView=\(inView) content=\(contentGray) margin=\(marginGray)")

        XCTAssertEqual(contentGray, expectedContent, accuracy: 6, "content", file: file, line: line)
        XCTAssertEqual(marginGray, expectedMargin, accuracy: 6, "page margin", file: file, line: line)
    }

    private func slide(_ harness: Harness, toPage pageNumber: Int) {
        let slider = harness.controller.pageSlider
        slider.maximumValue = Float(harness.pdfView.document?.pageCount ?? 1)
        slider.value = Float(pageNumber)
        slider.sendActions(for: .valueChanged)
        settle()
    }

    private func gray(of image: UIImage, at point: CGPoint) throws -> Int {
        let (r, g, b) = try rgb(of: image, at: point)
        return (r + g + b) / 3
    }

    /// RGB at a view point, read through a known 8-bit RGBA context.
    private func rgb(of image: UIImage, at point: CGPoint) throws -> (Int, Int, Int) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let x = min(max(Int(point.x * image.scale), 0), width - 1)
        let y = min(max(Int(point.y * image.scale), 0), height - 1)
        let offset = (y * width + x) * 4
        return (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
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
        var rotation: Int = 0
    }

    private struct Harness {
        let controller: AppearanceTrackingPDFViewController
        let pages: [PageSpec]

        var pdfView: YabrPDFView { controller.pdfView }
        var surface: PDFReaderSurface { controller.surface }

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
        inNavigationController: Bool = false,
        initialPage: Int? = nil
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
            if spec.rotation != 0 {
                document.page(at: index)?.rotation = spec.rotation
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
        if let initialPage {
            // Same shape as a restored reading position with no in-page offset.
            controller.pageViewPositionHistory[initialPage] = PageViewPosition(scaler: 0, point: CGPoint(x: CGFloat.nan, y: CGFloat.nan))
        }

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
        // Adding a window to the host app's scene re-evaluates its SwiftUI views,
        // whose `appContainer` environment default asserts when
        // `AppContainer.shared` is nil (some suites clear it in tearDown).
        if AppContainer.shared == nil {
            _ = MockAppContainerFactory.makeContainer()
        }
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

@available(iOS 16.0, macCatalyst 16.0, *)
private final class AppearanceTrackingPDFViewController: YabrPDFViewController {
    private(set) var didAppear = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didAppear = true
    }
}

private final class StubPDFPreferenceRepository: ReaderPreferenceRepositoryProtocol {
    func loadInitialPreferences(for book: CalibreBook, readerType: ReaderType) -> ReaderEnginePreferences? { nil }
    func savePreferences(_ preferences: ReaderEnginePreferences, for book: CalibreBook, readerType: ReaderType) {}
    func loadFolioPreferences(for book: CalibreBook) -> FolioReaderPreferenceValue? { nil }
    func saveFolioPreferences(_ preferences: FolioReaderPreferenceValue, for book: CalibreBook) {}
    func loadReadiumPreferences(for book: CalibreBook) -> ReadiumPreferenceValue? { nil }
    func saveReadiumPreferences(_ preferences: ReadiumPreferenceValue, for book: CalibreBook) {}
    func loadPDFPreferences(for book: CalibreBook) -> PDFPreferenceValue? { nil }
    func savePDFPreferences(_ preferences: PDFPreferenceValue, for book: CalibreBook) {}
}

private final class PositionSpy: ReaderEngineDelegate {
    private(set) var pageNumbers: [Int] = []
    func readerEngine(_ engine: AnyObject, didUpdatePosition position: ReaderEnginePosition) {
        pageNumbers.append(position.pageNumber)
    }
    func readerEngine(_ engine: AnyObject, didAddHighlight highlight: ReaderEngineHighlight) {}
    func readerEngine(_ engine: AnyObject, didRemoveHighlight highlightId: String) {}
    func readerEngine(_ engine: AnyObject, didUpdatePreferences prefs: ReaderEnginePreferences) {}
}

private final class HighlightSpy: ReaderEngineDelegate {
    private(set) var added: [ReaderEngineHighlight] = []
    private(set) var removed: [String] = []
    func readerEngine(_ engine: AnyObject, didUpdatePosition position: ReaderEnginePosition) {}
    func readerEngine(_ engine: AnyObject, didAddHighlight highlight: ReaderEngineHighlight) {
        added.append(highlight)
    }
    func readerEngine(_ engine: AnyObject, didRemoveHighlight highlightId: String) {
        removed.append(highlightId)
    }
    func readerEngine(_ engine: AnyObject, didUpdatePreferences prefs: ReaderEnginePreferences) {}
}

private extension UIColor {
    var rgb255: (Int, Int, Int) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

@available(iOS 16.0, macCatalyst 16.0, *)
private final class PageWithBackgroundDelegate: NSObject, PDFDocumentDelegate {
    func classForPage() -> AnyClass { PDFPageWithBackground.self }
}
