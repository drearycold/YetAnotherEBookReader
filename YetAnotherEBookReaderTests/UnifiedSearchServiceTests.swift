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
    var container: AppContainer!
    
    override func setUp() async throws {
        try await super.setUp()

        let config = Realm.Configuration(inMemoryIdentifier: "UnifiedSearchServiceTests")
        DatabaseService.shared.setup(conf: config)
        container = MockAppContainerFactory.makeContainer(testName: "UnifiedSearchServiceTests")

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
        
        serverService = container.calibreServerService
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
        
        // Setup reachability staging in container
        let probeRequest1 = CalibreProbeServerRequest(server: server1, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        let info1 = CalibreServerInfo(server: server1, isPublic: false, url: URL(string: "http://localhost/1")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: mockLibrary1.id, libraryMap: [mockLibrary1.id: "Library 1"], request: probeRequest1)
        
        let probeRequest2 = CalibreProbeServerRequest(server: server2, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        let info2 = CalibreServerInfo(server: server2, isPublic: false, url: URL(string: "http://localhost/2")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: mockLibrary2.id, libraryMap: [mockLibrary2.id: "Library 2"], request: probeRequest2)
        
        container.calibreServerInfoStaging = [
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
        AppContainer.shared = nil
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

    private func collectResults(
        for key: SearchCriteriaMergedKey,
        timeout: TimeInterval = 5.0,
        until predicate: @escaping (UnifiedSearchResult) -> Bool
    ) async -> [UnifiedSearchResult] {
        let expectation = expectation(description: "Unified search stream emitted expected result")
        var results: [UnifiedSearchResult] = []
        var fulfilled = false
        let stream = await manager.search(key: key)
        let task = Task { @MainActor in
            for await update in stream {
                guard !Task.isCancelled else { break }
                let result = update.result
                results.append(result)
                if predicate(result), !fulfilled {
                    fulfilled = true
                    expectation.fulfill()
                    break
                }
            }
        }

        await fulfillment(of: [expectation], timeout: timeout)
        task.cancel()
        return results
    }
    
    func testAsyncStreamAndIncrementalMerging() async throws {
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
        
        let receivedResults = await collectResults(for: key) { result in
            result.books.count == 2
        }
        
        XCTAssertGreaterThanOrEqual(receivedResults.count, 2)
        let finalResult = receivedResults.last!
        XCTAssertEqual(finalResult.books.count, 2)
        XCTAssertEqual(finalResult.books.getOrNil(0)?.title, "Apple")
        XCTAssertEqual(finalResult.books.getOrNil(1)?.title, "Banana")
    }

    func testResetSearchAndWaitReturnsAfterForcedNetworkRequestCompletes() async throws {
        let criteria = SearchCriteria(
            searchString: "awaitable-refresh",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let key = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteria)
        let requestLock = NSLock()
        var completedRequestCount = 0

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            Thread.sleep(forTimeInterval: 0.05)

            requestLock.lock()
            completedRequestCount += 1
            requestLock.unlock()

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let searchResultJSON = """
            {
                "total_num": 0,
                "sort_order": "asc",
                "num_books_without_search": 0,
                "offset": 0,
                "num": 0,
                "sort": "title",
                "base_url": "/ajax/search/lib1",
                "query": "",
                "library_id": "lib1",
                "book_ids": [],
                "vl": ""
            }
            """
            return (response, searchResultJSON.data(using: .utf8)!)
        }

        let stream = await manager.search(key: key)
        for await update in stream {
            if update.statuses[mockLibrary1.id]?.loading == false {
                break
            }
        }

        requestLock.lock()
        let requestsBeforeRefresh = completedRequestCount
        requestLock.unlock()

        await manager.resetSearchAndWait(for: key, force: true)

        requestLock.lock()
        let requestsAfterRefresh = completedRequestCount
        requestLock.unlock()
        XCTAssertGreaterThan(requestsAfterRefresh, requestsBeforeRefresh)
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
        
        let initialResults = await collectResults(for: key) { result in
            result.books.count == 2
        }
        let lastResult = initialResults.last
        
        XCTAssertEqual(lastResult?.books.count, 2)
        XCTAssertEqual(lastResult?.limitNumber, 100)
        
        // Expand limit
        await manager.expandLimit(for: key, by: 50)
        let expandedResults = await collectResults(for: key) { result in
            result.limitNumber == 150
        }
        let lastExpandedResult = expandedResults.last
        XCTAssertEqual(lastExpandedResult?.limitNumber, 150)
        
        // Reset search
        await manager.resetSearch(for: key)
        let resetResults = await collectResults(for: key) { result in
            result.limitNumber == 100
        }
        let lastResetResult = resetResults.last
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
        
        let initialResults = await collectResults(for: key) { result in
            result.books.count == 2
        }
        let lastResult = initialResults.last
        
        XCTAssertEqual(lastResult?.books.count, 2)
        XCTAssertEqual(lastResult?.totalNumber, 2)
        XCTAssertEqual(lastResult?.limitNumber, 100)
        
        // Expand limit
        await manager.expandLimit(for: key, by: 50)
        let expandedResults = await collectResults(for: key) { result in
            result.limitNumber == 150
        }
        let lastExpandedResult = expandedResults.last
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
        
        async let resultsA = collectResults(for: keyA) { result in
            result.books.count == 1
        }
        async let resultsB = collectResults(for: keyB) { result in
            result.books.count == 1
        }
        let finalResultsA = await resultsA
        let finalResultsB = await resultsB
        
        XCTAssertEqual(finalResultsA.last?.books.first?.title, "Apple")
        XCTAssertEqual(finalResultsB.last?.books.first?.title, "Banana")
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
        
        async let resultsA = collectResults(for: keyA) { _ in true }
        async let resultsB = collectResults(for: keyB) { _ in true }
        let initialResultsA = await resultsA
        let initialResultsB = await resultsB
        
        XCTAssertEqual(initialResultsA.last?.limitNumber, 100)
        XCTAssertEqual(initialResultsB.last?.limitNumber, 100)
        
        // Expand limit for A only
        await manager.expandLimit(for: keyA, by: 50)
        let expandedA = await collectResults(for: keyA) { result in
            result.limitNumber == 150
        }
        XCTAssertEqual(expandedA.last?.limitNumber, 150)
        
        // Verify B's limit is still 100
        let currentB = await manager.getActiveSearch(for: keyB)
        XCTAssertEqual(currentB?.limitNumber, 100)
    }

    func testSearchCancellation() async throws {
        let criteria = SearchCriteria(
            searchString: "cancellation-test",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let key = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteria)
        
        MockURLProtocol.requestHandler = { request in
            Thread.sleep(forTimeInterval: 1.0)
            throw URLError(.cancelled)
        }
        
        let exp = expectation(description: "Subscription yields initial status")
        var receivedUpdate: SearchUpdate?
        
        var fulfilledCancellation = false
        let stream = await manager.search(key: key)
        let task = Task {
            for await update in stream {
                receivedUpdate = update
                if !fulfilledCancellation {
                    fulfilledCancellation = true
                    exp.fulfill()
                }
            }
        }
        
        await fulfillment(of: [exp], timeout: 2.0)
        task.cancel()
        
        XCTAssertNotNil(receivedUpdate)
    }

    func testSearchTimeout() async throws {
        let criteria = SearchCriteria(
            searchString: "timeout-test",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let key = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteria)
        
        MockURLProtocol.requestHandler = { request in
            throw URLError(.timedOut)
        }
        
        let exp = expectation(description: "Results received with error")
        var lastUpdate: SearchUpdate?
        
        var fulfilledTimeout = false
        let stream = await manager.search(key: key)
        let task = Task {
            for await update in stream {
                lastUpdate = update
                if let status = update.statuses[mockLibrary1.id], !status.loading && status.error != nil {
                    if !fulfilledTimeout {
                        fulfilledTimeout = true
                        exp.fulfill()
                    }
                }
            }
        }
        
        await fulfillment(of: [exp], timeout: 2.0)
        task.cancel()
        
        XCTAssertNotNil(lastUpdate)
        let status = lastUpdate?.statuses[mockLibrary1.id]
        XCTAssertEqual(status?.loading, false)
        XCTAssertNotNil(status?.error)
    }

    func testSearchEmptyResults() async throws {
        let criteria = SearchCriteria(
            searchString: "empty-test",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let key = SearchCriteriaMergedKey(libraryIds: [mockLibrary1.id], criteria: criteria)
        
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let searchResultJSON = """
            {
                "total_num": 0,
                "sort_order": "asc",
                "num_books_without_search": 0,
                "offset": 0,
                "num": 0,
                "sort": "title",
                "base_url": "/ajax/search/lib1",
                "query": "empty-test",
                "library_id": "lib1",
                "book_ids": [],
                "vl": ""
            }
            """
            return (response, searchResultJSON.data(using: .utf8)!)
        }
        
        let exp = expectation(description: "Empty results received")
        var finalResult: UnifiedSearchResult?
        
        var fulfilledEmpty = false
        let stream = await manager.search(key: key)
        let task = Task {
            for await update in stream {
                if let status = update.statuses[mockLibrary1.id], !status.loading {
                    if !fulfilledEmpty {
                        fulfilledEmpty = true
                        finalResult = update.result
                        exp.fulfill()
                    }
                }
            }
        }
        
        await fulfillment(of: [exp], timeout: 2.0)
        task.cancel()
        
        XCTAssertNotNil(finalResult)
        XCTAssertEqual(finalResult?.books.count, 0)
    }
}

// Concrete Mock Repository for testing
class MockSearchCacheRepository: SearchCacheRepository {
    private let lock = NSRecursiveLock()
    
    private var _cachedLibraryResults: [String: LibraryCachedResult] = [:]
    private var _booksByLibrary: [String: [Int32: CalibreBook]] = [:]
    var localSearchResult = LocalLibrarySearchResult()

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
        
        lock.unlock()
    }

    func fetchBooks(
        library: CalibreLibrary,
        bookIds: [Int32]
    ) throws -> [Int32: CalibreBook] {
        lock.lock()
        defer { lock.unlock() }
        let books = _booksByLibrary[library.id] ?? [:]
        return bookIds.reduce(into: [Int32: CalibreBook]()) { partialResult, bookId in
            partialResult[bookId] = books[bookId]
        }
    }

    func searchLocalLibrary(
        library: CalibreLibrary,
        criteria: SearchCriteria,
        offset: Int,
        limit: Int
    ) throws -> LocalLibrarySearchResult {
        lock.lock()
        defer { lock.unlock() }
        var result = localSearchResult
        result.offset = offset
        result.num = result.bookIds.count
        return result
    }

    func writeMetadataEntries(
        library: CalibreLibrary,
        entries: [String: CalibreBookEntry?],
        json: NSDictionary?
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        var books = _booksByLibrary[library.id] ?? [:]
        entries.forEach { key, entry in
            guard let entry = entry, let bookId = Int32(key) else { return }
            var book = books[bookId] ?? CalibreBook(id: bookId, library: library)
            book.title = entry.title
            book.publisher = entry.publisher ?? ""
            book.series = entry.series ?? ""
            book.seriesIndex = entry.series_index ?? 0.0
            book.rating = Int(entry.rating * 2)
            book.authors = entry.authors
            book.tags = entry.tags
            book.comments = entry.comments ?? ""
            books[bookId] = book
        }
        _booksByLibrary[library.id] = books
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
