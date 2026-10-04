import XCTest
import UIKit
import PDFKit
@testable import YetAnotherEBookReader

@available(iOS 16.0, macCatalyst 16.0, *)
@MainActor
final class YabrPDFViewControllerTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        tempURLs.removeAll()
    }

    func testOpenReturnsMinusOneWhenMetaSourceHasNoURL() {
        let controller = SpyYabrPDFViewController()
        controller.yabrPDFMetaSource = MockYabrPDFMetaSource(pdfURL: nil)

        XCTAssertEqual(controller.open(), -1)
        XCTAssertNil(controller.pdfView.document)
    }

    func testOpenLoadsPDFAndRestoresInitialPosition() throws {
        let pdfURL = try makePDFURL(name: "open-restores-position", pageCount: 2)
        var options = PDFPreferenceValue()
        options.lastScale = 1.75

        let controller = SpyYabrPDFViewController()
        controller.yabrPDFMetaSource = MockYabrPDFMetaSource(pdfURL: pdfURL, options: options)
        controller.initialPosition = ReaderEnginePosition(pageNumber: 2, pageOffsetX: 12, pageOffsetY: 34)

        XCTAssertEqual(controller.open(), 0)
        XCTAssertEqual(controller.pdfView.document?.pageCount, 2)
        XCTAssertEqual(controller.pdfView.displayMode, .singlePage)
        XCTAssertEqual(controller.pdfView.displayDirection, .vertical)
        XCTAssertEqual(controller.pageViewPositionHistory[2]?.point, CGPoint(x: 12, y: 34))
        XCTAssertEqual(controller.pageViewPositionHistory[2]?.scaler, CGFloat(options.lastScale))
    }

    func testOpenPreservesNonTriStateThemeModeFromMetaSource() throws {
        let pdfURL = try makePDFURL(name: "open-preserves-forest-theme", pageCount: 1)
        let options = PDFPreferenceValue(themeMode: .forest, pageMode: .Page, readingDirection: .LtR_TtB)

        let controller = SpyYabrPDFViewController()
        controller.yabrPDFMetaSource = MockYabrPDFMetaSource(pdfURL: pdfURL, options: options)

        XCTAssertEqual(controller.open(), 0)
        XCTAssertEqual(controller.pdfOptions.themeMode, .forest)
        XCTAssertFalse(controller.surface.themeOverlayView.isHidden)
        XCTAssertFalse(controller.pageRenderTheme.drawsInverted)
    }

    func testNavigationBarHasNoCloseButton() {
        let controller = SpyYabrPDFViewController()
        controller.loadViewIfNeeded()

        let items = controller.navigationItem.leftBarButtonItems ?? []
        XCTAssertFalse(items.isEmpty)
        XCTAssertFalse(items.contains { $0.image == UIImage(systemName: "xmark.circle") }, "The reader workspace owns closing; YabrPDF must not add its own close button.")
    }

    func testNavigationItemAppearanceFollowsTheme() throws {
        let controller = SpyYabrPDFViewController()

        for theme in PDFThemeMode.allCases {
            controller.pdfOptions = PDFPreferenceValue(themeMode: theme)
            let item = controller.navigationItem
            let appearance = try XCTUnwrap(item.standardAppearance, "\(theme)")
            for other in [item.scrollEdgeAppearance, item.compactAppearance, item.compactScrollEdgeAppearance] {
                XCTAssertEqual(other?.backgroundColor, appearance.backgroundColor, "\(theme): every bar state uses the theme appearance")
            }

            let fill = controller.pdfOptions.fillColor
            if fill.alpha > 0 {
                XCTAssertEqual(appearance.backgroundColor?.cgColor.components, fill.components, "\(theme)")
                XCTAssertNil(appearance.backgroundEffect, "\(theme) bar should be opaque")
            } else {
                XCTAssertNil(appearance.backgroundColor, "none keeps the system bar background")
            }
            let titleColor = appearance.titleTextAttributes[.foregroundColor] as? UIColor
            XCTAssertEqual(titleColor, theme == .dark ? .white : .black, "\(theme)")
        }
    }

    /// `open()` sets the options before the reader is pushed; the bar must still be
    /// themed once it appears, even when the bar itself carries the app's wood look.
    func testThemeSetBeforePushAppliesToNavigationBar() {
        let controller = SpyYabrPDFViewController()
        controller.pdfOptions = PDFPreferenceValue(themeMode: .dark)

        let nav = UINavigationController(rootViewController: controller)
        let wood = UINavigationBarAppearance()
        wood.configureWithOpaqueBackground()
        wood.backgroundColor = .brown
        nav.navigationBar.standardAppearance = wood
        nav.navigationBar.scrollEdgeAppearance = wood
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()

        XCTAssertEqual(nav.navigationBar.tintColor, .lightText)
        XCTAssertEqual(controller.navigationItem.standardAppearance?.backgroundColor?.cgColor.components, CGColor(gray: 0, alpha: 1).components)

        controller.pdfOptions = PDFPreferenceValue(themeMode: .serpia)
        XCTAssertEqual(nav.navigationBar.tintColor, .darkText)
    }

    /// In the reader workspace the status bar sits over its black background, not
    /// over a reader, so the reader container keeps it light for every reader
    /// theme and whether or not the reader shows its nav bar.
    func testReaderNavigationControllerKeepsStatusBarLightInWorkspace() {
        let controller = SpyYabrPDFViewController()
        controller.pdfOptions = PDFPreferenceValue(themeMode: .serpia)
        let nav = makeReaderNavigationController(presentationID: UUID(), root: controller)

        for hidden in [false, true] {
            nav.setNavigationBarHidden(hidden, animated: false)
            XCTAssertNil(nav.childForStatusBarStyle, "navigationBarHidden=\(hidden)")
            XCTAssertEqual(nav.preferredStatusBarStyle, .lightContent, "navigationBarHidden=\(hidden)")
        }
    }

    /// Outside the workspace (book preview) the reader keeps UIKit's default: the
    /// top reader decides while the nav bar is hidden.
    func testReaderNavigationControllerDefersStatusBarOutsideWorkspace() {
        let controller = SpyYabrPDFViewController()
        let nav = makeReaderNavigationController(presentationID: nil, root: controller)

        nav.setNavigationBarHidden(true, animated: false)
        XCTAssertTrue(nav.childForStatusBarStyle === controller)
    }

    private func makeReaderNavigationController(presentationID: UUID?, root: UIViewController) -> YabrEBookReaderNavigationController {
        let nav = YabrEBookReaderNavigationController(
            container: MockAppContainerFactory.makeContainer(testName: "YabrPDFViewControllerTests-statusBar"),
            book: TestFixtures.makeBook(),
            readerInfo: ReaderInfo(
                deviceName: "test-device",
                url: URL(fileURLWithPath: "/tmp/test.pdf"),
                missing: false,
                format: .PDF,
                readerType: .YabrPDF,
                position: BookDeviceReadingPosition(readerName: ReaderType.YabrPDF.id)
            ),
            presentationID: presentationID,
            lifecycleEvents: { AsyncStream { $0.finish() } }
        )
        nav.viewControllers = [root]
        return nav
    }

    func testPresentedSheetsUseReaderTheme() {
        let controller = SpyYabrPDFViewController()
        controller.pdfOptions = PDFPreferenceValue(themeMode: .forest)
        let root = UIViewController()

        let nav = controller.themedNavigationController(rootViewController: root)

        XCTAssertTrue(nav.viewControllers.first === root)
        XCTAssertEqual(root.navigationItem.standardAppearance?.backgroundColor?.cgColor.components, controller.pdfOptions.fillColor.components)
        // FolioReader's sheets: accent bar buttons, titles in the theme's text colour.
        let style = controller.pdfOptions.themePalette.listStyle
        XCTAssertEqual(nav.navigationBar.tintColor, style.accent)
        XCTAssertEqual(root.navigationItem.standardAppearance?.titleTextAttributes[.foregroundColor] as? UIColor, style.text)
        XCTAssertEqual(nav.overrideUserInterfaceStyle, .light)
    }

    /// Search is its own sheet, opened from the nav bar as in FolioReader, and it
    /// keeps its query and results between presentations.
    func testSearchHasItsOwnButtonAndKeepsItsState() throws {
        let pdfURL = try makePDFURL(name: "search-button", pageCount: 2)
        let controller = SpyYabrPDFViewController()
        let metaSource = MockYabrPDFMetaSource(pdfURL: pdfURL)
        controller.yabrPDFMetaSource = metaSource
        XCTAssertEqual(controller.open(), 0)
        controller.loadViewIfNeeded()

        let left = try XCTUnwrap(controller.navigationItem.leftBarButtonItems)
        XCTAssertEqual(left.map(\.title), ["Navigations", "Annotations", "Search"])
        XCTAssertEqual(left.last?.image, UIImage(systemName: "magnifyingglass"))

        controller.presentSearch()
        let nav = try XCTUnwrap(controller.capturedPresentedViewController as? UINavigationController)
        XCTAssertTrue(nav.viewControllers.first === controller.searchList)
        XCTAssertEqual(controller.searchList.title, "Search")
        XCTAssertNotNil(controller.searchList.navigationItem.leftBarButtonItem, "Close")
        XCTAssertTrue(controller.searchList.pdfViewController === controller, "works without a page VC parent")
        XCTAssertTrue((controller.searchList.yabrPDFMetaSource as AnyObject?) === metaSource)

        controller.searchList.searchBar.text = "Page"
        controller.searchList.currentQuery = "Page"
        nav.viewControllers = []
        controller.presentSearch()
        let reopened = try XCTUnwrap(controller.capturedPresentedViewController as? UINavigationController)
        XCTAssertTrue(reopened.viewControllers.first === controller.searchList, "the same list")
        XCTAssertEqual(controller.searchList.searchBar.text, "Page")
        XCTAssertEqual(controller.searchList.currentQuery, "Page")
    }

    /// As FolioReader's history: newest first, one entry per query regardless
    /// of case and diacritics, at most 100.
    func testSearchHistory() {
        var history = PDFSearchHistory()
        history.record("Boolean")
        history.record("  index ")
        history.record("café")
        history.record("CAFE")
        history.record("   ")
        XCTAssertEqual(history.queries, ["CAFE", "index", "Boolean"])

        history.remove("index")
        XCTAssertEqual(history.queries, ["CAFE", "Boolean"])

        (0..<120).forEach { history.record("q\($0)") }
        XCTAssertEqual(history.queries.count, PDFSearchHistory.maxCount)
        XCTAssertEqual(history.queries.first, "q119")
    }

    /// An empty search bar lists this session's searches; picking one searches
    /// it again; opening a result records its query. The history lives with
    /// the reader's search list, so reopening the sheet keeps it.
    func testSearchListShowsHistoryWhenEmpty() throws {
        let controller = SpyYabrPDFViewController()
        controller.yabrPDFMetaSource = MockYabrPDFMetaSource(pdfURL: try makePDFURL(name: "search-history", pageCount: 1))
        XCTAssertEqual(controller.open(), 0)
        let list = controller.searchList
        list.loadViewIfNeeded()
        XCTAssertTrue(list.history.isEmpty, "nothing carried over from earlier sessions")

        list.currentQuery = "inverted index"
        list.recordCurrentQuery()
        list.currentQuery = "posting"
        list.recordCurrentQuery()
        list.currentQuery = ""
        list.tableView.reloadData()

        XCTAssertTrue(list.isShowingHistory)
        XCTAssertEqual(list.tableView(list.tableView, numberOfRowsInSection: 0), 2)
        let first = list.tableView(list.tableView, cellForRowAt: IndexPath(row: 0, section: 0))
        XCTAssertEqual((first.contentConfiguration as? UIListContentConfiguration)?.text, "posting")

        list.tableView(list.tableView, didSelectRowAt: IndexPath(row: 1, section: 0))
        XCTAssertEqual(list.searchBar.text, "inverted index")
        XCTAssertEqual(list.currentQuery, "inverted index")
        XCTAssertFalse(list.isShowingHistory)

        controller.presentSearch()
        XCTAssertEqual(controller.searchList.history, ["posting", "inverted index"])
    }

    /// The search list outlives its sheets, so a theme changed in between is
    /// applied when it is shown again.
    func testKeptSearchListFollowsThemeChanges() throws {
        let controller = SpyYabrPDFViewController()
        controller.yabrPDFMetaSource = MockYabrPDFMetaSource(pdfURL: try makePDFURL(name: "search-theme", pageCount: 1))
        XCTAssertEqual(controller.open(), 0)
        controller.pdfOptions = PDFPreferenceValue(themeMode: .none)
        let list = controller.searchList
        list.loadViewIfNeeded()
        list.viewWillAppear(false)
        let light = PDFThemePalette(themeMode: .none).listStyle
        XCTAssertEqual(list.searchBar.searchTextField.textColor, light.text)

        var options = controller.pdfOptions
        options.themeMode = .dark
        controller.pdfOptions = options
        controller.presentSearch()
        list.viewWillAppear(false)

        let dark = PDFThemePalette(themeMode: .dark).listStyle
        XCTAssertEqual(list.searchBar.searchTextField.textColor, dark.text)
        XCTAssertEqual(list.tableView.backgroundColor, dark.background)
        XCTAssertEqual(list.searchBar.barTintColor, dark.background)
        XCTAssertEqual(list.tableView.separatorColor, dark.separator)
    }

    func testAnnotationsSheetHasNoSearchTab() {
        let controller = SpyYabrPDFViewController()
        controller.yabrPDFMetaSource = MockYabrPDFMetaSource(pdfURL: nil)
        let annotations = YabrPDFAnnotationPageVC()
        annotations.pdfViewController = controller
        annotations.yabrPDFMetaSource = controller.yabrPDFMetaSource
        annotations.loadViewIfNeeded()

        XCTAssertEqual(annotations.segmentedControlItems, ["Bookmark", "Highlight"])
        XCTAssertFalse(annotations.viewList.contains { $0 is YabrPDFSearchList })
    }

    /// A chapter's first page belongs to that chapter only; the last chapter and
    /// pages before the first chapter do not index past the outline list.
    func testCurrentChapterIsUniqueAtChapterBoundaries() {
        let starts: [Int?] = [31, 38, 40]
        XCTAssertEqual(YabrPDFChapterList.currentIndex(startPages: starts, currentPage: 38), 1)
        XCTAssertEqual(YabrPDFChapterList.currentIndex(startPages: starts, currentPage: 39), 1)
        XCTAssertEqual(YabrPDFChapterList.currentIndex(startPages: starts, currentPage: 37), 0)
        XCTAssertEqual(YabrPDFChapterList.currentIndex(startPages: starts, currentPage: 581), 2)
        XCTAssertNil(YabrPDFChapterList.currentIndex(startPages: starts, currentPage: 30))
        XCTAssertNil(YabrPDFChapterList.currentIndex(startPages: [], currentPage: 1))
        XCTAssertEqual(YabrPDFChapterList.currentIndex(startPages: [nil, 10, 20], currentPage: 15), 1, "outlines without a page are skipped")
        XCTAssertEqual(YabrPDFChapterList.currentIndex(startPages: [10, 10, 20], currentPage: 10), 1, "the deepest of outlines on the same page")
    }

    func testChapterCellMarksCurrentInAccentAndIndentsByLevel() {
        let style = PDFThemePalette(themeMode: .serpia).listStyle
        let cell = YabrPDFChapterListCell(style: .default, reuseIdentifier: nil)

        cell.configure(title: "Boolean retrieval", page: 38, level: 0, isCurrent: true, style: style)
        XCTAssertEqual(cell.indexLabel.textColor, style.accent)
        XCTAssertEqual(cell.pageLabel.text, "p. 38")
        XCTAssertEqual(cell.indexLeadingConstraint.constant, YabrPDFChapterListCell.baseIndent)
        XCTAssertNil(cell.contentView.backgroundColor, "no row background, as in FolioReader")

        cell.configure(title: "An example", page: 40, level: 2, isCurrent: false, style: style)
        XCTAssertEqual(cell.indexLabel.textColor, style.text)
        XCTAssertEqual(cell.indexLeadingConstraint.constant, YabrPDFChapterListCell.baseIndent + 2 * YabrPDFChapterListCell.indentPerLevel)
        XCTAssertEqual(cell.indexLabel.font.pointSize, 14)
    }

    /// Under dark a listed highlight uses the page's dim fill, so its text stays
    /// readable; rows grow with the text and the note.
    func testHighlightCellIsReadableAndSelfSizing() throws {
        let style = PDFThemePalette(themeMode: .dark).listStyle
        let fill = style.highlightFill(.yellow)
        XCTAssertEqual(components(fill, style: .dark).3, PDFHighlightAnnotations.darkFillAlpha, accuracy: 0.01)
        let fillOverSheet = UIColor(
            red: components(fill, style: .dark).0 * PDFHighlightAnnotations.darkFillAlpha + components(style.background, style: .dark).0 * (1 - PDFHighlightAnnotations.darkFillAlpha),
            green: components(fill, style: .dark).1 * PDFHighlightAnnotations.darkFillAlpha + components(style.background, style: .dark).1 * (1 - PDFHighlightAnnotations.darkFillAlpha),
            blue: components(fill, style: .dark).2 * PDFHighlightAnnotations.darkFillAlpha + components(style.background, style: .dark).2 * (1 - PDFHighlightAnnotations.darkFillAlpha),
            alpha: 1
        )
        XCTAssertGreaterThanOrEqual(contrast(style.highlightText, fillOverSheet, style: .dark), 4.5)

        let cell = YabrPDFHighlightListCell(style: .default, reuseIdentifier: nil)
        func height(_ highlight: PDFHighlight) -> CGFloat {
            cell.configure(highlight: highlight, date: "TODAY", style: style)
            return cell.contentView.systemLayoutSizeFitting(
                CGSize(width: 400, height: 0),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
        }
        let short = PDFHighlight(uuid: UUID(), pos: [], type: BookHighlightStyle.yellow.rawValue, content: "Short", note: nil, date: Date())
        var long = short
        long.content = String(repeating: "A long highlighted passage that wraps. ", count: 8)
        let shortHeight = height(short)
        XCTAssertTrue(cell.noteLabel.isHidden)
        let longHeight = height(long)
        XCTAssertGreaterThan(longHeight, shortHeight + 40, "the whole passage shows")
        long.note = "A thought"
        XCTAssertGreaterThan(height(long), longHeight)
        XCTAssertFalse(cell.noteLabel.isHidden)
        let attributes = cell.highlightLabel.attributedText?.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual(attributes?[.backgroundColor] as? UIColor, fill)
    }

    /// Thumbnails look like the page: inverted under dark, tinted to the theme
    /// colour under sepia and forest.
    func testThumbnailRendersLikeThePage() throws {
        let document = try XCTUnwrap(PDFDocument(url: makePDFURL(name: "thumbnail", pageCount: 1)))
        let page = try XCTUnwrap(document.page(at: 0))
        /// The blank bottom-right corner, 0...255 per channel.
        func corner(_ image: UIImage) throws -> (Int, Int, Int) {
            let cgImage = try XCTUnwrap(image.cgImage)
            var pixel = [UInt8](repeating: 0, count: 4)
            let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: -CGFloat(cgImage.width) + 4, y: -2, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
            return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
        }
        func render(_ theme: PDFThemeMode) throws -> (Int, Int, Int) {
            try corner(YabrPDFThumbnailList.renderThumbnail(of: page, size: CGSize(width: 90, height: 120), palette: PDFThemePalette(themeMode: theme)))
        }
        let none = try render(.none)
        XCTAssertGreaterThan(min(none.0, none.1, none.2), 240)
        let dark = try render(.dark)
        XCTAssertLessThan(max(dark.0, dark.1, dark.2), 20)
        for theme in [PDFThemeMode.serpia, .forest] {
            let tinted = try render(theme)
            let background = try XCTUnwrap(PDFThemePalette(themeMode: theme).background.components)
            XCTAssertEqual(Double(tinted.0), Double(background[0] * 255), accuracy: 3, "\(theme) \(tinted)")
            XCTAssertEqual(Double(tinted.1), Double(background[1] * 255), accuracy: 3, "\(theme) \(tinted)")
            XCTAssertEqual(Double(tinted.2), Double(background[2] * 255), accuracy: 3, "\(theme) \(tinted)")
        }
    }

    func testApplyPreferencesMapsReaderEnginePreferencesToPDFOptions() {
        let controller = SpyYabrPDFViewController()
        let preferences = ReaderEnginePreferences(themeMode: 3, scroll: true, scrollDirection: 1)

        controller.applyPreferences(preferences)

        XCTAssertEqual(controller.pdfOptions.themeMode, .dark)
        XCTAssertEqual(controller.pdfOptions.pageMode, .Scroll)
        XCTAssertEqual(controller.pdfOptions.scrollDirection, .Horizontal)
    }

    func testPDFPreferenceValueRoundTripAndReaderEngineMapping() {
        let realmObject = PDFOptions()
        realmObject.themeMode = .dark
        realmObject.selectedAutoScaler = .Custom
        realmObject.pageMode = .Scroll
        realmObject.readingDirection = .TtB_RtL
        realmObject.scrollDirection = .Horizontal
        realmObject.hMarginAutoScaler = 11
        realmObject.vMarginAutoScaler = 12
        realmObject.hMarginDetectStrength = 4
        realmObject.vMarginDetectStrength = 5
        realmObject.marginOffset = 3
        realmObject.lastScale = 2.2
        realmObject.rememberInPagePosition = false

        let value = realmObject.toValue()
        XCTAssertEqual(value.fillColor.components, CGColor(gray: 0.0, alpha: 1.0).components)
        XCTAssertTrue(value.isDark)
        XCTAssertEqual(value.isDark("dark", "light"), "dark")

        let engine = value.toReaderEnginePreferences()
        XCTAssertEqual(engine.themeMode, 3)
        XCTAssertEqual(engine.scroll, true)
        XCTAssertEqual(engine.scrollDirection, 1)

        let copied = PDFOptions()
        copied.apply(value)
        XCTAssertEqual(copied.toValue(), value)

        var updated = PDFPreferenceValue()
        updated.apply(ReaderEnginePreferences(themeMode: 1, scroll: true, scrollDirection: 1))
        XCTAssertEqual(updated.themeMode, .serpia)
        XCTAssertEqual(updated.pageMode, .Scroll)
        XCTAssertEqual(updated.scrollDirection, .Horizontal)

        updated.apply(ReaderEnginePreferences(themeMode: 2))
        XCTAssertEqual(updated.themeMode, .forest)

        updated.apply(ReaderEnginePreferences(themeMode: 4))
        XCTAssertEqual(updated.themeMode, .dark)
    }

    func testPDFOptionViewModelCommitTriggersSingleCallback() {
        var callbackValues: [PDFPreferenceValue] = []
        let model = PDFOptionViewModel(
            preferences: PDFPreferenceValue(),
            onPreferencesChanged: { callbackValues.append($0) }
        )

        model.preferences.themeMode = .dark
        model.preferences.pageMode = .Scroll
        model.preferences.scrollDirection = .Horizontal
        model.commit()

        XCTAssertEqual(callbackValues.count, 1)
        XCTAssertEqual(callbackValues.first, model.preferences)
    }

    func testSelectionMenuWithoutDictViewerOffersHighlightAndUnderline() {
        let controller = SpyYabrPDFViewController()
        controller.yabrPDFMetaSource = MockYabrPDFMetaSource(pdfURL: nil, dictViewer: nil)

        let elements = controller.menuManager.selectionMenuElements().compactMap { $0 as? UIAction }

        XCTAssertEqual(elements.map(\.identifier), [PDFMenuManager.ActionID.highlight, PDFMenuManager.ActionID.underline, PDFMenuManager.ActionID.note])
        XCTAssertEqual(elements.map(\.title), ["Highlight", "Underline", "Note"])
        XCTAssertTrue(elements.allSatisfy { $0.image != nil })
    }

    func testSelectionMenuWithDictViewerIncludesDictionaryAction() {
        let controller = SpyYabrPDFViewController()
        let dictViewer = UINavigationController(rootViewController: UIViewController())
        controller.yabrPDFMetaSource = MockYabrPDFMetaSource(pdfURL: nil, dictViewer: ("MDict", dictViewer))

        let elements = controller.menuManager.selectionMenuElements().compactMap { $0 as? UIAction }

        XCTAssertEqual(elements.map(\.identifier), [PDFMenuManager.ActionID.highlight, PDFMenuManager.ActionID.underline, PDFMenuManager.ActionID.note, PDFMenuManager.ActionID.dictionary])
        XCTAssertEqual(elements.last?.title, "MDict")
    }

    func testNoteEditorSavesTrimmedTextAndCancelSavesNothing() {
        var saved: [String?] = []
        let editor = YabrPDFNoteEditorViewController(quote: "Quoted text", style: .green, note: nil)
        editor.onSave = { saved.append($0) }
        editor.loadViewIfNeeded()

        XCTAssertEqual(editor.quote, "Quoted text")
        XCTAssertFalse(editor.isModalInPresentation, "nothing to lose yet")
        editor.textView.text = "  a note \n"
        editor.textViewDidChange(editor.textView)
        XCTAssertTrue(editor.isModalInPresentation, "edited text is not swiped away")

        editor.save()
        XCTAssertEqual(saved, ["a note"])

        let cancelled = YabrPDFNoteEditorViewController(quote: "Q", style: .yellow, note: "old")
        cancelled.onSave = { saved.append($0) }
        cancelled.loadViewIfNeeded()
        XCTAssertEqual(cancelled.textView.text, "old")
        cancelled.textView.text = "changed"
        cancelled.cancel()
        XCTAssertEqual(saved, ["a note"], "cancel saves nothing")

        let cleared = YabrPDFNoteEditorViewController(quote: "Q", style: .yellow, note: "old")
        cleared.onSave = { saved.append($0) }
        cleared.loadViewIfNeeded()
        cleared.textView.text = "  "
        cleared.save()
        XCTAssertEqual(saved, ["a note", nil], "blank clears the note")
    }

    /// Under dark the quote is marked like the dark page marks it (a dim fill
    /// under primary text), and the sheet is raised off the black page.
    func testNoteEditorUnderDarkKeepsQuoteReadableAndSheetDistinct() throws {
        let palette = PDFThemePalette(themeMode: .dark)
        let editor = YabrPDFNoteEditorViewController(quote: "Quoted text", style: .yellow, note: nil, palette: palette)
        editor.loadViewIfNeeded()
        let dark = UITraitCollection(userInterfaceStyle: .dark)

        let attributes = editor.quotedText().attributes(at: 0, effectiveRange: nil)
        let fill = try XCTUnwrap(attributes[.backgroundColor] as? UIColor)
        XCTAssertEqual(fill.cgColor.alpha, PDFHighlightAnnotations.darkFillAlpha, accuracy: 0.01, "dim, like the page")
        let text = try XCTUnwrap(attributes[.foregroundColor] as? UIColor)
        XCTAssertEqual(text.resolvedColor(with: dark), UIColor.label.resolvedColor(with: dark))

        let sheet = try XCTUnwrap(editor.view.backgroundColor)
        XCTAssertEqual(sheet, palette.sheetBackground)
        var white: CGFloat = 0
        sheet.getWhite(&white, alpha: nil)
        XCTAssertGreaterThan(white, 0.05, "not the page's black")
        XCTAssertEqual(editor.navigationItem.standardAppearance?.backgroundColor, sheet, "the bar matches the sheet")

        // Light themes keep the page colour and the full-strength mark.
        let sepia = YabrPDFNoteEditorViewController(quote: "Q", style: .yellow, note: nil, palette: PDFThemePalette(themeMode: .serpia))
        sepia.loadViewIfNeeded()
        XCTAssertEqual(sepia.view.backgroundColor?.cgColor.components, PDFThemePalette(themeMode: .serpia).background.components)
        let sepiaFill = try XCTUnwrap(sepia.quotedText().attributes(at: 0, effectiveRange: nil)[.backgroundColor] as? UIColor)
        XCTAssertEqual(sepiaFill.cgColor.alpha, 1, accuracy: 0.01)
    }

    func testHighlightListSwipeOffersNoteAndDeletesThroughAnnotationManager() throws {
        let controller = SpyYabrPDFViewController()
        let metaSource = MockYabrPDFMetaSource(pdfURL: nil)
        let highlight = PDFHighlight(
            uuid: UUID(),
            pos: [PDFHighlight.PageLocation(page: 1, ranges: [NSRange(location: 0, length: 4)])],
            type: BookHighlightStyle.yellow.rawValue,
            content: "Text",
            note: "noted",
            date: Date()
        )
        metaSource.highlightsValue = [highlight]
        controller.yabrPDFMetaSource = metaSource
        let spy = HighlightRemovalSpy()
        controller.annotationManager.delegate = spy

        let page = YabrPDFAnnotationPageVC()
        page.pdfViewController = controller
        page.yabrPDFMetaSource = metaSource
        page.loadViewIfNeeded()
        let list = page.highlightViewController
        page.setViewControllers([list], direction: .forward, animated: false)
        list.loadViewIfNeeded()

        let configuration = try XCTUnwrap(list.tableView(list.tableView, trailingSwipeActionsConfigurationForRowAt: IndexPath(row: 0, section: 0)))
        XCTAssertEqual(configuration.actions.map(\.title), ["Delete", "Edit Note"])
        XCTAssertEqual(configuration.actions.first?.style, .destructive)

        let delete = try XCTUnwrap(configuration.actions.first)
        var completed: Bool?
        delete.handler(delete, UIView()) { completed = $0 }
        XCTAssertEqual(spy.removed, [highlight.uuid.uuidString], "persisted removal goes through the annotation manager")
        XCTAssertEqual(completed, true)
    }

    func testSurfaceHostsTheActivePageViewAndRelaysItsNotifications() {
        let controller = SpyYabrPDFViewController()
        controller.loadViewIfNeeded()
        XCTAssertTrue(controller.pdfView === controller.surface.activeView)
        XCTAssertTrue(controller.pdfView.superview === controller.surface)
        XCTAssertTrue(controller.surface.superview === controller.view)

        let relayedNames: [Notification.Name] = [.readerSurfacePageChanged, .readerSurfaceScaleChanged, .readerSurfaceDisplayBoxChanged]
        var relayed: [Notification.Name] = []
        let observers = relayedNames.map { name in
            NotificationCenter.default.addObserver(forName: name, object: controller.surface, queue: nil) { relayed.append($0.name) }
        }
        defer { observers.forEach(NotificationCenter.default.removeObserver) }

        for name in [Notification.Name.PDFViewPageChanged, .PDFViewScaleChanged, .PDFViewDisplayBoxChanged] {
            NotificationCenter.default.post(name: name, object: controller.pdfView)
        }
        NotificationCenter.default.post(name: .PDFViewPageChanged, object: controller.pdfViewAux)

        XCTAssertEqual(relayed, relayedNames, "only the active page view's notifications are relayed")
    }

    func testEditMenuInteractionIsInstalledOnSurface() {
        let controller = SpyYabrPDFViewController()
        controller.loadViewIfNeeded()

        let interactions = controller.surface.interactions.compactMap { $0 as? UIEditMenuInteraction }
        XCTAssertTrue(interactions.contains { $0.delegate === controller.menuManager })
    }

    func testHandleScaleChangeUpdatesLastScale() throws {
        let controller = SpyYabrPDFViewController()
        let pdfURL = try makePDFURL(name: "scale-change", pageCount: 1)
        let metaSource = MockYabrPDFMetaSource(pdfURL: pdfURL)
        controller.yabrPDFMetaSource = metaSource
        controller.pdfView.document = PDFDocument(url: pdfURL)
        controller.pdfView.minScaleFactor = 1.0
        controller.pdfView.maxScaleFactor = 4.0
        controller.pdfOptions.lastScale = 1.0
        let updateCallCountBefore = metaSource.updateCallCount
        controller.pdfView.scaleFactor = 2.25

        controller.handleScaleChange(nil)

        XCTAssertEqual(controller.pdfOptions.lastScale, 2.25, accuracy: 0.0001)
        XCTAssertEqual(metaSource.optionsValue.lastScale, 2.25, accuracy: 0.0001)
        XCTAssertEqual(metaSource.updateCallCount, updateCallCountBefore + 1)
    }

    func testPDFMetaSourceLoadsPreferencesFromRepositoryAndPersistsUpdates() {
        let book = TestFixtures.makeBook()
        let repository = MockPDFPreferenceRepository()
        repository.loadedPDFPreferences = PDFPreferenceValue(themeMode: .dark, pageMode: .Scroll, lastScale: 1.4)
        let metaSource = YabrEBookReaderPDFMetaSource(
            book: book,
            readerInfo: ReaderInfo(
                deviceName: "test-device",
                url: URL(fileURLWithPath: "/tmp/test.pdf"),
                missing: false,
                format: .PDF,
                readerType: .YabrPDF,
                position: BookDeviceReadingPosition(readerName: ReaderType.YabrPDF.id)
            ),
            preferenceRepository: repository
        )

        XCTAssertEqual(metaSource.yabrPDFOptions(nil)?.themeMode, .dark)
        XCTAssertTrue(repository.savedPDFPreferences.isEmpty)

        let updated = PDFPreferenceValue(themeMode: .forest, pageMode: .Page, lastScale: 2.0)
        metaSource.yabrPDFOptions(nil, update: updated)

        XCTAssertEqual(repository.savedPDFPreferences.last, updated)
    }

    func testPDFMetaSourceCreatesDefaultPreferencesWhenRepositoryIsEmpty() {
        let book = TestFixtures.makeBook()
        let repository = MockPDFPreferenceRepository()

        let metaSource = YabrEBookReaderPDFMetaSource(
            book: book,
            readerInfo: ReaderInfo(
                deviceName: "test-device",
                url: URL(fileURLWithPath: "/tmp/test.pdf"),
                missing: false,
                format: .PDF,
                readerType: .YabrPDF,
                position: BookDeviceReadingPosition(readerName: ReaderType.YabrPDF.id)
            ),
            preferenceRepository: repository
        )

        XCTAssertEqual(metaSource.yabrPDFOptions(nil), PDFPreferenceValue())
        XCTAssertEqual(repository.savedPDFPreferences, [PDFPreferenceValue()])
    }

    /// Highlights are saved under the id they are read back with (the book's
    /// annotation id), not the shelf identity, or the highlight list and the next
    /// open never see them.
    func testHighlightsAreSavedUnderTheAnnotationBookId() throws {
        let controller = YabrPDFViewController()
        controller.yabrPDFMetaSource = MockYabrPDFMetaSource(pdfURL: nil, key: "shelf-key")
        XCTAssertEqual(controller.annotationManager.bookId, "pref-shelf-key")
    }

    func testSharePDFOriginalCreatesTemporaryFileAndPresentsActivityController() throws {
        let pdfURL = try makePDFURL(name: "share-original", pageCount: 1)
        let controller = SpyYabrPDFViewController()
        controller.yabrPDFMetaSource = MockYabrPDFMetaSource(
            pdfURL: pdfURL,
            title: "Share Book",
            author: "Tester",
            key: "share-original-key"
        )

        controller.sharePDF(annotated: false)

        let tmpFile = expectedSharedPDFURL(bookKey: "share-original-key", title: "Share Book", author: "Tester")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpFile.path))
        XCTAssertTrue(controller.capturedPresentedViewController is UIActivityViewController)
    }

    func testSharePDFAnnotatedWritesPDF() throws {
        let pdfURL = try makePDFURL(name: "share-annotated", pageCount: 1)
        let controller = SpyYabrPDFViewController()
        controller.yabrPDFMetaSource = MockYabrPDFMetaSource(
            pdfURL: pdfURL,
            title: "Annotated Book",
            author: "Tester",
            key: "share-annotated-key"
        )
        controller.pdfView.document = PDFDocument(url: pdfURL)

        controller.sharePDF(annotated: true)

        let tmpFile = expectedSharedPDFURL(bookKey: "share-annotated-key", title: "Annotated Book", author: "Tester")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpFile.path))
        XCTAssertTrue(controller.capturedPresentedViewController is UIActivityViewController)
    }

    private func makePDFURL(name: String, pageCount: Int) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).pdf")

        let document = PDFDocument()
        for index in 0..<pageCount {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 160)).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 120, height: 160))
                let text = "Page \(index + 1)"
                text.draw(at: CGPoint(x: 12, y: 12), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 18),
                    .foregroundColor: UIColor.black
                ])
            }
            guard let page = PDFPage(image: image) else {
                XCTFail("Unable to create PDF page")
                continue
            }
            document.insert(page, at: index)
        }

        XCTAssertTrue(document.write(to: url))
        tempURLs.append(url)
        return url
    }

    private func expectedSharedPDFURL(bookKey: String, title: String, author: String) -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(bookKey, isDirectory: true)
        tempURLs.append(directory.appendingPathComponent("\(title) - \(author).pdf"))
        return directory.appendingPathComponent("\(title) - \(author).pdf")
    }
}

