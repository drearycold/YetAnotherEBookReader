import XCTest

final class YetAnotherEBookReaderUITests: XCTestCase {
    private enum AccessibilityID {
        static let recentScreen = "screen.recent"
        static let discoverScreen = "screen.discover"
        static let browseScreen = "screen.browse"
        static let settingsScreen = "screen.settings"
        static let browseBookListScreen = "screen.browse.book-list"
        static let bookDetailScreen = "screen.book-detail"

        static let recentBook = "shelf.book.mock"
        static let recentBookOptions = "shelf.book.options.mock"
        static let recentBookDetails = "shelf.book.details.mock"
        static let browseLibrary = "browse.library.ui-test"
        static let browseBook = "browse.book.mock"
        static let browseBookAlpha = "browse.book.2"
        static let browseBookBeta = "browse.book.3"
        static let browseSearchField = "browse.search.field"
        static let browseSearchClear = "browse.search.clear"
        static let browseNoResults = "browse.no-results"
        static let browseSortMenu = "browse.sort.menu"
        static let browseSortTitle = "browse.sort.title"
        static let browseBatchMode = "browse.batch.mode"
        static let browseSelectionToolbar = "browse.selection.toolbar"
        static let browseSelectionSelectAll = "browse.selection.select-all"
        static let browseSelectionDownload = "browse.selection.download"
        static let browseSelectionClear = "browse.selection.clear"
        static let browseSelectionCancel = "browse.selection.cancel"
        static let browseBatchSheet = "browse.batch.sheet"
        static let browseBatchSheetFormatEPUB = "browse.batch.sheet.format.epub"
        static let browseBatchSheetSummary = "browse.batch.sheet.summary"
        static let browseBatchSheetCancel = "browse.batch.sheet.cancel"
        static let browseCategoryAuthors = "browse.category.authors"
        static let browseCategoryTags = "browse.category.tags"
        static let browseCategorySeries = "browse.category.series"
        static let browseCategoryAuthorsPage = "browse.category.authors.page"
        static let browseCategoryTagsPage = "browse.category.tags.page"
        static let browseCategorySeriesPage = "browse.category.series.page"
        static let browseCategoryAuthorsAlpha = "browse.category.authors.item.alpha-author"
        static let browseCategoryTagsAlpha = "browse.category.tags.item.alpha-tag"
        static let browseCategoryTagsBeta = "browse.category.tags.item.beta-tag"
        static let browseCategorySeriesMock = "browse.category.series.item.mock-series"
        static let browseCategorySeriesAlpha = "browse.category.series.item.alpha-series"
        static let browseCategorySeriesBeta = "browse.category.series.item.beta-series"
        static let browseCategorySeriesSearch = "browse.category.series.search"
        static let browseCategorySeriesClear = "browse.category.series.clear"
        static let browseCategoryMenu = "browse.category.menu"
        static let browseCategoryMenuTags = "browse.category.menu.tags"
        static let browseCategoryTagsDone = "browse.category.tags.done"
        static let browseFilterClear = "browse.filter.clear"
        static let browseFilterRemoveTagsAlpha = "browse.filter.remove.tags.alpha-tag"
        static let settingsServer = "settings.server.ui-test"
        static let closeBookDetail = "book-detail.close"
        static let bookDetailTitle = "book-detail.title"
        static let readerFolioScreen = "reader.folio.screen"
        static let readerFolioContent = "reader.folio.content"
        static let readerFolioPosition = "reader.folio.position"
        static let readerFolioClose = "reader.folio.close"
    }

    private let waitTimeout: TimeInterval = 10
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()

        app = XCUIApplication()
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing-mock-library"]
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testLaunchSmokeNavigatesAcrossMainTabs() throws {
        launchApp()

        tapTab(label: "Recent", screen: AccessibilityID.recentScreen)
        tapTab(label: "Discover", screen: AccessibilityID.discoverScreen)
        tapTab(label: "Browse", screen: AccessibilityID.browseScreen)
        tapTab(label: "Settings", screen: AccessibilityID.settingsScreen)
    }

    func testRecentMockBookOpensDetailAndReturnsToShelf() throws {
        launchApp()

        waitForIdentifier(AccessibilityID.recentBookOptions).tap()
        waitForIdentifier(AccessibilityID.recentBookDetails).tap()
        waitForIdentifier(AccessibilityID.bookDetailScreen)
        waitForIdentifier(AccessibilityID.bookDetailTitle)

        waitForIdentifier(AccessibilityID.closeBookDetail).tap()
        waitForIdentifier(AccessibilityID.recentScreen)
    }

