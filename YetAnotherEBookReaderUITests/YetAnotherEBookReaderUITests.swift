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
        static let bookDetailTitle = "book-detail.title"
        static let bookDetailRead = "book-detail.read"
        static let bookDetailHistory = "book-detail.history"
        static let readingHistoryScreen = "screen.reading-history"
        static let readingHistoryContinue = "reading-history.continue"
        static let readingHistoryPosition = "reading-history.position"
        static let readingPositionScreen = "screen.reading-position"
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

                navigateBackFromNavigationStack()
                waitForNonExistence(AccessibilityID.bookDetailScreen)
                waitForIdentifier(AccessibilityID.recentBook)
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

            // The reader workspace is an overlay over the tabs. Book detail is pushed, so a reader
            // opened from it must show above it, and closing the reader must return to it.
            runActivity(named: "Reader opened from book detail shows above it and closes back to it") {
                waitForIdentifier(AccessibilityID.recentBookOptions).tap()
                waitForIdentifier(AccessibilityID.recentBookDetails).tap()
                waitForIdentifier(AccessibilityID.bookDetailScreen)
                waitForIdentifier(AccessibilityID.bookDetailRead).tap()

                let reader = waitForIdentifier(AccessibilityID.readerFolioScreen)
                waitForIdentifier(AccessibilityID.readerFolioContent, timeout: readerLoadTimeout)
                XCTAssertTrue(reader.isHittable, "The reader should show above the book detail")

                waitForIdentifier(AccessibilityID.readerFolioClose).tap()
                waitForNonExistence(AccessibilityID.readerFolioScreen)
                waitForIdentifier(AccessibilityID.bookDetailScreen)
            }

            runActivity(named: "Continue Reading from reading history shows the reader above it") {
                waitForIdentifier(AccessibilityID.bookDetailHistory).tap()
                waitForIdentifier(AccessibilityID.readingHistoryScreen)
                waitForIdentifier(AccessibilityID.readingHistoryContinue).tap()

                let reader = waitForIdentifier(AccessibilityID.readerFolioScreen)
                waitForIdentifier(AccessibilityID.readerFolioContent, timeout: readerLoadTimeout)
                XCTAssertTrue(reader.isHittable, "The reader should show above the reading history")

                waitForIdentifier(AccessibilityID.readerFolioClose).tap()
                waitForNonExistence(AccessibilityID.readerFolioScreen)
                waitForIdentifier(AccessibilityID.readingHistoryScreen)

                // A row's info pushes its position detail through History's hidden link.
                waitForIdentifier(AccessibilityID.readingHistoryPosition).tap()
                waitForIdentifier(AccessibilityID.readingPositionScreen)
                waitForIdentifier("reading-position.continue").tap()
                waitForIdentifier(AccessibilityID.readerFolioContent, timeout: readerLoadTimeout)
                waitForIdentifier(AccessibilityID.readerFolioClose).tap()
                waitForNonExistence(AccessibilityID.readerFolioScreen)
                waitForIdentifier(AccessibilityID.readingPositionScreen)
                navigateBackFromNavigationStack()
                waitForNonExistence(AccessibilityID.readingPositionScreen)
                waitForIdentifier(AccessibilityID.readingHistoryScreen)

                navigateBackFromNavigationStack()
                waitForIdentifier(AccessibilityID.bookDetailScreen)
                navigateBackFromNavigationStack()
                waitForNonExistence(AccessibilityID.bookDetailScreen)
                waitForIdentifier(AccessibilityID.recentBook)
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

/// Opt-in native journeys against real calibre servers and a separately installed app copy.
/// Supply the three YABR_ONBOARDING_* variables through the UI runner's xctestrun environment.
final class CalibreOnboardingUITests: XCTestCase {
    private var app: XCUIApplication!
    private var singleURL = ""
    private var multiURL = ""

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        let bundleID = environment["YABR_ONBOARDING_BUNDLE_ID"] ?? ""
        singleURL = environment["YABR_ONBOARDING_SINGLE_URL"] ?? ""
        multiURL = environment["YABR_ONBOARDING_MULTI_URL"] ?? ""
        try XCTSkipIf(bundleID.isEmpty || singleURL.isEmpty || multiURL.isEmpty,
                      "Requires an isolated app installation and local calibre test servers")
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: bundleID)
        // Uses the existing test-host consent gate, with normal disk persistence and networking.
        app.launchEnvironment["XCTestConfigurationFilePath"] = "/tmp/CalibreOnboardingValidation"
        app.launch()
        element("welcome.calibre")
    }

    func testConnectionRecoveryKeepsActionsVisibleAndUsesEditedConfiguration() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["YABR_CONNECTION_CONTROL_URL"] == nil,
                      "Requires the P4 loopback connection-control proxy")
        try connectionMode("html503")
        connect(name: "P4 Recovery Server", url: singleURL)
        assertRecovery(status: 503, screenshot: "p4-add-long-html-503")
        try connectionMode("auth401")
        element("server.connection.retry").tap()
        assertRecovery(status: 401, screenshot: "p4-add-http-401")
        try connectionMode("auth403")
        element("server.connection.retry").tap()
        assertRecovery(status: 403, screenshot: "p4-add-http-403")
        element("server.connection.edit").tap()
        XCTAssertEqual(app.textFields["Name Your Server"].value as? String, "P4 Recovery Server")
        XCTAssertEqual(app.textFields["Internal Server Address"].value as? String, singleURL + "/")
        replaceURL("http://127.0.0.1:1")
        element("server.connection.connect").tap()
        assertRecovery(status: nil, screenshot: "p4-add-cannot-connect")
        element("server.connection.result.cancel").tap()
        element("server.connection.cancel").tap()
        app.terminate()
        app.launch()
        element("welcome.calibre") // failed probes did not save a server
        element("welcome.browse").tap()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertFalse(app.staticTexts["P4 Recovery Server"].exists)
        app.tabBars.buttons["Recent"].tap()

        try connectionMode("auth_basic")
        connect(name: "P4 Recovery Server", url: singleURL)
        assertRecovery(status: 401, screenshot: "p4-auth-challenge-without-credentials")
        element("server.connection.edit").tap()
        let require = app.switches["Require"].firstMatch
        for _ in 0..<4 {
            if require.isHittable { break }
            app.swipeUp()
        }
        // SwiftUI exposes the whole row as a Switch; tap the visible switch at its trailing edge.
        require.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let user = app.textFields["Username"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: user)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        user.tap()
        user.typeText("contract")
        let password = app.secureTextFields.firstMatch
        password.tap()
        password.typeText("wrong")
        element("server.connection.connect").tap()
        assertRecovery(status: 401, screenshot: "p4-auth-rejected-credentials")
        element("server.connection.edit").tap()
        for _ in 0..<4 {
            if password.isHittable { break }
            app.swipeUp()
        }
        XCTAssertEqual(user.value as? String, "contract")
        XCTAssertEqual((password.value as? String)?.count, 5)
        // The clear icon is immediately to the right of this field on both supported form layouts.
        password.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 12, dy: 0)).tap()
        XCTAssertTrue((password.value as? String ?? "").isEmpty)
        password.tap()
        password.typeText("correct")
        XCTAssertEqual((password.value as? String)?.count, 7)
        element("server.connection.connect").tap()
        waitForEnabled(element("server.connection.confirm"))
        capture("p4-corrected-credentials-connected")
        element("server.connection.confirm").tap()
        element("screen.browse.book-list")
        XCTAssertTrue(app.staticTexts["Quick Start Guide"].firstMatch.waitForExistence(timeout: 30))
        capture("p4-recovered-to-real-book-list")
        back()
        app.tabBars.buttons["Settings"].tap()
        app.staticTexts["P4 Recovery Server"].firstMatch.tap()
        app.buttons["Modify Configuration"].firstMatch.tap()
        element("server.connection.form")
        let name = app.textFields["Name Your Server"]
        element("server.connection.field.Name.clear").tap()
        name.tap()
        name.typeText("P4 Edited Server")
        try connectionMode("html503")
        element("server.connection.connect").tap()
        assertRecovery(status: 503, screenshot: "p4-modify-long-html-503")
        element("server.connection.edit").tap()
        XCTAssertEqual(name.value as? String, "P4 Edited Server")
        capture("p4-modify-retains-input")
        element("server.connection.connect").tap()
        assertRecovery(status: 503, screenshot: "p4-modify-still-failing")
        try connectionMode("success")
        element("server.connection.retry").tap()
        waitForEnabled(element("server.connection.confirm"))
        element("server.connection.confirm").tap()
        XCTAssertTrue(app.navigationBars["P4 Edited Server"].waitForExistence(timeout: 20), app.debugDescription)
        capture("p4-modify-retry-success")
        app.terminate()
        app.launch()
        element("welcome.browse").tap()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["P4 Edited Server"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["P4 Recovery Server"].exists)
        app.tabBars.buttons["Browse"].tap()
        app.staticTexts["Calibre Library"].firstMatch.tap()
        element("screen.browse.book-list")
        XCTAssertTrue(app.staticTexts["Quick Start Guide"].firstMatch.waitForExistence(timeout: 30))
        capture("p4-modified-connection-still-browses")
    }

    private func assertRecovery(status: Int?, screenshot: String) {
        waitForEnabled(element("server.connection.retry"))
        capture(screenshot + "-initial")
        let title = element("server.connection.status.title")
        XCTAssertEqual(title.label, status.map { "Connection Failed (HTTP \($0))" } ?? "Connection Failed")
        let message = element("server.connection.status.message")
        XCTAssertLessThan(message.label.count, 180)
        XCTAssertFalse(message.label.contains("<html>"))
        XCTAssertFalse(element("server.connection.confirm").isEnabled)
        for id in ["server.connection.edit", "server.connection.retry"] {
            let action = element(id)
            XCTAssertTrue(action.isHittable, app.debugDescription)
            XCTAssertTrue(app.frame.contains(action.frame), app.debugDescription)
        }
        capture(screenshot) // No scrolling on the error page, including iPhone 7.
    }

    private func connectionMode(_ mode: String) throws {
        let base = try XCTUnwrap(ProcessInfo.processInfo.environment["YABR_CONNECTION_CONTROL_URL"])
        let url = try XCTUnwrap(URL(string: base + "?mode=" + mode))
        let configured = expectation(description: "Configure connection response")
        URLSession.shared.dataTask(with: url) { _, response, error in
            XCTAssertNil(error)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            configured.fulfill()
        }.resume()
        wait(for: [configured], timeout: 10)
    }

    func testSingleLibraryCancelFailureRetryAndBrowse() {
        capture("welcome")
        element("welcome.import")
        element("welcome.calibre").tap()
        element("server.connection.form")
        capture("direct-connection-form")
        element("server.connection.cancel").tap()
        element("welcome.calibre")
        XCTAssertFalse(app.tabBars.buttons["Settings"].isSelected)

        // A successful probe cancelled before Add must leave no saved server, even after relaunch.
        connect(name: "P2 Cancelled Server", url: singleURL)
        waitForEnabled(element("server.connection.confirm"))
        capture("successful-probe-before-cancel")
        element("server.connection.result.cancel").tap()
        element("server.connection.cancel").tap()
        app.terminate()
        app.launch()
        element("welcome.calibre")
        element("welcome.browse").tap()
        app.tabBars.buttons["Settings"].tap()
        element("screen.settings")
        XCTAssertFalse(app.staticTexts["P2 Cancelled Server"].exists)
        app.tabBars.buttons["Recent"].tap()

        connect(name: "P2 Single Server", url: "http://127.0.0.1:1")
        waitForEnabled(element("server.connection.retry"))
        XCTAssertFalse(element("server.connection.confirm").isEnabled)
        capture("connection-failed")
        element("server.connection.result.cancel").tap()
        replaceURL(singleURL)
        element("server.connection.connect").tap()
        waitForEnabled(element("server.connection.confirm"))
        capture("single-library-confirm")
        element("server.connection.confirm").tap()
        element("screen.browse.book-list")
        XCTAssertTrue(app.navigationBars["Calibre Library"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Quick Start Guide"].firstMatch.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["Browse"].isSelected)
        capture("single-library-books")
        back()
        XCTAssertTrue(app.navigationBars["Library Browser"].waitForExistence(timeout: 10), app.debugDescription)
        app.staticTexts["Calibre Library"].firstMatch.tap()
        element("screen.browse.book-list")
        back()
        app.tabBars.buttons["Settings"].tap()
        app.staticTexts["P2 Single Server"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Calibre Library"].firstMatch.waitForExistence(timeout: 10))
        capture("settings-management-preserved")
        app.terminate()
        app.launch()
        element("welcome.browse").tap()
        app.staticTexts["Calibre Library"].firstMatch.tap()
        element("screen.browse.book-list")
        XCTAssertTrue(app.staticTexts["Quick Start Guide"].firstMatch.waitForExistence(timeout: 30))
        capture("saved-library-after-relaunch")
    }

    func testMultipleLibrariesRequireChoiceAndBrowseOnlyTheChosenLibrary() {
        connect(name: "P2 Multiple Server", url: multiURL)
        let first = element("server.connection.library.P2_First_Library")
        let second = element("server.connection.library.P2_Second_Library")
        let confirm = element("server.connection.confirm")
        XCTAssertFalse(confirm.isEnabled)
        capture("multiple-libraries-require-choice")
        first.tap()
        second.tap()
        waitForEnabled(confirm)
        capture("second-library-selected")
        confirm.tap()
        element("screen.browse.book-list")
        XCTAssertTrue(app.navigationBars["P2 Second Library"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["P2 Second Only Book"].firstMatch.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertFalse(app.staticTexts["P2 First Only Book"].exists)
        XCTAssertFalse(app.staticTexts["Quick Start Guide"].exists)
        capture("chosen-library-books")
        // Supplementary filter coverage on modern systems. On iOS 15 the menu did not open
        // in the native harness; keep its connection/back-navigation checks independent.
        if #available(iOS 16, *) {
            element("browse.category.menu").tap()
            element("browse.category.menu.authors").tap()
            element("browse.category.authors.item.john-schember").tap()
            element("browse.category.authors.done").tap()
            element("browse.filter.chip.authors.john-schember")
            XCTAssertTrue(app.staticTexts["P2 Second Only Book"].firstMatch.waitForExistence(timeout: 20))
            XCTAssertFalse(app.staticTexts["P2 First Only Book"].exists)
            capture("connected-library-category-filter")
            element("browse.filter.clear").tap()
        }

        if min(app.frame.width, app.frame.height) > 600 {
            XCUIDevice.shared.orientation = .landscapeLeft
            let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
                app.frame.width > app.frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 10), .completed, app.debugDescription)
            XCTAssertTrue(app.staticTexts["P2 Second Only Book"].firstMatch.waitForExistence(timeout: 10))
            element("browse.book.mock").tap()
            element("screen.book-detail")
            capture("chosen-book-detail-landscape")
            back()
            element("screen.browse.book-list")
            capture("chosen-library-landscape")
            XCUIDevice.shared.orientation = .portrait
        }
        back()
        XCTAssertTrue(app.staticTexts["P2 First Library"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["P2 First Library"].firstMatch.tap()
        element("screen.browse.book-list")
        XCTAssertTrue(app.staticTexts["P2 First Only Book"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["P2 Second Only Book"].exists)
        capture("other-library-remains-browsable")
    }

    /// The optional control endpoint forwards to real calibre and can delay/fail a download.
    func testDownloadAndReadFromRealCalibreWithRetryCancellationAndCachedResume() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["YABR_DOWNLOAD_READ_CONTROL_URL"] == nil,
                      "Requires the P3 real-calibre download-control proxy")
        connect(name: "P3 Read Server", url: singleURL)
        waitForEnabled(element("server.connection.confirm"))
        element("server.connection.confirm").tap()
        element("screen.browse.book-list")
        element("browse.book.mock").tap()
        element("screen.book-detail")
        waitForReadLabel("Download and Read")
        capture("p3-visible-download-and-read")

        try downloadMode("success")
        element("book-detail.read").tap() // The only reading action from this uncached detail.
        element("reader.folio.content")
        let bodyText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "e-book management tool")).firstMatch
        // Normal mode scrolls within chapters vertically and changes chapters horizontally.
        for _ in 0..<10 {
            if bodyText.exists && bodyText.isHittable { break }
            app.collectionViews["reader.folio.screen"].firstMatch.swipeLeft()
        }
        waitForVisibleBody(bodyText)
        capture("p3-one-read-action-reaches-body")
        closeReaderWorkspace()
        waitForReadLabel("Read")
        capture("p3-cached-read")
        element("book-detail.read").tap()
        element("reader.folio.content")
        waitForVisibleBody(bodyText)
        capture("p3-resumes-existing-position")
        closeReaderWorkspace()

        clearDownloadedFiles()
        try downloadMode("success")
        element("book-detail.download-only").tap()
        waitForReadLabel("Read")
        XCTAssertFalse(app.webViews["reader.folio.content"].exists)
        capture("p3-download-only-stays-in-detail")

        clearDownloadedFiles()
        try downloadMode("fail_once")
        element("book-detail.read").tap()
        XCTAssertTrue(app.alerts["Error Download Book"].waitForExistence(timeout: 20), app.debugDescription)
        capture("p3-download-failure-retry")
        app.alerts.buttons.firstMatch.tap()
        waitForReadLabel("Download and Read")
        element("book-detail.read").tap()
        element("reader.folio.content")
        capture("p3-retry-opens-reader")
        closeReaderWorkspace()

        clearDownloadedFiles()
        try downloadMode("slow")
        element("book-detail.read").tap()
        element("book-detail.cancel-download").tap()
        waitForReadLabel("Download and Read")
        XCTAssertFalse(app.webViews["reader.folio.content"].waitForExistence(timeout: 9))
        capture("p3-cancel-does-not-open")

        element("book-detail.read").tap()
        element("book-detail.cancel-download")
        back()
        element("screen.browse.book-list")
        XCTAssertFalse(app.webViews["reader.folio.content"].waitForExistence(timeout: 9))
        capture("p3-leave-detail-does-not-open")
        element("browse.book.mock").tap()
        waitForReadLabel("Read")
        XCTAssertFalse(app.webViews["reader.folio.content"].exists)
        element("book-detail.read").tap()
        element("reader.folio.content")
        capture("p3-explicit-read-after-return")
    }

    func testPreviewLifecycleAndFormatActionsPreserveReadingPosition() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["YABR_PREVIEW_CONTROL_URL"] == nil,
                      "Requires the BD3 loopback manifest fixture")
        connect(name: "BD3 Preview Server", url: singleURL)
        waitForEnabled(element("server.connection.confirm"))
        element("server.connection.confirm").tap()
        element("screen.browse.book-list")
        element("browse.book.mock").tap()
        try downloadMode("success")
        let isIPadFixture = ProcessInfo.processInfo.environment["YABR_PREVIEW_IPAD"] == "1"
        if isIPadFixture {
            // The tablet defaults to PDF. Select EPUB through the same per-format action as a user.
            openFilesMenu()
            element("Download EPUB Only").tap()
            waitForReadLabel("Read")
        }
        element("book-detail.read").tap()
        element("reader.folio.content")
        let body = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "e-book management tool")).firstMatch
        for _ in 0..<10 {
            if body.exists && body.isHittable { break }
            app.collectionViews["reader.folio.screen"].firstMatch.swipeLeft()
        }
        waitForVisibleBody(body)
        closeReaderWorkspace()
        waitForReadLabel("Read")

        try previewMode("success")
        openPreview()
        element("Preview Chapter\n  Nested Chapter\n")
        capture("bd3-preview-nested-contents")
        if ProcessInfo.processInfo.environment["YABR_PREVIEW_IPAD"] == "1" {
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(element("book-preview.close").isHittable, app.debugDescription)
            capture("bd3-ipad-preview-landscape")
            XCUIDevice.shared.orientation = .portrait
        }
        // Ordinary preview reader controls exercise the actual Folio integration.
        app.buttons["Preview"].firstMatch.tap()
        element("reader.folio.content")
        capture("bd3-isolated-preview-reader")
        element("book-preview.close").tap()
        waitForReadLabel("Read")
        element("book-detail.read").tap()
        element("reader.folio.content")
        waitForVisibleBody(body)
        capture("bd3-resume-original-chapter-after-preview")
        closeReaderWorkspace()

        for (mode, text) in [("empty", "No table of contents in this book."),
                             ("waiting", "The server is generating the table of contents. Try again shortly."),
                             ("invalid", "The server returned an invalid table of contents. Please try again.")] {
            try previewMode(mode)
            openPreview()
            element(text)
            capture("bd3-preview-" + mode)
            if mode != "empty" {
                try previewMode("success")
                element("book-preview.retry").tap()
                element("Preview Chapter\n  Nested Chapter\n")
                capture("bd3-retry-" + mode)
            }
            element("book-preview.close").tap()
            waitForReadLabel("Read")
        }
        try previewMode("offline")
        openPreview()
        let contents = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Introduction")).firstMatch
        XCTAssertTrue(contents.waitForExistence(timeout: 20), app.debugDescription)
        capture("bd3-offline-downloaded-contents")
        element("book-preview.close").tap()
        try previewMode("slow")
        openPreview()
        element("book-preview.close").tap()
        waitForReadLabel("Read")
        XCTAssertFalse(app.staticTexts["Late Chapter\n"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "screen.book-preview").firstMatch.exists)
        capture("bd3-dismiss-rejects-late-manifest")
        clearDownloadedFiles()
        capture("bd3-confirmed-cache-removal")
        try downloadMode("slow")
        if isIPadFixture {
            openFilesMenu()
            element("Download EPUB Only").tap()
        } else {
            element("book-detail.read").tap()
        }
        openFilesMenu()
        element("Pause EPUB Download").tap()
        openFilesMenu()
        let resume = element("Resume EPUB Download")
        waitForEnabled(resume)
        capture("bd3-paused-format-download")
        resume.tap()
        if isIPadFixture {
            waitForReadLabel("Read")
            XCTAssertFalse(app.webViews["reader.folio.content"].exists)
            element("book-detail.read").tap()
        }
        element("reader.folio.content")
        waitForVisibleBody(body)
        capture("bd3-resumed-download-opens-saved-position")
        closeReaderWorkspace()
        waitForReadLabel("Read")
    }

    private func openFilesMenu() {
        let snapshot = XCTAttachment(string: app.debugDescription)
        snapshot.name = "bd3-toolbar-before-menu"
        snapshot.lifetime = .keepAlways
        add(snapshot)
        let button = app.buttons["Files and Formats"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
        button.tap()
    }

    private func openPreview() {
        openFilesMenu()
        element("Preview EPUB").tap()
        element("screen.book-preview")
    }

    private func previewMode(_ mode: String) throws {
        try configureFixture(mode, environmentKey: "YABR_PREVIEW_CONTROL_URL")
    }

    func testDetailInActualIPadSplitWindow() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["YABR_DETAIL_SPLIT"] == "1",
                          "Requires the isolated iPad Release fixture")
        let descriptionKey = "YABR_DESCRIPTION_CONTROL_URL"
        let hasDescriptionFixture = ProcessInfo.processInfo.environment[descriptionKey] != nil
        if hasDescriptionFixture {
            try configureFixture("long", environmentKey: descriptionKey)
        }
        connect(name: "Split View Server", url: singleURL)
        waitForEnabled(element("server.connection.confirm"))
        element("server.connection.confirm").tap()
        let book = app.descendants(matching: .any).matching(identifier: "browse.book.mock").firstMatch
        reveal(book)
        book.tap()
        element("book-detail.title")
        capture("bd2-before-split")

        // Ordinary system multitasking: reveal the Dock and drag Safari to the right edge.
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.998))
        let dock = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
        bottom.press(forDuration: 0.05, thenDragTo: dock, withVelocity: .slow, thenHoldForDuration: 0.1)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let safari = springboard.icons["Safari"].firstMatch
        XCTAssertTrue(safari.waitForExistence(timeout: 10), springboard.debugDescription)
        let icon = safari.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let right = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.5))
        icon.press(forDuration: 0.5, thenDragTo: right, withVelocity: .slow, thenHoldForDuration: 1)
        let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.windows.firstMatch.frame.width < 600
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 15), .completed, app.debugDescription)
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, 300)
        capture("bd2-ipad-split-overview")
        let read = element("book-detail.read")
        reveal(read)
        assertHorizontalBounds(read)
        XCTAssertTrue(read.isHittable)
        capture("bd2-ipad-split-read")
        if hasDescriptionFixture {
            let toggle = app.buttons["book-description.toggle"].firstMatch
            reveal(toggle)
            XCTAssertEqual(toggle.label, "Show More")
            assertHorizontalBounds(toggle)
            capture("bd4-description-split")

            let jump = app.links["Jump to the final paragraph"].firstMatch
            reveal(jump, upward: false)
            jump.tap()
            let end = app.staticTexts["BD4 Final Paragraph"].firstMatch
            let reachedAnchor = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                end.exists && end.isHittable && self.app.windows.firstMatch.frame.contains(end.frame)
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [reachedAnchor], timeout: 15), .completed, app.debugDescription)
            XCTAssertEqual(toggle.label, "Show Less")
            capture("bd4-description-split-anchor")
        }
    }

    func testDescriptionReflowsAndUpdatesInBookDetail() throws {
        let key = "YABR_DESCRIPTION_CONTROL_URL"
        try XCTSkipIf(ProcessInfo.processInfo.environment[key] == nil, "Requires the BD4 description fixture")
        try configureFixture("long", environmentKey: key)
        connect(name: "BD4 Description Server", url: singleURL)
        waitForEnabled(element("server.connection.confirm"))
        element("server.connection.confirm").tap()
        element("screen.browse.book-list")
        let first = element("browse.book.mock")
        reveal(first)
        first.tap()
        element("book-detail.title")
        let heading = app.staticTexts["Description"].firstMatch
        reveal(heading)
        let toggle = app.buttons["book-description.toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(toggle.label, "Show More")
        reveal(toggle)
        capture("bd4-description-collapsed")
        toggle.tap()
        XCTAssertEqual(toggle.label, "Show Less")
        let ending = app.staticTexts["BD4 Final Paragraph"].firstMatch
        reveal(ending)
        XCTAssertTrue(ending.isHittable)
        capture("bd4-description-expanded")
        reveal(toggle)
        toggle.tap()
        XCTAssertEqual(toggle.label, "Show More")
        reveal(heading, upward: false)

        if app.windows.firstMatch.frame.width >= 700 {
            XCUIDevice.shared.orientation = .landscapeLeft
            reveal(heading)
            XCTAssertEqual(toggle.label, "Show More")
            assertHorizontalBounds(toggle)
            capture("bd4-description-landscape")
            XCUIDevice.shared.orientation = .portrait
        }

        try configureFixture("short", environmentKey: key)
        element("book-detail.refresh").tap()
        reveal(heading, upward: false)
        let updated = app.staticTexts["BD4 Short Synopsis"].firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 20), app.debugDescription)
        reveal(updated)
        XCTAssertFalse(toggle.exists)
        capture("bd4-description-short-after-refresh")

        let logs = app.buttons["Activity Logs"].firstMatch
        reveal(logs, maxDrags: 28)
        logs.tap()
        XCTAssertTrue(app.navigationBars["Activity Logs"].waitForExistence(timeout: 10))
        capture("bd4-activity-logs")
        app.navigationBars["Activity Logs"].buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["Book Details"].waitForExistence(timeout: 10))

        back()
        let second = element("browse.book.2")
        reveal(second)
        second.tap()
        element("book-detail.title")
        reveal(app.staticTexts["Files and Formats"].firstMatch)
        XCTAssertFalse(heading.exists)
        XCTAssertFalse(toggle.exists)
        XCTAssertFalse(updated.exists)
        capture("bd4-description-empty-other-book")
    }

    func testDetailMetadataRefreshUpdatesDisplayedValues() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["YABR_DETAIL_METADATA_CONTROL_URL"] == nil,
                      "Requires the BD2 real-Calibre metadata control fixture")
        try configureFixture("original", environmentKey: "YABR_DETAIL_METADATA_CONTROL_URL")
        connect(name: "BD2 Metadata Server", url: singleURL)
        waitForEnabled(element("server.connection.confirm"))
        element("server.connection.confirm").tap()
        element("browse.book.mock").tap()
        element("book-detail.title")
        let information = app.staticTexts["Book Information"].firstMatch
        reveal(information)
        let original = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "BD2 Original Publisher")).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 15), app.debugDescription)
        capture("bd2-metadata-before")

        try configureFixture("updated", environmentKey: "YABR_DETAIL_METADATA_CONTROL_URL")
        element("book-detail.refresh").tap()
        let updatedTitle = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label ENDSWITH %@", "book-detail.title", "— Refreshed")).firstMatch
        XCTAssertTrue(updatedTitle.waitForExistence(timeout: 20), app.debugDescription)
        let updatedPublisher = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "BD2 Updated Publisher")).firstMatch
        XCTAssertTrue(updatedPublisher.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Updated Tag")).firstMatch.exists)
        XCTAssertFalse(original.exists)
        reveal(updatedPublisher)
        capture("bd2-metadata-after")
    }

    /// Real-server layout fixture: book 1 has a long title, multiple authors and formats;
    /// book 2 has no cover, publication data or description. Run with normal and accessibility text.
    func testDetailAdaptiveLayoutAndSparseMetadata() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["YABR_DETAIL_LAYOUT"] == "1",
                          "Requires the BD2 long/sparse real-Calibre fixture")
        connect(name: "BD2 Layout Server", url: singleURL)
        waitForEnabled(element("server.connection.confirm"))
        reveal(element("server.connection.confirm"))
        element("server.connection.confirm").tap()
        element("screen.browse.book-list")
        let book = element("browse.book.mock")
        reveal(book)
        book.tap()
        element("screen.book-detail")
        let title = element("book-detail.title")
        XCTAssertGreaterThan(title.label.count, 100)
        XCTAssertTrue(element("book-detail.authors").label.contains("Ada"))
        assertHorizontalBounds(title)
        capture("bd2-long-overview")
        let read = element("book-detail.read")
        reveal(read)
        assertHorizontalBounds(read)
        XCTAssertTrue(read.isHittable)
        capture("bd2-long-read-action")
        for heading in ["Reading Progress", "Description", "Files and Formats", "Book Information", "Sync and Advanced"] {
            let item = app.staticTexts[heading].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 10), app.debugDescription)
            reveal(item)
            assertHorizontalBounds(item)
            capture("bd2-section-" + heading.replacingOccurrences(of: " ", with: "-"))
        }
        let epub = app.buttons["Download EPUB Only"].firstMatch
        reveal(epub, upward: false)
        XCTAssertTrue(epub.isHittable)
        assertHorizontalBounds(epub)
        capture("bd2-format-actions")

        if app.windows.firstMatch.frame.width >= 700 {
            XCUIDevice.shared.orientation = .landscapeLeft
            reveal(title, upward: false)
            assertHorizontalBounds(title)
            capture("bd2-ipad-landscape")
            XCUIDevice.shared.orientation = .portrait
        }
        back()
        let sparse = app.descendants(matching: .any).matching(identifier: "browse.book.2").firstMatch
        reveal(sparse)
        sparse.tap()
        element("book-detail.title")
        capture("bd2-no-cover-sparse-overview")
        XCTAssertFalse(app.staticTexts["Published"].exists)
        XCTAssertFalse(app.staticTexts["Publisher"].exists)
        XCTAssertFalse(app.staticTexts["Series"].exists)
        XCTAssertFalse(app.staticTexts["Description"].exists)
        let information = app.staticTexts["Book Information"].firstMatch
        reveal(information)
        capture("bd2-sparse-information")
        back()
        element("screen.browse.book-list")
    }

    private func reveal(_ item: XCUIElement, upward: Bool = true, maxDrags: Int = 20) {
        for _ in 0..<maxDrags {
            let collection = app.collectionViews.firstMatch
            let table = app.tables.firstMatch
            let list = collection.exists ? collection : table
            if item.exists && item.isHittable {
                // A browse row can be taller than its list at accessibility sizes.
                if list.exists { return }
                let window = app.windows.firstMatch.frame
                let tabBar = app.tabBars.firstMatch
                let bottom = tabBar.exists && tabBar.frame.minY > window.midY ? tabBar.frame.minY : window.maxY - 20
                let navigationBottom = app.navigationBars.firstMatch.frame.maxY
                let frame = item.frame
                let fits = frame.height <= bottom - navigationBottom
                    ? frame.minY >= navigationBottom && frame.maxY <= bottom
                    : frame.maxY > navigationBottom && frame.minY < bottom
                if fits { return }
            }
            if list.exists {
                if upward { list.swipeUp() } else { list.swipeDown() }
                continue
            }
            // Small, position-aware drags avoid skipping a control at accessibility sizes.
            // Use the card padding: avoid both the WebView and the system scroll indicator.
            let window = app.windows.firstMatch.frame
            let top = app.navigationBars.firstMatch.frame.maxY + 12
            let tabBar = app.tabBars.firstMatch
            let bottom = (tabBar.exists && tabBar.frame.minY > window.midY ? tabBar.frame.minY : window.maxY) - 12
            let frame = item.exists ? item.frame : .zero
            let moveUp = item.exists ? frame.maxY > bottom : upward
            let remaining = moveUp ? frame.maxY - bottom : top - frame.minY
            let distance = min(180, max(50, remaining + 12))
            let middle = (top + bottom) / 2
            let startY = middle + (moveUp ? distance / 2 : -distance / 2)
            let endY = middle - (moveUp ? distance / 2 : -distance / 2)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: 24, dy: startY))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: 24, dy: endY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(item.isHittable, app.debugDescription)
    }

    private func assertHorizontalBounds(_ item: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let frame = item.frame
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 1, file: file, line: line)
    }

    func testDetailRefreshKeepsCachedReadAndHistoryReturn() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["YABR_DETAIL_REFRESH_CONTROL_URL"] == nil,
                      "Requires the BD1 metadata-control proxy")
        try configureFixture("success", environmentKey: "YABR_DETAIL_REFRESH_CONTROL_URL")
        try downloadMode("success")
        connect(name: "BD1 Detail Server", url: singleURL)
        waitForEnabled(element("server.connection.confirm"))
        element("server.connection.confirm").tap()
        element("screen.browse.book-list")
        element("browse.book.mock").tap()
        waitForReadLabel("Download and Read")
        element("book-detail.download-only").tap()
        waitForReadLabel("Read")
        XCTAssertTrue(app.buttons["Clear Downloaded Files"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.buttons["Refresh Book Details"].waitForExistence(timeout: 3), app.debugDescription)

        try configureFixture("failed", environmentKey: "YABR_DETAIL_REFRESH_CONTROL_URL")
        element("book-detail.refresh").tap()
        let retry = app.buttons["Retry Refresh"]
        XCTAssertTrue(retry.waitForExistence(timeout: 20), app.debugDescription)
        waitForReadLabel("Read")
        capture("bd1-refresh-failed-cache-readable")
        try configureFixture("success", environmentKey: "YABR_DETAIL_REFRESH_CONTROL_URL")
        for _ in 0..<6 {
            if retry.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(retry.isHittable, app.debugDescription)
        retry.tap()
        XCTAssertTrue(app.staticTexts["In Sync with Server"].waitForExistence(timeout: 20), app.debugDescription)

        try configureFixture("unavailable", environmentKey: "YABR_DETAIL_REFRESH_CONTROL_URL")
        element("book-detail.refresh").tap()
        XCTAssertTrue(app.staticTexts["Unavailable on Server"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Downloaded"].exists, app.debugDescription)
        capture("bd1-server-unavailable-cache-retained")
        let read = element("book-detail.read")
        for _ in 0..<6 {
            if read.isHittable { break }
            app.swipeDown()
        }
        waitForReadLabel("Read")
        read.tap()
        element("reader.folio.content")
        closeReaderWorkspace()
        element("book-detail.history").tap()
        element("screen.reading-history")
        back()
        element("screen.book-detail")
        waitForReadLabel("Read")
        XCTAssertTrue(app.staticTexts["Unavailable on Server"].exists, app.debugDescription)
        capture("bd1-history-return-preserves-detail")
        try configureFixture("success", environmentKey: "YABR_DETAIL_REFRESH_CONTROL_URL")
    }

    private func waitForVisibleBody(_ body: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: body)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed, app.debugDescription)
    }

    private func closeReaderWorkspace() {
        let buttons = app.buttons.matching(NSPredicate(format: "label == 'Close'"))
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        guard let close = buttons.allElementsBoundByIndex.last else {
            return XCTFail("Missing workspace Close button: \(app.debugDescription)")
        }
        close.tap()
    }

    private func waitForReadLabel(_ title: String) {
        let action = element("book-detail.read")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ AND enabled == true", title), object: action)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, app.debugDescription)
    }

    private func clearDownloadedFiles() {
        openFilesMenu()
        element("Clear EPUB Download").tap()
        element("Clear Downloaded File?")
        element("Clear EPUB Download").tap()
        waitForReadLabel("Download and Read")
    }

    private func downloadMode(_ mode: String) throws {
        try configureFixture(mode, environmentKey: "YABR_DOWNLOAD_READ_CONTROL_URL")
    }

    private func configureFixture(_ mode: String, environmentKey: String) throws {
        let base = try XCTUnwrap(ProcessInfo.processInfo.environment[environmentKey])
        let url = try XCTUnwrap(URL(string: base + "?mode=" + mode))
        let configured = expectation(description: "Configure download transport")
        URLSession.shared.dataTask(with: url) { _, response, error in
            XCTAssertNil(error)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            configured.fulfill()
        }.resume()
        wait(for: [configured], timeout: 10)
    }

    private func connect(name: String, url: String) {
        element("welcome.calibre").tap()
        element("server.connection.form")
        let nameField = app.textFields["Name Your Server"]
        nameField.tap()
        nameField.typeText(name)
        replaceURL(url)
        element("server.connection.connect").tap()
        element("server.connection.result")
    }

    private func replaceURL(_ url: String) {
        let field = app.textFields["Internal Server Address"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        element("server.connection.field.URL.clear").tap()
        field.tap()
        field.typeText(url)
    }

    @discardableResult private func element(_ id: String) -> XCUIElement {
        let result = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20), "Missing \(id): \(app.debugDescription)")
        return result
    }

    private func waitForEnabled(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, app.debugDescription)
    }

    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func capture(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}


