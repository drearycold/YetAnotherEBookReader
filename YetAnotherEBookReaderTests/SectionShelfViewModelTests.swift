//
//  SectionShelfViewModelTests.swift
//  YetAnotherEBookReaderTests
//

import XCTest
import Combine
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
class SectionShelfViewModelTests: XCTestCase {
    var viewModel: SectionShelfViewModel!
    var mockAppContainer: AppContainer!
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        mockAppContainer = MockAppContainerFactory.makeContainer(testName: "SectionShelfViewModelTests-\(UUID().uuidString)")
        
        viewModel = SectionShelfViewModel(container: mockAppContainer)
        cancellables = []
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        mockAppContainer = nil
        cancellables = nil
        try super.tearDownWithError()
    }
    
    func testInitialization() {
        XCTAssertEqual(viewModel.displaySections.count, 0)
        XCTAssertEqual(viewModel.pickedLibraries.count, 0)
    }
    
    func testRefreshShelf() {
        viewModel.refreshShelf()
    }
    
    func testDownloadSelectedBooks() {
        viewModel.downloadSelectedBooks(bookIds: [])
        viewModel.downloadSelectedBooks(bookIds: ["non-existent"])
    }
    
    func testUpdateShelfModels() async throws {
        let uuid = UUID()
        let server = CalibreServer(uuid: uuid, name: "Mock Server", baseUrl: "http://localhost:8080", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "libId", name: "MockLibrary")
        mockAppContainer.calibreLibraries[library.id] = library
        
        let section = ShelfSectionItem(
            id: "\(library.id) || testSection",
            title: "Test Section",
            books: []
        )
        
        let expectation = XCTestExpectation(description: "Subscription updates shelf sections")
        
        viewModel.$displaySections
            .dropFirst()
            .sink { sections in
                if !sections.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        mockAppContainer.discoverShelfItemsSubject.send([section])
        
        await fulfillment(of: [expectation], timeout: 3.0)
        
        XCTAssertEqual(viewModel.displaySections.count, 1)
        XCTAssertEqual(viewModel.displaySections[0].id, "\(library.id) || testSection")
    }
    
    func testTapBook() throws {
        viewModel.tapBook(bookId: "non-existent")
        XCTAssertNil(viewModel.presentingBookDetailId)
        
        viewModel.selectionState.isEditing = true
        viewModel.tapBook(bookId: "test-id")
        XCTAssertTrue(viewModel.selectionState.selectedBookIds.contains("test-id"))
        viewModel.tapBook(bookId: "test-id")
        XCTAssertFalse(viewModel.selectionState.selectedBookIds.contains("test-id"))
    }
    
    func testDownloadSelectedBooksWrapper() throws {
        viewModel.selectionState.selectedBookIds = ["test-book-id"]
        viewModel.selectionState.isEditing = true
        
        viewModel.downloadSelectedBooks()
        
        XCTAssertTrue(viewModel.selectionState.selectedBookIds.isEmpty)
        XCTAssertFalse(viewModel.selectionState.isEditing)
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
    
    func testSelectAllAndClear() throws {
        let item = ShelfBookItem(id: "book-1", title: "Book 1", coverURL: "", progress: 50, status: .ready)
        let section = ShelfSectionItem(id: "section-1", title: "Section 1", books: [item])
        
        viewModel.displaySections = [section]
        
        viewModel.selectAllBooks()
        XCTAssertEqual(viewModel.selectionState.selectedBookIds.count, 1)
        XCTAssertTrue(viewModel.selectionState.selectedBookIds.contains("book-1"))
        
        viewModel.clearSelection()
        XCTAssertEqual(viewModel.selectionState.selectedBookIds.count, 0)
    }
}