    func testBrowseBookDetailOpensImmediatelyAndCanReopenAfterBack() throws {
        launchApp()
        tapTab(label: "Browse", screen: AccessibilityID.browseScreen)

        waitForIdentifier(AccessibilityID.browseLibrary).tap()
        waitForIdentifier(AccessibilityID.browseBookListScreen)

        openMockBookDetail()
        navigateBackFromBookDetail()
        waitForIdentifier(AccessibilityID.browseBookListScreen)

        openMockBookDetail()
    }

    func testSettingsShowsMockServerWithoutNetworkInteraction() throws {
        launchApp()
        tapTab(label: "Settings", screen: AccessibilityID.settingsScreen)

        let serverRow = waitForIdentifier(AccessibilityID.settingsServer)
        XCTAssertTrue(serverRow.label.contains("UI Test Server"), app.debugDescription)
    }

    func testRecentMockBookOpensFolioReaderPagesAndCloses() throws {
        launchApp()

        waitForIdentifier(AccessibilityID.recentBook).tap()
        waitForIdentifier(AccessibilityID.readerFolioScreen)
        waitForIdentifier(AccessibilityID.readerFolioContent)

        let position = waitForIdentifier(AccessibilityID.readerFolioPosition)
        let initialPosition = position.label
        let pageCollection = app.collectionViews[AccessibilityID.readerFolioScreen].firstMatch
        XCTAssertTrue(
            pageCollection.waitForExistence(timeout: waitTimeout),
            "Expected FolioReader page collection.\n\(app.debugDescription)"
        )
        pageCollection.swipeLeft()

        waitForCondition("FolioReader position should change after paging") {
            position.exists && position.label != initialPosition
        }

        waitForIdentifier(AccessibilityID.readerFolioClose).tap()
        waitForIdentifier(AccessibilityID.recentScreen)
        waitForNonExistence(AccessibilityID.readerFolioScreen)
    }

    func testBrowseSearchFiltersNoResultsAndClearsToFullList() throws {
        openBrowseBookList()

        let searchField = waitForIdentifier(AccessibilityID.browseSearchField)
        searchField.tap()
        searchField.typeText("Alpha")
        searchField.typeText("\n")

        waitForIdentifier(AccessibilityID.browseBookAlpha)
        waitForNonExistence(AccessibilityID.browseBookBeta)
        waitForNonExistence(AccessibilityID.browseBook)

        searchField.tap()
        searchField.typeText("No Such UI Test Book")
        searchField.typeText("\n")

        let noResults = waitForIdentifier(AccessibilityID.browseNoResults)
        waitForLabel(noResults, containing: "Found no books.")
        waitForNonExistence(AccessibilityID.browseBookAlpha)

        waitForIdentifier(AccessibilityID.browseSearchClear).tap()
        waitForIdentifier(AccessibilityID.browseBook)
        waitForIdentifier(AccessibilityID.browseBookAlpha)
        waitForIdentifier(AccessibilityID.browseBookBeta)
    }

    func testBrowseTitleSortTogglesAscendingAndDescending() throws {
        openBrowseBookList()
        waitForIdentifier(AccessibilityID.browseBook)
        waitForIdentifier(AccessibilityID.browseBookAlpha)
        waitForIdentifier(AccessibilityID.browseBookBeta)

        chooseTitleSort()
        waitForBrowseBookOrder([AccessibilityID.browseBookAlpha, AccessibilityID.browseBookBeta, AccessibilityID.browseBook])

        chooseTitleSort()
        waitForBrowseBookOrder([AccessibilityID.browseBook, AccessibilityID.browseBookBeta, AccessibilityID.browseBookAlpha])
    }

