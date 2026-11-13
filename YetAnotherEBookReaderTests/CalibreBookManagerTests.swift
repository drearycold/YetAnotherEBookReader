//
//  CalibreBookManagerTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-23.
//

import XCTest
@testable import YetAnotherEBookReader

final class CalibreBookManagerTests: XCTestCase {
    private var container: AppContainer!
    private var bookManager: CalibreBookManager!
    private var library: CalibreLibrary!

    override func setUpWithError() throws {
        container = MockAppContainerFactory.makeContainer(testName: "CalibreBookManagerTests")
        bookManager = container.bookManager
        library = container.libraryManager.calibreLibraries.first?.value
        XCTAssertNotNil(library, "Mock library should be populated")
    }

    override func tearDownWithError() throws {
        container = nil
        bookManager = nil
        library = nil
    }

    func testPopulateBookShelf() {
        // Create a mock book and mark it inShelf = true
        var book = CalibreBook(id: 101, library: library)
        book.title = "Shelf Book"
        book.inShelf = true
        bookManager.updateBook(book: book)

        // Clear in-memory dictionary
        bookManager.booksInShelf.removeAll()

        let expectation = XCTestExpectation(description: "Wait for booksInShelf to be populated")
        
        let manager = bookManager!
        let observationTask = Task {
            for await books in manager.booksInShelfSnapshots() {
                if books[book.inShelfId] != nil {
                    expectation.fulfill()
                    return
                }
            }
        }
        defer {
            observationTask.cancel()
        }

        // Populate
        var completionCount = 0
        var completionWasOnMainThread = false
        bookManager.populateBookShelf {
            completionCount += 1
            completionWasOnMainThread = Thread.isMainThread
        }

        wait(for: [expectation], timeout: 5.0)

        // Verify loaded
        XCTAssertNotNil(bookManager.booksInShelf[book.inShelfId])
        XCTAssertEqual(bookManager.booksInShelf[book.inShelfId]?.title, "Shelf Book")
        XCTAssertEqual(completionCount, 1)
        XCTAssertTrue(completionWasOnMainThread)
    }

    func testPopulateBookShelfSendsShelfUpdateByDefault() async {
        let expectation = XCTestExpectation(description: "Shelf update is sent")
        let task = Task { @MainActor in
            for await signal in container.calibreUpdates() {
                if case .shelf = signal {
                    expectation.fulfill()
                    return
                }
            }
        }

        await Task.yield()
        bookManager.populateBookShelf()

        await fulfillment(of: [expectation], timeout: 1.0)
        task.cancel()
    }

    func testPopulateBookShelfCanSuppressShelfUpdate() async {
        let invertedExpectation = XCTestExpectation(description: "Shelf update is not sent")
        invertedExpectation.isInverted = true
        let task = Task { @MainActor in
            for await signal in container.calibreUpdates() {
                if case .shelf = signal {
                    invertedExpectation.fulfill()
                }
            }
        }

        await Task.yield()
        var completionCount = 0
        var completionWasOnMainThread = false
        bookManager.populateBookShelf(sendShelfUpdate: false) {
            completionCount += 1
            completionWasOnMainThread = Thread.isMainThread
        }

        await fulfillment(of: [invertedExpectation], timeout: 0.2)
        task.cancel()
        XCTAssertEqual(completionCount, 1)
        XCTAssertTrue(completionWasOnMainThread)
        XCTAssertTrue(bookManager.isShelfLoaded)
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

    func testDeleteBook() {
        var book = CalibreBook(id: 104, library: library)
        book.title = "Delete Me"
        bookManager.updateBook(book: book)
        XCTAssertTrue(bookManager.bookExists(forPrimaryKey: book.inShelfId))

        bookManager.deleteBook(book: book)
        XCTAssertFalse(bookManager.bookExists(forPrimaryKey: book.inShelfId))
    }

    func testSelectedBookIdPublishesChange() {
        let expectation = self.expectation(description: "selectedBookId publisher fires")
        var receivedId: String? = nil

        let manager = bookManager!
        let observationTask = Task {
            for await id in manager.selectedBookIdSnapshots() {
                guard id == "test-selected-id" else { continue }
                receivedId = id
                expectation.fulfill()
                return
            }
        }
        defer {
            observationTask.cancel()
        }

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

    func testGetBookReturnsRepositoryDomainBook() {
        var book = CalibreBook(id: 106, library: library)
        book.title = "Repository Title"
        book.inShelf = true

        bookManager.updateBook(book: book)

        let domainBook = bookManager.getBook(for: book.inShelfId)
        XCTAssertNotNil(domainBook)
        XCTAssertEqual(domainBook?.title, "Repository Title")
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

@MainActor
final class LocalFileCommitTests: XCTestCase {
    func testFailedOverwriteCopyKeepsThePreviousBook() throws {
        try assertFailedOverwrite(move: false)
    }

    func testFailedOverwriteMoveKeepsThePreviousBook() throws {
        try assertFailedOverwrite(move: true, failReplacement: true)
    }

    func testFailedRemovalKeepsTheBookAndItsFile() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var files = CalibreBookManager.FileOperations()
        files.remove = { _ in throw CocoaError(.fileWriteNoPermission) }
        let manager = fixture.manager(files: files)
        let signals = fixture.container.calibreUpdates()
        let deleted = expectation(description: "Failed removal does not publish deleted")
        deleted.isInverted = true
        let observer = Task {
            for await event in signals {
                if case .deleted(let id) = event, id == fixture.oldBook.inShelfId {
                    deleted.fulfill()
                    return
                }
            }
        }
        defer { observer.cancel() }
        XCTAssertEqual(manager.clearCache(book: fixture.oldBook, format: .PDF), .fileFailed)

        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.oldBytes)
        XCTAssertTrue(fixture.repository.getBook(id: fixture.oldBook.inShelfId)?.formats["PDF"]?.cached == true)
        XCTAssertTrue(manager.booksInShelf[fixture.oldBook.inShelfId]?.formats["PDF"]?.cached == true)
        await fulfillment(of: [deleted], timeout: 0.25)
    }

    func testPostCommitLibraryCleanupDoesNotRecreateDeletedRecords() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var files = CalibreBookManager.FileOperations()
        files.remove = { _ in throw CocoaError(.fileWriteNoPermission) }
        let manager = fixture.manager(files: files)
        try fixture.repository.commitBookFiles(saving: [], deleting: [fixture.oldBook.inShelfId])
        manager.discardShelfBooks(in: [fixture.oldBook.library.id])

        XCTAssertNil(fixture.repository.getBook(id: fixture.oldBook.inShelfId))
        XCTAssertNil(manager.booksInShelf[fixture.oldBook.inShelfId])
        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.oldBytes)
    }

