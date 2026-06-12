//
//  UnifiedSearchManagerTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-10.
//

import XCTest
import Combine
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
class UnifiedSearchServiceTests: XCTestCase {
    
    var repository: MockSearchCacheRepository!
    var libraryProvider: MockLibraryProvider!
    var manager: UnifiedSearchService!
    var mockLibrary1: CalibreLibrary!
    var mockLibrary2: CalibreLibrary!
    var cancellables: Set<AnyCancellable>!
    var serverService: CalibreServerService!
    
    override func setUp() async throws {
        try await super.setUp()
        
        let config = Realm.Configuration(inMemoryIdentifier: "UnifiedSearchServiceTests-\(UUID().uuidString)")
        DatabaseService.shared.setup(conf: config)
        let logger = CalibreActivityLogger(realmConf: config)
        let modelData = ModelData(mock: true)
        modelData.realmConf = config
        
        let server1 = CalibreServer(uuid: UUID(), name: "Server1", baseUrl: "http://localhost/1", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        mockLibrary1 = CalibreLibrary(server: server1, key: "lib1", name: "Library 1")
        
        let server2 = CalibreServer(uuid: UUID(), name: "Server2", baseUrl: "http://localhost/2", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        mockLibrary2 = CalibreLibrary(server: server2, key: "lib2", name: "Library 2")
        
        repository = MockSearchCacheRepository()
        libraryProvider = MockLibraryProvider()
        libraryProvider.libraries = [
            mockLibrary1.id: mockLibrary1,
            mockLibrary2.id: mockLibrary2
        ]
        
        serverService = modelData.calibreServerService
        let librarySearch = LibrarySearchService(service: serverService, repository: repository)
        manager = UnifiedSearchService(
            mergeService: UnifiedSearchMergeService(),
            repository: repository,
            librarySearchService: librarySearch,
            libraryProvider: libraryProvider
        )
        cancellables = Set<AnyCancellable>()
        
        await manager.setReachabilityProviders(
            reachable: { _, _ in true },
            reachableNoPublic: { _ in true }
        )
        
        // Setup ephemeral URLSession with MockURLProtocol
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        
        // Register mock sessions in the service
        for server in [server1, server2] {
            for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
                let key = CalibreServerURLSessionKey(server: server, timeout: 600, qos: qos)
                serverService.metadataSessions[key] = mockSession
            }
        }
        
        // Setup reachability staging in modelData
        let probeRequest1 = CalibreProbeServerRequest(server: server1, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        let info1 = CalibreServerInfo(server: server1, isPublic: false, url: URL(string: "http://localhost/1")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: mockLibrary1.id, libraryMap: [mockLibrary1.id: "Library 1"], request: probeRequest1)
        
        let probeRequest2 = CalibreProbeServerRequest(server: server2, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        let info2 = CalibreServerInfo(server: server2, isPublic: false, url: URL(string: "http://localhost/2")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: mockLibrary2.id, libraryMap: [mockLibrary2.id: "Library 2"], request: probeRequest2)
        
        modelData.calibreServerInfoStaging = [
            server1.uuid.uuidString: info1,
            server2.uuid.uuidString: info2
        ]
        
        // Default MockURLProtocol requestHandler
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            
            let libraryId = url.path.components(separatedBy: "/").last ?? "lib1"
            let searchResultJSON = """
            {
                "total_num": 0,
                "sort_order": "asc",
                "num_books_without_search": 0,
                "offset": 0,
                "num": 0,
                "sort": "title",
                "base_url": "/ajax/search/\\(libraryId)",
                "query": "",
                "library_id": "\\(libraryId)",
                "book_ids": [],
                "vl": ""
            }
            """
            
            if url.path.contains("ajax/search") {
                return (response, searchResultJSON.data(using: .utf8)!)
            } else if url.path.contains("ajax/books") {
                return (response, "{}".data(using: .utf8)!)
            }
            throw URLError(.badURL)
        }
    }
    
    override func tearDown() async throws {
        repository = nil
        libraryProvider = nil
        manager = nil
        mockLibrary1 = nil
        mockLibrary2 = nil
        cancellables = nil
        serverService = nil
        ModelData.shared = nil
        try await super.tearDown()
    }
    
    func createMockBook(id: Int32, title: String, library: CalibreLibrary) -> CalibreBook {
        var book = CalibreBook(id: id, library: library)
        book.title = title
        book.timestamp = Date()
        book.pubDate = Date()
        book.lastModified = Date()
        return book
    }
    
    func testPublisherAndIncrementalMerging() async throws {
        // Setup ephemeral URLSession with MockURLProtocol
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        
        for server in [mockLibrary1.server, mockLibrary2.server] {
            for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
                let key = CalibreServerURLSessionKey(server: server, timeout: 600, qos: qos)
                serverService.metadataSessions[key] = mockSession
            }
        }
        
        let searchResultJSON1 = """
        {
            "total_num": 1,
            "sort_order": "asc",
            "num_books_without_search": 1,
            "offset": 0,
            "num": 1,
            "sort": "title",
            "base_url": "/ajax/search/lib1",
            "query": "test",
            "library_id": "lib1",
            "book_ids": [1],
            "vl": ""
        }
        """
        
        let metadataJSON1 = """
        {
            "1": {
                "thumbnail": "/get/thumb/1/lib1",
                "series": null,
                "languages": ["eng"],
                "title_sort": "Apple",
                "identifiers": {},
                "user_categories": {},
                "pages": 0,
                "authors": ["Author A"],
                "link_maps": {},
                "cover": "/get/cover/1/lib1",
                "author_sort": "A, Author",
                "title": "Apple",
                "publisher": null,
                "author_sort_map": {"Author A": "A, Author"},
                "tags": [],
                "user_metadata": {},
                "uuid": "uuid-apple",
                "last_modified": "2023-07-25T03:11:04+00:00",
                "series_index": null,
                "pubdate": "2023-07-21T07:43:05+00:00",
                "application_id": 1,
                "rating": 0.0,
                "comments": "",
                "timestamp": "2023-07-21T07:43:05+00:00",
                "format_metadata": {
                    "epub": { "path": "apple.epub", "size": 100, "mtime": "2023-07-21T07:43:05+00:00" }
                },
                "formats": ["epub"],
                "main_format": {"epub": "/get/epub/1/lib1"},
                "other_formats": {},
                "category_urls": {}
            }
        }
        """
        
        let searchResultJSON2 = """
        {
            "total_num": 1,
            "sort_order": "asc",
            "num_books_without_search": 1,
            "offset": 0,
            "num": 1,
            "sort": "title",
            "base_url": "/ajax/search/lib2",
            "query": "test",
            "library_id": "lib2",
            "book_ids": [2],
            "vl": ""
        }
        """
        
        let metadataJSON2 = """
        {
            "2": {
                "thumbnail": "/get/thumb/2/lib2",
                "series": null,
                "languages": ["eng"],
                "title_sort": "Banana",
                "identifiers": {},
                "user_categories": {},
                "pages": 0,
                "authors": ["Author B"],
                "link_maps": {},
                "cover": "/get/cover/2/lib2",
                "author_sort": "B, Author",
                "title": "Banana",
                "publisher": null,
                "author_sort_map": {"Author B": "B, Author"},
                "tags": [],
                "user_metadata": {},
                "uuid": "uuid-banana",
                "last_modified": "2023-07-25T03:11:04+00:00",
                "series_index": null,
                "pubdate": "2023-07-21T07:43:05+00:00",
                "application_id": 2,
                "rating": 0.0,
                "comments": "",
                "timestamp": "2023-07-21T07:43:05+00:00",
                "format_metadata": {
                    "epub": { "path": "banana.epub", "size": 200, "mtime": "2023-07-21T07:43:05+00:00" }
                },
                "formats": ["epub"],
                "main_format": {"epub": "/get/epub/2/lib2"},
                "other_formats": {},
                "category_urls": {}
            }
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            
            if url.path.contains("ajax/search/lib1") {
                return (response, searchResultJSON1.data(using: .utf8)!)
            } else if url.path.contains("ajax/books/lib1") {
                return (response, metadataJSON1.data(using: .utf8)!)
            } else if url.path.contains("ajax/search/lib2") {
                return (response, searchResultJSON2.data(using: .utf8)!)
            } else if url.path.contains("ajax/books/lib2") {
                return (response, metadataJSON2.data(using: .utf8)!)
            }
            throw URLError(.badURL)
        }
        
        let criteria = SearchCriteria(
            searchString: "test",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let key = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id, mockLibrary2.id], criteria: criteria)
        
        var receivedResults: [UnifiedSearchResult] = []
        let expectation = expectation(description: "Unified results received")
        var fulfilled = false
        
        manager.publisher(for: key)
            .receive(on: DispatchQueue.main)
            .sink { result in
                receivedResults.append(result)
                if result.books.count == 2 && !fulfilled {
                    fulfilled = true
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
            
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertGreaterThanOrEqual(receivedResults.count, 2)
        let finalResult = receivedResults.last!
        XCTAssertEqual(finalResult.books.count, 2)
        XCTAssertEqual(finalResult.books.getOrNil(0)?.title, "Apple")
        XCTAssertEqual(finalResult.books.getOrNil(1)?.title, "Banana")
    }
    
    func testExpandLimitAndResetSearch() async throws {
        let criteria = SearchCriteria(
            searchString: "test",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let key = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteria)
        
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
            libraryId: mockLibrary1.id,
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
            .receive(on: DispatchQueue.main)
            .sink { result in
                lastResult = result
                if result.books.count == 2 && !fulfilled {
                    fulfilled = true
                    expectation1.fulfill()
                }
            }
            .store(in: &cancellables)
        
        await fulfillment(of: [expectation1], timeout: 2.0)
        
        XCTAssertEqual(lastResult?.books.count, 2)
        XCTAssertEqual(lastResult?.limitNumber, 100)
        
        // Expand limit
        let expectation2 = expectation(description: "Limit expanded")
        var limitExpanded = false
        var lastExpandedResult: UnifiedSearchResult?
        manager.publisher(for: key)
            .receive(on: DispatchQueue.main)
            .sink { result in
                if result.limitNumber == 150 && !limitExpanded {
                    limitExpanded = true
                    lastExpandedResult = result
                    expectation2.fulfill()
                }
            }
            .store(in: &cancellables)
            
        await manager.expandLimit(for: key, by: 50)
        await fulfillment(of: [expectation2], timeout: 2.0)
        XCTAssertEqual(lastExpandedResult?.limitNumber, 150)
        
        // Reset search
        let expectation3 = expectation(description: "Search reset")
        var searchReset = false
        var lastResetResult: UnifiedSearchResult?
        manager.publisher(for: key)
            .receive(on: DispatchQueue.main)
            .sink { result in
                if result.limitNumber == 100 && !searchReset {
                    searchReset = true
                    lastResetResult = result
                    expectation3.fulfill()
                }
            }
            .store(in: &cancellables)
            
        await manager.resetSearch(for: key)
        await fulfillment(of: [expectation3], timeout: 2.0)
        XCTAssertEqual(lastResetResult?.limitNumber, 100)
    }
    
    func testEmptyLibraryIdsMergingAndExpansion() async throws {
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
            libraryId: mockLibrary1.id,
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
            libraryId: mockLibrary2.id,
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
            .receive(on: DispatchQueue.main)
            .sink { result in
                lastResult = result
                if result.books.count == 2 && !fulfilled {
                    fulfilled = true
                    expectation1.fulfill()
                }
            }
            .store(in: &cancellables)
            
        await fulfillment(of: [expectation1], timeout: 2.0)
        
        XCTAssertEqual(lastResult?.books.count, 2)
        XCTAssertEqual(lastResult?.totalNumber, 2)
        XCTAssertEqual(lastResult?.limitNumber, 100)
        
        // Expand limit
        let expectation2 = expectation(description: "Limit expanded for empty libraryIds")
        var limitExpanded = false
        var lastExpandedResult: UnifiedSearchResult?
        manager.publisher(for: key)
            .receive(on: DispatchQueue.main)
            .sink { result in
                if result.limitNumber == 150 && !limitExpanded {
                    limitExpanded = true
                    lastExpandedResult = result
                    expectation2.fulfill()
                }
            }
            .store(in: &cancellables)
            
        await manager.expandLimit(for: key, by: 50)
        await fulfillment(of: [expectation2], timeout: 2.0)
        XCTAssertEqual(lastExpandedResult?.limitNumber, 150)
    }
    
    func testMultipleSearchCriteriaHandling() async throws {
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
        
        let keyA = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteriaA)
        let keyB = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteriaB)
        
        // Prep cache for A
        let bookA = createMockBook(id: 1, title: "Apple", library: mockLibrary1)
        let resA = LibrarySourceSearchResult(generation: Date(), totalNumber: 1, bookIds: [1], books: [bookA])
        try repository.saveLibrarySourceResult(
            libraryId: mockLibrary1.id,
            search: "apple",
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: resA
        )
        
        // Prep cache for B
        let bookB = createMockBook(id: 2, title: "Banana", library: mockLibrary1)
        let resB = LibrarySourceSearchResult(generation: Date(), totalNumber: 1, bookIds: [2], books: [bookB])
        try repository.saveLibrarySourceResult(
            libraryId: mockLibrary1.id,
            search: "banana",
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "http://localhost/1",
            result: resB
        )
        
        var resultsA: [UnifiedSearchResult] = []
        var resultsB: [UnifiedSearchResult] = []
        
        let expA = expectation(description: "Results A received")
        let expB = expectation(description: "Results B received")
        
        var fulfilledA = false
        manager.publisher(for: keyA)
            .receive(on: DispatchQueue.main)
            .sink { result in
                resultsA.append(result)
                if result.books.count == 1 && !fulfilledA {
                    fulfilledA = true
                    expA.fulfill()
                }
            }
            .store(in: &cancellables)
            
        var fulfilledB = false
        manager.publisher(for: keyB)
            .receive(on: DispatchQueue.main)
            .sink { result in
                resultsB.append(result)
                if result.books.count == 1 && !fulfilledB {
                    fulfilledB = true
                    expB.fulfill()
                }
            }
            .store(in: &cancellables)
            
        await fulfillment(of: [expA, expB], timeout: 2.0)
        
        XCTAssertEqual(resultsA.last?.books.first?.title, "Apple")
        XCTAssertEqual(resultsB.last?.books.first?.title, "Banana")
    }
    
    func testLimitExpansionIsolatesCriteria() async throws {
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
        
        let keyA = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteriaA)
        let keyB = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteriaB)
        
        var resultsA: [UnifiedSearchResult] = []
        var resultsB: [UnifiedSearchResult] = []
        
        let expA = expectation(description: "Results A received")
        let expB = expectation(description: "Results B received")
        
        var fulfilledA = false
        manager.publisher(for: keyA)
            .receive(on: DispatchQueue.main)
            .sink { result in
                resultsA.append(result)
                if resultsA.count == 1 && !fulfilledA {
                    fulfilledA = true
                    expA.fulfill()
                }
            }
            .store(in: &cancellables)
            
        var fulfilledB = false
        manager.publisher(for: keyB)
            .receive(on: DispatchQueue.main)
            .sink { result in
                resultsB.append(result)
                if resultsB.count == 1 && !fulfilledB {
                    fulfilledB = true
                    expB.fulfill()
                }
            }
            .store(in: &cancellables)
            
        await fulfillment(of: [expA, expB], timeout: 2.0)
        
        XCTAssertEqual(resultsA.last?.limitNumber, 100)
        XCTAssertEqual(resultsB.last?.limitNumber, 100)
        
        // Expand limit for A only
        let expA2 = expectation(description: "Results A expanded")
        var fulfilledA2 = false
        manager.publisher(for: keyA)
            .receive(on: DispatchQueue.main)
            .sink { result in
                if result.limitNumber == 150 && !fulfilledA2 {
                    fulfilledA2 = true
                    expA2.fulfill()
                }
            }
            .store(in: &cancellables)
            
        await manager.expandLimit(for: keyA, by: 50)
        await fulfillment(of: [expA2], timeout: 2.0)
        
        // Verify B's limit is still 100
        var currentB: UnifiedSearchResult?
        let expB2 = expectation(description: "Verify B's limit")
        var fulfilledB2 = false
        manager.publisher(for: keyB)
            .receive(on: DispatchQueue.main)
            .sink { result in
                currentB = result
                if !fulfilledB2 {
                    fulfilledB2 = true
                    expB2.fulfill()
                }
            }
            .store(in: &cancellables)
        await fulfillment(of: [expB2], timeout: 2.0)
        
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

@MainActor
class MockLibraryProvider: LibraryProvider {
    var libraries: [String: CalibreLibrary] = [:]
    
    func getLibraries() -> [String: CalibreLibrary] {
        return libraries
    }
    
    func isServerReachable(server: CalibreServer, isPublic: Bool) -> Bool? {
        return true
    }
    
    func isServerReachable(server: CalibreServer) -> Bool {
        return true
    }
}
