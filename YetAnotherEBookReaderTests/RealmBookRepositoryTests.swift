//
//  RealmBookRepositoryTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-24.
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

final class RealmBookRepositoryTests: XCTestCase, LibraryResolver {
    private var databaseService: DatabaseService!
    private var repository: RealmBookRepository!
    private var realmConfig: Realm.Configuration!
    
    // LibraryResolver
    private var resolvedLibraries: [String: CalibreLibrary] = [:]
    func library(forServerUUID serverUUID: String, libraryName: String) -> CalibreLibrary? {
        let key = "\(serverUUID)_\(libraryName)"
        return resolvedLibraries[key]
    }
    
    override func setUpWithError() throws {
        realmConfig = MockDatabaseService.inMemoryConfiguration()
        databaseService = DatabaseService.shared
        databaseService.setup(conf: realmConfig)
        repository = RealmBookRepository(databaseService: databaseService, libraryResolver: self)
        resolvedLibraries.removeAll()
    }
    
    override func tearDownWithError() throws {
        databaseService = nil
        repository = nil
        realmConfig = nil
        resolvedLibraries.removeAll()
    }
    
    func testSaveBook_persistsToRealm() throws {
        let server = TestFixtures.makeServer()
        let library = TestFixtures.makeLibrary(server: server, key: "lib1", name: "Library One")
        resolvedLibraries["\(server.uuid.uuidString)_Library One"] = library
        
        let book = TestFixtures.makeBook(id: 42, library: library)
        
        // Save
        repository.saveBook(book)
        
        // Fetch
        let fetched = repository.getBook(id: book.inShelfId)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, book.id)
        XCTAssertEqual(fetched?.title, book.title)
    }
    
    func testGetBook_byPrimaryKey() throws {
        let server = TestFixtures.makeServer()
        let library = TestFixtures.makeLibrary(server: server, name: "Get Lib")
        resolvedLibraries["\(server.uuid.uuidString)_\(library.name)"] = library
        
        let book = TestFixtures.makeBook(id: 99, library: library)
        repository.saveBook(book)
        
        let fetched = repository.getBook(id: book.inShelfId)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, book.title)
    }
    
    func testDeleteBook_removesFromRealm() throws {
        let server = TestFixtures.makeServer()
        let library = TestFixtures.makeLibrary(server: server, name: "Delete Library")
        resolvedLibraries["\(server.uuid.uuidString)_\(library.name)"] = library
        
        let book = TestFixtures.makeBook(id: 50, library: library)
        repository.saveBook(book)
        XCTAssertTrue(repository.bookExists(id: book.inShelfId))
        
        repository.deleteBook(id: book.inShelfId)
        XCTAssertFalse(repository.bookExists(id: book.inShelfId))
    }
    
    func testGetAllBooksInShelf() throws {
        let server = TestFixtures.makeServer()
        let library = TestFixtures.makeLibrary(server: server, name: "Shelf Library")
        resolvedLibraries["\(server.uuid.uuidString)_\(library.name)"] = library
        
        var book1 = TestFixtures.makeBook(id: 1, library: library)
        book1.inShelf = true
        var book2 = TestFixtures.makeBook(id: 2, library: library)
        book2.inShelf = false
        
        repository.saveBook(book1)
        repository.saveBook(book2)
        
        let shelfBooks = repository.getAllBooksInShelf()
        XCTAssertEqual(shelfBooks.count, 1)
        XCTAssertEqual(shelfBooks.first?.id, book1.id)
    }
    
    func testSaveBook_updatesExisting() throws {
        let server = TestFixtures.makeServer()
        let library = TestFixtures.makeLibrary(server: server, name: "Update Library")
        resolvedLibraries["\(server.uuid.uuidString)_\(library.name)"] = library
        
        var book = TestFixtures.makeBook(id: 5, library: library)
        book.title = "Original Title"
        repository.saveBook(book)
        
        var updatedBook = book
        updatedBook.title = "Updated Title"
        repository.saveBook(updatedBook)
        
        let fetched = repository.getBook(id: book.inShelfId)
        XCTAssertEqual(fetched?.title, "Updated Title")
    }
    
    func testBookExists() throws {
        let server = TestFixtures.makeServer()
        let library = TestFixtures.makeLibrary(server: server, name: "Exists Library")
        resolvedLibraries["\(server.uuid.uuidString)_\(library.name)"] = library
        
        let book = TestFixtures.makeBook(id: 10, library: library)
        XCTAssertFalse(repository.bookExists(id: book.inShelfId))
        
        repository.saveBook(book)
        XCTAssertTrue(repository.bookExists(id: book.inShelfId))
    }
    
    func testPersistMetadataEntriesUpdatesExistingBookAndReturnsShelfBook() throws {
        let server = TestFixtures.makeServer()
        let library = TestFixtures.makeLibrary(server: server, name: "Metadata Library")
        resolvedLibraries["\(server.uuid.uuidString)_\(library.name)"] = library

        var book = TestFixtures.makeBook(id: 301, library: library)
        book.title = "Old Title"
        book.inShelf = true
        repository.saveBook(book)

        var entry = CalibreBookEntry()
        entry.title = "Updated Metadata Title"
        entry.publisher = "Metadata Publisher"
        entry.last_modified = "2026-07-03T01:02:03+00:00"
        entry.timestamp = "2026-07-03T01:02:03+00:00"
        entry.pubdate = "2026-07-02T01:02:03+00:00"
        entry.authors = ["Metadata Author"]
        entry.tags = ["Repository"]
        entry.format_metadata = [
            "EPUB": CalibreBookFormatMetadataEntry(
                path: "Updated Metadata Title.epub",
                size: 4096,
                mtime: "2026-07-03T01:02:03.000+00:00"
            )
        ]

        let result = repository.persistMetadataEntries(
            library: library,
            bookIds: [book.id],
            entries: [book.id.description: entry],
            json: [
                book.id.description: [
                    "user_metadata": [
                        "#genre": [
                            "label": "Genre",
                            "#value#": "Reference"
                        ]
                    ]
                ]
            ],
            includeAnnotationBooks: false
        )

        XCTAssertEqual(result.booksUpdated, [book.id])
        XCTAssertEqual(result.booksInShelf.first?.title, "Updated Metadata Title")
        XCTAssertEqual(repository.getBook(id: book.inShelfId)?.publisher, "Metadata Publisher")
    }
    
    /// calibre answers null for a book it no longer has: the book is reported deleted, kept, and
    /// marked synced so it isn't asked for again until it changes.
    func testPersistMetadataEntriesReportsANullEntryAsDeleted() throws {
        let server = TestFixtures.makeServer()
        let library = TestFixtures.makeLibrary(server: server, name: "Deleted Library")
        resolvedLibraries["\(server.uuid.uuidString)_\(library.name)"] = library

        var book = TestFixtures.makeBook(id: 302, library: library)
        book.inShelf = true
        book.lastModified = Date(timeIntervalSince1970: 1_000)
        book.lastSynced = Date(timeIntervalSince1970: 0)
        repository.saveBook(book)

        let result = repository.persistMetadataEntries(
            library: library,
            bookIds: [book.id],
            entries: [book.id.description: nil],
            json: [:],
            includeAnnotationBooks: false
        )

        XCTAssertEqual(result.booksDeleted, [book.id])
        XCTAssertEqual(result.booksUpdated, [])
        let kept = try XCTUnwrap(repository.getBook(id: book.inShelfId))
        XCTAssertTrue(kept.inShelf)
        XCTAssertFalse(kept.needsMetadataRefresh)
    }

    func testResetBooks() throws {
        let server = TestFixtures.makeServer()
        let library = TestFixtures.makeLibrary(server: server, name: "Reset Library")
        resolvedLibraries["\(server.uuid.uuidString)_\(library.name)"] = library
        
        var book = TestFixtures.makeBook(id: 301, library: library)
        book.lastModified = Date()
        book.lastSynced = Date()
        book.title = "Original Title"
        repository.saveBook(book)
        
        repository.resetBooks(serverUUID: server.uuid.uuidString, libraryName: library.name)
        
        let fetched = repository.getBook(id: book.inShelfId)
        XCTAssertEqual(fetched?.title, "Original Title")
        XCTAssertEqual(fetched?.lastModified, book.lastModified)
        XCTAssertEqual(fetched?.lastSynced, .distantPast)
        XCTAssertEqual(fetched?.needsMetadataRefresh, true)
    }
    
    func testObserveBookPublishesInitialRealmNotificationAndUpdates() async throws {
        let server = TestFixtures.makeServer()
        let library = TestFixtures.makeLibrary(server: server, name: "Observe Library")
        resolvedLibraries["\(server.uuid.uuidString)_\(library.name)"] = library
        
        var book = TestFixtures.makeBook(id: 100, library: library)
        book.title = "Initial Title"
        repository.saveBook(book)
        
        let initialExpectation = expectation(description: "Initial existing book observed")
        let updateExpectation = expectation(description: "Book update observed")
        var observedBooks: [CalibreBook?] = []
        
        let task = Task { @MainActor [repository] in
            guard let repository else { return }
            for await observedBook in repository.observeBook(id: book.inShelfId) {
                observedBooks.append(observedBook)
                if observedBooks.count == 1 {
                    initialExpectation.fulfill()
                } else if observedBooks.count >= 2 {
                    updateExpectation.fulfill()
                    break
                }
            }
        }

        await fulfillment(of: [initialExpectation], timeout: 2.0)
        book.title = "Updated Title"
        repository.saveBook(book)
        
        await fulfillment(of: [updateExpectation], timeout: 2.0)
        task.cancel()
        
        XCTAssertEqual(observedBooks.count, 2)
        XCTAssertEqual(observedBooks[0]?.title, "Initial Title")
        XCTAssertEqual(observedBooks[1]?.id, book.id)
        XCTAssertEqual(observedBooks[1]?.title, "Updated Title")
    }
}
