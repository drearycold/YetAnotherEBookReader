//
//  CalibreBookManagerTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-23.
//

import XCTest
import RealmSwift
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

    @MainActor
    func testCacheInfoAndLifecycle() async {
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
        if book.library.server.isLocal {
            _ = await bookManager.removeLocalFile(book: book, format: .EPUB)
        } else {
            bookManager.clearCache(book: book, format: .EPUB)
        }
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
    func testStartupScanKeepsTheCommittedImportVersionAndMetadata() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let manager = fixture.manager()
        let imported = await manager.importBook(LocalBookImportRequest(url: fixture.source, doMove: false, overwrite: true, asNew: false))
        let id = try XCTUnwrap(imported.bookId)
        var book = try XCTUnwrap(fixture.repository.getBook(library: fixture.oldBook.library, bookId: id))
        book.title = "Publication title"
        fixture.repository.saveBook(book)

        await manager.scanLocalBooks()
        let scanned = try XCTUnwrap(fixture.repository.getBook(id: book.inShelfId))
        XCTAssertEqual(scanned.title, book.title)
        XCTAssertEqual(scanned.lastSynced, book.lastSynced)
    }

    func testStartupScanReconcilesSwappedFilenamesInEitherOrder() async throws {
        for originalNames in [["A.epub", "B.epub"], ["B.epub", "A.epub"]] {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            try fixture.removeSeedBook()
            let first = try await fixture.importEPUB(named: originalNames[0], content: "First")
            let second = try await fixture.importEPUB(named: originalNames[1], content: "Second")
            XCTAssertNotEqual(first.id, second.id)
            let firstFile = fixture.libraryDirectory.appendingPathComponent(originalNames[0])
            let secondFile = fixture.libraryDirectory.appendingPathComponent(originalNames[1])
            let temporary = fixture.libraryDirectory.appendingPathComponent("swap.tmp")
            try FileManager.default.moveItem(at: firstFile, to: temporary)
            try FileManager.default.moveItem(at: secondFile, to: firstFile)
            try FileManager.default.moveItem(at: temporary, to: secondFile)

            let restarted = fixture.manager()
            for book in [first, second] { restarted.booksInShelf[book.inShelfId] = book }
            await restarted.scanLocalBooks()
            try assertIndexed(first, at: secondFile, fixture: fixture)
            try assertIndexed(second, at: firstFile, fixture: fixture)
            try assertBrowseIDs([first.id, second.id], fixture: fixture)
            XCTAssertEqual(Set(restarted.booksInShelf.values.map(\.id)), [first.id, second.id])

            let versions = [first, second].map { fixture.repository.getBook(id: $0.inShelfId)?.lastSynced }
            await restarted.scanLocalBooks()
            XCTAssertEqual([first, second].map { fixture.repository.getBook(id: $0.inShelfId)?.lastSynced }, versions)
            try assertBrowseIDs([first.id, second.id], fixture: fixture)
        }
    }

    func testStartupScanRebindsRenamedBookAndKeepsNewContentAtItsOldPath() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.removeSeedBook()
        let original = try await fixture.importEPUB(named: "A.epub", content: "Original")
        let oldPath = fixture.libraryDirectory.appendingPathComponent("A.epub")
        let renamedPath = fixture.libraryDirectory.appendingPathComponent("B.epub")
        try FileManager.default.moveItem(at: oldPath, to: renamedPath)
        let replacement = try fixture.makeEPUB(named: "Replacement.epub", content: "Replacement")
        try FileManager.default.copyItem(at: replacement, to: oldPath)
        let replacementID = try XCTUnwrap(localBookID(oldPath))

        let restarted = fixture.manager()
        await restarted.scanLocalBooks()
        try assertIndexed(original, at: renamedPath, fixture: fixture)
        XCTAssertEqual(fixture.repository.getBook(library: original.library, bookId: replacementID)?.formats["EPUB"]?.filename, "A.epub")
        try assertBrowseIDs([original.id, replacementID], fixture: fixture)
    }

    func testStartupScanRemovesTheDisplacedRecordWhenItsContentIsGone() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.removeSeedBook()
        let original = try await fixture.importEPUB(named: "A.epub", content: "Original")
        let path = fixture.libraryDirectory.appendingPathComponent("A.epub")
        // A prior scan can leave a missing book in Browse while taking it off the shelf.
        let restarted = fixture.manager()
        restarted.booksInShelf[original.inShelfId] = original
        try FileManager.default.removeItem(at: path)
        await restarted.scanLocalBooks()
        XCTAssertEqual(fixture.repository.getBook(id: original.inShelfId)?.inShelf, false)
        XCTAssertNil(restarted.booksInShelf[original.inShelfId])
        let replacement = try fixture.makeEPUB(named: "Replacement.epub", content: "Replacement")
        let bytes = try Data(contentsOf: replacement)
        try bytes.write(to: path, options: .atomic)
        let replacementID = try XCTUnwrap(localBookID(path))

        await restarted.scanLocalBooks()
        XCTAssertNil(fixture.repository.getBook(id: original.inShelfId))
        XCTAssertEqual(fixture.repository.getBook(library: original.library, bookId: replacementID)?.formats["EPUB"]?.filename, "A.epub")
        XCTAssertEqual(try Data(contentsOf: path), bytes)
        XCTAssertEqual(Set(restarted.booksInShelf.values.map(\.id)), [replacementID])
        XCTAssertEqual(fixture.container.readingPositionRepository.getPositions(for: original).map(\.lastReadChapter),
                       [original.title])
        XCTAssertEqual(fixture.container.annotationRepository
            .getBookmarks(forBookId: original.inShelfId, excludeRemoved: true).map(\.title), [original.title])
        try assertBrowseIDs([replacementID], fixture: fixture)
    }

    func testStartupScanKeepsRenamedBookAndIgnoresDuplicateAndPrivateCopies() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.removeSeedBook()
        let original = try await fixture.importEPUB(named: "C.epub", content: "Original")
        let oldPath = fixture.libraryDirectory.appendingPathComponent("C.epub")
        let renamedPath = fixture.libraryDirectory.appendingPathComponent("B.epub")
        try FileManager.default.moveItem(at: oldPath, to: renamedPath)
        let privateFolder = fixture.libraryDirectory.appendingPathComponent(".dsreader-file-test")
        try FileManager.default.createDirectory(at: privateFolder, withIntermediateDirectories: false)
        let privateFile = try fixture.makeEPUB(named: "Private.epub", content: "Staged")
        try FileManager.default.copyItem(at: privateFile, to: privateFolder.appendingPathComponent("Private.epub"))

        let restarted = fixture.manager()
        await restarted.scanLocalBooks()
        try assertIndexed(original, at: renamedPath, fixture: fixture)
        let version = fixture.repository.getBook(id: original.inShelfId)?.lastSynced
        try FileManager.default.copyItem(at: renamedPath, to: fixture.libraryDirectory.appendingPathComponent("A.epub"))
        await restarted.scanLocalBooks()
        try assertIndexed(original, at: renamedPath, fixture: fixture)
        XCTAssertEqual(fixture.repository.getBook(id: original.inShelfId)?.lastSynced, version)
        try assertBrowseIDs([original.id], fixture: fixture)
    }

    func testStartupRebindingRejectsLateTitlesAndCoversFromSwappedPaths() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.removeSeedBook()
        let metadata = ControlledMetadata()
        let (manager, coordinator, covers) = fixture.makeManager(metadata: { try await metadata.load($0) })
        let first = try await fixture.importEPUB(named: "A.epub", content: "First", using: manager)
        let oldFirst = try XCTUnwrap(coordinator.enrichmentTask(bookID: first.inShelfId))
        await metadata.waitForRequests(1)
        let second = try await fixture.importEPUB(named: "B.epub", content: "Second", using: manager)
        let oldSecond = try XCTUnwrap(coordinator.enrichmentTask(bookID: second.inShelfId))
        await metadata.waitForRequests(2)
        let a = fixture.libraryDirectory.appendingPathComponent("A.epub")
        let b = fixture.libraryDirectory.appendingPathComponent("B.epub")
        let temporary = fixture.libraryDirectory.appendingPathComponent("swap.tmp")
        try FileManager.default.moveItem(at: a, to: temporary)
        try FileManager.default.moveItem(at: b, to: a)
        try FileManager.default.moveItem(at: temporary, to: b)

        await manager.scanLocalBooks()
        XCTAssertTrue(oldFirst.isCancelled)
        XCTAssertTrue(oldSecond.isCancelled)
        let currentFirst = try XCTUnwrap(coordinator.enrichmentTask(bookID: first.inShelfId))
        let currentSecond = try XCTUnwrap(coordinator.enrichmentTask(bookID: second.inShelfId))
        await metadata.waitForRequests(4)
        await metadata.finish(0, title: "Stale A", cover: Data([0]))
        await metadata.finish(1, title: "Stale B", cover: Data([1]))
        await oldFirst.value
        await oldSecond.value
        XCTAssertTrue(covers.writes.isEmpty)
        await metadata.finish(2, title: "Parsed title", cover: Data([2]))
        await metadata.finish(3, title: "Parsed title", cover: Data([3]))
        await currentFirst.value
        await currentSecond.value
        XCTAssertEqual(Set(covers.writes.map(\.data)), [Data([2]), Data([3])])
        try assertIndexed(first, at: b, fixture: fixture)
        try assertIndexed(second, at: a, fixture: fixture)
    }

    private func assertIndexed(_ expected: CalibreBook, at url: URL, fixture: Fixture,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let saved = try XCTUnwrap(fixture.repository.getBook(id: expected.inShelfId), file: file, line: line)
        let filename = try XCTUnwrap(saved.formats["EPUB"]?.filename, file: file, line: line)
        let indexedURL = fixture.libraryDirectory.appendingPathComponent(filename)
        XCTAssertEqual(indexedURL, url, file: file, line: line)
        XCTAssertEqual(localBookID(indexedURL), expected.id, file: file, line: line)
        XCTAssertEqual(try Data(contentsOf: indexedURL), try Data(contentsOf: url), file: file, line: line)
        XCTAssertEqual(saved.title, expected.title, file: file, line: line)
        XCTAssertEqual(saved.formats["EPUB"]?.selected, true, file: file, line: line)
        XCTAssertTrue(saved.inShelf, file: file, line: line)
        let positions = fixture.container.readingPositionRepository.getPositions(for: saved)
        XCTAssertEqual(positions.map(\.lastReadChapter), [expected.title], file: file, line: line)
        let bookmarks = fixture.container.annotationRepository.getBookmarks(forBookId: saved.inShelfId, excludeRemoved: true)
        XCTAssertEqual(bookmarks.map(\.title), [expected.title], file: file, line: line)
    }

    private func assertBrowseIDs(_ ids: Set<Int32>, fixture: Fixture,
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        let browse = try fixture.browse()
        let expected = ids.union(fixture.mockBookIDs)
        XCTAssertEqual(browse.totalNumber, expected.count, file: file, line: line)
        XCTAssertEqual(Set(browse.bookIds), expected, file: file, line: line)
    }

    func testFailedOverwriteCopyKeepsThePreviousBook() async throws {
        try await assertFailedOverwrite(move: false)
    }

    func testFailedOverwriteMoveKeepsThePreviousBook() async throws {
        try await assertFailedOverwrite(move: true, failReplacement: true)
    }

    func testFailedRemovalKeepsTheBookAndItsFile() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var files = LocalBookFileOperations()
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
        let outcome = await manager.removeLocalFile(book: fixture.oldBook, format: .PDF)
        XCTAssertEqual(outcome, .fileFailed)

        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.oldBytes)
        XCTAssertTrue(fixture.repository.getBook(id: fixture.oldBook.inShelfId)?.formats["PDF"]?.cached == true)
        XCTAssertTrue(manager.booksInShelf[fixture.oldBook.inShelfId]?.formats["PDF"]?.cached == true)
        await fulfillment(of: [deleted], timeout: 0.25)
    }

    func testPostCommitLibraryCleanupDoesNotRecreateDeletedRecords() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let attempted = expectation(description: "Committed removal attempts file cleanup")
        var files = LocalBookFileOperations()
        files.remove = { _ in
            attempted.fulfill()
            throw CocoaError(.fileWriteNoPermission)
        }
        let manager = fixture.manager(files: files)
        fixture.repository.deleteBook(id: fixture.oldBook.inShelfId)
        manager.discardShelfBooks(in: [fixture.oldBook.library.id])
        await fulfillment(of: [attempted], timeout: 5)

        XCTAssertNil(fixture.repository.getBook(id: fixture.oldBook.inShelfId))
        XCTAssertNil(manager.booksInShelf[fixture.oldBook.inShelfId])
        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.oldBytes)
    }

    func testFailedInstallRetainsTheMoveSource() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try FileManager.default.removeItem(at: fixture.destination)
        var files = LocalBookFileOperations()
        files.move = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        let manager = fixture.manager(files: files)

        let result = await manager.importBook(LocalBookImportRequest(url: fixture.source, doMove: true, overwrite: false, asNew: false))
        XCTAssertEqual(result.error, .fileOpFail)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.path))
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.newBytes)
    }

    func testStorageFailureRestoresTheOldFileAndCanRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let manager = fixture.manager()
        fixture.repository.rejectCommit = true
        let failed = await manager.importBook(LocalBookImportRequest(url: fixture.source, doMove: true, overwrite: true, asNew: false))
        XCTAssertEqual(failed.error, .loadMetaFail)
        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.oldBytes)
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.newBytes)
        XCTAssertNotNil(manager.booksInShelf[fixture.oldBook.inShelfId])
        XCTAssertNotNil(fixture.repository.getBook(id: fixture.oldBook.inShelfId))

        fixture.repository.rejectCommit = false
        let success = await manager.importBook(LocalBookImportRequest(url: fixture.source, doMove: true, overwrite: true, asNew: false))
        let bookId = try XCTUnwrap(success.bookId)
        XCTAssertNil(success.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.newBytes)
        XCTAssertEqual(localBookID(fixture.destination), bookId)
        XCTAssertNil(fixture.repository.getBook(id: fixture.oldBook.inShelfId))
        XCTAssertNil(manager.booksInShelf[fixture.oldBook.inShelfId])
        XCTAssertNotNil(fixture.repository.getBook(library: fixture.oldBook.library, bookId: bookId))
    }

    func testFailedRestoreRetainsTheRecoveryCopy() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.repository.rejectCommit = true
        var files = LocalBookFileOperations()
        let replace = files.replace
        files.replace = {
            if $0.lastPathComponent == "previous" { throw CocoaError(.fileWriteNoPermission) }
            try replace($0, $1)
        }
        let manager = fixture.manager(files: files)
        let result = await manager.importBook(LocalBookImportRequest(url: fixture.source, doMove: true, overwrite: true, asNew: false))
        XCTAssertEqual(result.error, .recoveryRequired)
        let folder = try XCTUnwrap(result.recoveryFolder)
        let backup = fixture.destination.deletingLastPathComponent().appendingPathComponent(folder)
            .appendingPathComponent("previous")
        XCTAssertEqual(try Data(contentsOf: backup), fixture.oldBytes)
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.newBytes)
        XCTAssertNotNil(fixture.repository.getBook(id: fixture.oldBook.inShelfId))
    }

    func testMissingFileRemovalIsIdempotentAndStorageFailureRestoresExistingFile() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let manager = fixture.manager()
        fixture.repository.rejectCommit = true
        let failed = await manager.removeLocalFile(book: fixture.oldBook, format: .PDF)
        XCTAssertEqual(failed, .storageFailed)
        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.oldBytes)
        XCTAssertNotNil(manager.booksInShelf[fixture.oldBook.inShelfId])
        fixture.repository.rejectCommit = false
        try FileManager.default.removeItem(at: fixture.destination)
        let removed = await manager.removeLocalFile(book: fixture.oldBook, format: .PDF)
        let repeated = await manager.removeLocalFile(book: fixture.oldBook, format: .PDF)
        XCTAssertEqual(removed, .committed())
        XCTAssertEqual(repeated, .committed())
        XCTAssertNil(fixture.repository.getBook(id: fixture.oldBook.inShelfId))
        XCTAssertNil(manager.booksInShelf[fixture.oldBook.inShelfId])
    }

    func testSameFileAndRepeatedImportDoNotCopyOrDeleteTheSource() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var files = LocalBookFileOperations()
        files.copy = { _, _ in XCTFail("The file is already at its destination"); throw CocoaError(.fileWriteNoPermission) }
        files.remove = { _ in XCTFail("The file is already at its destination"); throw CocoaError(.fileWriteNoPermission) }
        let manager = fixture.manager(files: files)

        let first = await manager.importBook(LocalBookImportRequest(url: fixture.destination, doMove: true, overwrite: false, asNew: false))
        let second = await manager.importBook(LocalBookImportRequest(url: fixture.destination, doMove: true, overwrite: false, asNew: false))
        XCTAssertNil(first.error)
        XCTAssertNil(second.error)
        XCTAssertEqual(first.bookId, second.bookId)
        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.oldBytes)
        XCTAssertEqual(manager.booksInShelf.count, 1)
    }

    func testCleanupFailureReportsACommittedImportAndSaveAsNewKeepsBothBooks() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var files = LocalBookFileOperations()
        files.remove = { url in
            if url.lastPathComponent.hasPrefix(".dsreader-file-") { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.removeItem(at: url)
        }
        let manager = fixture.manager(files: files)
        let conflict = await manager.importBook(LocalBookImportRequest(url: fixture.source))
        XCTAssertEqual(conflict.error, .destConflict)
        let result = await manager.importBook(LocalBookImportRequest(url: fixture.source, doMove: false, overwrite: false, asNew: true))
        XCTAssertNil(result.error)
        XCTAssertTrue(result.cleanupPending)
        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.oldBytes)
        let imported = fixture.destination.deletingLastPathComponent().appendingPathComponent("Sample (1).pdf")
        XCTAssertEqual(try Data(contentsOf: imported), fixture.newBytes)
        XCTAssertEqual(manager.booksInShelf.count, 2)
        XCTAssertEqual(fixture.repository.getBook(library: fixture.oldBook.library, bookId: try XCTUnwrap(result.bookId))?
            .formats["PDF"]?.filename, "Sample (1).pdf")
    }

    private func assertFailedOverwrite(move: Bool, failReplacement: Bool = false) async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var files = LocalBookFileOperations()
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
        let result = await manager.importBook(LocalBookImportRequest(url: fixture.source, doMove: move, overwrite: true, asNew: false))

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
        let mockBookIDs: Set<Int32>

        @MainActor
        init() throws {
            container = MockAppContainerFactory.makeContainer()
            let library = try XCTUnwrap(container.libraryManager.localLibrary)
            repository = FailingCommitRepository(databaseService: container.databaseService, libraryResolver: container)
            mockBookIDs = Set(try container.searchCacheRepository.searchLocalLibrary(
                library: library,
                criteria: .init(searchString: "", sortCriteria: .init(by: .Title, ascending: true), filterCriteriaCategory: [:]),
                offset: 0, limit: 20
            ).bookIds)
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

        var libraryDirectory: URL { destination.deletingLastPathComponent() }

        func browse() throws -> LocalLibrarySearchResult {
            try container.searchCacheRepository.searchLocalLibrary(
                library: oldBook.library,
                criteria: .init(searchString: "", sortCriteria: .init(by: .Title, ascending: true), filterCriteriaCategory: [:]),
                offset: 0, limit: 20
            )
        }

        func removeSeedBook() throws {
            try FileManager.default.removeItem(at: destination)
            repository.deleteBook(id: oldBook.inShelfId)
        }

        func makeEPUB(named filename: String, content: String) throws -> URL {
            // Use the bundled EPUB with a different ZIP comment to distinguish content IDs.
            let bundle = try XCTUnwrap(Bundle.main.url(forResource: "UI Test Fixture", withExtension: "epub"))
            var data = try Data(contentsOf: bundle)
            XCTAssertEqual(data.suffix(2), Data([0, 0]), "The bundled EPUB has no existing ZIP comment")
            let comment = Data(content.utf8)
            let length = UInt16(comment.count)
            data.replaceSubrange((data.count - 2)..<data.count, with: [UInt8(truncatingIfNeeded: length), UInt8(length >> 8)])
            data.append(comment)
            let file = source.deletingLastPathComponent().appendingPathComponent(filename)
            try data.write(to: file)
            return file
        }

        @MainActor
        func importEPUB(named filename: String, content: String, using importer: CalibreBookManager? = nil) async throws -> CalibreBook {
            let source = try makeEPUB(named: filename, content: content)
            let result = await (importer ?? manager()).importBook(.init(url: source))
            XCTAssertNil(result.error)
            let id = try XCTUnwrap(result.bookId)
            var book = try XCTUnwrap(repository.getBook(library: oldBook.library, bookId: id))
            book.title = "Metadata for \(content)"
            book.formats["EPUB"]?.selected = true
            repository.saveBook(book)
            container.readingPositionRepository.savePosition(
                TestFixtures.makeReadingPosition(lastReadPage: 7, lastReadChapter: book.title), for: book
            )
            _ = container.annotationRepository.saveBookmark(.init(
                bookId: book.inShelfId, page: 7, pos_type: "epubcfi",
                pos: "epubcfi(/6/2)", title: book.title, date: Date()
            ))
            return book
        }

        @MainActor
        func manager(files: LocalBookFileOperations = .init()) -> CalibreBookManager {
            makeManager(files: files, metadata: { _ in LocalPublicationMetadata(title: nil, cover: nil) }).manager
        }

        @MainActor
        func makeManager(
            files: LocalBookFileOperations = .init(),
            metadata: @escaping LocalBookImportCoordinator.MetadataLoader
        ) -> (manager: CalibreBookManager, imports: LocalBookImportCoordinator, covers: RecordingCovers) {
            let imports = LocalBookImportCoordinator(repository: repository, files: files, loadMetadata: metadata)
            let covers = RecordingCovers()
            let manager = CalibreBookManager(container: container, databaseService: container.databaseService,
                                             bookRepository: repository, files: files,
                                             localDirectory: destination.deletingLastPathComponent(),
                                             localImports: imports, localCoverCache: covers)
            if let seeded = repository.getBook(id: oldBook.inShelfId) {
                manager.booksInShelf[seeded.inShelfId] = seeded
            }
            return (manager, imports, covers)
        }

        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }

    private final class FailingCommitRepository: RealmBookRepository {
        var rejectCommit = false
        var beforeCommit: (() -> Void)?
        var afterCommit: (() -> Void)?

        override func commitLocalBookFiles(scope: LocalBookStorageScope, saving books: [CalibreBook], deleting ids: Set<String>,
                                           cancelled: () -> Bool) throws {
            if rejectCommit { throw CocoaError(.fileWriteNoPermission) }
            beforeCommit?()
            try super.commitLocalBookFiles(scope: scope, saving: books, deleting: ids, cancelled: cancelled)
            afterCommit?()
        }
    }
}

