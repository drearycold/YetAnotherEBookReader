//
//  ShelfDisplayModelsTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-22.
//

import XCTest
import Combine
@testable import YetAnotherEBookReader

@MainActor class ShelfDisplayModelsTests: XCTestCase {
    
    
    func testRecentShelfViewModelMapping() async throws {
        let mockAppContainer = MockAppContainerFactory.makeContainer(testName: "ShelfDisplayModelsTests-\(UUID().uuidString)")
        let viewModel = RecentShelfViewModel(container: mockAppContainer)
        
        let item = ShelfBookItem(
            id: "test-id",
            title: "Test Title",
            coverURL: "https://example.com/cover.png",
            progress: 42,
            status: .ready
        )
        
        mockAppContainer.recentShelfItemsSubject.send([item])
        
        // Wait briefly for Combine
        try await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertEqual(viewModel.displayBooks.count, 1)
        XCTAssertEqual(viewModel.displayBooks[0].id, "test-id")
        XCTAssertEqual(viewModel.displayBooks[0].title, "Test Title")
    }
    
    func testSectionShelfViewModelMappingAndFilters() async throws {
        let mockAppContainer = MockAppContainerFactory.makeContainer(testName: "ShelfDisplayModelsTests-\(UUID().uuidString)")
        
        // Setup library config in mockAppContainer
        let uuid = UUID()
        let mockServer = CalibreServer(uuid: uuid, name: "Test Server", baseUrl: "http://localhost", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let mockLibrary = CalibreLibrary(server: mockServer, key: "testLibrary", name: "Test Library")
        let libraryId = mockLibrary.id
        mockAppContainer.calibreLibraries[libraryId] = mockLibrary
        
        let viewModel = SectionShelfViewModel(container: mockAppContainer)
        
        let bookItem = ShelfBookItem(
            id: "test-id",
            title: "Test Title",
            coverURL: "https://example.com/cover.png",
            progress: 0,
            status: .ready
        )
        
        let section = ShelfSectionItem(
            id: libraryId + " || testSection",
            title: "testSection",
            books: [bookItem]
        )
        
        mockAppContainer.discoverShelfItemsSubject.send([section])
        
        // Wait for collect(.byTime(RunLoop.main, .seconds(1))) which has 1s latency
        try await Task.sleep(nanoseconds: 1_200_000_000)
        
        XCTAssertEqual(viewModel.displaySections.count, 1)
        XCTAssertEqual(viewModel.displaySections.getOrNil(0)?.books.count, 1)
        XCTAssertEqual(viewModel.libraryFilters.count, 1)
        XCTAssertEqual(viewModel.libraryFilters.getOrNil(0)?.id, libraryId)
        XCTAssertFalse(viewModel.libraryFilters.getOrNil(0)?.isSelected ?? true)
        
        // Test Toggling filter
        viewModel.toggleLibraryFilter(libraryId: libraryId)
        XCTAssertTrue(viewModel.pickedLibraries.contains(libraryId))
        
        // Wait for discovery updates
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertTrue(viewModel.libraryFilters.getOrNil(0)?.isSelected ?? false)
        
        // Test resetting filters
        viewModel.resetLibraryFilters()
        XCTAssertTrue(viewModel.pickedLibraries.isEmpty)
        
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertFalse(viewModel.libraryFilters.getOrNil(0)?.isSelected ?? true)
    }
}
