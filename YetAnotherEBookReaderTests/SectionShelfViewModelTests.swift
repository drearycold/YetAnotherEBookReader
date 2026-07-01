//
//  SectionShelfViewModelTests.swift
//  YetAnotherEBookReaderTests
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
class SectionShelfViewModelTests: XCTestCase {
    var viewModel: SectionShelfViewModel!
    var mockAppContainer: AppContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()

        mockAppContainer = MockAppContainerFactory.makeContainer(testName: "SectionShelfViewModelTests")
        mockAppContainer.bookManager.isShelfLoaded = false

        viewModel = SectionShelfViewModel(container: mockAppContainer)
    }

    override func tearDownWithError() throws {
        viewModel = nil
        mockAppContainer = nil
        try super.tearDownWithError()
    }

    func testInitialization() {
        XCTAssertEqual(viewModel.displaySections.count, 0)
        XCTAssertEqual(viewModel.pickedLibraries.count, 0)
    }

    func testRefreshShelf() async {
        await viewModel.refreshShelf()
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testDownloadSelectedBooks() {
        viewModel.downloadSelectedBooks(bookIds: [])
        viewModel.downloadSelectedBooks(bookIds: ["non-existent"])
    }

    func testUpdateShelfModels() async {
        let uuid = UUID()
        let server = CalibreServer(uuid: uuid, name: "Mock Server", baseUrl: "http://localhost:8080", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "libId", name: "MockLibrary")
        mockAppContainer.calibreLibraries[library.id] = library

        let section = ShelfSectionItem(
            id: "Author: testSection",
            title: "Author: testSection",
            books: []
        )

        publishDiscoverSections([section])
        await waitForViewModelUpdate { self.viewModel.displaySections.count == 1 }

        XCTAssertEqual(viewModel.displaySections.count, 1)
        XCTAssertEqual(viewModel.displaySections.getOrNil(0)?.id, "Author: testSection")
    }

    func testTapBook() throws {
        viewModel.tapBook(bookId: "non-existent")
        XCTAssertNil(viewModel.presentingBookDetailId)

        viewModel.selectionState.isEditing = true
        viewModel.tapBook(bookId: "test-id")
        XCTAssertTrue(viewModel.selectionState.selectedBookIds.contains("test-id"))
        viewModel.tapBook(bookId: "test-id")
        XCTAssertFalse(viewModel.selectionState.selectedBookIds.contains("test-id"))
    }

    func testDownloadSelectedBooksWrapper() throws {
        viewModel.selectionState.selectedBookIds = ["test-book-id"]
        viewModel.selectionState.isEditing = true

        viewModel.downloadSelectedBooks()

        XCTAssertTrue(viewModel.selectionState.selectedBookIds.isEmpty)
        XCTAssertFalse(viewModel.selectionState.isEditing)
    }

    func testCalibreUpdatedDeletionDismissal() async throws {
        viewModel.presentingBookDetailId = "deleted-book-id"
        mockAppContainer.calibreUpdatedSubject.send(.deleted("deleted-book-id"))

        await waitForViewModelUpdate { self.viewModel.presentingBookDetailId == nil }
        XCTAssertNil(viewModel.presentingBookDetailId)
    }

    func testSelectAllAndClear() throws {
        let item = ShelfBookItem(id: "book-1", title: "Book 1", coverURL: "", progress: 50, status: .ready)
        let section = ShelfSectionItem(id: "section-1", title: "Section 1", books: [item])

        viewModel.displaySections = [section]

        viewModel.selectAllBooks()
        XCTAssertEqual(viewModel.selectionState.selectedBookIds.count, 1)
        XCTAssertTrue(viewModel.selectionState.selectedBookIds.contains("book-1"))

        viewModel.clearSelection()
        XCTAssertEqual(viewModel.selectionState.selectedBookIds.count, 0)
    }

    // MARK: - Cross-library section + book-level library filter

    private func makeLibrary(serverName: String, libraryKey: String, libraryName: String) -> (server: CalibreServer, library: CalibreLibrary) {
        let server = CalibreServer(uuid: UUID(), name: serverName, baseUrl: "http://localhost/\(serverName)", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: libraryKey, name: libraryName)
        return (server, library)
    }

    func testCrossLibraryAuthorSectionShownWithoutFilter() async {
        let (_, lib1) = makeLibrary(serverName: "S1", libraryKey: "k1", libraryName: "Library 1")
        let (_, lib2) = makeLibrary(serverName: "S2", libraryKey: "k2", libraryName: "Library 2")
        mockAppContainer.calibreLibraries[lib1.id] = lib1
        mockAppContainer.calibreLibraries[lib2.id] = lib2

        let book1 = ShelfBookItem(id: "b1", title: "Book 1", coverURL: "", progress: 0, status: .ready, libraryId: lib1.id)
        let book2 = ShelfBookItem(id: "b2", title: "Book 2", coverURL: "", progress: 0, status: .ready, libraryId: lib2.id)
        let section = ShelfSectionItem(id: "Author: Ursula K. Le Guin", title: "Author: Ursula K. Le Guin", books: [book1, book2])

        publishDiscoverSections([section])
        await waitForViewModelUpdate { self.viewModel.displaySections.count == 1 }

        XCTAssertEqual(viewModel.displaySections.count, 1)
        XCTAssertEqual(viewModel.displaySections.getOrNil(0)?.books.count, 2)
        XCTAssertEqual(viewModel.libraryFilters.count, 2)
        XCTAssertTrue(viewModel.pickedLibraries.isEmpty)
    }

    func testLibraryFilterFiltersBooksNotSections() async {
        let (_, lib1) = makeLibrary(serverName: "S1", libraryKey: "k1", libraryName: "Library 1")
        let (_, lib2) = makeLibrary(serverName: "S2", libraryKey: "k2", libraryName: "Library 2")
        mockAppContainer.calibreLibraries[lib1.id] = lib1
        mockAppContainer.calibreLibraries[lib2.id] = lib2

        let book1 = ShelfBookItem(id: "b1", title: "Book 1", coverURL: "", progress: 0, status: .ready, libraryId: lib1.id)
        let book2 = ShelfBookItem(id: "b2", title: "Book 2", coverURL: "", progress: 0, status: .ready, libraryId: lib2.id)
        let section = ShelfSectionItem(id: "Author: Ursula K. Le Guin", title: "Author: Ursula K. Le Guin", books: [book1, book2])

        publishDiscoverSections([section])
        await waitForViewModelUpdate { self.viewModel.displaySections.count == 1 }
        viewModel.toggleLibraryFilter(libraryId: lib1.id)

        XCTAssertEqual(viewModel.displaySections.count, 1)
        XCTAssertEqual(viewModel.displaySections.getOrNil(0)?.books.count, 1)
        XCTAssertEqual(viewModel.displaySections.getOrNil(0)?.books.getOrNil(0)?.id, "b1")
        XCTAssertEqual(viewModel.displaySections.getOrNil(0)?.id, "Author: Ursula K. Le Guin")
    }

    func testEmptySectionAfterFilterHidden() async {
        let (_, lib1) = makeLibrary(serverName: "S1", libraryKey: "k1", libraryName: "Library 1")
        let (_, lib2) = makeLibrary(serverName: "S2", libraryKey: "k2", libraryName: "Library 2")
        mockAppContainer.calibreLibraries[lib1.id] = lib1
        mockAppContainer.calibreLibraries[lib2.id] = lib2

        let book1 = ShelfBookItem(id: "b1", title: "Book 1", coverURL: "", progress: 0, status: .ready, libraryId: lib1.id)
        let section = ShelfSectionItem(id: "Author: One", title: "Author: One", books: [book1])

        publishDiscoverSections([section])
        await waitForViewModelUpdate { self.viewModel.displaySections.count == 1 }
        viewModel.toggleLibraryFilter(libraryId: lib2.id)

        XCTAssertEqual(viewModel.displaySections.count, 0)
    }

    func testLibraryFiltersAggregatedFromBookLevelLibraryId() async {
        let (_, lib1) = makeLibrary(serverName: "S1", libraryKey: "k1", libraryName: "Library 1")
        let (_, lib2) = makeLibrary(serverName: "S2", libraryKey: "k2", libraryName: "Library 2")
        mockAppContainer.calibreLibraries[lib1.id] = lib1
        mockAppContainer.calibreLibraries[lib2.id] = lib2

        let book1 = ShelfBookItem(id: "b1", title: "Book 1", coverURL: "", progress: 0, status: .ready, libraryId: lib1.id)
        let book2 = ShelfBookItem(id: "b2", title: "Book 2", coverURL: "", progress: 0, status: .ready, libraryId: lib2.id)
        let s1 = ShelfSectionItem(id: "Author: A", title: "Author: A", books: [book1])
        let s2 = ShelfSectionItem(id: "Author: B", title: "Author: B", books: [book2])

        publishDiscoverSections([s1, s2])
        await waitForViewModelUpdate { self.viewModel.displaySections.count == 2 }

        let filterIds = Set(viewModel.libraryFilters.map { $0.id })
        XCTAssertEqual(viewModel.libraryFilters.count, 2)
        XCTAssertTrue(filterIds.contains(lib1.id))
        XCTAssertTrue(filterIds.contains(lib2.id))
    }

    func testBootstrapIfDatabaseReadyIdempotent() {
        // Without a database-ready container, bootstrap is a no-op.
        let freshContainer = MockAppContainerFactory.makeContainer(testName: "SectionShelfViewModelTests-bootstrap")
        freshContainer.bookManager.isShelfLoaded = false
        let freshVM = SectionShelfViewModel(container: freshContainer)

        // Calling twice should not crash and should not double-fill sections.
        freshVM.bootstrapIfDatabaseReady()
        freshVM.bootstrapIfDatabaseReady()

        XCTAssertEqual(freshVM.displaySections.count, 0)
    }

    func testInitialLoadCompleteTracking() async throws {
        XCTAssertFalse(viewModel.isInitialLoadComplete)

        mockAppContainer.shelfDataModel.setDiscoverShelfSnapshotForTesting(
            .init(sections: [], isInitialLoadComplete: true),
            sendLegacySubject: false
        )

        await waitForViewModelUpdate { self.viewModel.isInitialLoadComplete }
        XCTAssertTrue(viewModel.isInitialLoadComplete)
    }

    private func publishDiscoverSections(_ sections: [ShelfSectionItem], isInitialLoadComplete: Bool = false) {
        mockAppContainer.shelfDataModel.setDiscoverShelfSnapshotForTesting(
            .init(sections: sections, isInitialLoadComplete: isInitialLoadComplete),
            sendLegacySubject: false
        )
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