@available(iOS 16.0, macCatalyst 16.0, *)
private final class SpyYabrPDFViewController: YabrPDFViewController {
    private(set) var capturedPresentedViewController: UIViewController?

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        capturedPresentedViewController = viewControllerToPresent
        completion?()
    }
}

@available(iOS 16.0, macCatalyst 16.0, *)
private final class MockYabrPDFMetaSource: YabrPDFMetaSource {
    private let pdfURLValue: URL?
    private let title: String
    private let author: String
    private let key: String
    private let dictViewerValue: (String, UINavigationController)?
    private(set) var optionsValue: PDFPreferenceValue
    private(set) var updateCallCount = 0

    init(
        pdfURL: URL?,
        title: String = "Test Title",
        author: String = "Test Author",
        key: String = "test-key",
        dictViewer: (String, UINavigationController)? = nil,
        options: PDFPreferenceValue = PDFPreferenceValue()
    ) {
        self.pdfURLValue = pdfURL
        self.title = title
        self.author = author
        self.key = key
        self.dictViewerValue = dictViewer
        self.optionsValue = options
    }

    func yabrPDFBook(_ view: YabrPDFView?, info: String) -> String? {
        switch info {
        case "Title":
            return title
        case "Author":
            return author
        case "Key":
            return key
        case "PrefId":
            return "pref-\(key)"
        default:
            return nil
        }
    }

