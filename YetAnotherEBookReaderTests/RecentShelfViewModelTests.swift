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
        viewModel = RecentShelfViewModel(container: mockAppContainer)
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        mockAppContainer = nil
    }
    
    func testInitialization() throws {
        XCTAssertEqual(viewModel.displayBooks.count, 0)
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
    
    func testCalibreUpdatedDeletionDismissal() throws {
        viewModel.presentingBookDetailId = "deleted-book-id"
        mockAppContainer.calibreUpdatedSubject.send(.deleted("deleted-book-id"))
        
        let expectation = XCTestExpectation(description: "Detail dismissed")
        DispatchQueue.main.async {
            XCTAssertNil(self.viewModel.presentingBookDetailId)
            expectation.fulfill()
        }
        self.wait(for: [expectation], timeout: 1.0)
    }
}
