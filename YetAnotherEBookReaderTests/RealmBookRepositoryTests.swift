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
    
    func testBulkUpdateBooks() throws {
        let server = TestFixtures.makeServer()
        let library = TestFixtures.makeLibrary(server: server, name: "Bulk Library")
        resolvedLibraries["\(server.uuid.uuidString)_\(library.name)"] = library
        
        let book1 = TestFixtures.makeBook(id: 10, library: library)
        let book2 = TestFixtures.makeBook(id: 20, library: library)
        
        repository.saveBook(book1)
        repository.saveBook(book2)
        
        let records: [[String: Any]] = [
            ["primaryKey": book1.inShelfId, "title": "Bulk Updated Title 1"],
            ["primaryKey": book2.inShelfId, "title": "Bulk Updated Title 2"]
        ]
        
        repository.bulkUpdateBooks(records: records)
        
        XCTAssertEqual(repository.getBook(id: book1.inShelfId)?.title, "Bulk Updated Title 1")
        XCTAssertEqual(repository.getBook(id: book2.inShelfId)?.title, "Bulk Updated Title 2")
    }
    
    func testFindDeletedBookIds() throws {
        let server = TestFixtures.makeServer()
        let library = TestFixtures.makeLibrary(server: server, name: "Delete Ids Library")
        resolvedLibraries["\(server.uuid.uuidString)_\(library.name)"] = library
        
        var book1 = TestFixtures.makeBook(id: 101, library: library)
        book1.inShelf = false
        
        var book2 = TestFixtures.makeBook(id: 102, library: library)
        book2.inShelf = false
        
        var book3 = TestFixtures.makeBook(id: 103, library: library)
        book3.inShelf = true
        
        repository.saveBook(book1)
        repository.saveBook(book2)
        repository.saveBook(book3)
        
        let activeIds: [String: Any] = ["101": true]
        
        let deletedIds = repository.findDeletedBookIds(
            serverUUID: server.uuid.uuidString,
            libraryName: library.name,
            activeIds: activeIds
        )
        
        XCTAssertEqual(deletedIds, [102])
    }
    
    func testCountAndNeedUpdateBooks() throws {
        let server = TestFixtures.makeServer()
        let library = TestFixtures.makeLibrary(server: server, name: "Update Check Library")
        resolvedLibraries["\(server.uuid.uuidString)_\(library.name)"] = library
        
        let now = Date()
        
        var book1 = TestFixtures.makeBook(id: 201, library: library)
        book1.lastModified = now.addingTimeInterval(-100)
        book1.lastSynced = now
        repository.saveBook(book1)
        
        var book2 = TestFixtures.makeBook(id: 202, library: library)
        book2.lastModified = now.addingTimeInterval(-50)
        book2.lastSynced = now.addingTimeInterval(-200)
        repository.saveBook(book2)
        
        var book3 = TestFixtures.makeBook(id: 203, library: library)
        book3.lastModified = now
        book3.lastSynced = now.addingTimeInterval(-200)
        repository.saveBook(book3)
        
        let result = repository.countAndNeedUpdateBooks(
            serverUUID: server.uuid.uuidString,
            libraryName: library.name
        )
        
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.needUpdateIds, [203, 202])
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
        XCTAssertEqual(fetched?.title, "__RESET__")
        XCTAssertEqual(fetched?.lastModified.timeIntervalSince1970, 0)
        XCTAssertEqual(fetched?.lastSynced.timeIntervalSince1970, 0)
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
