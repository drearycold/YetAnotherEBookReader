//
//  RecentShelfViewModelTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by opencode on 2026/6/18.
//

import XCTest
import SwiftUI
import Combine
@testable import YetAnotherEBookReader

@MainActor class RecentShelfViewModelTests: XCTestCase {
    var viewModel: RecentShelfViewModel!
    var mockAppContainer: AppContainer!
    
    override func setUpWithError() throws {
        mockAppContainer = MockAppContainerFactory.makeContainer(testName: "RecentShelfViewModelTests")
        mockAppContainer.bookManager.isShelfLoaded = false
        viewModel = RecentShelfViewModel(container: mockAppContainer)
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        mockAppContainer = nil
    }
    
    func testInitialization() async throws {
        await waitForViewModelUpdate {
            self.viewModel.loadedBooks != nil
        }
        XCTAssertEqual(viewModel.loadedBooks, [])
        XCTAssertEqual(viewModel.displayBooks.count, 0)
    }
    
    func testLoadedBooksPublication() async throws {
        let item = ShelfBookItem(id: "1", title: "Book", coverURL: "", progress: 0, status: .ready)

        mockAppContainer.shelfDataModel.setRecentShelfSnapshotForTesting(
            .init(books: [item])
        )
        await waitForViewModelUpdate {
            self.viewModel.loadedBooks?.count == 1
        }

        XCTAssertNotNil(viewModel.loadedBooks)
        XCTAssertEqual(viewModel.loadedBooks?.count, 1)
        XCTAssertEqual(viewModel.displayBooks.count, 1)
    }
    
    func testRefreshShelf() throws {
        viewModel.refreshShelf()
    }
    
    func testDeleteBook() throws {
        viewModel.deleteBook(bookId: "test-id")
        viewModel.deleteBooks(bookIds: ["test-id-1", "test-id-2"])
    }
    
    func testPrepareReading() throws {
        let readerInfoNil = viewModel.prepareReading(bookId: "non-existent")
        XCTAssertNil(readerInfoNil)
        
        if let mockBook = mockAppContainer.bookManager.readingBook {
            let readerInfo = viewModel.prepareReading(bookId: mockBook.inShelfId)
            XCTAssertNotNil(readerInfo)
        }
    }
    
    func testTapBook() throws {
        viewModel.tapBook(bookId: "non-existent")
        XCTAssertNil(viewModel.activeAlert)
        
        if let mockBook = mockAppContainer.bookManager.readingBook {
            mockAppContainer.booksInShelf[mockBook.inShelfId] = mockBook
            
            viewModel.selectionState.isEditing = true
            XCTAssertFalse(viewModel.selectionState.selectedBookIds.contains(mockBook.inShelfId))
            viewModel.tapBook(bookId: mockBook.inShelfId)
            XCTAssertTrue(viewModel.selectionState.selectedBookIds.contains(mockBook.inShelfId))
            
            viewModel.tapBook(bookId: mockBook.inShelfId)
            XCTAssertFalse(viewModel.selectionState.selectedBookIds.contains(mockBook.inShelfId))
            viewModel.selectionState.isEditing = false
            
            viewModel.tapBook(bookId: mockBook.inShelfId)
            XCTAssertEqual(mockAppContainer.sessionManager.activeReaderPresentation?.book.inShelfId, mockBook.inShelfId)
            XCTAssertEqual(mockAppContainer.sessionManager.activeReaderPresentation?.source, .shelf)
        }
    }

    func testTapBookTreatsPausedDownloadAsActive() throws {
        let library = try XCTUnwrap(mockAppContainer.libraryManager.calibreLibraries.first?.value)
        var book = CalibreBook(id: 4321, library: library)
        book.formats[Format.EPUB.rawValue] = FormatInfo(
            selected: true,
            filename: "paused-shelf.epub",
            serverSize: 100,
            serverMTime: Date(),
            cached: false,
            cacheSize: 0,
            cacheMTime: Date.distantPast
        )
        if let savedURL = getSavedUrl(book: book, format: .EPUB) {
            try? FileManager.default.removeItem(at: savedURL)
        }
        mockAppContainer.bookManager.booksInShelf[book.inShelfId] = book

        let sourceURL = URL(string: "http://localhost/get/EPUB/4321/library")!
        mockAppContainer.downloadManager.activeDownloads[sourceURL] = BookFormatDownload(
            isDownloading: false,
            isPaused: true,
            progress: 0.5,
            resumeData: nil,
            book: book,
            format: .EPUB,
            startDatetime: Date(),
            sourceURL: sourceURL,
            savedURL: URL(fileURLWithPath: "/tmp/paused-shelf.epub"),
            modificationDate: Date()
        )

        viewModel.tapBook(bookId: book.inShelfId)

        guard case .downloadingFormat(let alertBook, let alertFormat) = viewModel.activeAlert else {
            return XCTFail("Expected paused active download to show downloading alert")
        }
        XCTAssertEqual(alertBook.id, book.id)
        XCTAssertEqual(alertFormat, .EPUB)
    }
    
    func testRefreshBookFormats() throws {
        if let mockBook = mockAppContainer.bookManager.readingBook {
            mockAppContainer.booksInShelf[mockBook.inShelfId] = mockBook
            viewModel.refreshBookFormats(bookId: mockBook.inShelfId)
        }
    }
    
    func testCalibreUpdatedDeletionDismissal() async throws {
        viewModel.presentingBookDetailId = "deleted-book-id"
        await waitForViewModelUpdate {
            self.viewModel.loadedBooks != nil
        }
        mockAppContainer.publishCalibreUpdate(.deleted("deleted-book-id"))

        await waitForViewModelUpdate {
            self.viewModel.presentingBookDetailId == nil
        }
        XCTAssertNil(viewModel.presentingBookDetailId)
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
