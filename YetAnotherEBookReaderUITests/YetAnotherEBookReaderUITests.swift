import Foundation
import XCTest

class UIJourneyTestCase: XCTestCase {
    fileprivate enum AccessibilityID {
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
        static let browseSortModified = "browse.sort.modified"
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

    fileprivate let waitTimeout: TimeInterval = 10
    fileprivate let readerLoadTimeout: TimeInterval = 30
    fileprivate var app: XCUIApplication!
    fileprivate var elementCache = [String: XCUIElement]()

    override func setUpWithError() throws {
        try super.setUpWithError()

        app = XCUIApplication()
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing-mock-library"]
        elementCache.removeAll(keepingCapacity: true)
    }

    override func tearDown() {
        elementCache.removeAll(keepingCapacity: false)
        app = nil
        super.tearDown()
    }

    fileprivate func runMainTabsAndSettingsJourney() {
        runJourney(named: "Main tabs and Settings") {
            launchApp()

            runActivity(named: "Launch smoke navigates across main tabs") {
                tapTab(label: "Recent", screen: AccessibilityID.recentScreen)
                tapTab(label: "Discover", screen: AccessibilityID.discoverScreen)
                tapTab(label: "Browse", screen: AccessibilityID.browseScreen)
                tapTab(label: "Settings", screen: AccessibilityID.settingsScreen)
            }

            runActivity(named: "Settings shows mock server without network interaction") {
                tapTab(label: "Settings", screen: AccessibilityID.settingsScreen)

                let serverRow = waitForIdentifier(AccessibilityID.settingsServer)
                XCTAssertTrue(serverRow.label.contains("UI Test Server"), app.debugDescription)
            }
        }
    }

    fileprivate func runRecentDetailsAndFolioReaderJourney() {
        runJourney(named: "Recent details and FolioReader") {
            launchApp()

            runActivity(named: "Recent mock book opens detail and returns to shelf") {
                waitForIdentifier(AccessibilityID.recentBookOptions).tap()
                waitForIdentifier(AccessibilityID.recentBookDetails).tap()
                waitForIdentifier(AccessibilityID.bookDetailScreen)
                waitForIdentifier(AccessibilityID.bookDetailTitle)

                waitForIdentifier(AccessibilityID.closeBookDetail).tap()
                waitForIdentifier(AccessibilityID.recentScreen)
            }

            runActivity(named: "Recent mock book opens FolioReader, pages, and closes") {
                waitForIdentifier(AccessibilityID.recentBook).tap()
                waitForIdentifier(AccessibilityID.readerFolioScreen)
                waitForIdentifier(AccessibilityID.readerFolioContent, timeout: readerLoadTimeout)

                let position = waitForIdentifier(AccessibilityID.readerFolioPosition)
                let initialPosition = position.label
                let pageCollection = app.collectionViews[AccessibilityID.readerFolioScreen].firstMatch
                waitForElement(pageCollection, description: "FolioReader page collection")
                pageCollection.swipeLeft()

                waitForCondition("FolioReader position should change after paging") {
                    position.exists && position.label != initialPosition
                }

                waitForIdentifier(AccessibilityID.readerFolioClose).tap()
                waitForIdentifier(AccessibilityID.recentScreen)
                waitForNonExistence(AccessibilityID.readerFolioScreen)
            }
        }
    }

    fileprivate func runBrowseDetailsSearchAndSortJourney() {
        runJourney(named: "Browse details, search, and sort") {
            launchApp()
            tapTab(label: "Browse", screen: AccessibilityID.browseScreen)
            waitForIdentifier(AccessibilityID.browseLibrary).tap()
            waitForIdentifier(AccessibilityID.browseBookListScreen)

            runActivity(named: "Browse book detail opens immediately and can reopen after back") {
                openMockBookDetail()
                navigateBackFromNavigationStack()
                waitForIdentifier(AccessibilityID.browseBookListScreen)

                openMockBookDetail()
                navigateBackFromNavigationStack()
                waitForIdentifier(AccessibilityID.browseBookListScreen)
            }

            runActivity(named: "Browse search filters no results and clears to full list") {
                resetBrowseBookListState(restoreDefaultSort: false)
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
                waitForAllBrowseBooks()
            }

            runActivity(named: "Browse title sort toggles ascending and descending") {
                resetBrowseBookListState(restoreDefaultSort: true)
                waitForAllBrowseBooks()

                chooseTitleSort()
                waitForBrowseBookOrder([
                    AccessibilityID.browseBookAlpha,
                    AccessibilityID.browseBookBeta,
                    AccessibilityID.browseBook
                ])

                chooseTitleSort()
                waitForBrowseBookOrder([
                    AccessibilityID.browseBook,
                    AccessibilityID.browseBookBeta,
                    AccessibilityID.browseBookAlpha
                ])
            }
        }
    }

    fileprivate func runBrowseBatchSelectionAndConfirmationJourney() {
        runJourney(named: "Browse batch selection and confirmation") {
            launchApp()
            openBrowseBookList()

            runActivity(named: "Browse batch selection and confirmation can be cancelled") {
                resetBrowseBookListState(restoreDefaultSort: false)
                waitForIdentifier(AccessibilityID.browseBatchMode).tap()
                waitForIdentifier(AccessibilityID.browseSelectionToolbar)

                let downloadButton = waitForIdentifier(AccessibilityID.browseSelectionDownload)
                let mockBook = waitForIdentifier(AccessibilityID.browseBook)
                let alphaBook = waitForIdentifier(AccessibilityID.browseBookAlpha)
                let betaBook = waitForIdentifier(AccessibilityID.browseBookBeta)
                waitForLabel(downloadButton, containing: "(0)")
                XCTAssertFalse(downloadButton.isEnabled, app.debugDescription)

                mockBook.tap()
                waitForLabel(downloadButton, containing: "(1)")
                XCTAssertTrue(downloadButton.isEnabled, app.debugDescription)

                mockBook.tap()
                waitForLabel(downloadButton, containing: "(0)")
                XCTAssertFalse(downloadButton.isEnabled, app.debugDescription)

                alphaBook.tap()
                waitForLabel(downloadButton, containing: "(1)")
                waitForIdentifier(AccessibilityID.browseSelectionSelectAll).tap()
                waitForLabel(downloadButton, containing: "(3)")

                let clearButton = waitForIdentifier(AccessibilityID.browseSelectionClear)
                clearButton.tap()
                waitForLabel(downloadButton, containing: "(0)")
                XCTAssertFalse(downloadButton.isEnabled, app.debugDescription)

                betaBook.tap()
                waitForIdentifier(AccessibilityID.browseSelectionCancel).tap()
                waitForIdentifier(AccessibilityID.browseBatchMode)

                waitForIdentifier(AccessibilityID.browseBatchMode).tap()
                waitForIdentifier(AccessibilityID.browseSelectionSelectAll).tap()
                waitForLabel(downloadButton, containing: "(3)")
                downloadButton.tap()

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
        }
    }

    fileprivate func runBrowseCategoriesAndFiltersJourney() {
        runJourney(named: "Browse Authors, Series, Tags, and filters") {
            launchApp()
            tapTab(label: "Browse", screen: AccessibilityID.browseScreen)

            runActivity(named: "Browse Authors category filters to Alpha book") {
                waitForIdentifier(AccessibilityID.browseCategoryAuthors).tap()
                waitForIdentifier(AccessibilityID.browseCategoryAuthorsPage)
                waitForIdentifier(AccessibilityID.browseCategoryAuthorsAlpha).tap()

                waitForIdentifier(AccessibilityID.browseBookListScreen)
                waitForIdentifier(AccessibilityID.browseBookAlpha)
                waitForNonExistence(AccessibilityID.browseBook)
                waitForNonExistence(AccessibilityID.browseBookBeta)

                resetBrowseBookListState(restoreDefaultSort: true)
                navigateBackFromNavigationStack()
                waitForIdentifier(AccessibilityID.browseCategoryAuthorsPage)
                navigateBackFromNavigationStack()
                waitForIdentifier(AccessibilityID.browseCategoryAuthors)
            }

            runActivity(named: "Browse Series category search filters and clears") {
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

                navigateBackFromNavigationStack()
                waitForIdentifier(AccessibilityID.browseCategorySeries)
            }

            runActivity(named: "Browse header Tags can select multiple and clear") {
                openBrowseBookList()

                waitForIdentifier(AccessibilityID.browseCategoryMenu).tap()
                waitForIdentifier(AccessibilityID.browseCategoryMenuTags).tap()
                waitForIdentifier(AccessibilityID.browseCategoryTagsPage)

                let alphaTag = waitForIdentifier(AccessibilityID.browseCategoryTagsAlpha)
                let betaTag = waitForIdentifier(AccessibilityID.browseCategoryTagsBeta)
                alphaTag.tap()
                betaTag.tap()
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
                waitForAllBrowseBooks()
            }
        }
    }

    fileprivate func launchApp() {
        app.launch()
        waitForIdentifier(AccessibilityID.recentScreen)
    }

    fileprivate func tapTab(label: String, screen: String) {
        let tab = app.tabBars.buttons[label].firstMatch
        waitForElement(tab, description: "tab '\(label)'")
        tab.tap()
        waitForIdentifier(screen)
    }

    fileprivate func openMockBookDetail() {
        waitForIdentifier(AccessibilityID.browseBook).tap()
        waitForIdentifier(AccessibilityID.bookDetailScreen)
        waitForIdentifier(AccessibilityID.bookDetailTitle)
    }

    fileprivate func openBrowseBookList() {
        tapTab(label: "Browse", screen: AccessibilityID.browseScreen)
        waitForIdentifier(AccessibilityID.browseLibrary).tap()
        waitForIdentifier(AccessibilityID.browseBookListScreen)
    }

    fileprivate func chooseTitleSort() {
        waitForIdentifier(AccessibilityID.browseSortMenu).tap()
        waitForIdentifier(AccessibilityID.browseSortTitle).tap()
    }

    fileprivate func chooseSort(_ identifier: String) {
        waitForIdentifier(AccessibilityID.browseSortMenu).tap()
        waitForIdentifier(identifier).tap()
    }

    fileprivate func resetBrowseBookListState(restoreDefaultSort: Bool) {
        let sheet = queryForIdentifier(AccessibilityID.browseBatchSheet)
        if sheet.exists {
            waitForIdentifier(AccessibilityID.browseBatchSheetCancel).tap()
            waitForNonExistence(AccessibilityID.browseBatchSheet)
        }

        let batchCancel = queryForIdentifier(AccessibilityID.browseSelectionCancel)
        if batchCancel.exists {
            batchCancel.tap()
            waitForIdentifier(AccessibilityID.browseBatchMode)
        }

        let searchClear = queryForIdentifier(AccessibilityID.browseSearchClear)
        if searchClear.exists {
            searchClear.tap()
            waitForAllBrowseBooks()
        }

        let filterClear = queryForIdentifier(AccessibilityID.browseFilterClear)
        if filterClear.exists {
            filterClear.tap()
            waitForNonExistence(AccessibilityID.browseFilterClear)
            waitForAllBrowseBooks()
        }

        if restoreDefaultSort {
            // Selecting another key first makes Modified descending deterministic,
            // regardless of the sort state left by a preceding category filter.
            chooseSort(AccessibilityID.browseSortTitle)
            chooseSort(AccessibilityID.browseSortModified)
        }
    }

    fileprivate func waitForAllBrowseBooks() {
        waitForIdentifier(AccessibilityID.browseBook)
        waitForIdentifier(AccessibilityID.browseBookAlpha)
        waitForIdentifier(AccessibilityID.browseBookBeta)
    }

    fileprivate func waitForBrowseBookOrder(_ expected: [String]) {
        waitForCondition("Browse rows should be ordered as expected") {
            self.browseBookIdentifiersInAccessibilityOrder() == expected
        }
    }

    fileprivate func browseBookIdentifiersInAccessibilityOrder() -> [String] {
        let browseBookIDs = [
            AccessibilityID.browseBook,
            AccessibilityID.browseBookAlpha,
            AccessibilityID.browseBookBeta
        ]
        return browseBookIDs
            .map { ($0, queryForIdentifier($0)) }
            .filter { $0.1.exists }
            .sorted { $0.1.frame.minY < $1.1.frame.minY }
            .map(\.0)
    }

    fileprivate func navigateBackFromNavigationStack() {
        let navigationBar = app.navigationBars.element(boundBy: 0)
        let backButton = navigationBar.buttons.element(boundBy: 0)
        waitForElement(backButton, description: "navigation back button")
        backButton.tap()
    }

    @discardableResult
    fileprivate func waitForIdentifier(
        _ identifier: String,
        timeout: TimeInterval = 10
    ) -> XCUIElement {
        let element = queryForIdentifier(identifier)
        if element.exists {
            return element
        }

        waitForElement(
            element,
            description: "accessibility identifier '\(identifier)'",
            timeout: timeout
        )
        return element
    }

    fileprivate func queryForIdentifier(_ identifier: String) -> XCUIElement {
        if let cachedElement = elementCache[identifier] {
            return cachedElement
        }

        let element: XCUIElement
        if identifier == AccessibilityID.browseSelectionToolbar {
            element = app.otherElements[identifier].firstMatch
        } else if identifier.hasPrefix("screen.") || identifier == AccessibilityID.readerFolioScreen {
            element = app.descendants(matching: .any)
                .matching(identifier: identifier)
                .firstMatch
        } else if identifier.contains(".page") {
            element = app.descendants(matching: .any)
                .matching(identifier: identifier)
                .firstMatch
        } else if identifier == AccessibilityID.browseSearchField
            || (identifier.hasPrefix("browse.category.") && identifier.hasSuffix(".search")) {
            element = app.textFields[identifier].firstMatch
        } else if identifier == AccessibilityID.readerFolioContent {
            element = app.webViews[identifier].firstMatch
        } else if identifier == AccessibilityID.browseNoResults
            || identifier == AccessibilityID.browseBatchSheetSummary
            || identifier == AccessibilityID.browseBatchSheetFormatEPUB
            || identifier == AccessibilityID.bookDetailTitle
            || identifier == AccessibilityID.readerFolioPosition {
            element = app.staticTexts[identifier].firstMatch
        } else if identifier == AccessibilityID.browseBatchSheet {
            element = app.collectionViews[identifier].firstMatch
        } else if identifier.hasPrefix("browse.")
            || identifier.hasPrefix("shelf.")
            || identifier.hasPrefix("book-detail.")
            || identifier.hasPrefix("reader.folio.")
            || identifier == AccessibilityID.settingsServer {
            element = app.buttons[identifier].firstMatch
        } else {
            element = app.descendants(matching: .any)
                .matching(identifier: identifier)
                .firstMatch
        }

        elementCache[identifier] = element
        return element
    }

    fileprivate func waitForLabel(_ element: XCUIElement, containing text: String) {
        if element.exists && element.label.contains(text) {
            return
        }

        waitForCondition("Expected '\(element.identifier)' to contain '\(text)'") {
            element.exists && element.label.contains(text)
        }
    }

    fileprivate func waitForNonExistence(_ identifier: String) {
        let element = queryForIdentifier(identifier)
        if !element.exists {
            return
        }

        waitForCondition("Expected accessibility identifier '\(identifier)' to disappear") {
            !element.exists
        }
    }

    fileprivate func waitForElement(
        _ element: XCUIElement,
        description: String,
        timeout: TimeInterval = 10
    ) {
        if element.exists {
            return
        }

        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Expected \(description).\n\(app.debugDescription)"
        )
    }

    fileprivate func runJourney(named name: String, body: () -> Void) {
        let startedAt = Date()
        defer {
            logTiming(kind: "journey", name: name, startedAt: startedAt)
        }
        body()
    }

    fileprivate func runActivity(named name: String, body: () -> Void) {
        XCTContext.runActivity(named: name) { _ in
            let startedAt = Date()
            defer {
                logTiming(kind: "activity", name: name, startedAt: startedAt)
            }
            body()
        }
    }

    fileprivate func logTiming(kind: String, name: String, startedAt: Date) {
        let duration = Date().timeIntervalSince(startedAt)
        print(String(format: "[UITestTiming] %@ %@ %.3fs", kind, name, duration))
    }

    fileprivate func waitForCondition(_ message: String, condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() },
            object: nil
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: waitTimeout)
        XCTAssertEqual(result, XCTWaiter.Result.completed, "\(message).\n\(app.debugDescription)")
    }
}

final class YetAnotherEBookReaderUITests: UIJourneyTestCase {
    func testJourneyMainTabsAndSettings() throws {
        runMainTabsAndSettingsJourney()
    }
}

final class YetAnotherEBookReaderRecentUITests: UIJourneyTestCase {
    func testJourneyRecentDetailsAndFolioReader() throws {
        runRecentDetailsAndFolioReaderJourney()
    }
}

final class YetAnotherEBookReaderBrowseDetailsUITests: UIJourneyTestCase {
    func testJourneyBrowseDetailsSearchAndSort() throws {
        runBrowseDetailsSearchAndSortJourney()
    }
}

final class YetAnotherEBookReaderBrowseBatchUITests: UIJourneyTestCase {
    func testJourneyBrowseBatchSelectionAndConfirmation() throws {
        runBrowseBatchSelectionAndConfirmationJourney()
    }
}

final class YetAnotherEBookReaderBrowseCategoriesUITests: UIJourneyTestCase {
    func testJourneyBrowseCategoriesAndFilters() throws {
        runBrowseCategoriesAndFiltersJourney()
    }
}
