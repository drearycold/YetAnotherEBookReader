//
//  UnifiedSearchManagerTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-10.
//

import XCTest
import Combine
@testable import YetAnotherEBookReader

class UnifiedSearchManagerTests: XCTestCase {
    
    var repository: MockSearchCacheRepository!
    var manager: UnifiedSearchManager!
    var mockLibrary1: CalibreLibrary!
    var mockLibrary2: CalibreLibrary!
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        repository = MockSearchCacheRepository()
        manager = UnifiedSearchManager(
            mergeService: UnifiedSearchMergeService(),
            repository: repository
        )
        cancellables = Set<AnyCancellable>()
        
        let server1 = CalibreServer(uuid: UUID(), name: "Server1", baseUrl: "http://localhost/1", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        mockLibrary1 = CalibreLibrary(server: server1, key: "lib1", name: "Library 1")
        
        let server2 = CalibreServer(uuid: UUID(), name: "Server2", baseUrl: "http://localhost/2", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        mockLibrary2 = CalibreLibrary(server: server2, key: "lib2", name: "Library 2")
        
        // Mock reachability provider in manager
        manager.isServerReachableProvider = { server, isPublic in
            return true
        }
        manager.isServerReachableNoPublicProvider = { server in
            return true
        }
    }
    
    override func tearDownWithError() throws {
        repository = nil
        manager = nil
        mockLibrary1 = nil
        mockLibrary2 = nil
        cancellables = nil
        ModelData.shared = nil
        try super.tearDownWithError()
    }
    
    func createMockBook(id: Int32, title: String, library: CalibreLibrary) -> CalibreBook {
        var book = CalibreBook(id: id, library: library)
        book.title = title
        book.timestamp = Date()
        book.pubDate = Date()
        book.lastModified = Date()
        return book
    }
    
    func testPublisherAndIncrementalMerging() throws {
        let criteria = SearchCriteria(
            searchString: "test",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let key = SearchCriteriaMergedKey(libraryIds: ["lib1", "lib2"], criteria: criteria)
        
        var receivedResults: [UnifiedSearchResult] = []
        let expectation = expectation(description: "Unified results received")
        
        manager.publisher(for: key)
            .sink { result in
                receivedResults.append(result)
                if receivedResults.count == 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Emitted initial blank result (1st emission)
        XCTAssertEqual(receivedResults.count, 1)
        XCTAssertEqual(receivedResults[0].books.count, 0)
        
        // Simulate lib1 completing search (2nd emission)
        let bookA = createMockBook(id: 1, title: "Apple", library: mockLibrary1)
        let lib1Result = LibrarySourceSearchResult(
            generation: Date(),
            totalNumber: 1,
            bookIds: [1],
            books: [bookA]
        )
        try repository.saveLibrarySourceResult(
            libraryId: "lib1",
            search: "test",
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: lib1Result
        )
        
        // Simulate lib2 completing search (3rd emission)
        let bookB = createMockBook(id: 2, title: "Banana", library: mockLibrary2)
        let lib2Result = LibrarySourceSearchResult(
            generation: Date(),
            totalNumber: 1,
            bookIds: [2],
            books: [bookB]
        )
        try repository.saveLibrarySourceResult(
            libraryId: "lib2",
            search: "test",
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/2",
            result: lib2Result
        )
        
        waitForExpectations(timeout: 2.0)
        
        XCTAssertEqual(receivedResults.count, 3)
        let finalResult = receivedResults[2]
        XCTAssertEqual(finalResult.books.count, 2)
        XCTAssertEqual(finalResult.books[0].title, "Apple")
        XCTAssertEqual(finalResult.books[1].title, "Banana")
    }
    
    func testExpandLimitAndResetSearch() throws {
        let criteria = SearchCriteria(
            searchString: "test",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let key = SearchCriteriaMergedKey(libraryIds: ["lib1"], criteria: criteria)
        
        // Prep cache
        let book1 = createMockBook(id: 1, title: "A", library: mockLibrary1)
        let book2 = createMockBook(id: 2, title: "B", library: mockLibrary1)
        let lib1Result = LibrarySourceSearchResult(
            generation: Date(),
            totalNumber: 2,
            bookIds: [1, 2],
            books: [book1, book2]
        )
        try repository.saveLibrarySourceResult(
            libraryId: "lib1",
            search: "test",
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: lib1Result
        )
        
        let expectation1 = expectation(description: "Initial merge completed")
        var lastResult: UnifiedSearchResult?
        var fulfilled = false
        manager.publisher(for: key)
            .sink { result in
                lastResult = result
                if result.books.count == 2 && !fulfilled {
                    fulfilled = true
                    expectation1.fulfill()
                }
            }
            .store(in: &cancellables)
        
        waitForExpectations(timeout: 2.0)
        
        XCTAssertEqual(lastResult?.books.count, 2)
        XCTAssertEqual(lastResult?.limitNumber, 100)
        
        // Expand limit
        let expectation2 = expectation(description: "Limit expanded")
        var limitExpanded = false
        var lastExpandedResult: UnifiedSearchResult?
        manager.publisher(for: key)
            .sink { result in
                if result.limitNumber == 150 && !limitExpanded {
                    limitExpanded = true
                    lastExpandedResult = result
                    expectation2.fulfill()
                }
            }
            .store(in: &cancellables)
            
        manager.expandLimit(for: key, by: 50)
        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(lastExpandedResult?.limitNumber, 150)
        
        // Reset search
        let expectation3 = expectation(description: "Search reset")
        var searchReset = false
        var lastResetResult: UnifiedSearchResult?
        manager.publisher(for: key)
            .sink { result in
                if result.limitNumber == 100 && !searchReset {
                    searchReset = true
                    lastResetResult = result
                    expectation3.fulfill()
                }
            }
            .store(in: &cancellables)
            
        manager.resetSearch(for: key)
        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(lastResetResult?.limitNumber, 100)
    }
    
    func testEmptyLibraryIdsMergingAndExpansion() throws {
        // Setup ModelData.shared
        let modelData = ModelData()
        modelData.calibreLibraries = [
            "lib1": mockLibrary1,
            "lib2": mockLibrary2
        ]
        ModelData.shared = modelData
        
        let criteria = SearchCriteria(
            searchString: "test",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        // Key with empty libraryIds representing "All Libraries"
        let key = SearchCriteriaMergedKey(libraryIds: [], criteria: criteria)
        
        // Save mock library cached results
        let book1 = createMockBook(id: 1, title: "A", library: mockLibrary1)
        let book2 = createMockBook(id: 2, title: "B", library: mockLibrary2)
        
        let lib1Result = LibrarySourceSearchResult(
            generation: Date(),
            totalNumber: 1,
            bookIds: [1],
            books: [book1]
        )
        try repository.saveLibrarySourceResult(
            libraryId: "lib1",
            search: "test",
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: lib1Result
        )
        
        let lib2Result = LibrarySourceSearchResult(
            generation: Date(),
            totalNumber: 1,
            bookIds: [2],
            books: [book2]
        )
        try repository.saveLibrarySourceResult(
            libraryId: "lib2",
            search: "test",
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/2",
            result: lib2Result
        )
        
        let expectation1 = expectation(description: "Merge completed for empty libraryIds")
        var lastResult: UnifiedSearchResult?
        var fulfilled = false
        
        manager.publisher(for: key)
            .sink { result in
                lastResult = result
                if result.books.count == 2 && !fulfilled {
                    fulfilled = true
                    expectation1.fulfill()
                }
            }
            .store(in: &cancellables)
            
        waitForExpectations(timeout: 2.0)
        
        XCTAssertEqual(lastResult?.books.count, 2)
        XCTAssertEqual(lastResult?.totalNumber, 2)
        XCTAssertEqual(lastResult?.limitNumber, 100)
        
        // Expand limit
        let expectation2 = expectation(description: "Limit expanded for empty libraryIds")
        var limitExpanded = false
        var lastExpandedResult: UnifiedSearchResult?
        manager.publisher(for: key)
            .sink { result in
                if result.limitNumber == 150 && !limitExpanded {
                    limitExpanded = true
                    lastExpandedResult = result
                    expectation2.fulfill()
                }
            }
            .store(in: &cancellables)
            
        manager.expandLimit(for: key, by: 50)
        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(lastExpandedResult?.limitNumber, 150)
    }
    
    func testMultipleSearchCriteriaHandling() throws {
        let criteriaA = SearchCriteria(
            searchString: "apple",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let criteriaB = SearchCriteria(
            searchString: "banana",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        
        let keyA = SearchCriteriaMergedKey(libraryIds: ["lib1"], criteria: criteriaA)
        let keyB = SearchCriteriaMergedKey(libraryIds: ["lib1"], criteria: criteriaB)
        
        var resultsA: [UnifiedSearchResult] = []
        var resultsB: [UnifiedSearchResult] = []
        
        let expA = expectation(description: "Results A received")
        let expB = expectation(description: "Results B received")
        
        manager.publisher(for: keyA)
            .sink { result in
                resultsA.append(result)
                if resultsA.count == 2 {
                    expA.fulfill()
                }
            }
            .store(in: &cancellables)
            
        manager.publisher(for: keyB)
            .sink { result in
                resultsB.append(result)
                if resultsB.count == 2 {
                    expB.fulfill()
                }
            }
            .store(in: &cancellables)
            
        // Initial empty results emitted for both
        XCTAssertEqual(resultsA.count, 1)
        XCTAssertEqual(resultsB.count, 1)
        
        // Save result for A
        let bookA = createMockBook(id: 1, title: "Apple", library: mockLibrary1)
        let resA = LibrarySourceSearchResult(generation: Date(), totalNumber: 1, bookIds: [1], books: [bookA])
        try repository.saveLibrarySourceResult(
            libraryId: "lib1",
            search: "apple",
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: resA
        )
        
        // Save result for B
        let bookB = createMockBook(id: 2, title: "Banana", library: mockLibrary1)
        let resB = LibrarySourceSearchResult(generation: Date(), totalNumber: 1, bookIds: [2], books: [bookB])
        try repository.saveLibrarySourceResult(
            libraryId: "lib1",
            search: "banana",
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: resB
        )
        
        waitForExpectations(timeout: 2.0)
        
        XCTAssertEqual(resultsA.last?.books.first?.title, "Apple")
        XCTAssertEqual(resultsB.last?.books.first?.title, "Banana")
    }
    
    func testLimitExpansionIsolatesCriteria() throws {
        let criteriaA = SearchCriteria(
            searchString: "apple",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let criteriaB = SearchCriteria(
            searchString: "banana",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        
        let keyA = SearchCriteriaMergedKey(libraryIds: ["lib1"], criteria: criteriaA)
        let keyB = SearchCriteriaMergedKey(libraryIds: ["lib1"], criteria: criteriaB)
        
        var resultsA: [UnifiedSearchResult] = []
        var resultsB: [UnifiedSearchResult] = []
        
        let expA = expectation(description: "Results A received")
        let expB = expectation(description: "Results B received")
        
        manager.publisher(for: keyA)
            .sink { result in
                resultsA.append(result)
                if resultsA.count == 1 {
                    expA.fulfill()
                }
            }
            .store(in: &cancellables)
            
        manager.publisher(for: keyB)
            .sink { result in
                resultsB.append(result)
                if resultsB.count == 1 {
                    expB.fulfill()
                }
            }
            .store(in: &cancellables)
            
        waitForExpectations(timeout: 2.0)
        
        XCTAssertEqual(resultsA.last?.limitNumber, 100)
        XCTAssertEqual(resultsB.last?.limitNumber, 100)
        
        // Expand limit for A only
        let expA2 = expectation(description: "Results A expanded")
        manager.publisher(for: keyA)
            .sink { result in
                if result.limitNumber == 150 {
                    expA2.fulfill()
                }
            }
            .store(in: &cancellables)
            
        manager.expandLimit(for: keyA, by: 50)
        waitForExpectations(timeout: 2.0)
        
        // Verify B's limit is still 100
        var currentB: UnifiedSearchResult?
        let expB2 = expectation(description: "Verify B's limit")
        manager.publisher(for: keyB)
            .sink { result in
                currentB = result
                expB2.fulfill()
            }
            .store(in: &cancellables)
        waitForExpectations(timeout: 2.0)
        
        XCTAssertEqual(currentB?.limitNumber, 100)
    }
}

// Concrete Mock Repository for testing
class MockSearchCacheRepository: SearchCacheRepository {
    private let lock = NSRecursiveLock()
    
    private var _cachedLibraryResults: [String: LibraryCachedResult] = [:]
    private var librarySubjects: [String: CurrentValueSubject<LibraryCachedResult, Error>] = [:]
    
    private func makeKey(libraryId: String, search: String, sortBy: SortCriteria, sortAsc: Bool, filters: [String: Set<String>]) -> String {
        let filterStr = filters.keys.sorted().map { "\($0):\(filters[$0]?.sorted() ?? [])" }.joined(separator: ",")
        return "\(libraryId)|\(search)|\(sortBy.rawValue)|\(sortAsc)|\(filterStr)"
    }
    
    func fetchLibraryCachedResult(
        libraryId: String,
        search: String,
        sortBy: SortCriteria,
        sortAsc: Bool,
        filters: [String: Set<String>]
    ) throws -> LibraryCachedResult? {
        lock.lock()
        defer { lock.unlock() }
        let key = makeKey(libraryId: libraryId, search: search, sortBy: sortBy, sortAsc: sortAsc, filters: filters)
        return _cachedLibraryResults[key]
    }
    
    func saveLibrarySourceResult(
        libraryId: String,
        search: String,
        sortBy: SortCriteria,
        sortAsc: Bool,
        filters: [String: Set<String>],
        sourceUrl: String,
        result: LibrarySourceSearchResult
    ) throws {
        lock.lock()
        let key = makeKey(libraryId: libraryId, search: search, sortBy: sortBy, sortAsc: sortAsc, filters: filters)
        var cached = _cachedLibraryResults[key] ?? LibraryCachedResult(
            libraryId: libraryId,
            search: search,
            sortBy: sortBy,
            sortAsc: sortAsc,
            filters: filters,
            sources: [:]
        )
        cached.sources[sourceUrl] = result
        _cachedLibraryResults[key] = cached
        
        let subject = librarySubjects[key]
        lock.unlock()
        
        if let subject = subject {
            subject.send(cached)
        }
    }
    
    func libraryCachedResultPublisher(
        libraryId: String,
        search: String,
        sortBy: SortCriteria,
        sortAsc: Bool,
        filters: [String: Set<String>]
    ) -> AnyPublisher<LibraryCachedResult, Error> {
        lock.lock()
        defer { lock.unlock() }
        let key = makeKey(libraryId: libraryId, search: search, sortBy: sortBy, sortAsc: sortAsc, filters: filters)
        if let subject = librarySubjects[key] {
            return subject.eraseToAnyPublisher()
        }
        let initial = _cachedLibraryResults[key] ?? LibraryCachedResult(
            libraryId: libraryId,
            search: search,
            sortBy: sortBy,
            sortAsc: sortAsc,
            filters: filters,
            sources: [:]
        )
        let subject = CurrentValueSubject<LibraryCachedResult, Error>(initial)
        librarySubjects[key] = subject
        return subject.eraseToAnyPublisher()
    }
}