    func yabrPDFURL(_ view: YabrPDFView?) -> URL? {
        pdfURLValue
    }

    func yabrPDFDocument(_ view: YabrPDFView?) -> PDFDocument? {
        view?.document
    }

    func yabrPDFNavigate(_ view: YabrPDFView?, pageNumber: Int, offset: CGPoint) {
    }

    func yabrPDFNavigate(_ view: YabrPDFView?, destination: PDFDestination) {
    }

    func yabrPDFOutline(_ view: YabrPDFView?, for page: Int) -> PDFOutline? {
        nil
    }

    func yabrPDFOptions(_ view: YabrPDFView?) -> PDFPreferenceValue? {
        optionsValue
    }

    func yabrPDFOptions(_ view: YabrPDFView?, update options: PDFPreferenceValue) {
        updateCallCount += 1
        optionsValue = options
    }

    func yabrPDFDictViewer(_ view: YabrPDFView?) -> (String, UINavigationController)? {
        dictViewerValue
    }

    func yabrPDFBookmarks(_ view: YabrPDFView?) -> [PDFBookmark] {
        []
    }

    func yabrPDFBookmarks(_ view: YabrPDFView?, update bookmark: PDFBookmark) {
    }

    func yabrPDFBookmarks(_ view: YabrPDFView?, remove bookmark: PDFBookmark) {
    }