extension LocalFileCommitTests {
    func testOutOfOrderOverwriteMetadataKeepsTheNewTitleAndCover() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let metadata = ControlledMetadata()
        let (manager, imports, covers) = fixture.makeManager(metadata: { try await metadata.load($0) })
        let original = await manager.importBook(.init(url: fixture.destination))
        let oldID = CalibreBook.identity(library: fixture.oldBook.library, bookId: try XCTUnwrap(original.bookId))
        let oldTask = try XCTUnwrap(imports.enrichmentTask(bookID: oldID))
        await metadata.waitForRequests(1)

        let replacement = await manager.importBook(.init(url: fixture.source, overwrite: true))
        let newID = CalibreBook.identity(library: fixture.oldBook.library, bookId: try XCTUnwrap(replacement.bookId))
        let newTask = try XCTUnwrap(imports.enrichmentTask(bookID: newID))
        await metadata.waitForRequests(2)
        XCTAssertTrue(oldTask.isCancelled)
        await metadata.finish(1, title: "Replacement", cover: Data([2]))
        await newTask.value
        await metadata.finish(0, title: "Outdated", cover: Data([1]))
        await oldTask.value

        XCTAssertNil(fixture.repository.getBook(id: oldID))
        XCTAssertEqual(fixture.repository.getBook(id: newID)?.title, "Replacement")
        XCTAssertEqual(covers.writes.map(\.data), [Data([2])])
        XCTAssertNil(imports.enrichmentTask(bookID: newID))
        XCTAssertTrue(fixture.container.sessionManager.readerPresentations.isEmpty)
    }

    func testSameIDReimportRetiresOldLoaderAndMergesOnlyMetadata() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let metadata = ControlledMetadata()
        let (manager, imports, covers) = fixture.makeManager(metadata: { try await metadata.load($0) })
        let first = await manager.importBook(.init(url: fixture.source, overwrite: true))
        let id = CalibreBook.identity(library: fixture.oldBook.library, bookId: try XCTUnwrap(first.bookId))
        let firstTask = try XCTUnwrap(imports.enrichmentTask(bookID: id))
        await metadata.waitForRequests(1)

        let duplicate = await manager.importBook(.init(url: fixture.source, asNew: true))
        XCTAssertEqual(duplicate.bookId, first.bookId)
        XCTAssertNil(duplicate.error)
        let requestCount = await metadata.requestCount
        XCTAssertEqual(requestCount, 1)
        let removed = await manager.clearCache(inShelfId: id)
        XCTAssertEqual(removed, .committed())
        XCTAssertTrue(firstTask.isCancelled)
        XCTAssertNil(fixture.repository.getBook(id: id))

        let reimported = await manager.importBook(.init(url: fixture.source))
        XCTAssertEqual(reimported.bookId, first.bookId)
        let secondTask = try XCTUnwrap(imports.enrichmentTask(bookID: id))
        await metadata.waitForRequests(2)
        var current = try XCTUnwrap(fixture.repository.getBook(id: id))
        current.formats["PDF"]?.selected = true
        current.formats["EPUB"] = FormatInfo(serverSize: 25, serverMTime: .distantPast, cached: true,
                                             cacheSize: 25, cacheMTime: .distantPast)
        current.lastUpdated = Date()
        fixture.repository.saveBook(current)

        await metadata.finish(1, title: "Current edition", cover: Data([2]))
        await secondTask.value
        await metadata.finish(0, title: "Retired edition", cover: Data([1]))
        await firstTask.value

        let saved = try XCTUnwrap(fixture.repository.getBook(id: id))
        XCTAssertEqual(saved.title, "Current edition")
        XCTAssertEqual(saved.formats["PDF"]?.selected, true)
        XCTAssertEqual(saved.formats["EPUB"]?.cacheSize, 25)
        XCTAssertEqual(saved.lastUpdated, current.lastUpdated)
        XCTAssertTrue(saved.inShelf)
        XCTAssertEqual(manager.booksInShelf[id]?.formats["EPUB"]?.cacheSize, 25)
        XCTAssertEqual(covers.writes.map(\.data), [Data([2])])
    }

    func testMetadataCannotReshelveABookOrStoreItsCover() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let metadata = ControlledMetadata()
        let (manager, imports, covers) = fixture.makeManager(metadata: { try await metadata.load($0) })
        let imported = await manager.importBook(.init(url: fixture.source, overwrite: true))
        let id = CalibreBook.identity(library: fixture.oldBook.library, bookId: try XCTUnwrap(imported.bookId))
        let enrichment = try XCTUnwrap(imports.enrichmentTask(bookID: id))
        await metadata.waitForRequests(1)
        manager.removeFromShelf(inShelfId: id)
        await metadata.finish(0, title: "Late", cover: Data([1]))
        await enrichment.value

        XCTAssertEqual(fixture.repository.getBook(id: id)?.inShelf, false)
        XCTAssertEqual(fixture.repository.getBook(id: id)?.title, "Sample")
        XCTAssertNil(manager.booksInShelf[id])
        XCTAssertTrue(covers.writes.isEmpty)
    }

    func testDatabaseSwitchRetiresEnrichmentEvenAfterSwitchingBack() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let metadata = ControlledMetadata()
        let (manager, imports, covers) = fixture.makeManager(metadata: { try await metadata.load($0) })
        let imported = await manager.importBook(.init(url: fixture.source, overwrite: true))
        let id = CalibreBook.identity(library: fixture.oldBook.library, bookId: try XCTUnwrap(imported.bookId))
        let enrichment = try XCTUnwrap(imports.enrichmentTask(bookID: id))
        await metadata.waitForRequests(1)

        let database = fixture.container.databaseService
        let original = try XCTUnwrap(database.realmConf)
        database.configure(conf: Realm.Configuration(inMemoryIdentifier: UUID().uuidString))
        database.configure(conf: original)
        await metadata.finish(0, title: "Wrong database", cover: Data([1]))
        await enrichment.value

        XCTAssertEqual(fixture.repository.getBook(id: id)?.title, "Sample")
        XCTAssertTrue(covers.writes.isEmpty)
        XCTAssertNil(imports.enrichmentTask(bookID: id))
    }

    func testCommittedLibraryRemovalRejectsLateMetadata() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let metadata = ControlledMetadata()
        let (manager, imports, covers) = fixture.makeManager(metadata: { try await metadata.load($0) })
        let imported = await manager.importBook(.init(url: fixture.source, overwrite: true))
        let id = CalibreBook.identity(library: fixture.oldBook.library, bookId: try XCTUnwrap(imported.bookId))
        let enrichment = try XCTUnwrap(imports.enrichmentTask(bookID: id))
        await metadata.waitForRequests(1)
        try fixture.container.libraryManager.removeLibrary(library: fixture.oldBook.library)
        await metadata.finish(0, title: "Removed library", cover: Data([1]))
        await enrichment.value

        XCTAssertFalse(fixture.repository.bookExists(id: id))
        XCTAssertTrue(covers.writes.isEmpty)
        XCTAssertNil(imports.enrichmentTask(bookID: id))
    }

    func testMetadataFailureAndOwnerReleaseDoNotHoldTheImportOpen() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let metadata = ControlledMetadata()
        var owner: (manager: CalibreBookManager, imports: LocalBookImportCoordinator, covers: RecordingCovers)? =
            fixture.makeManager(metadata: { try await metadata.load($0) })
        let first = await owner?.manager.importBook(.init(url: fixture.destination))
        let id = CalibreBook.identity(library: fixture.oldBook.library, bookId: try XCTUnwrap(first?.bookId))
        let failed = try XCTUnwrap(owner?.imports.enrichmentTask(bookID: id))
        await metadata.waitForRequests(1)
        await metadata.fail(0)
        await failed.value
        XCTAssertNil(owner?.imports.enrichmentTask(bookID: id))
        XCTAssertNotNil(fixture.repository.getBook(id: id))

        let second = await owner?.manager.importBook(.init(url: fixture.source, overwrite: true))
        let next = CalibreBook.identity(library: fixture.oldBook.library, bookId: try XCTUnwrap(second?.bookId))
        let pending = try XCTUnwrap(owner?.imports.enrichmentTask(bookID: next))
        await metadata.waitForRequests(2)
        weak var coordinator = owner?.imports
        owner = nil
        XCTAssertNil(coordinator)
        XCTAssertTrue(pending.isCancelled)
        await metadata.finish(1, title: "Released owner", cover: Data([1]))
        await pending.value
        XCTAssertEqual(fixture.repository.getBook(id: next)?.title, "Sample")
    }

    func testCancellationDuringStagingLeavesTheMainActorResponsiveAndKeepsTheOldBook() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let staged = expectation(description: "Source copied into staging")
        let gate = DispatchSemaphore(value: 0)
        var files = LocalBookFileOperations()
        let copy = files.copy
        files.copy = { source, target in
            try copy(source, target)
            if target.lastPathComponent == "incoming" {
                XCTAssertFalse(Thread.isMainThread)
                staged.fulfill()
                _ = gate.wait(timeout: .now() + 10)
            }
        }
        let manager = fixture.manager(files: files)
        let task = Task { await manager.importBook(.init(url: fixture.source, doMove: true, overwrite: true)) }
        await fulfillment(of: [staged], timeout: 5)
        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.oldBytes)
        task.cancel()
        gate.signal()
        let result = await task.value

        XCTAssertEqual(result.error, .cancelled)
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.newBytes)
        XCTAssertNotNil(fixture.repository.getBook(id: fixture.oldBook.inShelfId))
        try assertNoStaging(in: fixture)
    }

    func testCancellationAfterInstallRollsBackAndKeepsTheSource() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let installed = expectation(description: "Replacement installed")
        let gate = DispatchSemaphore(value: 0)
        var files = LocalBookFileOperations()
        let replace = files.replace
        files.replace = { source, target in
            try replace(source, target)
            if source.lastPathComponent == "incoming" {
                installed.fulfill()
                _ = gate.wait(timeout: .now() + 10)
            }
        }
        let manager = fixture.manager(files: files)
        let task = Task { await manager.importBook(.init(url: fixture.source, doMove: true, overwrite: true)) }
        await fulfillment(of: [installed], timeout: 5)
        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.newBytes)
        task.cancel()
        gate.signal()
        let result = await task.value

        XCTAssertEqual(result.error, .cancelled)
        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.oldBytes)
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.newBytes)
        XCTAssertNotNil(fixture.repository.getBook(id: fixture.oldBook.inShelfId))
        try assertNoStaging(in: fixture)
    }

    func testCancellationAtRepositoryBoundaryRestoresTheInstalledFile() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let committing = expectation(description: "Replacement reached the repository")
        let gate = DispatchSemaphore(value: 0)
        fixture.repository.beforeCommit = {
            committing.fulfill()
            _ = gate.wait(timeout: .now() + 10)
        }
        let manager = fixture.manager()
        let task = Task { await manager.importBook(.init(url: fixture.source, doMove: true, overwrite: true)) }
        await fulfillment(of: [committing], timeout: 5)
        task.cancel()
        gate.signal()
        let result = await task.value

        XCTAssertEqual(result.error, .cancelled)
        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.oldBytes)
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.newBytes)
        XCTAssertNotNil(fixture.repository.getBook(id: fixture.oldBook.inShelfId))
        try assertNoStaging(in: fixture)
    }

    func testCancellationAfterCommitStillCleansSourceAndPublishes() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let committed = expectation(description: "Realm committed")
        let gate = DispatchSemaphore(value: 0)
        fixture.repository.afterCommit = {
            committed.fulfill()
            _ = gate.wait(timeout: .now() + 10)
        }
        let manager = fixture.manager()
        let task = Task { await manager.importBook(.init(url: fixture.source, doMove: true, overwrite: true)) }
        await fulfillment(of: [committed], timeout: 5)
        task.cancel()
        gate.signal()
        let result = await task.value

        XCTAssertNil(result.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.newBytes)
        XCTAssertNil(manager.booksInShelf[fixture.oldBook.inShelfId])
        XCTAssertEqual(manager.booksInShelf.values.map(\.id), [try XCTUnwrap(result.bookId)])
        try assertNoStaging(in: fixture)
    }

    func testQueuedOverwriteAndStartupScanUseTheLatestFileAndRecord() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let staging = expectation(description: "First import is on the worker")
        let gate = DispatchSemaphore(value: 0)
        var files = LocalBookFileOperations()
        let copy = files.copy
        files.copy = { source, target in
            try copy(source, target)
            if source == fixture.source && target.lastPathComponent == "incoming" {
                staging.fulfill()
                _ = gate.wait(timeout: .now() + 10)
            }
        }
        let nextDirectory = fixture.directory.appendingPathComponent("next", isDirectory: true)
        try FileManager.default.createDirectory(at: nextDirectory, withIntermediateDirectories: true)
        let next = nextDirectory.appendingPathComponent(fixture.source.lastPathComponent)
        let nextBytes = Data("third version of file".utf8)
        try nextBytes.write(to: next)
        let manager = fixture.manager(files: files)
        let first = Task { await manager.importBook(.init(url: fixture.source, overwrite: true)) }
        await fulfillment(of: [staging], timeout: 5)
        let second = Task { await manager.importBook(.init(url: next, overwrite: true)) }
        let scan = Task { await manager.scanLocalBooks() }
        gate.signal()

        let firstResult = await first.value
        let secondResult = await second.value
        await scan.value
        XCTAssertNil(firstResult.error)
        XCTAssertNil(secondResult.error)
        XCTAssertEqual(try Data(contentsOf: fixture.destination), nextBytes)
        XCTAssertEqual(manager.booksInShelf.values.map(\.id), [try XCTUnwrap(secondResult.bookId)])
        try assertNoStaging(in: fixture)
    }

    private func assertNoStaging(in fixture: Fixture) throws {
        let items = try FileManager.default.contentsOfDirectory(atPath: fixture.destination.deletingLastPathComponent().path)
        XCTAssertFalse(items.contains { $0.hasPrefix(".dsreader-file-") })
    }

    private actor ControlledMetadata {
        private var next = 0
        private var pending = [Int: CheckedContinuation<LocalPublicationMetadata, Error>]()
        private var waiters = [(Int, CheckedContinuation<Void, Never>)]()
        var requestCount: Int { next }

        func load(_ url: URL) async throws -> LocalPublicationMetadata {
            try await withCheckedThrowingContinuation { continuation in
                pending[next] = continuation
                next += 1
                waiters.filter { $0.0 <= next }.forEach { $0.1.resume() }
                waiters.removeAll { $0.0 <= next }
            }
        }

        func waitForRequests(_ count: Int) async {
            guard next < count else { return }
            await withCheckedContinuation { waiters.append((count, $0)) }
        }

        func finish(_ index: Int, title: String, cover: Data) {
            pending.removeValue(forKey: index)?.resume(returning: LocalPublicationMetadata(title: title, cover: cover))
        }

        func fail(_ index: Int) {
            pending.removeValue(forKey: index)?.resume(throwing: CocoaError(.fileReadCorruptFile))
        }
    }

    private final class RecordingCovers: BookCoverCaching {
        var writes = [(url: URL, data: Data)]()
        func configureAuthentication(serverProvider: CalibreServerSnapshotProviding) {}
        func storeCoverData(_ data: Data, for url: URL) { writes.append((url, data)) }
        func removeCover(for url: URL) {}
    }
}