    func testFailedInstallRetainsTheMoveSource() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try FileManager.default.removeItem(at: fixture.destination)
        var files = CalibreBookManager.FileOperations()
        files.move = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        let manager = fixture.manager(files: files)

        let result = manager.onOpenURL(url: fixture.source, doMove: true, doOverwrite: false, asNew: false)
        XCTAssertEqual(result.error, .fileOpFail)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.path))
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.newBytes)
    }

    func testStorageFailureRestoresTheOldFileAndCanRetry() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let manager = fixture.manager()
        fixture.repository.rejectCommit = true
        let failed = manager.onOpenURL(url: fixture.source, doMove: true, doOverwrite: true, asNew: false)
        XCTAssertEqual(failed.error, .loadMetaFail)
        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.oldBytes)
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.newBytes)
        XCTAssertNotNil(manager.booksInShelf[fixture.oldBook.inShelfId])
        XCTAssertNotNil(fixture.repository.getBook(id: fixture.oldBook.inShelfId))

        fixture.repository.rejectCommit = false
        let success = manager.onOpenURL(url: fixture.source, doMove: true, doOverwrite: true, asNew: false)
        let bookId = try XCTUnwrap(success.bookId)
        XCTAssertNil(success.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.newBytes)
        XCTAssertEqual(manager.calcLocalFileBookId(for: fixture.destination), bookId)
        XCTAssertNil(fixture.repository.getBook(id: fixture.oldBook.inShelfId))
        XCTAssertNil(manager.booksInShelf[fixture.oldBook.inShelfId])
        XCTAssertNotNil(fixture.repository.getBook(library: fixture.oldBook.library, bookId: bookId))
    }

    func testFailedRestoreRetainsTheRecoveryCopy() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.repository.rejectCommit = true
        var files = CalibreBookManager.FileOperations()
        let replace = files.replace
        files.replace = {
            if $0.lastPathComponent == "previous" { throw CocoaError(.fileWriteNoPermission) }
            try replace($0, $1)
        }
        let manager = fixture.manager(files: files)
        let result = manager.onOpenURL(url: fixture.source, doMove: true, doOverwrite: true, asNew: false)
        XCTAssertEqual(result.error, .recoveryRequired)
        let folder = try XCTUnwrap(result.recoveryFolder)
        let backup = fixture.destination.deletingLastPathComponent().appendingPathComponent(folder)
            .appendingPathComponent("previous")
        XCTAssertEqual(try Data(contentsOf: backup), fixture.oldBytes)
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.newBytes)
        XCTAssertNotNil(fixture.repository.getBook(id: fixture.oldBook.inShelfId))
    }

    func testMissingFileRemovalIsIdempotentAndStorageFailureRestoresExistingFile() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let manager = fixture.manager()
        fixture.repository.rejectCommit = true
        XCTAssertEqual(manager.clearCache(book: fixture.oldBook, format: .PDF), .storageFailed)
        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.oldBytes)
        XCTAssertNotNil(manager.booksInShelf[fixture.oldBook.inShelfId])
        fixture.repository.rejectCommit = false
        try FileManager.default.removeItem(at: fixture.destination)
        XCTAssertEqual(manager.clearCache(book: fixture.oldBook, format: .PDF), .committed())
        XCTAssertEqual(manager.clearCache(book: fixture.oldBook, format: .PDF), .committed())
        XCTAssertNil(fixture.repository.getBook(id: fixture.oldBook.inShelfId))
        XCTAssertNil(manager.booksInShelf[fixture.oldBook.inShelfId])
    }

    func testSameFileAndRepeatedImportDoNotCopyOrDeleteTheSource() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var files = CalibreBookManager.FileOperations()
        files.copy = { _, _ in XCTFail("The file is already at its destination"); throw CocoaError(.fileWriteNoPermission) }
        files.remove = { _ in XCTFail("The file is already at its destination"); throw CocoaError(.fileWriteNoPermission) }
        let manager = fixture.manager(files: files)

        let first = manager.onOpenURL(url: fixture.destination, doMove: true, doOverwrite: false, asNew: false)
        let second = manager.onOpenURL(url: fixture.destination, doMove: true, doOverwrite: false, asNew: false)
        XCTAssertNil(first.error)
        XCTAssertNil(second.error)
        XCTAssertEqual(first.bookId, second.bookId)
        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.oldBytes)
        XCTAssertEqual(manager.booksInShelf.count, 1)
    }

    func testCleanupFailureReportsACommittedImportAndSaveAsNewKeepsBothBooks() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var files = CalibreBookManager.FileOperations()
        files.remove = { url in
            if url.lastPathComponent.hasPrefix(".dsreader-file-") { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.removeItem(at: url)
        }
        let manager = fixture.manager(files: files)
        XCTAssertEqual(manager.onOpenURL(url: fixture.source, doMove: false, doOverwrite: false, asNew: false).error,
                       .destConflict)
        let result = manager.onOpenURL(url: fixture.source, doMove: false, doOverwrite: false, asNew: true)
        XCTAssertNil(result.error)
        XCTAssertTrue(result.cleanupPending)
        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.oldBytes)
        let imported = fixture.destination.deletingLastPathComponent().appendingPathComponent("Sample (1).pdf")
        XCTAssertEqual(try Data(contentsOf: imported), fixture.newBytes)
        XCTAssertEqual(manager.booksInShelf.count, 2)
        XCTAssertEqual(fixture.repository.getBook(library: fixture.oldBook.library, bookId: try XCTUnwrap(result.bookId))?
            .formats["PDF"]?.filename, "Sample (1).pdf")
    }

    private func assertFailedOverwrite(move: Bool, failReplacement: Bool = false) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var files = CalibreBookManager.FileOperations()
        if move {
            files.move = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        }
        if failReplacement {
            files.replace = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        }
        if !move {
            files.copy = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        }
        let manager = fixture.manager(files: files)
        let result = manager.onOpenURL(url: fixture.source, doMove: move, doOverwrite: true, asNew: false)

        XCTAssertEqual(result.error, .fileOpFail)
        XCTAssertEqual(try? Data(contentsOf: fixture.destination), fixture.oldBytes)
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.newBytes)
        XCTAssertTrue(fixture.repository.getBook(id: fixture.oldBook.inShelfId)?.formats["PDF"]?.cached == true)
        XCTAssertNotNil(manager.booksInShelf[fixture.oldBook.inShelfId])
    }

    private struct Fixture {
        let directory: URL
        let source: URL
        let destination: URL
        let oldBytes = Data("old PDF fixture".utf8)
        let newBytes = Data("new PDF fixture".utf8)
        let container: AppContainer
        let repository: FailingCommitRepository
        let oldBook: CalibreBook

        @MainActor
        init() throws {
            container = MockAppContainerFactory.makeContainer()
            let library = try XCTUnwrap(container.libraryManager.localLibrary)
            repository = FailingCommitRepository(databaseService: container.databaseService, libraryResolver: container)
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let target = directory.appendingPathComponent("library", isDirectory: true)
            let incoming = directory.appendingPathComponent("incoming", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
            source = incoming.appendingPathComponent("Sample.pdf")
            destination = target.appendingPathComponent("Sample.pdf")
            try oldBytes.write(to: destination)
            try newBytes.write(to: source)
            var book = CalibreBook(id: 42, library: library)
            book.title = "Previous book"
            book.inShelf = true
            book.formats["PDF"] = FormatInfo(filename: "Sample.pdf", serverSize: UInt64(oldBytes.count),
                                             serverMTime: .distantPast, cached: true,
                                             cacheSize: UInt64(oldBytes.count), cacheMTime: .distantPast)
            oldBook = book
            repository.saveBook(book)
        }

        @MainActor
        func manager(files: CalibreBookManager.FileOperations = .init()) -> CalibreBookManager {
            let manager = CalibreBookManager(container: container, databaseService: container.databaseService,
                                             bookRepository: repository, files: files,
                                             localDirectory: destination.deletingLastPathComponent())
            manager.booksInShelf[oldBook.inShelfId] = oldBook
            return manager
        }

        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }

    private final class FailingCommitRepository: RealmBookRepository {
        var rejectCommit = false

        override func commitBookFiles(saving books: [CalibreBook], deleting ids: Set<String>) throws {
            if rejectCommit { throw CocoaError(.fileWriteNoPermission) }
            try super.commitBookFiles(saving: books, deleting: ids)
        }
    }
}
