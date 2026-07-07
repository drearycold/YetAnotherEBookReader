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

    override func setUpWithError() throws {
        container = MockAppContainerFactory.makeContainer(
            testName: "ReadingSessionManagerTests"
        )

        manager = ReadingSessionManager(container: container)
    }

    override func tearDownWithError() throws {
        AppContainer.shared = nil
        manager = nil
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