    var highlightsValue: [PDFHighlight] = []

    func yabrPDFHighlights(_ view: YabrPDFView?) -> [PDFHighlight] {
        highlightsValue
    }

    func yabrPDFHighlights(_ view: YabrPDFView?, getById highlightId: UUID) -> PDFHighlight? {
        nil
    }

    func yabrPDFHighlights(_ view: YabrPDFView?, update highlight: PDFHighlight) {
    }

    func yabrPDFHighlights(_ view: YabrPDFView?, remove highlight: PDFHighlight) {
    }

    func yabrPDFReferenceText(_ view: YabrPDFView?) -> String? {
        nil
    }

    func yabrPDFReferenceText(_ view: YabrPDFView?, set refText: String?) {
    }

    func yabrPDFOptionsIsNight<T>(_ view: YabrPDFView?, _ f: T, _ l: T) -> T {
        optionsValue.isDark(f, l)
    }
}

private final class MockPDFPreferenceRepository: ReaderPreferenceRepositoryProtocol {
    var loadedPDFPreferences: PDFPreferenceValue?
    var savedPDFPreferences: [PDFPreferenceValue] = []

    func loadInitialPreferences(for book: CalibreBook, readerType: ReaderType) -> ReaderEnginePreferences? {
        nil
    }

    func savePreferences(_ preferences: ReaderEnginePreferences, for book: CalibreBook, readerType: ReaderType) {
    }