/// Uses only normal startup discovery of a CC0 EPUB in the isolated app's Local Library folder.
final class BookDetailLocalFileUITests: XCTestCase {
    func testLocalFileWithoutCoverReadsAndReturnsThroughHistory() throws {
        let bundle = ProcessInfo.processInfo.environment["YABR_LOCAL_DETAIL_BUNDLE_ID"] ?? ""
        try XCTSkipIf(bundle.isEmpty, "Requires an isolated Release app with a local EPUB fixture")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: bundle)
        app.launchEnvironment["XCTestConfigurationFilePath"] = "/tmp/BD2LocalFileValidation"
        app.launch()
        let options = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "shelf.book.options.")).firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 30), app.debugDescription)
        options.tap()
        let details = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "shelf.book.details.")).firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 10), app.debugDescription)
        details.tap()
        let title = app.staticTexts["book-detail.title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15), app.debugDescription)
        let read = app.buttons["book-detail.read"].firstMatch
        XCTAssertEqual(read.label, "Read")
        XCTAssertTrue(app.staticTexts["Local File"].exists)
        capture("bd2-local-no-cover-detail")
        app.buttons["Files and Formats"].firstMatch.tap()
        XCTAssertFalse(app.buttons["Clear EPUB Download"].exists)
        XCTAssertFalse(app.buttons["Download EPUB Only"].exists)
        let preview = app.buttons["Preview EPUB"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10), app.debugDescription)
        preview.tap()
        let localContents = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "The Compass and the Quiet Map")).firstMatch
        XCTAssertTrue(localContents.waitForExistence(timeout: 20), app.debugDescription)
        capture("bd3-local-contents-without-server")
        app.buttons["Preview"].firstMatch.tap()
        XCTAssertTrue(app.webViews["reader.folio.content"].waitForExistence(timeout: 30), app.debugDescription)
        capture("bd3-local-preview-reader")
        app.buttons["book-preview.close"].firstMatch.tap()
        XCTAssertTrue(read.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["book-detail.progress-history"].exists, "Preview must not create reading history")
        read.tap()
        XCTAssertTrue(app.webViews["reader.folio.content"].waitForExistence(timeout: 30), app.debugDescription)
        let chapter = app.staticTexts["The Compass and the Quiet Map"].firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 20), app.debugDescription)
        capture("bd2-local-actual-reader")
        let close = app.buttons.matching(NSPredicate(format: "label == 'Close'"))
        XCTAssertTrue(close.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        guard let action = close.allElementsBoundByIndex.last else { return XCTFail("Missing workspace close") }
        action.tap()
        XCTAssertTrue(read.waitForExistence(timeout: 15))
        let progressHistory = app.buttons["book-detail.progress-history"].firstMatch
        XCTAssertTrue(progressHistory.waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["book-detail.history"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "screen.reading-history").firstMatch.waitForExistence(timeout: 15))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(read.label, "Read")
        capture("bd2-local-history-return")

        func capture(_ name: String) {
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            image.name = name
            image.lifetime = .keepAlways
            add(image)
        }
    }
}