    func testBrowseBatchSelectionAndConfirmationCanBeCancelled() throws {
        openBrowseBookList()

        waitForIdentifier(AccessibilityID.browseBatchMode).tap()
        waitForIdentifier(AccessibilityID.browseSelectionToolbar)

        let downloadButton = waitForIdentifier(AccessibilityID.browseSelectionDownload)
        waitForLabel(downloadButton, containing: "(0)")
        XCTAssertFalse(downloadButton.isEnabled, app.debugDescription)

        waitForIdentifier(AccessibilityID.browseBook).tap()
        waitForLabel(downloadButton, containing: "(1)")
        XCTAssertTrue(downloadButton.isEnabled, app.debugDescription)

        waitForIdentifier(AccessibilityID.browseBook).tap()
        waitForLabel(downloadButton, containing: "(0)")
        XCTAssertFalse(downloadButton.isEnabled, app.debugDescription)

        waitForIdentifier(AccessibilityID.browseBookAlpha).tap()
        waitForLabel(downloadButton, containing: "(1)")
        waitForIdentifier(AccessibilityID.browseSelectionSelectAll).tap()
        waitForLabel(downloadButton, containing: "(3)")

        waitForIdentifier(AccessibilityID.browseSelectionClear).tap()
        waitForLabel(downloadButton, containing: "(0)")
        XCTAssertFalse(downloadButton.isEnabled, app.debugDescription)

        waitForIdentifier(AccessibilityID.browseBookBeta).tap()
        waitForIdentifier(AccessibilityID.browseSelectionCancel).tap()
        waitForIdentifier(AccessibilityID.browseBatchMode)

        waitForIdentifier(AccessibilityID.browseBatchMode).tap()
        waitForIdentifier(AccessibilityID.browseSelectionSelectAll).tap()
        waitForLabel(waitForIdentifier(AccessibilityID.browseSelectionDownload), containing: "(3)")
        waitForIdentifier(AccessibilityID.browseSelectionDownload).tap()

        let formatRow = waitForIdentifier(AccessibilityID.browseBatchSheetFormatEPUB)
        XCTAssertTrue(formatRow.label.contains("EPUB"), app.debugDescription)
        XCTAssertTrue(formatRow.label.contains("3"), app.debugDescription)
        formatRow.tap()
        let summary = waitForIdentifier(AccessibilityID.browseBatchSheetSummary)
        waitForLabel(summary, containing: "3 books")

        waitForIdentifier(AccessibilityID.browseBatchSheetCancel).tap()
        waitForNonExistence(AccessibilityID.browseBatchSheet)
        waitForIdentifier(AccessibilityID.browseBook)
    }

    func testBrowseAuthorsCategoryFiltersToAlphaBook() throws {
        launchApp()
        tapTab(label: "Browse", screen: AccessibilityID.browseScreen)

        waitForIdentifier(AccessibilityID.browseCategoryAuthors).tap()
        waitForIdentifier(AccessibilityID.browseCategoryAuthorsPage)
        waitForIdentifier(AccessibilityID.browseCategoryAuthorsAlpha).tap()

        waitForIdentifier(AccessibilityID.browseBookListScreen)
        waitForIdentifier(AccessibilityID.browseBookAlpha)
        waitForNonExistence(AccessibilityID.browseBook)
        waitForNonExistence(AccessibilityID.browseBookBeta)
    }

    func testBrowseSeriesCategorySearchFiltersAndClears() throws {
        launchApp()
        tapTab(label: "Browse", screen: AccessibilityID.browseScreen)

        waitForIdentifier(AccessibilityID.browseCategorySeries).tap()
        waitForIdentifier(AccessibilityID.browseCategorySeriesPage)

        let searchField = waitForIdentifier(AccessibilityID.browseCategorySeriesSearch)
        searchField.tap()
        searchField.typeText("Beta")

        waitForIdentifier(AccessibilityID.browseCategorySeriesBeta)
        waitForNonExistence(AccessibilityID.browseCategorySeriesMock)
        waitForNonExistence(AccessibilityID.browseCategorySeriesAlpha)

        waitForIdentifier(AccessibilityID.browseCategorySeriesClear).tap()
        waitForIdentifier(AccessibilityID.browseCategorySeriesMock)
        waitForIdentifier(AccessibilityID.browseCategorySeriesAlpha)
        waitForIdentifier(AccessibilityID.browseCategorySeriesBeta)
    }

    func testBrowseHeaderTagsCanSelectMultipleAndClear() throws {
        openBrowseBookList()

        waitForIdentifier(AccessibilityID.browseCategoryMenu).tap()
        waitForIdentifier(AccessibilityID.browseCategoryMenuTags).tap()
        waitForIdentifier(AccessibilityID.browseCategoryTagsPage)

        waitForIdentifier(AccessibilityID.browseCategoryTagsAlpha).tap()
        waitForIdentifier(AccessibilityID.browseCategoryTagsBeta).tap()
        waitForIdentifier(AccessibilityID.browseCategoryTagsDone).tap()

        waitForIdentifier(AccessibilityID.browseBookListScreen)
        waitForIdentifier(AccessibilityID.browseFilterRemoveTagsAlpha)
        waitForIdentifier(AccessibilityID.browseBookAlpha)
        waitForIdentifier(AccessibilityID.browseBookBeta)
        waitForNonExistence(AccessibilityID.browseBook)

        waitForIdentifier(AccessibilityID.browseFilterRemoveTagsAlpha).tap()
        waitForNonExistence(AccessibilityID.browseBookAlpha)
        waitForIdentifier(AccessibilityID.browseBookBeta)

        waitForIdentifier(AccessibilityID.browseFilterClear).tap()
        waitForIdentifier(AccessibilityID.browseBook)
        waitForIdentifier(AccessibilityID.browseBookAlpha)
        waitForIdentifier(AccessibilityID.browseBookBeta)
    }

    private func launchApp() {
        app.launch()
        waitForIdentifier(AccessibilityID.recentScreen)
    }

