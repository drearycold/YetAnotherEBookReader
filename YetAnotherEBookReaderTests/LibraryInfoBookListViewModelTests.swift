//
//  LibraryInfoBookListViewModelTests.swift
//  YetAnotherEBookReaderTests
//

import XCTest
import Combine
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
class LibraryInfoBookListViewModelTests: XCTestCase {
    var listViewModel: LibraryInfoBookListViewModel!
    var container: AppContainer!
    var libraryInfoViewModel: LibraryInfoView.ViewModel!
    var searchViewModel: UnifiedSearchViewModel!
    var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        try super.setUpWithError()

        container = MockAppContainerFactory.makeContainer(testName: "LibraryInfoBookListViewModelTests")

        libraryInfoViewModel = LibraryInfoView.ViewModel()
        searchViewModel = UnifiedSearchViewModel(container: container)
        listViewModel = LibraryInfoBookListViewModel()
        cancellables = []
    }

    override func tearDownWithError() throws {
        listViewModel = nil
        libraryInfoViewModel = nil
        searchViewModel = nil
        container = nil
        cancellables = nil
        try super.tearDownWithError()
    }

    func testInitialization() {
        XCTAssertTrue(listViewModel.downloadBookList.isEmpty)
        XCTAssertEqual(listViewModel.searchString, "")
        XCTAssertFalse(listViewModel.batchDownloadSheetPresenting)
        XCTAssertFalse(listViewModel.booksListInfoPresenting)
        XCTAssertFalse(listViewModel.searchHistoryPresenting)
    }

    func testBrowseBookRowsUseDirectNavigationLinkInsteadOfSelectionDrivenNavigation() throws {
        let source = try String(contentsOf: sourceFileURL(
            "YetAnotherEBookReader/Views/LibraryInfoView/LibraryInfoBookListContent.swift"
        ))
        let parentSource = try String(contentsOf: sourceFileURL(
            "YetAnotherEBookReader/Views/LibraryInfoView/LibraryInfoBookListView.swift"
        ))

        XCTAssertTrue(source.contains("NavigationLink {"))
        XCTAssertTrue(source.contains("BookDetailView(bookId: book.inShelfId, viewMode: .LIBRARY)"))
        XCTAssertTrue(source.contains("container.bookManager.selectedBookId = book.inShelfId"))

        XCTAssertFalse(source.contains("List(selection:"))
        XCTAssertFalse(source.contains("tag: book.inShelfId"))
        XCTAssertFalse(source.contains("selection: selectedBookIdBinding"))
        XCTAssertFalse(source.contains("selectedBookIdBinding"))

        XCTAssertFalse(parentSource.contains(".sheet(item:"))
        XCTAssertFalse(parentSource.contains("presentingBookDetailId"))
    }

    func testBrowseSearchHeaderUsesInlineLayoutAndHidesClearButtonWhenEmpty() throws {
        let source = try String(contentsOf: sourceFileURL(
            "YetAnotherEBookReader/Views/LibraryInfoView/LibraryInfoBookListHeader.swift"
        ))

        XCTAssertTrue(source.contains("HStack(spacing: 6)"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(source.contains("if !listViewModel.searchString.isEmpty"))

        XCTAssertFalse(source.contains("ZStack {"))
        XCTAssertFalse(source.contains(".disabled(listViewModel.searchString.isEmpty)"))
        XCTAssertFalse(source.contains(".padding([.leading, .trailing], 24)"))
    }

    func testBrowseSearchHeaderUsesCategoryMenuAndActiveFilterChips() throws {
        let source = try String(contentsOf: sourceFileURL(
            "YetAnotherEBookReader/Views/LibraryInfoView/LibraryInfoBookListHeader.swift"
        ))

        XCTAssertTrue(source.contains("let filterItems = libraryInfoViewModel.visibleFilterItems"))
        XCTAssertTrue(source.contains("let categoryMenuItems = libraryInfoViewModel.availableCategoryMenuItems"))
        XCTAssertTrue(source.contains("if categoryMenuItems.isEmpty"))
        XCTAssertTrue(source.contains(".disabled(true)"))
        XCTAssertTrue(source.contains("ForEach(categoryMenuItems)"))
        XCTAssertTrue(source.contains("libraryInfoViewModel.headerCategorySelected = categoryItem.name"))
        XCTAssertTrue(source.contains("CategoryDetailView(categoryName: categoryName, preservesLibraryScope: true)"))
        XCTAssertTrue(source.contains("ForEach(filterItems)"))
        XCTAssertTrue(source.contains("libraryInfoViewModel.removeFilterCategory("))

        XCTAssertFalse(source.contains("filterCriteriaCategory[categoryFilter.key]?.remove"))
        XCTAssertFalse(source.contains("categoryFilter.key != libraryInfoViewModel.categoriesSelected"))
        XCTAssertFalse(source.contains("searchStringChanged(searchString: listViewModel.searchString"))
    }

    func testHeaderCategorySelectionReturnsToExistingBookList() throws {
        let source = try String(contentsOf: sourceFileURL(
            "YetAnotherEBookReader/Views/LibraryInfoView/LibraryInfoCategoryItemsView.swift"
        ))
        let parentSource = try String(contentsOf: sourceFileURL(
            "YetAnotherEBookReader/Views/LibraryInfoView/LibraryInfoView.swift"
        ))

        XCTAssertTrue(source.contains("if preservesLibraryScope"))
        XCTAssertTrue(source.contains("Button {"))
        XCTAssertTrue(source.contains("selectHeaderCategoryItem(categoryItem.name)"))
        XCTAssertTrue(source.contains("viewModel.preserveFilterCriteriaOnNextBookListAppear()"))
        XCTAssertTrue(source.contains("viewModel.headerCategorySelected = nil"))
        XCTAssertTrue(source.contains("NavigationLink(tag: categoryItem.name, selection: $viewModel.categoryItemSelected)"))
        XCTAssertTrue(source.contains("selectRootCategoryItem(categoryItem.name)"))
        XCTAssertTrue(parentSource.contains("let preserveFilters = viewModel.consumePreserveFilterCriteriaOnNextBookListAppear()"))
        XCTAssertTrue(parentSource.contains("if !preserveFilters"))
    }

    func testFilterCriteriaCategoryAPIsUpdateCriteriaAndVisibleItems() {
        libraryInfoViewModel.filterCriteriaLibraries = ["library-id"]
        libraryInfoViewModel.replaceFilterCategory(key: "Authors", value: "Author A")

        XCTAssertEqual(libraryInfoViewModel.filterCriteriaLibraries, [])
        XCTAssertEqual(libraryInfoViewModel.filterCriteriaCategory, ["Authors": Set(["Author A"])])
        XCTAssertEqual(
            libraryInfoViewModel.currentLibrarySearchResultKey.criteria.filterCriteriaCategory,
            ["Authors": Set(["Author A"])]
        )
        XCTAssertEqual(libraryInfoViewModel.visibleFilterItems.count, 1)
        XCTAssertEqual(libraryInfoViewModel.visibleFilterItems.first?.key, "Authors")
        XCTAssertEqual(libraryInfoViewModel.visibleFilterItems.first?.value, "Author A")

        libraryInfoViewModel.addFilterCategory(key: "Tags", value: "Fiction")
        libraryInfoViewModel.addFilterCategory(key: "Tags", value: "Sci-Fi")
        XCTAssertEqual(libraryInfoViewModel.filterCriteriaCategory["Tags"], Set(["Fiction", "Sci-Fi"]))
        XCTAssertEqual(
            libraryInfoViewModel.visibleFilterItems.map { "\($0.key):\($0.value)" },
            ["Authors:Author A", "Tags:Fiction", "Tags:Sci-Fi"]
        )

        libraryInfoViewModel.removeFilterCategory(key: "Tags", value: "Fiction")
        XCTAssertEqual(libraryInfoViewModel.filterCriteriaCategory["Tags"], Set(["Sci-Fi"]))

        libraryInfoViewModel.removeFilterCategory(key: "Tags", value: "Sci-Fi")
        XCTAssertNil(libraryInfoViewModel.filterCriteriaCategory["Tags"])
    }

    func testHeaderCategoryMenuItemsDoNotDependOnActiveFilters() {
        libraryInfoViewModel.availableCategories = [
            CategoryCacheSummary(categoryName: "Tags", itemsCount: 2, totalNumber: 3),
            CategoryCacheSummary(categoryName: "Authors", itemsCount: 1, totalNumber: 1)
        ]

        XCTAssertTrue(libraryInfoViewModel.visibleFilterItems.isEmpty)
        XCTAssertTrue(libraryInfoViewModel.hasHeaderCategoryMenuContent)
        XCTAssertEqual(libraryInfoViewModel.availableCategoryMenuItems.map(\.name), ["Authors", "Tags"])
    }

    func testReplaceFilterCategoryCanPreserveLibraryScopeForHeaderCategoryFlow() {
        libraryInfoViewModel.filterCriteriaLibraries = ["library-id"]

        libraryInfoViewModel.applyCategoryItemSelection(
            categoryName: "Tags",
            itemName: "Fiction",
            preservingLibraryScope: true
        )

        XCTAssertEqual(libraryInfoViewModel.filterCriteriaLibraries, ["library-id"])
        XCTAssertEqual(libraryInfoViewModel.filterCriteriaCategory, ["Tags": Set(["Fiction"])])
    }

    func testHeaderCategoryReturnPreserveFlagIsConsumedOnce() {
        XCTAssertFalse(libraryInfoViewModel.consumePreserveFilterCriteriaOnNextBookListAppear())

        libraryInfoViewModel.preserveFilterCriteriaOnNextBookListAppear()

        XCTAssertTrue(libraryInfoViewModel.consumePreserveFilterCriteriaOnNextBookListAppear())
        XCTAssertFalse(libraryInfoViewModel.consumePreserveFilterCriteriaOnNextBookListAppear())
    }

    func testApplyCategoryItemSelectionUsesCategorySortRules() {
        libraryInfoViewModel.sortCriteria = LibrarySearchSort(by: .Title, ascending: true)
        libraryInfoViewModel.applyCategoryItemSelection(categoryName: "Series", itemName: "Foundation")
        XCTAssertEqual(libraryInfoViewModel.sortCriteria.by, .SeriesIndex)
        XCTAssertTrue(libraryInfoViewModel.sortCriteria.ascending)

        libraryInfoViewModel.sortCriteria = LibrarySearchSort(by: .Title, ascending: true)
        libraryInfoViewModel.applyCategoryItemSelection(categoryName: "Authors", itemName: "Author A")
        XCTAssertEqual(libraryInfoViewModel.sortCriteria.by, .Publication)
        XCTAssertFalse(libraryInfoViewModel.sortCriteria.ascending)

        libraryInfoViewModel.sortCriteria = LibrarySearchSort(by: .Title, ascending: true)
        libraryInfoViewModel.applyCategoryItemSelection(categoryName: "Tags", itemName: "Fiction")
        XCTAssertEqual(libraryInfoViewModel.sortCriteria.by, .Modified)
        XCTAssertFalse(libraryInfoViewModel.sortCriteria.ascending)
    }

    func testVisibleFilterItemsIncludesCurrentCategorySelection() {
        libraryInfoViewModel.categoriesSelected = "Authors"
        libraryInfoViewModel.categoryItemSelected = "Author A"
        libraryInfoViewModel.replaceFilterCategory(key: "Authors", value: "Author A")

        XCTAssertEqual(libraryInfoViewModel.visibleFilterItems.count, 1)
        XCTAssertEqual(libraryInfoViewModel.visibleFilterItems.first?.key, "Authors")
        XCTAssertEqual(libraryInfoViewModel.visibleFilterItems.first?.value, "Author A")

        libraryInfoViewModel.clearFilterCriteria()
        XCTAssertTrue(libraryInfoViewModel.visibleFilterItems.isEmpty)
    }

    func testSyncDraftFromCriteria() {
        listViewModel.syncDraftFromCriteria("Hello World")
        XCTAssertEqual(listViewModel.searchString, "Hello World")
    }

    func testSubmitSearch() {
        listViewModel.searchString = "Query"
        listViewModel.submitSearch(libraryInfoViewModel: libraryInfoViewModel, searchViewModel: searchViewModel)

        XCTAssertEqual(libraryInfoViewModel.searchString, "Query")
    }

    func testClearSearch() {
        listViewModel.searchString = "Query"
        libraryInfoViewModel.searchString = "Query"

        listViewModel.clearSearch(libraryInfoViewModel: libraryInfoViewModel, searchViewModel: searchViewModel)

        XCTAssertEqual(listViewModel.searchString, "")
        XCTAssertEqual(libraryInfoViewModel.searchString, "")
    }

    func testPrepareBatchDownload() {
        let uuid = UUID()
        let server = CalibreServer(uuid: uuid, name: "S", baseUrl: "http://x", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "lib", name: "lib")

        let book1 = CalibreBook(id: 1, library: library)
        let book2 = CalibreBook(id: 2, library: library)

        listViewModel.prepareBatchDownload(books: [book1, book2])

        XCTAssertEqual(listViewModel.downloadBookList.count, 2)
        XCTAssertEqual(listViewModel.downloadBookList[0].id, 1)
        XCTAssertEqual(listViewModel.downloadBookList[1].id, 2)
        XCTAssertTrue(listViewModel.batchDownloadSheetPresenting)
    }

    func testBuildSectionsEmpty() {
        let sections = listViewModel.buildSections(books: [], sectionedBy: nil)
        XCTAssertTrue(sections.isEmpty)
    }

    func testBuildSectionsUngrouped() {
        let uuid = UUID()
        let server = CalibreServer(uuid: uuid, name: "S", baseUrl: "http://x", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "lib", name: "lib")
        let book = CalibreBook(id: 1, library: library)

        let sections = listViewModel.buildSections(books: [book], sectionedBy: nil)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].id, "all")
        XCTAssertEqual(sections[0].items.count, 1)
        XCTAssertEqual(sections[0].items[0].book.id, 1)
    }

    func testBuildSectionsGroupedByAuthor() {
        let uuid = UUID()
        let server = CalibreServer(uuid: uuid, name: "S", baseUrl: "http://x", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "lib", name: "lib")

        var book1 = CalibreBook(id: 1, library: library)
        book1.authors = ["Author Z"]
        var book2 = CalibreBook(id: 2, library: library)
        book2.authors = ["Author A"]

        let sections = listViewModel.buildSections(books: [book1, book2], sectionedBy: .Author)

        // Output should be sorted by key (Author A first, then Author Z)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].title, "Author A")
        XCTAssertEqual(sections[0].items.count, 1)
        XCTAssertEqual(sections[0].items[0].book.id, 2)

        XCTAssertEqual(sections[1].title, "Author Z")
        XCTAssertEqual(sections[1].items.count, 1)
        XCTAssertEqual(sections[1].items[0].book.id, 1)
    }

    func testBuildSectionsGroupedByRating() {
        let uuid = UUID()
        let server = CalibreServer(uuid: uuid, name: "S", baseUrl: "http://x", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "lib", name: "lib")

        var book1 = CalibreBook(id: 1, library: library)
        book1.rating = 2
        var book2 = CalibreBook(id: 2, library: library)
        book2.rating = 8

        let sections = listViewModel.buildSections(books: [book1, book2], sectionedBy: .Rating)

        // Output should be sorted by rating descending (8 first, then 2)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].id, "8")
        XCTAssertEqual(sections[0].title, CalibreBook.ratingDescription(for: 8))
        XCTAssertEqual(sections[0].items.count, 1)
        XCTAssertEqual(sections[0].items[0].book.id, 2)

        XCTAssertEqual(sections[1].id, "2")
        XCTAssertEqual(sections[1].title, CalibreBook.ratingDescription(for: 2))
        XCTAssertEqual(sections[1].items.count, 1)
        XCTAssertEqual(sections[1].items[0].book.id, 1)
    }

    func testFilterableAuthors() {
        let uuid = UUID()
        let server = CalibreServer(uuid: uuid, name: "S", baseUrl: "http://x", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "lib", name: "lib")
        var book = CalibreBook(id: 1, library: library)
        book.authors = ["Author A", "Author B"]

        // No filters yet
        let filtered1 = listViewModel.filterableAuthors(for: book, filterCriteriaCategory: [:])
        XCTAssertEqual(filtered1, ["Author A", "Author B"])

        // One filter matches "Author A"
        let filtered2 = listViewModel.filterableAuthors(for: book, filterCriteriaCategory: ["Authors": Set(["Author A"])])
        XCTAssertEqual(filtered2, ["Author B"])
    }

    func testFilterableTags() {
        let uuid = UUID()
        let server = CalibreServer(uuid: uuid, name: "S", baseUrl: "http://x", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "lib", name: "lib")
        var book = CalibreBook(id: 1, library: library)
        book.tags = ["Fiction", "Sci-Fi"]

        // No filters yet
        let filtered1 = listViewModel.filterableTags(for: book, filterCriteriaCategory: [:])
        XCTAssertEqual(filtered1, ["Fiction", "Sci-Fi"])

        // One filter matches "Fiction"
        let filtered2 = listViewModel.filterableTags(for: book, filterCriteriaCategory: ["Tags": Set(["Fiction"])])
        XCTAssertEqual(filtered2, ["Sci-Fi"])
    }

    func testShouldShowSeriesFilter() {
        let uuid = UUID()
        let server = CalibreServer(uuid: uuid, name: "S", baseUrl: "http://x", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "lib", name: "lib")
        var book = CalibreBook(id: 1, library: library)

        // Empty series should not show
        book.series = ""
        XCTAssertFalse(listViewModel.shouldShowSeriesFilter(for: book, filterCriteriaCategory: [:]))

        // Non-empty series, no filter -> should show
        book.series = "Foundation"
        XCTAssertTrue(listViewModel.shouldShowSeriesFilter(for: book, filterCriteriaCategory: [:]))

        // Non-empty series, filter matches -> should not show
        XCTAssertFalse(listViewModel.shouldShowSeriesFilter(for: book, filterCriteriaCategory: ["Series": Set(["Foundation"])]))
    }

    func testBindDownloadSnapshotsPublishesActiveDownload() async throws {
        let library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        var book = CalibreBook(id: 42, library: library)
        book.formats[Format.EPUB.rawValue] = FormatInfo(
            selected: true,
            filename: "library-info-download.epub",
            serverSize: 100,
            serverMTime: Date(),
            cached: false,
            cacheSize: 0,
            cacheMTime: Date.distantPast
        )
        let sourceURL = URL(string: "http://localhost/get/EPUB/42/library")!
        let download = BookFormatDownload(
            isDownloading: false,
            isPaused: true,
            progress: 0.5,
            resumeData: nil,
            book: book,
            format: .EPUB,
            startDatetime: Date(),
            sourceURL: sourceURL,
            savedURL: URL(fileURLWithPath: "/tmp/library-info-download.epub"),
            modificationDate: Date()
        )
        container.downloadManager.activeDownloads[sourceURL] = download

        listViewModel.bindDownloadSnapshots(container: container)

        await waitForViewModelUpdate {
            self.listViewModel.activeDownload(for: book)?.isPaused == true
        }
        XCTAssertEqual(listViewModel.activeDownload(for: book)?.progress, 0.5)
    }

    private func waitForViewModelUpdate(
        _ predicate: @escaping () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<50 {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(predicate(), file: file, line: line)
    }

    private func sourceFileURL(_ repositoryRelativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(repositoryRelativePath)
    }
}
