//
//  CalibreBookManagerTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-23.
//

import XCTest
import RealmSwift
import Combine
@testable import YetAnotherEBookReader

final class CalibreBookManagerTests: XCTestCase {
    private var container: AppContainer!
    private var bookManager: CalibreBookManager!
    private var library: CalibreLibrary!
    private var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        container = MockAppContainerFactory.makeContainer(testName: "CalibreBookManagerTests-\(UUID().uuidString)")
        bookManager = container.bookManager
        library = container.libraryManager.calibreLibraries.first?.value
        cancellables = []
        XCTAssertNotNil(library, "Mock library should be populated")
    }

    override func tearDownWithError() throws {
        container = nil
        bookManager = nil
        library = nil
        cancellables = nil
    }

    func testPopulateBookShelf() {
        // Create a mock book and mark it inShelf = true
        var book = CalibreBook(id: 101, library: library)
        book.title = "Shelf Book"
        book.inShelf = true
        bookManager.updateBook(book: book)

        // Clear in-memory dictionary
        bookManager.booksInShelf.removeAll()

        // Populate
        bookManager.populateBookShelf()

        // Verify loaded
        XCTAssertNotNil(bookManager.booksInShelf[book.inShelfId])
        XCTAssertEqual(bookManager.booksInShelf[book.inShelfId]?.title, "Shelf Book")
    }

    func testAddBookToShelfAndRemove() {
        var book = CalibreBook(id: 102, library: library)
        book.title = "Read Me"
        book.formats[Format.EPUB.rawValue] = .init(filename: "Read Me.epub", serverSize: 500, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date.distantPast, manifest: nil)

        // 1. Add to shelf
        bookManager.addToShelf(book: book, formats: [.EPUB])

        // Verify marked in shelf and formats updated
        let addedBook = bookManager.booksInShelf[book.inShelfId]
        XCTAssertNotNil(addedBook)
        XCTAssertTrue(addedBook?.inShelf ?? false)
        XCTAssertTrue(addedBook?.formats[Format.EPUB.rawValue]?.selected ?? false)

        // Verify repository is updated
        XCTAssertTrue(bookManager.bookExists(forPrimaryKey: book.inShelfId))

        // 2. Remove from shelf
        bookManager.removeFromShelf(inShelfId: book.inShelfId)

        // Verify removed from in-memory cache
        XCTAssertNil(bookManager.booksInShelf[book.inShelfId])

        // Verify database is updated
        let dbBook = bookManager.getBook(for: book.inShelfId)
        XCTAssertNotNil(dbBook)
        XCTAssertFalse(dbBook?.inShelf ?? true)
    }

    func testGetBookReturnsNilForUnknownId() {
        XCTAssertNil(bookManager.getBook(for: "non-existent-id"))
    }

    func testBookExists() {
        var book = CalibreBook(id: 103, library: library)
        book.title = "Existing Book"
        bookManager.updateBook(book: book)

        XCTAssertTrue(bookManager.bookExists(forPrimaryKey: book.inShelfId))
        XCTAssertFalse(bookManager.bookExists(forPrimaryKey: "fake-id"))
    }

    func testRemoveFromRealm() {
        var book = CalibreBook(id: 104, library: library)
        book.title = "Delete Me"
        bookManager.updateBook(book: book)
        XCTAssertTrue(bookManager.bookExists(forPrimaryKey: book.inShelfId))

        bookManager.removeFromRealm(book: book)
        XCTAssertFalse(bookManager.bookExists(forPrimaryKey: book.inShelfId))
    }

    func testSelectedBookIdPublishesChange() {
        let expectation = self.expectation(description: "selectedBookId publisher fires")
        var receivedId: String? = nil

        bookManager.$selectedBookId
            .dropFirst()
            .sink { id in
                receivedId = id
                expectation.fulfill()
            }
            .store(in: &cancellables)

        bookManager.selectedBookId = "test-selected-id"

        waitForExpectations(timeout: 2.0, handler: nil)
        XCTAssertEqual(receivedId, "test-selected-id")
        XCTAssertEqual(bookManager.readingBookInShelfId, "test-selected-id")
    }

    func testCurrentBookIdSetsSelectedBookId() {
        bookManager.currentBookId = "test-current-id"
        XCTAssertEqual(bookManager.selectedBookId, "test-current-id")
    }

    func testCacheInfoAndLifecycle() {
        var book = CalibreBook(id: 105, library: library)
        book.title = "Cached Book"
        book.formats[Format.EPUB.rawValue] = .init(filename: "Cached Book.epub", serverSize: 500, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date.distantPast, manifest: nil)

        // Add to cache (doesn't write file, but sets cache metadata)
        bookManager.addedCache(book: book, format: .EPUB)
        
        // Let's create a dummy file at the saved url to simulate cached format
        guard let savedUrl = getSavedUrl(book: book, format: .EPUB) else {
            XCTFail("Failed to get saved url")
            return
        }
        
        try? FileManager.default.createDirectory(at: savedUrl.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        FileManager.default.createFile(atPath: savedUrl.path, contents: Data("test".utf8), attributes: nil)
        defer {
            try? FileManager.default.removeItem(at: savedUrl)
        }

        let cacheInfo = bookManager.getCacheInfo(book: book, format: .EPUB)
        XCTAssertNotNil(cacheInfo)
        XCTAssertTrue(cacheInfo!.0 > 0) // file size > 0

        // Clear cache
        bookManager.clearCache(book: book, format: .EPUB)
        XCTAssertNil(bookManager.getCacheInfo(book: book, format: .EPUB))
    }

    func testConvertRealmBookToDomain() {
        let realm = try! Realm(configuration: container.realmConf!)
        let bookRealm = CalibreBookRealm()
        bookRealm.serverUUID = library.server.uuid.uuidString
        bookRealm.libraryName = library.name
        bookRealm.idInLib = 106
        bookRealm.title = "Realm Title"
        bookRealm.inShelf = true
        bookRealm.updatePrimaryKey()

        try! realm.write {
            realm.add(bookRealm, update: .modified)
        }

        let domainBook = bookManager.convert(bookRealm: bookRealm)
        XCTAssertNotNil(domainBook)
        XCTAssertEqual(domainBook?.title, "Realm Title")
        XCTAssertEqual(domainBook?.id, 106)
    }

    func testShouldAutoUpdateGoodreadsFailsWhenDisabled() {
        let result = bookManager.shouldAutoUpdateGoodreads(library: library)
        // In mock setup, Goodreads Sync or DSReaderHelper is disabled by default
        XCTAssertNil(result)
    }

    func testGoToNextAndPreviousBookStubsDoNotCrash() {
        bookManager.readingBook = CalibreBook(id: 201, library: library)
        
        // Stubs should not crash and should keep state intact
        bookManager.goToNextBook()
        XCTAssertEqual(bookManager.readingBook?.id, 201)
        
        bookManager.goToPreviousBook()
        XCTAssertEqual(bookManager.readingBook?.id, 201)
    }
}
