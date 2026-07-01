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
            .init(books: [item]),
            sendLegacySubject: false
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
            let _ = viewModel.activeAlert
        }
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
        mockAppContainer.calibreUpdatedSubject.send(.deleted("deleted-book-id"))

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
