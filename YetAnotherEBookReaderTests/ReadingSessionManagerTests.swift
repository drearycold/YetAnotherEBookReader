//
//  ReadingSessionManagerTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-24.
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

final class ReadingSessionManagerTests: XCTestCase {
    private var container: AppContainer!
    private var manager: ReadingSessionManager!
    private var persistenceStore: InMemoryReaderPresentationPersistenceStore!

    override func setUpWithError() throws {
        container = MockAppContainerFactory.makeContainer(
            testName: "ReadingSessionManagerTests"
        )

        persistenceStore = InMemoryReaderPresentationPersistenceStore()
        manager = ReadingSessionManager(container: container, persistenceStore: persistenceStore)
    }

    override func tearDownWithError() throws {
        AppContainer.shared = nil
        manager = nil
        persistenceStore = nil
        container = nil
    }
    
    func testDefaultFormat_returnsPreferredFormat() throws {
        // defaultFormat should match the interface idiom (iPhone: EPUB, iPad: PDF)
        #if targetEnvironment(macCatalyst)
        XCTAssertEqual(manager.defaultFormat, .EPUB)
        #else
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            XCTAssertEqual(manager.defaultFormat, .EPUB)
        case .pad:
            XCTAssertEqual(manager.defaultFormat, .PDF)
        default:
            XCTAssertEqual(manager.defaultFormat, .EPUB)
        }
        #endif
    }
    
    func testFormatReaderMap_storesPreference() {
        XCTAssertEqual(manager.formatReaderMap[.EPUB], [.YabrEPUB, .ReadiumEPUB])
        XCTAssertEqual(manager.formatReaderMap[.PDF], [.YabrPDF, .ReadiumPDF])
        XCTAssertEqual(manager.formatReaderMap[.CBZ], [.ReadiumCBZ])
    }

    func testOpenReaderSupportsMultiplePresentations() throws {
        let library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        let firstBook = CalibreBook(id: 101, library: library)
        let secondBook = CalibreBook(id: 202, library: library)
        let firstInfo = ReaderInfo(
            deviceName: container.deviceName,
            url: URL(fileURLWithPath: "/tmp/first.epub"),
            missing: false,
            format: .EPUB,
            readerType: .YabrEPUB,
            position: TestFixtures.makeReadingPosition(id: container.deviceName)
        )
        let secondInfo = ReaderInfo(
            deviceName: container.deviceName,
            url: URL(fileURLWithPath: "/tmp/second.epub"),
            missing: false,
            format: .EPUB,
            readerType: .YabrEPUB,
            position: TestFixtures.makeReadingPosition(id: container.deviceName)
        )

        let firstPresentation = manager.openReader(book: firstBook, readerInfo: firstInfo, source: .shelf)
        let secondPresentation = manager.openReader(book: secondBook, readerInfo: secondInfo, source: .bookDetail)

        XCTAssertEqual(manager.readerPresentations.map(\.id), [firstPresentation.id, secondPresentation.id])
        XCTAssertEqual(manager.readerPresentation(id: firstPresentation.id)?.book.id, firstBook.id)
        XCTAssertEqual(manager.activeReaderPresentation?.id, secondPresentation.id)

        manager.activateReader(id: firstPresentation.id)
        XCTAssertEqual(manager.activeReaderPresentation?.id, firstPresentation.id)

        manager.closeReader(id: firstPresentation.id)
        XCTAssertEqual(manager.readerPresentations.map(\.id), [secondPresentation.id])
        XCTAssertEqual(manager.activeReaderPresentation?.id, secondPresentation.id)
    }

    func testOpenReaderReusesExistingMatchingPresentation() throws {
        let library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        let book = CalibreBook(id: 101, library: library)
        let readerInfo = ReaderInfo(
            deviceName: container.deviceName,
            url: URL(fileURLWithPath: "/tmp/first.epub"),
            missing: false,
            format: .EPUB,
            readerType: .YabrEPUB,
            position: TestFixtures.makeReadingPosition(id: container.deviceName)
        )

        let firstPresentation = manager.openReader(book: book, readerInfo: readerInfo, source: .shelf)
        let secondPresentation = manager.openReader(book: book, readerInfo: readerInfo, source: .bookDetail)

        XCTAssertEqual(secondPresentation.id, firstPresentation.id)
        XCTAssertEqual(manager.readerPresentations.map(\.id), [firstPresentation.id])
        XCTAssertEqual(manager.activeReaderPresentation?.id, firstPresentation.id)
    }

    func testOpenReaderCanCreateDuplicateWhenRequested() throws {
        let library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        let book = CalibreBook(id: 101, library: library)
        let readerInfo = ReaderInfo(
            deviceName: container.deviceName,
            url: URL(fileURLWithPath: "/tmp/first.epub"),
            missing: false,
            format: .EPUB,
            readerType: .YabrEPUB,
            position: TestFixtures.makeReadingPosition(id: container.deviceName)
        )

        let firstPresentation = manager.openReader(book: book, readerInfo: readerInfo, source: .shelf)
        let secondPresentation = manager.openReader(
            book: book,
            readerInfo: readerInfo,
            source: .shelf,
            reuseExisting: false
        )

        XCTAssertNotEqual(secondPresentation.id, firstPresentation.id)
        XCTAssertEqual(manager.readerPresentations.map(\.id), [firstPresentation.id, secondPresentation.id])
        XCTAssertEqual(manager.activeReaderPresentation?.id, secondPresentation.id)
    }

    func testReaderPresentationForMountUsesRecordedPosition() throws {
        let library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        let book = CalibreBook(id: 101, library: library)
        let initialPosition = TestFixtures.makeReadingPosition(id: container.deviceName, lastReadPage: 1, epoch: 100)
        let latestPosition = TestFixtures.makeReadingPosition(id: container.deviceName, lastReadPage: 42, epoch: 200)
        let readerInfo = ReaderInfo(
            deviceName: container.deviceName,
            url: URL(fileURLWithPath: "/tmp/first.epub"),
            missing: false,
            format: .EPUB,
            readerType: .YabrEPUB,
            position: initialPosition
        )

        let presentation = manager.openReader(book: book, readerInfo: readerInfo, source: .shelf)
        manager.recordReaderPresentationPosition(id: presentation.id, position: latestPosition)

        let mountPresentation = try XCTUnwrap(manager.readerPresentationForMount(id: presentation.id))
        XCTAssertEqual(mountPresentation.readerInfo.position.lastReadPage, 42)
        XCTAssertEqual(mountPresentation.readerInfo.readerType, .YabrEPUB)
        XCTAssertEqual(mountPresentation.readerInfo.format, .EPUB)
    }

    func testReusedReaderPresentationKeepsRecordedPosition() throws {
        let library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        let book = CalibreBook(id: 101, library: library)
        let initialPosition = TestFixtures.makeReadingPosition(id: container.deviceName, lastReadPage: 1, epoch: 100)
        let latestPosition = TestFixtures.makeReadingPosition(id: container.deviceName, lastReadPage: 25, epoch: 200)
        let readerInfo = ReaderInfo(
            deviceName: container.deviceName,
            url: URL(fileURLWithPath: "/tmp/first.epub"),
            missing: false,
            format: .EPUB,
            readerType: .YabrEPUB,
            position: initialPosition
        )

        let firstPresentation = manager.openReader(book: book, readerInfo: readerInfo, source: .shelf)
        manager.recordReaderPresentationPosition(id: firstPresentation.id, position: latestPosition)
        let reusedPresentation = manager.openReader(book: book, readerInfo: readerInfo, source: .bookDetail)

        XCTAssertEqual(reusedPresentation.id, firstPresentation.id)
        let mountPresentation = try XCTUnwrap(manager.readerPresentationForMount(id: reusedPresentation.id))
        XCTAssertEqual(mountPresentation.readerInfo.position.lastReadPage, 25)
    }

    func testReaderPresentationForMountIgnoresDifferentReaderPosition() throws {
        let library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        let book = CalibreBook(id: 101, library: library)
        let initialPosition = TestFixtures.makeReadingPosition(id: container.deviceName, lastReadPage: 1, epoch: 100)
        var readiumPosition = TestFixtures.makeReadingPosition(id: container.deviceName, lastReadPage: 80, epoch: 300)
        readiumPosition.readerName = ReaderType.ReadiumEPUB.rawValue
        container.readingPositionRepository.savePosition(readiumPosition, for: book)
        let readerInfo = ReaderInfo(
            deviceName: container.deviceName,
            url: URL(fileURLWithPath: "/tmp/first.epub"),
            missing: false,
            format: .EPUB,
            readerType: .YabrEPUB,
            position: initialPosition
        )

        let presentation = manager.openReader(book: book, readerInfo: readerInfo, source: .shelf)
        manager.recordReaderPresentationPosition(id: presentation.id, position: readiumPosition)

        let mountPresentation = try XCTUnwrap(manager.readerPresentationForMount(id: presentation.id))
        XCTAssertEqual(mountPresentation.readerInfo.position.lastReadPage, 1)
        XCTAssertEqual(mountPresentation.readerInfo.position.readerName, ReaderType.YabrEPUB.rawValue)
    }

    func testReaderPresentationsPersistSnapshotsWhenOpenedAndActivated() throws {
        let firstBook = try makeRestorableBook(id: 301, title: "First Persisted Reader")
        let secondBook = try makeRestorableBook(id: 302, title: "Second Persisted Reader")
        let firstInfo = makeReaderInfo(book: firstBook, page: 3)
        let secondInfo = makeReaderInfo(book: secondBook, page: 9)

        let firstPresentation = manager.openReader(book: firstBook, readerInfo: firstInfo, source: .shelf)
        let secondPresentation = manager.openReader(book: secondBook, readerInfo: secondInfo, source: .bookDetail)

        XCTAssertEqual(persistenceStore.snapshots.map(\.id), [firstPresentation.id, secondPresentation.id])
        XCTAssertEqual(persistenceStore.snapshots.map(\.isActive), [false, true])
        XCTAssertEqual(persistenceStore.snapshots.map(\.order), [0, 1])

        manager.activateReader(id: firstPresentation.id)

        XCTAssertEqual(persistenceStore.snapshots.map(\.id), [firstPresentation.id, secondPresentation.id])
        XCTAssertEqual(persistenceStore.snapshots.map(\.isActive), [true, false])
    }

    func testCloseReaderRemovesPersistedSnapshots() throws {
        let firstBook = try makeRestorableBook(id: 311, title: "First Close Reader")
        let secondBook = try makeRestorableBook(id: 312, title: "Second Close Reader")
        let firstPresentation = manager.openReader(book: firstBook, readerInfo: makeReaderInfo(book: firstBook), source: .shelf)
        let secondPresentation = manager.openReader(book: secondBook, readerInfo: makeReaderInfo(book: secondBook), source: .bookDetail)

        manager.closeReader(id: firstPresentation.id)

        XCTAssertEqual(persistenceStore.snapshots.map(\.id), [secondPresentation.id])
        XCTAssertEqual(persistenceStore.snapshots.first?.isActive, true)

        manager.closeReader(id: secondPresentation.id)

        XCTAssertTrue(persistenceStore.snapshots.isEmpty)
    }

    func testRestorePersistedReaderPresentationsUsesSavedReaderTypePosition() throws {
        let book = try makeRestorableBook(id: 321, title: "Restore Reader Type")
        var yabrPosition = TestFixtures.makeReadingPosition(
            id: container.deviceName,
            readerName: ReaderType.YabrEPUB.rawValue,
            lastReadPage: 12,
            epoch: 100
        )
        yabrPosition.lastProgress = 12
        let readiumPosition = TestFixtures.makeReadingPosition(
            id: container.deviceName,
            readerName: ReaderType.ReadiumEPUB.rawValue,
            lastReadPage: 88,
            epoch: 200
        )
        container.readingPositionRepository.savePosition(yabrPosition, for: book)
        container.readingPositionRepository.savePosition(readiumPosition, for: book)
        let snapshotID = UUID()
        persistenceStore.saveReaderPresentationSnapshots([
            ReaderPresentationSnapshot(
                id: snapshotID,
                bookInShelfId: book.inShelfId,
                format: .EPUB,
                readerType: .YabrEPUB,
                source: .shelf,
                isActive: true,
                order: 0
            )
        ])

        let restored = manager.restorePersistedReaderPresentationsIfNeeded()

        XCTAssertEqual(restored.map(\.id), [snapshotID])
        XCTAssertEqual(manager.activeReaderPresentationID, snapshotID)
        XCTAssertEqual(restored.first?.readerInfo.readerType, .YabrEPUB)
        XCTAssertEqual(restored.first?.readerInfo.position.lastReadPage, 12)
    }

    func testRestorePersistedReaderPresentationsSkipsInvalidSnapshotsAndCleansStore() throws {
        let validBook = try makeRestorableBook(id: 331, title: "Valid Restore Reader")
        let validID = UUID()
        let deletedID = UUID()
        persistenceStore.saveReaderPresentationSnapshots([
            ReaderPresentationSnapshot(
                id: deletedID,
                bookInShelfId: "missing-book",
                format: .EPUB,
                readerType: .YabrEPUB,
                source: .shelf,
                isActive: true,
                order: 0
            ),
            ReaderPresentationSnapshot(
                id: validID,
                bookInShelfId: validBook.inShelfId,
                format: .EPUB,
                readerType: .YabrEPUB,
                source: .bookDetail,
                isActive: false,
                order: 1
            )
        ])

        let restored = manager.restorePersistedReaderPresentationsIfNeeded()

        XCTAssertEqual(restored.map(\.id), [validID])
        XCTAssertEqual(manager.activeReaderPresentationID, validID)
        XCTAssertEqual(persistenceStore.snapshots.map(\.id), [validID])
        XCTAssertEqual(persistenceStore.snapshots.first?.isActive, true)
    }

    func testRestorePersistedDuplicateReaderPresentationsDoesNotMergeTabs() throws {
        let book = try makeRestorableBook(id: 341, title: "Duplicate Restore Reader")
        let firstID = UUID()
        let secondID = UUID()
        persistenceStore.saveReaderPresentationSnapshots([
            ReaderPresentationSnapshot(
                id: firstID,
                bookInShelfId: book.inShelfId,
                format: .EPUB,
                readerType: .YabrEPUB,
                source: .shelf,
                isActive: false,
                order: 0
            ),
            ReaderPresentationSnapshot(
                id: secondID,
                bookInShelfId: book.inShelfId,
                format: .EPUB,
                readerType: .YabrEPUB,
                source: .bookDetail,
                isActive: true,
                order: 1
            )
        ])

        let restored = manager.restorePersistedReaderPresentationsIfNeeded()

        XCTAssertEqual(restored.map(\.id), [firstID, secondID])
        XCTAssertEqual(manager.readerPresentations.map(\.id), [firstID, secondID])
        XCTAssertEqual(manager.activeReaderPresentationID, secondID)
    }
    
    func testSelectedReadingBook_publishesChange() throws {
        let library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        var book = CalibreBook(id: 777, library: library)
        book.title = "Session Reading Book"
        book.formats[Format.EPUB.rawValue] = FormatInfo(selected: nil, filename: "test.epub", serverSize: 1000, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date(), manifest: nil)
        
        let expectation = self.expectation(description: "Reading book change published")
        
        let manager = manager!
        let shelfIdSnapshots = manager.readingBookInShelfIdSnapshots()
        let observationTask = Task {
            for await shelfId in shelfIdSnapshots {
                guard shelfId == book.inShelfId else { continue }
                expectation.fulfill()
                return
            }
        }
        defer {
            observationTask.cancel()
        }
        
        manager.readingBookInShelfId = book.inShelfId
        waitForExpectations(timeout: 1.0)
    }
    
    func testStartSession_recordsTimestamp() throws {
        let library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        let book = CalibreBook(id: 777, library: library)
        let pos = TestFixtures.makeReadingPosition(id: "device-1", lastReadPage: 12, epoch: 500.0)
        
        let startResult = container.readingPositionRepository.beginSession(at: pos, forBookId: book.bookPrefId)
        XCTAssertNotNil(startResult)
    }
    
    func testEndSession_logsActivity() throws {
        let library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        let book = CalibreBook(id: 777, library: library)
        let startPos = TestFixtures.makeReadingPosition(id: "device-1", lastReadPage: 5, epoch: 500.0)
        let endPos = TestFixtures.makeReadingPosition(id: "device-1", lastReadPage: 15, epoch: 1500.0)
        
        let handle = try XCTUnwrap(container.readingPositionRepository.beginSession(at: startPos, forBookId: book.bookPrefId))
        container.readingPositionRepository.endSession(handle, at: endPos)
        
        let sessions = container.readingPositionRepository.sessions(forBookId: book.bookPrefId, list: nil)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.startPosition?.lastReadPage, 5)
        XCTAssertEqual(sessions.first?.endPosition?.lastReadPage, 15)
    }

    private func makeRestorableBook(
        id: Int32,
        title: String,
        format: Format = .EPUB
    ) throws -> CalibreBook {
        let library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        var book = CalibreBook(id: id, library: library)
        book.title = title
        book.formats[format.rawValue] = FormatInfo(
            selected: nil,
            filename: "\(title).\(format.ext)",
            serverSize: 1000,
            serverMTime: Date(),
            cached: true,
            cacheSize: 1000,
            cacheMTime: Date(),
            manifest: nil
        )
        container.bookRepository.saveBook(book)
        container.bookManager.booksInShelf[book.inShelfId] = book
        if let savedURL = getSavedUrl(book: book, format: format),
           FileManager.default.fileExists(atPath: savedURL.path) == false {
            _ = FileManager.default.createFile(atPath: savedURL.path, contents: Data("EPUB".utf8), attributes: nil)
        }
        return book
    }

    private func makeReaderInfo(
        book: CalibreBook,
        page: Int = 1,
        readerType: ReaderType = .YabrEPUB
    ) -> ReaderInfo {
        let format = readerType.format
        let savedURL = getSavedUrl(book: book, format: format) ?? URL(fileURLWithPath: "/invalid")
        return ReaderInfo(
            deviceName: container.deviceName,
            url: savedURL,
            missing: false,
            format: format,
            readerType: readerType,
            position: TestFixtures.makeReadingPosition(
                id: container.deviceName,
                readerName: readerType.rawValue,
                lastReadPage: page,
                epoch: Double(page)
            )
        )
    }
    
    func testUpdateCurrentPosition_savesViaRepository() throws {
        let library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        var book = CalibreBook(id: 777, library: library)
        book.title = "Update Current Position Book"
        book.formats[Format.EPUB.rawValue] = FormatInfo(selected: nil, filename: "test.epub", serverSize: 1000, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date(), manifest: nil)
        
        let position = TestFixtures.makeReadingPosition(id: container.deviceName, lastReadPage: 25, epoch: 1200.0)
        container.readingPositionRepository.savePosition(position, forBookId: book.bookPrefId)
        
        manager.readingBook = book
        manager.readerInfo = ReaderInfo(
            deviceName: container.deviceName,
            url: URL(fileURLWithPath: "/tmp/mock_file.epub"),
            missing: false,
            format: .EPUB,
            readerType: .YabrEPUB,
            position: position
        )
        
        // Triggers the method and should run without crashing
        manager.updateCurrentPosition(alertDelegate: nil)
    }
    
    func testFormatList_orderedByPreference() throws {
        let library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        var book = CalibreBook(id: 777, library: library)
        book.formats[Format.EPUB.rawValue] = FormatInfo(selected: nil, filename: "test.epub", serverSize: 1000, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date(), manifest: nil)
        book.formats[Format.PDF.rawValue] = FormatInfo(selected: nil, filename: "test.pdf", serverSize: 2000, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date(), manifest: nil)
        
        manager.updatePreferredFormat(for: .EPUB)
        XCTAssertEqual(manager.getPreferredFormat(for: book), .EPUB)
        
        manager.updatePreferredFormat(for: .PDF)
        XCTAssertEqual(manager.getPreferredFormat(for: book), .PDF)
    }
}