    func loadFolioPreferences(for book: CalibreBook) -> FolioReaderPreferenceValue? {
        nil
    }

    func saveFolioPreferences(_ preferences: FolioReaderPreferenceValue, for book: CalibreBook) {
    }

    func loadReadiumPreferences(for book: CalibreBook) -> ReadiumPreferenceValue? {
        nil
    }

    func saveReadiumPreferences(_ preferences: ReadiumPreferenceValue, for book: CalibreBook) {
    }

    func loadPDFPreferences(for book: CalibreBook) -> PDFPreferenceValue? {
        loadedPDFPreferences
    }

    func savePDFPreferences(_ preferences: PDFPreferenceValue, for book: CalibreBook) {
        savedPDFPreferences.append(preferences)
    }
}

private final class HighlightRemovalSpy: ReaderEngineDelegate {
    private(set) var removed: [String] = []
    func readerEngine(_ engine: AnyObject, didUpdatePosition position: ReaderEnginePosition) {}
    func readerEngine(_ engine: AnyObject, didAddHighlight highlight: ReaderEngineHighlight) {}
    func readerEngine(_ engine: AnyObject, didRemoveHighlight highlightId: String) {
        removed.append(highlightId)
    }
    func readerEngine(_ engine: AnyObject, didUpdatePreferences prefs: ReaderEnginePreferences) {}
}
