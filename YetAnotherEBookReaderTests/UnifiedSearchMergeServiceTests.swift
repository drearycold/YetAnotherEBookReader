//
//  UnifiedSearchMergeServiceTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-10.
//

import XCTest
@testable import YetAnotherEBookReader

class UnifiedSearchMergeServiceTests: XCTestCase {
    
    var mergeService: UnifiedSearchMergeService!
    var mockLibrary1: CalibreLibrary!
    var mockLibrary2: CalibreLibrary!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        mergeService = UnifiedSearchMergeService()
        
        let server1 = CalibreServer(uuid: UUID(), name: "Server1", baseUrl: "http://localhost/1", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        mockLibrary1 = CalibreLibrary(server: server1, key: "lib1", name: "Library 1")
        
        let server2 = CalibreServer(uuid: UUID(), name: "Server2", baseUrl: "http://localhost/2", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        mockLibrary2 = CalibreLibrary(server: server2, key: "lib2", name: "Library 2")
    }
    
    override func tearDownWithError() throws {
        mergeService = nil
        mockLibrary1 = nil
        mockLibrary2 = nil
        try super.tearDownWithError()
    }
    
    func createMockBook(id: Int32, title: String, library: CalibreLibrary, timestamp: Date = Date(), pubDate: Date = Date(), lastModified: Date = Date(), seriesIndex: Double = 0.0) -> CalibreBook {
        var book = CalibreBook(id: id, library: library)
        book.title = title
        book.timestamp = timestamp
        book.pubDate = pubDate
        book.lastModified = lastModified
        book.seriesIndex = seriesIndex
        return book
    }
    
    func testMergeEmptyResults() throws {
        let libraryResults: [String: LibrarySourceSearchResult] = [:]
        let currentResult = UnifiedSearchResult(
            search: "test",
            sortBy: .Title,
            sortAsc: true,
            libraryIds: ["lib1", "lib2"],
            unifiedOffsets: [:],
            totalNumber: 0,
            limitNumber: 10,
            books: []
        )
        
        let merged = mergeService.merge(libraryResults: libraryResults, currentResult: currentResult)
        
        XCTAssertEqual(merged.books.count, 0)
        XCTAssertEqual(merged.totalNumber, 0)
    }
    
    func testMergeAscendingByTitle() throws {
        let bookA = createMockBook(id: 1, title: "Apple", library: mockLibrary1)
        let bookC = createMockBook(id: 2, title: "Cherry", library: mockLibrary1)
        let bookB = createMockBook(id: 3, title: "Banana", library: mockLibrary2)
        let bookD = createMockBook(id: 4, title: "Date", library: mockLibrary2)
        
        let libraryResults: [String: LibrarySourceSearchResult] = [
            "lib1": LibrarySourceSearchResult(generation: Date(), totalNumber: 2, bookIds: [1, 2], books: [bookA, bookC]),
            "lib2": LibrarySourceSearchResult(generation: Date(), totalNumber: 2, bookIds: [3, 4], books: [bookB, bookD])
        ]
        
        let currentResult = UnifiedSearchResult(
            search: "test",
            sortBy: .Title,
            sortAsc: true,
            libraryIds: ["lib1", "lib2"],
            unifiedOffsets: [
                "lib1": MergeOffset(offset: 0),
                "lib2": MergeOffset(offset: 0)
            ],
            totalNumber: 0,
            limitNumber: 10,
            books: []
        )
        
        let merged = mergeService.merge(libraryResults: libraryResults, currentResult: currentResult)
        
        XCTAssertEqual(merged.books.count, 4)
        XCTAssertEqual(merged.books[0].title, "Apple")
        XCTAssertEqual(merged.books[1].title, "Banana")
        XCTAssertEqual(merged.books[2].title, "Cherry")
        XCTAssertEqual(merged.books[3].title, "Date")
        
        XCTAssertTrue(merged.unifiedOffsets["lib1"]?.beenConsumed ?? false)
        XCTAssertTrue(merged.unifiedOffsets["lib2"]?.beenConsumed ?? false)
    }
    
    func testMergeDescendingByTitle() throws {
        let bookA = createMockBook(id: 1, title: "Apple", library: mockLibrary1)
        let bookC = createMockBook(id: 2, title: "Cherry", library: mockLibrary1)
        let bookB = createMockBook(id: 3, title: "Banana", library: mockLibrary2)
        let bookD = createMockBook(id: 4, title: "Date", library: mockLibrary2)
        
        // C > A, D > B
        let libraryResults: [String: LibrarySourceSearchResult] = [
            "lib1": LibrarySourceSearchResult(generation: Date(), totalNumber: 2, bookIds: [2, 1], books: [bookC, bookA]),
            "lib2": LibrarySourceSearchResult(generation: Date(), totalNumber: 2, bookIds: [4, 3], books: [bookD, bookB])
        ]
        
        let currentResult = UnifiedSearchResult(
            search: "test",
            sortBy: .Title,
            sortAsc: false,
            libraryIds: ["lib1", "lib2"],
            unifiedOffsets: [
                "lib1": MergeOffset(offset: 0),
                "lib2": MergeOffset(offset: 0)
            ],
            totalNumber: 0,
            limitNumber: 10,
            books: []
        )
        
        let merged = mergeService.merge(libraryResults: libraryResults, currentResult: currentResult)
        
        XCTAssertEqual(merged.books.count, 4)
        XCTAssertEqual(merged.books[0].title, "Date")
        XCTAssertEqual(merged.books[1].title, "Cherry")
        XCTAssertEqual(merged.books[2].title, "Banana")
        XCTAssertEqual(merged.books[3].title, "Apple")
    }
    
    func testMergeCutOffCondition() throws {
        let bookA = createMockBook(id: 1, title: "Apple", library: mockLibrary1)
        let bookB = createMockBook(id: 2, title: "Banana", library: mockLibrary2)
        
        // Total number is 5, but we only have 1 loaded.
        let libraryResults: [String: LibrarySourceSearchResult] = [
            "lib1": LibrarySourceSearchResult(generation: Date(), totalNumber: 5, bookIds: [1], books: [bookA]),
            "lib2": LibrarySourceSearchResult(generation: Date(), totalNumber: 1, bookIds: [2], books: [bookB])
        ]
        
        let currentResult = UnifiedSearchResult(
            search: "test",
            sortBy: .Title,
            sortAsc: true,
            libraryIds: ["lib1", "lib2"],
            unifiedOffsets: [
                "lib1": MergeOffset(offset: 0),
                "lib2": MergeOffset(offset: 0)
            ],
            totalNumber: 0,
            limitNumber: 10,
            books: []
        )
        
        let merged = mergeService.merge(libraryResults: libraryResults, currentResult: currentResult)
        
        XCTAssertEqual(merged.books.count, 2)
        XCTAssertTrue(merged.unifiedOffsets["lib1"]?.beenCutOff ?? false, "lib1 should be cut off since local data is exhausted but server has more")
        XCTAssertFalse(merged.unifiedOffsets["lib1"]?.beenConsumed ?? true)
        
        XCTAssertTrue(merged.unifiedOffsets["lib2"]?.beenConsumed ?? false, "lib2 should be consumed since local data is exhausted and server has no more")
        XCTAssertFalse(merged.unifiedOffsets["lib2"]?.beenCutOff ?? true)
    }
    
    func testMergeWithLimit() throws {
        let book1 = createMockBook(id: 1, title: "Book 1", library: mockLibrary1)
        let book2 = createMockBook(id: 2, title: "Book 2", library: mockLibrary1)
        let book3 = createMockBook(id: 3, title: "Book 3", library: mockLibrary2)
        let book4 = createMockBook(id: 4, title: "Book 4", library: mockLibrary2)
        
        let libraryResults: [String: LibrarySourceSearchResult] = [
            "lib1": LibrarySourceSearchResult(generation: Date(), totalNumber: 2, bookIds: [1, 2], books: [book1, book2]),
            "lib2": LibrarySourceSearchResult(generation: Date(), totalNumber: 2, bookIds: [3, 4], books: [book3, book4])
        ]
        
        let currentResult = UnifiedSearchResult(
            search: "test",
            sortBy: .Title,
            sortAsc: true,
            libraryIds: ["lib1", "lib2"],
            unifiedOffsets: [
                "lib1": MergeOffset(offset: 0),
                "lib2": MergeOffset(offset: 0)
            ],
            totalNumber: 0,
            limitNumber: 2, // Limit to 2 books
            books: []
        )
        
        let merged = mergeService.merge(libraryResults: libraryResults, currentResult: currentResult)
        
        XCTAssertEqual(merged.books.count, 2)
        XCTAssertEqual(merged.books[0].title, "Book 1")
        XCTAssertEqual(merged.books[1].title, "Book 2")
        
        // Since we limited to 2, offsets should only advance for what was consumed
        XCTAssertEqual(merged.unifiedOffsets["lib1"]?.offset, 2)
        XCTAssertEqual(merged.unifiedOffsets["lib2"]?.offset, 0)
    }
    
    func testStableSortingDuplicates() throws {
        let book1 = createMockBook(id: 1, title: "Duplicate", library: mockLibrary1)
        let book2 = createMockBook(id: 1, title: "Duplicate", library: mockLibrary2)
        
        let libraryResults: [String: LibrarySourceSearchResult] = [
            "lib1": LibrarySourceSearchResult(generation: Date(), totalNumber: 1, bookIds: [1], books: [book1]),
            "lib2": LibrarySourceSearchResult(generation: Date(), totalNumber: 1, bookIds: [1], books: [book2])
        ]
        
        let currentResult = UnifiedSearchResult(
            search: "test",
            sortBy: .Title,
            sortAsc: true,
            libraryIds: ["lib1", "lib2"],
            unifiedOffsets: [
                "lib1": MergeOffset(offset: 0),
                "lib2": MergeOffset(offset: 0)
            ],
            totalNumber: 0,
            limitNumber: 10,
            books: []
        )
        
        let merged = mergeService.merge(libraryResults: libraryResults, currentResult: currentResult)
        
        XCTAssertEqual(merged.books.count, 2)
        XCTAssertEqual(merged.books[0].library.key, "lib1", "Stable sorting should fall back to libraryId alphabetically (lib1 < lib2)")
        XCTAssertEqual(merged.books[1].library.key, "lib2")
    }
}