    private func tapTab(label: String, screen: String) {
        let tab = app.tabBars.buttons[label].firstMatch
        XCTAssertTrue(
            tab.waitForExistence(timeout: waitTimeout),
            "Expected tab '\(label)'.\n\(app.debugDescription)"
        )
        tab.tap()
        waitForIdentifier(screen)
    }

    private func openMockBookDetail() {
        waitForIdentifier(AccessibilityID.browseBook).tap()
        waitForIdentifier(AccessibilityID.bookDetailScreen)
        waitForIdentifier(AccessibilityID.bookDetailTitle)
    }

    private func openBrowseBookList() {
        launchApp()
        tapTab(label: "Browse", screen: AccessibilityID.browseScreen)
        waitForIdentifier(AccessibilityID.browseLibrary).tap()
        waitForIdentifier(AccessibilityID.browseBookListScreen)
    }

    private func chooseTitleSort() {
        waitForIdentifier(AccessibilityID.browseSortMenu).tap()
        waitForIdentifier(AccessibilityID.browseSortTitle).tap()
    }

    private func waitForBrowseBookOrder(_ expected: [String]) {
        waitForCondition("Browse rows should be ordered as expected") {
            self.browseBookIdentifiersInAccessibilityOrder() == expected
        }
    }

    private func browseBookIdentifiersInAccessibilityOrder() -> [String] {
        let browseBookIDs = [
            AccessibilityID.browseBook,
            AccessibilityID.browseBookAlpha,
            AccessibilityID.browseBookBeta
        ]
        return browseBookIDs
            .map { ($0, app.descendants(matching: .any).matching(identifier: $0).firstMatch) }
            .filter { $0.1.exists }
            .sorted { $0.1.frame.minY < $1.1.frame.minY }
            .map(\.0)
    }

    private func navigateBackFromBookDetail() {
        let navigationBar = app.navigationBars.element(boundBy: 0)
        let backButton = navigationBar.buttons.element(boundBy: 0)
        XCTAssertTrue(
            backButton.waitForExistence(timeout: waitTimeout),
            "Expected a navigation back button.\n\(app.debugDescription)"
        )
        backButton.tap()
    }

    @discardableResult
    private func waitForIdentifier(_ identifier: String) -> XCUIElement {
        let element = queryForIdentifier(identifier)
        XCTAssertTrue(
            element.waitForExistence(timeout: waitTimeout),
            "Expected accessibility identifier '\(identifier)'.\n\(app.debugDescription)"
        )
        return element
    }

    private func queryForIdentifier(_ identifier: String) -> XCUIElement {
        if identifier == AccessibilityID.browseSelectionToolbar {
            return app.otherElements[identifier].firstMatch
        }
        if identifier.hasPrefix("screen.") || identifier == AccessibilityID.readerFolioScreen {
            return app.descendants(matching: .any)
                .matching(identifier: identifier)
                .firstMatch
        }
        if identifier.contains(".page") {
            return app.descendants(matching: .any)
                .matching(identifier: identifier)
                .firstMatch
        }
        if identifier == AccessibilityID.browseSearchField
            || (identifier.hasPrefix("browse.category.") && identifier.hasSuffix(".search")) {
            return app.textFields[identifier].firstMatch
        }
        if identifier == AccessibilityID.readerFolioContent {
            return app.webViews[identifier].firstMatch
        }
        if identifier == AccessibilityID.browseNoResults
            || identifier == AccessibilityID.browseBatchSheetSummary
            || identifier == AccessibilityID.browseBatchSheetFormatEPUB
            || identifier == AccessibilityID.bookDetailTitle
            || identifier == AccessibilityID.readerFolioPosition {
            return app.staticTexts[identifier].firstMatch
        }
        if identifier == AccessibilityID.browseBatchSheet {
            return app.collectionViews[identifier].firstMatch
        }
        if identifier.hasPrefix("browse.")
            || identifier.hasPrefix("shelf.")
            || identifier.hasPrefix("book-detail.")
            || identifier.hasPrefix("reader.folio.")
            || identifier == AccessibilityID.settingsServer {
            return app.buttons[identifier].firstMatch
        }
        return app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String) {
        waitForCondition("Expected '\(element.identifier)' to contain '\(text)'") {
            element.exists && element.label.contains(text)
        }
    }

    private func waitForNonExistence(_ identifier: String) {
        let element = queryForIdentifier(identifier)
        waitForCondition("Expected accessibility identifier '\(identifier)' to disappear") {
            !element.exists
        }
    }

    private func waitForCondition(_ message: String, condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() },
            object: nil
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: waitTimeout)
        XCTAssertEqual(result, XCTWaiter.Result.completed, "\(message).\n\(app.debugDescription)")
    }
}
