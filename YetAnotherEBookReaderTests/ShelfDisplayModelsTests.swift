//
//  ShelfDisplayModelsTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-22.
//

import XCTest
import Combine
@testable import YetAnotherEBookReader

@MainActor class ShelfDisplayModelsTests: XCTestCase {
    
    
    func testRecentShelfViewModelMapping() throws {
        let mockAppContainer = MockAppContainerFactory.makeContainer(testName: "ShelfDisplayModelsTests")
        let viewModel = RecentShelfViewModel(container: mockAppContainer)
        
        let item = ShelfBookItem(
            id: "test-id",
            title: "Test Title",
            coverURL: "https://example.com/cover.png",
            progress: 42,
            status: .ready
        )
        
        let expectation = XCTestExpectation(description: "Wait for Combine")
        let cancellable = viewModel.$loadedBooks
            .dropFirst()
            .sink { books in
                if books?.first?.id == "test-id" {
                    expectation.fulfill()
                }
            }
        
        mockAppContainer.recentShelfItemsSubject.send([item])
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(viewModel.displayBooks.count, 1)
        XCTAssertEqual(viewModel.displayBooks[0].id, "test-id")
        XCTAssertEqual(viewModel.displayBooks[0].title, "Test Title")
        cancellable.cancel()
    }
    
    func testSectionShelfViewModelMappingAndFilters() {
        let mockAppContainer = MockAppContainerFactory.makeContainer(testName: "ShelfDisplayModelsTests")

        // Setup library config in mockAppContainer
        let uuid = UUID()
        let mockServer = CalibreServer(uuid: uuid, name: "Test Server", baseUrl: "http://localhost", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let mockLibrary = CalibreLibrary(server: mockServer, key: "testLibrary", name: "Test Library")
        let libraryId = mockLibrary.id
        mockAppContainer.calibreLibraries[libraryId] = mockLibrary

        let viewModel = SectionShelfViewModel(container: mockAppContainer)

        let bookItem = ShelfBookItem(
            id: "test-id",
            title: "Test Title",
            coverURL: "https://example.com/cover.png",
            progress: 0,
            status: .ready,
            libraryId: libraryId
        )

        // Cross-library author section: the section id is "Author: <name>"
        // and the per-book libraryId carries the library ownership. The
        // view model no longer parses the section id to decide visibility.
        let section = ShelfSectionItem(
            id: "Author: testSection",
            title: "Author: testSection",
            books: [bookItem]
        )

        // The viewModel sink is wired directly to
        // discoverShelfItemsSubject (no .collect/.receive(on:)),
        // so it fires synchronously on send() and the section is
        // reflected in displaySections immediately. The shelf
        // data model also sends "Author: Unknown" sections
        // asynchronously, so we check displaySections right after
        // send, before the bootstrapper's emission arrives and
        // overwrites our test section.
        mockAppContainer.discoverShelfItemsSubject.send([section])

        XCTAssertEqual(viewModel.displaySections.count, 1)
        XCTAssertEqual(viewModel.displaySections.getOrNil(0)?.books.count, 1)
        XCTAssertEqual(viewModel.libraryFilters.count, 1)
        XCTAssertEqual(viewModel.libraryFilters.getOrNil(0)?.id, libraryId)
        XCTAssertFalse(viewModel.libraryFilters.getOrNil(0)?.isSelected ?? true)

        // Test Toggling filter
        viewModel.toggleLibraryFilter(libraryId: libraryId)
        XCTAssertTrue(viewModel.pickedLibraries.contains(libraryId))
        // toggleLibraryFilter calls applyFiltering synchronously.
        XCTAssertTrue(viewModel.libraryFilters.getOrNil(0)?.isSelected ?? false)
        // Section still visible (1 book matches the picked library).
        XCTAssertEqual(viewModel.displaySections.count, 1)
        XCTAssertEqual(viewModel.displaySections.getOrNil(0)?.books.count, 1)

        // Test resetting filters
        viewModel.resetLibraryFilters()
        XCTAssertTrue(viewModel.pickedLibraries.isEmpty)
        // resetLibraryFilters calls applyFiltering synchronously.
        XCTAssertFalse(viewModel.libraryFilters.getOrNil(0)?.isSelected ?? true)
        XCTAssertEqual(viewModel.displaySections.count, 1)
    }

    // MARK: - ShelfBookItem libraryId

    func testShelfBookItemDefaultLibraryIdNil() {
        // Recent shelf still constructs ShelfBookItem with the original
        // 5-argument call site; libraryId must default to nil.
        let item = ShelfBookItem(
            id: "recent-1",
            title: "Recent Book",
            coverURL: "",
            progress: 0,
            status: .local
        )
        XCTAssertNil(item.libraryId)
    }

    func testShelfBookItemLibraryIdRoundTrips() {
        let item = ShelfBookItem(
            id: "disc-1",
            title: "Discover Book",
            coverURL: "",
            progress: 0,
            status: .ready,
            libraryId: "lib-abc"
        )
        XCTAssertEqual(item.libraryId, "lib-abc")
    }

    // MARK: - YabrShelfDataModel.buildShelfSectionItem

    func testBuildShelfSectionItemPopulatesLibraryId() {
        let mockAppContainer = MockAppContainerFactory.makeContainer(testName: "ShelfDisplayModelsTests-buildShelf")
        let shelfDataModel = mockAppContainer.shelfDataModel

        let server = CalibreServer(uuid: UUID(), name: "S", baseUrl: "http://localhost", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "k", name: "L")
        let book = CalibreBook(id: 42, library: library)

        let category = YabrShelfDataModel.CategoryObject(type: .Author, category: "Ursula K. Le Guin")
        category.unifiedSearchResult = UnifiedSearchResult(books: [book])

        let section = shelfDataModel.buildShelfSectionItem(category: category)

        XCTAssertEqual(section.id, "Author: Ursula K. Le Guin")
        XCTAssertEqual(section.title, "Author: Ursula K. Le Guin")
        XCTAssertEqual(section.books.count, 1)
        XCTAssertEqual(section.books.getOrNil(0)?.libraryId, library.id)
        XCTAssertEqual(section.books.getOrNil(0)?.id, book.inShelfId)
    }

    func testBuildShelfSectionItemUsesInShelfIdFormat() {
        // The book id must match the CalibreBookRealm primary key format
        // ("id^libraryName@serverUUID") so that downstream consumers
        // (bookExists, getBook, BookDetailView) can find the book.
        // Using the bare Int32 id would cause `bookExists(forPrimaryKey:)`
        // to return false and BookDetailView to stay on "Loading...".
        let mockAppContainer = MockAppContainerFactory.makeContainer(testName: "ShelfDisplayModelsTests-buildShelf-format")
        let shelfDataModel = mockAppContainer.shelfDataModel

        let server = CalibreServer(uuid: UUID(), name: "S", baseUrl: "http://localhost", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "k", name: "My Library")
        let book = CalibreBook(id: 42, library: library)

        let category = YabrShelfDataModel.CategoryObject(type: .Author, category: "Some Author")
        category.unifiedSearchResult = UnifiedSearchResult(books: [book])

        let section = shelfDataModel.buildShelfSectionItem(category: category)
        let bookId = section.books.getOrNil(0)?.id

        XCTAssertNotEqual(bookId, "42", "Bare Int32 id is not the CalibreBookRealm primary key")
        XCTAssertEqual(bookId, "42^My Library@\(server.uuid.uuidString)")
        XCTAssertEqual(bookId, book.inShelfId)
    }
}
