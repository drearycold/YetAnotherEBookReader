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
        XCTAssertTrue(listViewModel.selectedBookIds.isEmpty)
        XCTAssertTrue(listViewModel.downloadBookList.isEmpty)
        XCTAssertEqual(listViewModel.searchString, "")
        XCTAssertFalse(listViewModel.batchDownloadSheetPresenting)
        XCTAssertFalse(listViewModel.booksListInfoPresenting)
        XCTAssertFalse(listViewModel.searchHistoryPresenting)
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
}
