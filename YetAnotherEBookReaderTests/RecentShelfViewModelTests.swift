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
    var mockModelData: ModelData!
    
    override func setUpWithError() throws {
        mockModelData = ModelData(mock: true)
        viewModel = RecentShelfViewModel(modelData: mockModelData)
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        mockModelData = nil
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
        
        if let mockBook = mockModelData.readingBook {
            let readerInfo = viewModel.prepareReading(bookId: mockBook.inShelfId)
            XCTAssertNotNil(readerInfo)
        }
    }
    
    func testTapBook() throws {
        viewModel.tapBook(bookId: "non-existent")
        XCTAssertNil(viewModel.activeAlert)
        
        if let mockBook = mockModelData.readingBook {
            mockModelData.booksInShelf[mockBook.inShelfId] = mockBook
            
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
        if let mockBook = mockModelData.readingBook {
            mockModelData.booksInShelf[mockBook.inShelfId] = mockBook
            viewModel.refreshBookFormats(bookId: mockBook.inShelfId)
        }
    }
    
    func testCalibreUpdatedDeletionDismissal() throws {
        viewModel.presentingBookDetailId = "deleted-book-id"
        mockModelData.calibreUpdatedSubject.send(.deleted("deleted-book-id"))
        
        let expectation = XCTestExpectation(description: "Detail dismissed")
        DispatchQueue.main.async {
            XCTAssertNil(self.viewModel.presentingBookDetailId)
            expectation.fulfill()
        }
        self.wait(for: [expectation], timeout: 1.0)
    }
}
