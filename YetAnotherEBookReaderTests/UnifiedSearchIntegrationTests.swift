//
//  UnifiedSearchIntegrationTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-11.
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

func debugLog(_ message: String) {
    print("[DEBUG_LOG] \(message)")
}

class UnifiedSearchIntegrationTests: XCTestCase {

    var container: AppContainer!
    var unifiedSearchService: UnifiedSearchService!
    var mockServer: CalibreServer!
    var mockLibrary: CalibreLibrary!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Setup logger

        debugLog("setUpWithError started")

        // Setup in-memory Realm for testing
        let config = Realm.Configuration(inMemoryIdentifier: "UnifiedSearchIntegrationTests")
        container = MockAppContainerFactory.makeContainer(
            mainRealmConfiguration: config,
            testName: "UnifiedSearchIntegrationTests"
        )

        // Setup mock server and library
        mockServer = CalibreServer(
            uuid: UUID(),
            name: "TestServer",
            baseUrl: "http://localhost:8080",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        mockLibrary = CalibreLibrary(server: mockServer, key: "lib1", name: "Library 1")

        try container.serverRepository.saveServer(mockServer)
        try container.libraryRepository.saveLibrary(mockLibrary)
        container.libraryManager.calibreLibraries = [mockLibrary.id: mockLibrary]

        // Mock server reachability staging
        let probeRequest = CalibreProbeServerRequest(
            server: mockServer,
            isPublic: false,
            updateLibrary: false,
            autoUpdateOnly: false
        )
        let serverInfo = CalibreServerInfo(
            server: mockServer,
            isPublic: false,
            url: URL(string: "http://localhost:8080")!,
            reachable: true,
            probing: false,
            errorMsg: "Success",
            defaultLibrary: mockLibrary.id,
            libraryMap: [mockLibrary.id: "Library 1"],
            request: probeRequest
        )
        container.calibreServerInfoStaging = [mockServer.uuid.uuidString: serverInfo]

        // Setup ephemeral URLSession with MockURLProtocol
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)

        // Create test services and pre-populate metadataSessions
        let logger = CalibreActivityLogger(repository: container.activityLogRepository)
        let service = CalibreServerService(
            logger: logger,
            config: container,
            database: container.databaseService
        )

        // Register mock sessions in the service
        let keyDefault = CalibreServerURLSessionKey(server: mockServer, timeout: 600, qos: .default)
        let keyBackground = CalibreServerURLSessionKey(server: mockServer, timeout: 600, qos: .background)
        let keyUtility = CalibreServerURLSessionKey(server: mockServer, timeout: 600, qos: .utility)
        service.metadataSessions = [
            keyDefault: mockSession,
            keyBackground: mockSession,
            keyUtility: mockSession
        ]

        let cacheRepository = RealmSearchCacheStore(config: config, container: container)
        let librarySearchService = LibrarySearchService(service: service, repository: cacheRepository)
        let unifiedSearchService = UnifiedSearchService(
            repository: cacheRepository,
            librarySearchService: librarySearchService,
            libraryProvider: container
        )

        container.calibreServerService = service
        container.searchCacheRepository = cacheRepository
        container.librarySearchService = librarySearchService
        container.unifiedSearchService = unifiedSearchService
        container.categoryCacheRepository = cacheRepository
        container.libraryCategoryService = LibraryCategoryService(service: service, repository: cacheRepository)
        container.unifiedCategoryService = UnifiedCategoryService(repository: cacheRepository, libraryProvider: container)

        self.unifiedSearchService = unifiedSearchService
        debugLog("setUpWithError finished")
    }

    override func tearDownWithError() throws {
        unifiedSearchService = nil
        container = nil
        mockServer = nil
        mockLibrary = nil
        try super.tearDownWithError()
    }

    func testUnifiedSearchEndToEndWithMockServer() async throws {
        debugLog("testUnifiedSearchEndToEndWithMockServer started")

        // Mock search response JSON
        let searchResultJSON = """
        {
            "total_num": 1,
            "sort_order": "asc",
            "num_books_without_search": 1,
            "offset": 0,
            "num": 1,
            "sort": "title",
            "base_url": "/ajax/search/lib1",
            "query": "",
            "library_id": "lib1",
            "book_ids": [1],
            "vl": ""
        }
        """

        // Mock metadata response JSON
        let metadataJSON = """
        {
            "1": {
                "thumbnail": "/get/thumb/1/lib1",
                "series": null,
                "languages": ["eng"],
                "title_sort": "Quick Start Guide",
                "identifiers": {},
                "user_categories": {},
                "pages": 0,
                "authors": ["John Schember"],
                "link_maps": {},
                "cover": "/get/cover/1/lib1",
                "author_sort": "Schember, John",
                "title": "Quick Start Guide",
                "publisher": null,
                "author_sort_map": {"John Schember": "Schember, John"},
                "tags": [],
                "user_metadata": {
                    "#pages": {
                        "table": "custom_column_1",
                        "column": "value",
                        "datatype": "int",
                        "is_multiple": null,
                        "kind": "field",
                        "name": "Pages",
                        "search_terms": ["#pages"],
                        "label": "pages",
                        "colnum": 1,
                        "display": {"number_format": null, "description": ""},
                        "is_custom": true,
                        "is_category": false,
                        "link_column": "value",
                        "category_sort": "value",
                        "is_csp": false,
                        "is_editable": true,
                        "rec_index": 23,
                        "#value#": 13,
                        "#extra#": null,
                        "is_multiple2": {}
                    },
                    "#words": {
                        "table": "custom_column_2",
                        "column": "value",
                        "datatype": "int",
                        "is_multiple": null,
                        "kind": "field",
                        "name": "Words",
                        "search_terms": ["#words"],
                        "label": "words",
                        "colnum": 2,
                        "display": {"number_format": null, "description": ""},
                        "is_custom": true,
                        "is_category": false,
                        "link_column": "value",
                        "category_sort": "value",
                        "is_csp": false,
                        "is_editable": true,
                        "rec_index": 24,
                        "#value#": 5111,
                        "#extra#": null,
                        "is_multiple2": {}
                    }
                },
                "uuid": "0458f36e-0e8d-4a7c-9d10-2a7131c7e4af",
                "last_modified": "2023-07-25T03:11:04+00:00",
                "series_index": null,
                "pubdate": "2023-07-21T07:43:05+00:00",
                "application_id": 1,
                "rating": 0.0,
                "comments": "calibre Quick Start Guide",
                "timestamp": "2023-07-21T07:43:05+00:00",
                "format_metadata": {
                    "epub": {
                        "path": "/Users/peterlee/Calibre Library/John Schember/Quick Start Guide (1)/Quick Start Guide - John Schember.epub",
                        "size": 55532,
                        "mtime": "2023-07-21T07:43:05.274319+00:00"
                    }
                },
                "formats": ["epub"],
                "main_format": {"epub": "/get/epub/1/lib1"},
                "other_formats": {},
                "category_urls": {
                    "series": {},
                    "languages": {},
                    "authors": {"John Schember": "/ajax/books_in/617574686f7273/31/lib1"},
                    "publisher": {},
                    "tags": {}
                }
            }
        }
        """

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                debugLog("requestHandler got request without URL")
                throw URLError(.badURL)
            }
            debugLog("requestHandler intercepting url: \(url.absoluteString)")

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            if url.path.contains("ajax/search/lib1") {
                debugLog("requestHandler returning search JSON")
                return (response, searchResultJSON.data(using: .utf8)!)
            } else if url.path.contains("ajax/books/lib1") {
                debugLog("requestHandler returning metadata JSON")
                return (response, metadataJSON.data(using: .utf8)!)
            }

            debugLog("requestHandler unhandled path: \(url.path)")
            throw URLError(.badURL)
        }

        // Create SearchCriteria
        let criteria = SearchCriteria(
            searchString: "Integration",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        // Key uses the library.id
        let key = SearchCriteriaMergedKey(libraryIds: [mockLibrary.id], criteria: criteria)

        let expectation = expectation(description: "UnifiedSearchManager returns search results from network")
        var finalResult: UnifiedSearchResult?

        debugLog("subscribing to async search stream")
        let stream = await unifiedSearchService.search(key: key)
        let task = Task {
            for await update in stream {
                debugLog("stream emitted result with \(update.result.books.count) books")
                if update.result.books.count > 0 {
                    finalResult = update.result
                    expectation.fulfill()
                    break
                }
            }
        }
        await fulfillment(of: [expectation], timeout: 5.0)
        task.cancel()

        debugLog("test finished. result: \(String(describing: finalResult))")

        XCTAssertNotNil(finalResult)
        XCTAssertEqual(finalResult?.books.count, 1)
        XCTAssertEqual(finalResult?.books.first?.title, "Quick Start Guide")
        XCTAssertEqual(finalResult?.books.first?.authors.first, "John Schember")
        await container.calibreServerService.logger.flushPendingActivitiesForTesting()
        let entries = await container.activityLogRepository.fetchTestSnapshots(libraryId: mockLibrary.id, bookId: nil, since: .distantPast)
        XCTAssertEqual(entries.filter { $0.kind == .search }.count, 1)
        XCTAssertEqual(entries.filter { $0.kind == .batchMetadata }.count, 1)
        XCTAssertTrue(entries.allSatisfy { $0.state == .finished(.succeeded) })
        XCTAssertFalse(entries.first { $0.kind == .search }?.request.endpointURL?.contains("Integration") ?? true)
    }

    func testSearchCacheSaveInsertsMissingDomainBooks() throws {
        let config = Realm.Configuration(inMemoryIdentifier: "SearchCacheMissingBookInsert-\(UUID().uuidString)")
        let store = RealmSearchCacheStore(config: config, container: container)
        var book = CalibreBook(id: 42, library: mockLibrary)
        book.title = "Cache-only Book"

        try store.saveLibrarySourceResult(
            libraryId: mockLibrary.id,
            search: "cache-only",
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "test-source",
            result: LibrarySourceSearchResult(
                generation: Date(timeIntervalSince1970: 123),
                totalNumber: 1,
                bookIds: [book.id],
                books: [book]
            )
        )

        let realm = try Realm(configuration: config)
        let primaryKey = CalibreBookRealm.PrimaryKey(
            serverUUID: mockLibrary.server.uuid.uuidString,
            libraryName: mockLibrary.name,
            id: book.id.description
        )
        XCTAssertEqual(
            realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)?.title,
            book.title
        )
        XCTAssertEqual(realm.objects(CalibreLibrarySearchObject.self).count, 1)
    }

    func testSearchCacheSaveSkipsIdenticalSourceUpdate() throws {
        let config = Realm.Configuration(inMemoryIdentifier: "SearchCacheNoOp-\(UUID().uuidString)")
        let store = RealmSearchCacheStore(config: config, container: container)
        let result = LibrarySourceSearchResult(
            generation: Date(timeIntervalSince1970: 456),
            totalNumber: 2,
            bookIds: [1, 2],
            books: []
        )

        try store.saveLibrarySourceResult(
            libraryId: mockLibrary.id,
            search: "same",
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "test-source",
            result: result
        )

        let realm = try Realm(configuration: config)
        let source = try XCTUnwrap(
            realm.objects(CalibreLibrarySearchObject.self).first?.sources["test-source"] ?? nil
        )
        let unexpectedChange = expectation(description: "Identical cache save must not modify Realm")
        unexpectedChange.isInverted = true
        let token = source.observe { change in
            if case .change = change {
                unexpectedChange.fulfill()
            }
        }

        try store.saveLibrarySourceResult(
            libraryId: mockLibrary.id,
            search: "same",
            sortBy: .Title,
            sortAsc: true,
            filters: [:],
            sourceUrl: "test-source",
            result: result
        )

        wait(for: [unexpectedChange], timeout: 0.2)
        token.invalidate()
    }

    func testSearchCacheLocalLibrarySearchUnionsSameCategoryFiltersSortsAndPaginates() throws {
        let config = Realm.Configuration(inMemoryIdentifier: "SearchCacheLocalSearch-\(UUID().uuidString)")
        let store = RealmSearchCacheStore(config: config, container: container)
        let realm = try Realm(configuration: config)

        var firstBook = CalibreBook(id: 1, library: mockLibrary)
        firstBook.title = "Swift Basics"
        firstBook.authors = ["Taylor"]
        firstBook.tags = ["Programming"]
        firstBook.publisher = "Docs"

        var secondBook = CalibreBook(id: 2, library: mockLibrary)
        secondBook.title = "Advanced Swift"
        secondBook.authors = ["Morgan"]
        secondBook.tags = ["Programming"]
        secondBook.publisher = "Docs"

        var thirdBook = CalibreBook(id: 3, library: mockLibrary)
        thirdBook.title = "Swift Cooking"
        thirdBook.authors = ["Casey"]
        thirdBook.tags = ["Food"]
        thirdBook.publisher = "Kitchen"

        try realm.write {
            realm.add(firstBook.makeRealmObject(), update: .modified)
            realm.add(secondBook.makeRealmObject(), update: .modified)
            realm.add(thirdBook.makeRealmObject(), update: .modified)
        }

        let criteria = SearchCriteria(
            searchString: "swift",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: ["Tags": Set(["Programming", "Food"])]
        )

        let result = try store.searchLocalLibrary(
            library: mockLibrary,
            criteria: criteria,
            offset: 1,
            limit: 1
        )

        XCTAssertEqual(result.totalNumber, 3)
        XCTAssertEqual(result.numBooksWithoutSearch, 3)
        XCTAssertEqual(result.offset, 1)
        XCTAssertEqual(result.num, 1)
        XCTAssertEqual(result.sort, SortCriteria.Title.sortQueryParam)
        XCTAssertEqual(result.bookIds, [1])
    }

    func testSearchCacheWriteMetadataEntriesCreatesAndReadsDomainBook() throws {
        let config = Realm.Configuration(inMemoryIdentifier: "SearchCacheMetadataWrite-\(UUID().uuidString)")
        let store = RealmSearchCacheStore(config: config, container: container)
        var entry = CalibreBookEntry()
        entry.title = "Metadata Book"
        entry.publisher = "Metadata Press"
        entry.series = "Boundary"
        entry.series_index = 2.5
        entry.pubdate = "2026-01-02T03:04:05+00:00"
        entry.timestamp = "2026-01-03T03:04:05+00:00"
        entry.last_modified = "2026-01-04T03:04:05+00:00"
        entry.authors = ["Author One", "Author Two"]
        entry.tags = ["Realm", "Search"]
        entry.rating = 4.0
        entry.comments = "Created from metadata entry"
        entry.identifiers = ["isbn": "12345"]
        entry.format_metadata = [
            "epub": CalibreBookFormatMetadataEntry(
                path: "Metadata Book.epub",
                size: 2048,
                mtime: "2026-01-05T03:04:05.000+00:00"
            )
        ]

        let root: NSDictionary = [
            "77": [
                "user_metadata": [
                    "#genre": [
                        "label": "Genre",
                        "#value#": "Reference"
                    ]
                ]
            ]
        ]

        try store.writeMetadataEntries(
            library: mockLibrary,
            entries: ["77": entry],
            json: root
        )

        let books = try store.fetchBooks(library: mockLibrary, bookIds: [77])
        let book = try XCTUnwrap(books[77])
        XCTAssertEqual(book.title, "Metadata Book")
        XCTAssertEqual(book.publisher, "Metadata Press")
        XCTAssertEqual(book.series, "Boundary")
        XCTAssertEqual(book.seriesIndex, 2.5)
        XCTAssertEqual(book.authors, ["Author One", "Author Two"])
        XCTAssertEqual(book.tags, ["Realm", "Search"])
        XCTAssertEqual(book.rating, 8)
        XCTAssertEqual(book.comments, "Created from metadata entry")
        XCTAssertEqual(book.identifiers["isbn"], "12345")
        XCTAssertEqual(book.formats["EPUB"]?.serverSize, 2048)
        XCTAssertEqual(book.userMetadatas["Genre"] as? String, "Reference")
    }

    func testUnifiedSearchFailureHttpStatus() async throws {
        debugLog("testUnifiedSearchFailureHttpStatus started")

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("Not Found".utf8))
        }

        let criteria = SearchCriteria(
            searchString: "ErrorSearch",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [:]
        )
        let key = SearchCriteriaMergedKey(libraryIds: [mockLibrary.id], criteria: criteria)

        let stream = await unifiedSearchService.search(key: key)
        var receivedStatuses: [String: LibrarySearchStatus] = [:]

        for await update in stream {
            receivedStatuses = update.statuses
            if update.statuses[mockLibrary.id]?.loading == false {
                break
            }
        }

        let status = try XCTUnwrap(receivedStatuses[mockLibrary.id])
        XCTAssertFalse(status.loading)

        guard let error = status.error else {
            return XCTFail("Expected search error but got nil")
        }

        if case .network(let apiError) = error {
            if case .httpStatus(let code, _) = apiError {
                XCTAssertEqual(code, 404)
            } else {
                XCTFail("Expected httpStatus error but got \(apiError)")
            }
        } else {
            XCTFail("Expected .network error but got \(error)")
        }
    }
}

@MainActor
final class CacheRequestContextTests: XCTestCase {
    func testActiveLibraryScopeChangeRestartsSearchWithItsCacheVisible() async throws {
        try await assertSearchContinuesAfterScopeChange(replacementFails: false)
    }

    func testReplacementSearchFailureKeepsAnySourceCacheAndReportsNetworkFailure() async throws {
        try await assertSearchContinuesAfterScopeChange(replacementFails: true)
    }

    func testHiddenLibraryDoesNotRestartItsSearch() async throws {
        try await assertSearchContinuesAfterScopeChange(replacementFails: false, change: .hide)
    }

    func testRemovedLibraryDoesNotRestartItsSearch() async throws {
        try await assertSearchContinuesAfterScopeChange(replacementFails: false, change: .remove)
    }

    func testRepeatedScopeChangesKeepTheCurrentCacheAndOtherLibraryWithoutLooping() async throws {
        try await assertSearchContinuesAfterScopeChange(replacementFails: false, change: .twice)
    }

    func testChangingCriteriaCancelsTheSupersededLibraryRequest() async throws {
        let fixture = try Fixture(protocolClass: CancellableSearchURLProtocol.self)
        let container = fixture.container
        let library = fixture.library
        let first = SearchCriteriaMergedKey(libraryIds: [library.id], criteria: fixture.criteria)
        let second = SearchCriteriaMergedKey(libraryIds: [library.id], criteria: .init(
            searchString: "other criteria", sortCriteria: fixture.criteria.sortCriteria, filterCriteriaCategory: [:]
        ))
        let started = expectation(description: "Old criteria metadata is in flight")
        let stopped = expectation(description: "Old criteria transport is canceled")
        let settled = expectation(description: "New criteria settles")
        let oldAttempts = SearchAttempts()
        CancellableSearchURLProtocol.onRequest = { request in
            let url = try XCTUnwrap(request.url)
            if url.path.contains("ajax/search") {
                let query = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems?.first { $0.name == "query" }?.value
                if query == first.criteria.searchString {
                    _ = oldAttempts.next()
                    return try Self.searchResponse(request, bookId: 456)
                }
            } else if url.query?.contains("ids=456") == true {
                started.fulfill()
                return nil
            }
            return try Self.searchResponse(request, bookId: 457)
        }
        CancellableSearchURLProtocol.onStop = { request in
            if request.url?.query?.contains("ids=456") == true { stopped.fulfill() }
        }
        defer {
            CancellableSearchURLProtocol.onRequest = nil
            CancellableSearchURLProtocol.onStop = nil
        }

        let oldObserver = Task {
            let stream = await container.unifiedSearchService.search(key: first, force: true)
            for await _ in stream {}
        }
        defer { oldObserver.cancel() }
        await fulfillment(of: [started], timeout: 10)
        var updated = library
        updated.lastModified = Date(timeIntervalSince1970: 500)
        try publishScope(updated, in: container)
        oldObserver.cancel()

        var final: SearchUpdate?
        let observer = Task {
            let stream = await container.unifiedSearchService.search(key: second, force: true)
            for await update in stream where update.statuses[library.id]?.loading == false {
                final = update
                settled.fulfill()
                return
            }
        }
        defer { observer.cancel() }
        await fulfillment(of: [stopped, settled], timeout: 10)
        XCTAssertEqual(oldAttempts.count, 1)
        XCTAssertEqual(final?.result.books.map(\.id), [457])
        XCTAssertNil(final?.statuses[library.id]?.error)
        XCTAssertTrue(try container.searchCacheRepository.fetchBooks(library: updated, bookIds: [456]).isEmpty)
    }

    private final class CancellableSearchURLProtocol: URLProtocol, @unchecked Sendable {
        static var onRequest: ((URLRequest) throws -> (HTTPURLResponse, Data)?)?
        static var onStop: ((URLRequest) -> Void)?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            do {
                guard let (response, data) = try Self.onRequest?(request) else { return }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {
            Self.onStop?(request)
        }
    }

    private enum ScopeChange { case generation, hide, remove, twice }

    private func assertSearchContinuesAfterScopeChange(
        replacementFails: Bool, change: ScopeChange = .generation
    ) async throws {
        let fixture = try Fixture()
        let container = fixture.container
        let library = fixture.library
        let criteria = fixture.criteria
        let repeated = change == .twice
        let other = TestFixtures.makeLibrary(server: library.server, key: "other", name: "Other")
        if repeated {
            try container.libraryRepository.saveLibrary(other)
            container.libraryManager.calibreLibraries[other.id] = other
        }
        let key = SearchCriteriaMergedKey(libraryIds: repeated ? [library.id, other.id] : [library.id], criteria: criteria)
        try seedSearchCache(library: library, criteria: criteria, container: container)

        let metadataStarted = expectation(description: "Original metadata request is held")
        let replacementStarted = repeated || replacementFails
            ? expectation(description: "Replacement request is held") : nil
        let gate = DispatchSemaphore(value: 0)
        let replacementGate = DispatchSemaphore(value: 0)
        let attempts = SearchAttempts()
        let otherAttempts = SearchAttempts()
        defer {
            gate.signal()
            replacementGate.signal()
            MockURLProtocol.requestHandler = nil
        }
        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            if url.path.hasSuffix("/other") {
                if url.path.contains("ajax/search") { _ = otherAttempts.next() }
                return try Self.searchResponse(request, bookId: 458)
            }
            if url.path.contains("ajax/search") {
                let attempt = attempts.next()
                if replacementFails, attempt > 1 {
                    replacementStarted?.fulfill()
                    guard replacementGate.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
                    let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil))
                    return (response, Data())
                }
                return try Self.searchResponse(request, bookId: attempt == 1 ? 456 : 457)
            }
            if url.query?.contains("ids=456") == true {
                metadataStarted.fulfill()
                guard gate.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
                return try Self.searchResponse(request, bookId: 456)
            }
            if repeated, let replacementStarted, url.query?.contains("ids=457") == true {
                replacementStarted.fulfill()
                guard replacementGate.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
            }
            return try Self.searchResponse(request, bookId: 457)
        }

        let initialCache = expectation(description: "Historical cache visible before the network reply")
        let settled = expectation(description: "Search settles after the library changes")
        let generation = Date(timeIntervalSince1970: 500)
        var final: SearchUpdate?
        var sawReplacementCache = false
        var sawOtherLibrary = false
        let observer = Task {
            let stream = await container.unifiedSearchService.search(key: key, force: true)
            var sawInitialCache = false
            for await update in stream {
                let book = update.result.books.first { $0.library.id == library.id }
                if repeated {
                    let hasOther = update.result.books.contains { $0.library.id == other.id && $0.id == 458 }
                    if sawOtherLibrary { XCTAssertTrue(hasOther, "The other library's result stays visible") }
                    sawOtherLibrary = sawOtherLibrary || hasOther
                }
                if update.statuses[library.id]?.loading == true, book?.id == 42 {
                    if !sawInitialCache {
                        sawInitialCache = true
                        initialCache.fulfill()
                    }
                    if book?.library.lastModified == generation || book?.library.categoryFields["Authors"] == "author_sort" {
                        sawReplacementCache = true
                    }
                }
                if sawInitialCache, update.statuses[library.id]?.loading == false,
                   !update.statuses.values.contains(where: \.loading) {
                    final = update
                    settled.fulfill()
                    return
                }
            }
        }
        defer { observer.cancel() }
        await fulfillment(of: [initialCache, metadataStarted], timeout: 10)
        var updated = library
        switch change {
        case .generation:
            updated.lastModified = generation
            try publishScope(updated, in: container)
        case .hide:
            try container.libraryManager.hideLibrary(libraryId: library.id, serverID: library.server.id)
        case .remove:
            try container.libraryManager.removeLibrary(library: library)
        case .twice:
            updated.categoryFields["Authors"] = "author_sort"
            try publishScope(updated, in: container)
        }
        gate.signal()

        if let replacementStarted {
            await fulfillment(of: [replacementStarted], timeout: 10)
            if repeated {
                updated.lastModified = generation
                try publishScope(updated, in: container)
            } else {
                try seedSearchCache(library: updated, criteria: criteria, container: container, bookId: 43)
            }
            replacementGate.signal()
        }

        await fulfillment(of: [settled], timeout: 10)
        let result = try XCTUnwrap(final)
        XCTAssertTrue(try container.searchCacheRepository.fetchBooks(library: updated, bookIds: [456]).isEmpty)
        if change == .hide || change == .remove {
            XCTAssertEqual(attempts.count, 1)
            XCTAssertEqual(result.result.books, [])
            XCTAssertEqual(result.statuses[library.id]?.error, .superseded)
            return
        }
        XCTAssertEqual(attempts.count, 2)
        XCTAssertTrue(sawReplacementCache, "The replacement should first publish the cache mapped to its current scope")
        if repeated {
            XCTAssertEqual(otherAttempts.count, 1)
            XCTAssertEqual(Set(result.result.books.map(\.id)), [42, 458])
            XCTAssertEqual(result.result.books.first { $0.library.id == library.id }?.library.lastModified, generation)
            XCTAssertTrue(try container.searchCacheRepository.fetchBooks(library: updated, bookIds: [457]).isEmpty)
            XCTAssertEqual(result.statuses[library.id]?.error, .superseded)
            XCTAssertTrue(result.statuses[library.id]?.fromCache == true)
            return
        }
        XCTAssertEqual(result.result.books.map(\.id), replacementFails ? [43] : [457])
        XCTAssertEqual(result.result.books.first?.library.lastModified, generation)
        if replacementFails {
            guard case .network? = result.statuses[library.id]?.failure else { return XCTFail("Expected a network failure") }
            XCTAssertTrue(result.statuses[library.id]?.fromCache == true)
        } else {
            XCTAssertNil(result.statuses[library.id]?.error)
        }
    }

    private func publishScope(_ library: CalibreLibrary, in container: AppContainer) throws {
        try container.libraryRepository.saveLibrary(library)
        container.libraryManager.calibreLibraries[library.id] = library
    }

    private func seedSearchCache(
        library: CalibreLibrary, criteria: SearchCriteria, container: AppContainer, bookId: Int32 = 42
    ) throws {
        let historical = CalibreBook(id: bookId, library: library)
        try container.searchCacheRepository.saveLibrarySourceResult(
            libraryId: library.id, search: criteria.searchString, sortBy: criteria.sortCriteria.by,
            sortAsc: criteria.sortCriteria.ascending, filters: criteria.filterCriteriaCategory,
            sourceUrl: library.server.publicUrl,
            result: .init(generation: library.lastModified, totalNumber: 1, bookIds: [bookId], books: [historical])
        )
    }

    private final class SearchAttempts: @unchecked Sendable {
        private let lock = NSLock()
        private var attempts = 0
        var count: Int { lock.withLock { attempts } }

        func next() -> Int {
            lock.withLock {
                attempts += 1
                return attempts
            }
        }
    }

    func testDelayedSearchMetadataDoesNotWriteIntoAReplacementDatabase() async throws {
        let fixture = try Fixture()
        let container = fixture.container
        let library = fixture.library
        let oldRealm = try XCTUnwrap(container.databaseService.realm)
        let oldStore = RealmSearchCacheStore(config: oldRealm.configuration, container: container)
        let requested = expectation(description: "Metadata request entered transport")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal(); MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("ajax/books") == true {
                requested.fulfill()
                guard gate.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
            }
            return try Self.searchResponse(request)
        }

        let task = Task {
            try await container.librarySearchService.searchAndFetchMetadata(
                library: library, criteria: fixture.criteria, limit: 10, force: true
            )
        }
        defer { task.cancel() }
        await fulfillment(of: [requested], timeout: 10)

        let replacement = Realm.Configuration(inMemoryIdentifier: UUID().uuidString, schemaVersion: DatabaseSchema.version)
        try container.databaseService.openMainRealm(conf: replacement)
        try container.serverRepository.saveServer(library.server)
        try container.libraryRepository.saveLibrary(library)
        var sentinel = CalibreBook(id: 456, library: library)
        sentinel.title = "Replacement database"
        container.bookRepository.saveBook(sentinel)
        gate.signal()

        do {
            _ = try await task.value
            XCTFail("The replaced database's request returned a result")
        } catch {
            XCTAssertEqual(error as? CacheContextError, .superseded)
        }
        XCTAssertTrue(try oldStore.fetchBooks(library: library, bookIds: [456]).isEmpty)
        withExtendedLifetime(oldRealm) {}
        XCTAssertEqual(try container.searchCacheRepository.fetchBooks(library: library, bookIds: [456])[456]?.title,
                       "Replacement database")

        MockURLProtocol.requestHandler = Self.searchResponse
        let current = try await container.librarySearchService.searchAndFetchMetadata(
            library: library, criteria: fixture.criteria, limit: 10, force: true, forceMetadataRefresh: true
        )
        XCTAssertEqual(current.sources.values.first?.books.first?.title, "Network Book")
    }

    func testSearchKeepsItsChosenAddressAcrossReachabilityChanges() async throws {
        let fixture = try Fixture()
        let container = fixture.container
        let library = fixture.library
        let requested = expectation(description: "Search request entered transport")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal(); MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("ajax/search") == true {
                requested.fulfill()
                guard gate.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
            } else if request.url?.path.contains("ajax/books") == true {
                XCTAssertEqual(request.url?.port, 19749, "Metadata must use the same URL as search")
            }
            return try Self.searchResponse(request)
        }
        let task = Task {
            try await container.librarySearchService.searchAndFetchMetadata(
                library: library, criteria: fixture.criteria, limit: 10, force: true
            )
        }
        defer { task.cancel() }
        await fulfillment(of: [requested], timeout: 10)
        try fixture.publishReachability(isPublic: true)
        gate.signal()

        let result = try await task.value
        XCTAssertEqual(result.sources[library.server.baseUrl]?.books.first?.title, "Network Book")
        XCTAssertNil(result.sources[library.server.publicUrl])
    }

    func testSearchMetadataDoesNotReinsertABookDeletedWhileAwaitingTheAnswer() async throws {
        let fixture = try Fixture()
        let container = fixture.container
        let library = fixture.library
        let book = CalibreBook(id: 456, library: library)
        container.bookRepository.saveBook(book)
        let requested = expectation(description: "Metadata for the existing book entered transport")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal(); MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("ajax/books") == true {
                requested.fulfill()
                guard gate.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
            }
            return try Self.searchResponse(request)
        }
        let task = Task {
            try await container.librarySearchService.searchAndFetchMetadata(
                library: library, criteria: fixture.criteria, limit: 10, force: true, forceMetadataRefresh: true
            )
        }
        defer { task.cancel() }
        await fulfillment(of: [requested], timeout: 10)
        container.bookRepository.deleteBook(id: book.inShelfId)
        gate.signal()

        let result = try await task.value
        XCTAssertEqual(result.sources[library.server.baseUrl]?.bookIds, [book.id])
        XCTAssertEqual(result.sources[library.server.baseUrl]?.books, [])
        XCTAssertTrue(try container.searchCacheRepository.fetchBooks(library: library, bookIds: [book.id]).isEmpty)
    }

    func testCategoryAnswerFromBeforeHideAndRestoreIsDiscarded() async throws {
        let fixture = try Fixture()
        let container = fixture.container
        let library = fixture.library
        let category = CalibreLibraryCategory(name: "Authors", url: "/ajax/category/authors", icon: "", is_category: true)
        let requested = expectation(description: "Category request entered transport")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal(); MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { request in
            requested.fulfill()
            guard gate.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
            return try Self.categoryResponse(request)
        }
        let task = Task {
            try await container.libraryCategoryService.fetchAndCacheCategory(library: library, category: category)
        }
        defer { task.cancel() }
        await fulfillment(of: [requested], timeout: 10)
        try container.libraryManager.hideLibrary(libraryId: library.id, serverID: library.server.id)
        try container.libraryManager.restoreLibrary(libraryId: library.id, serverID: library.server.id)
        let restored = try XCTUnwrap(container.getLibraries()[library.id])
        XCTAssertTrue(library.hasSameCacheScope(as: restored), "The lifetime must detect a hide and restore even when the values match")
        gate.signal()

        do {
            _ = try await task.value
            XCTFail("A category request from before hide and restore committed")
        } catch {
            XCTAssertEqual(error as? CacheContextError, .superseded)
        }
        XCTAssertNil(try container.categoryCacheRepository.fetchLibraryCategoryResult(libraryId: library.id, categoryName: category.name))

        MockURLProtocol.requestHandler = Self.categoryResponse
        let current = try await container.libraryCategoryService.fetchAndCacheCategory(library: restored, category: category)
        XCTAssertEqual(current.items.map(\.name), ["Author"])
    }

    func testLateMetadataCannotReplaceCacheAfterTheConnectionChanges() async throws {
        let fixture = try Fixture()
        let container = fixture.container
        let library = fixture.library
        let criteria = fixture.criteria
        var historical = CalibreBook(id: 42, library: library)
        historical.title = "Historical result"
        try container.searchCacheRepository.saveLibrarySourceResult(
            libraryId: library.id, search: criteria.searchString, sortBy: .Title, sortAsc: true,
            filters: [:], sourceUrl: library.server.baseUrl,
            result: .init(totalNumber: 1, bookIds: [42], books: [historical])
        )

        let requested = expectation(description: "Metadata for the old connection entered transport")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal(); MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("ajax/library-info") == true {
                let url = try XCTUnwrap(request.url)
                let unavailable = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil))
                return (unavailable, Data())
            }
            if request.url?.path.contains("ajax/books") == true {
                requested.fulfill()
                guard gate.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
            }
            return try Self.searchResponse(request)
        }
        let task = Task {
            try await container.librarySearchService.searchAndFetchMetadata(library: library, criteria: criteria, limit: 10, force: true)
        }
        defer { task.cancel() }
        await fulfillment(of: [requested], timeout: 10)

        var replacement = library.server
        replacement.baseUrl = "http://localhost:19751"
        replacement.hasPublicUrl = false
        let probeSessionConfig = URLSessionConfiguration.ephemeral
        probeSessionConfig.protocolClasses = [MockURLProtocol.self]
        container.calibreServerService.metadataSessions[
            CalibreServerURLSessionKey(server: replacement, timeout: 10, qos: .default)
        ] = URLSession(configuration: probeSessionConfig)
        try container.serverManager.updateConnection(replacement, ifCurrent: library.server)
        gate.signal()

        do {
            _ = try await task.value
            XCTFail("A response from the old connection committed")
        } catch {
            XCTAssertEqual(error as? CacheContextError, .superseded)
        }
        let current = try XCTUnwrap(container.getLibraries()[library.id])
        XCTAssertTrue(try container.searchCacheRepository.fetchBooks(library: current, bookIds: [456]).isEmpty)
        let cached = try container.searchCacheRepository.fetchLibraryCachedResult(
            library: current, search: criteria.searchString, sortBy: .Title, sortAsc: true, filters: [:]
        )
        XCTAssertEqual(cached?.sources[library.server.baseUrl]?.books.first?.title, "Historical result")
        XCTAssertEqual(cached?.sources[library.server.baseUrl]?.books.first?.library.server.baseUrl, replacement.baseUrl)
    }

    func testCategoryObserverAndPreparedPageStayInTheirOriginalDatabase() async throws {
        let fixture = try Fixture()
        let container = fixture.container
        let libraryId = fixture.library.id
        let oldRealm = try XCTUnwrap(container.databaseService.realm)
        let oldStore = RealmSearchCacheStore(config: oldRealm.configuration, container: container)
        let bound = try container.categoryCacheRepository.snapshot()
        func save(_ title: String, generation: TimeInterval, to cache: CategoryCacheRepository) throws {
            let item = LibraryCategoryItem(name: title, averageRating: 0, count: 1, url: title)
            try cache.saveLibraryCategoryResult(libraryId: libraryId, categoryName: "Authors", result: .init(
                libraryId: libraryId, categoryName: "Authors", items: [item],
                generation: Date(timeIntervalSince1970: generation), totalNumber: 1
            ))
        }
        try save("Old", generation: 1, to: oldStore)
        let query = try await container.unifiedCategoryService.prepareQuery(libraryIds: [])
        let initial = expectation(description: "Original database observation registered")
        let finished = expectation(description: "Old database notifications no longer delivered")
        let observer = Task {
            var updates = bound.observeCategorySummaries().makeAsyncIterator()
            let first = await updates.next()
            XCTAssertEqual(first?.first?.categoryName, "Authors")
            initial.fulfill()
            let afterSwitch = await updates.next()
            XCTAssertNil(afterSwitch)
            finished.fulfill()
        }
        defer { observer.cancel() }
        await fulfillment(of: [initial], timeout: 5)

        let replacement = Realm.Configuration(inMemoryIdentifier: UUID().uuidString, schemaVersion: DatabaseSchema.version)
        try container.databaseService.openMainRealm(conf: replacement)
        try save("New", generation: 2, to: container.categoryCacheRepository)
        try save("Late", generation: 3, to: oldStore)
        await fulfillment(of: [finished], timeout: 5)
        withExtendedLifetime(oldRealm) {}

        do {
            _ = try await container.unifiedCategoryService.mergeCategoryPage(
                categoryName: "Authors", searchString: "", query: query, offset: 0, limit: 10
            )
            XCTFail("A prepared category page followed the database switch")
        } catch {
            XCTAssertEqual(error as? CacheContextError, .superseded)
        }
        let fresh = try await container.unifiedCategoryService.mergeCategoryPage(
            categoryName: "Authors", searchString: "", libraryIds: [libraryId], offset: 0, limit: 10
        )
        XCTAssertEqual(fresh.items.map(\.name), ["New"])
    }

    private struct Fixture {
        let container: AppContainer
        let library: CalibreLibrary
        let criteria = SearchCriteria(searchString: "story", sortCriteria: .init(by: .Title, ascending: true),
                                      filterCriteriaCategory: [:])

        @MainActor
        init(protocolClass: AnyClass = MockURLProtocol.self) throws {
            container = MockAppContainerFactory.makeContainer()
            let server = TestFixtures.makeServer(baseUrl: "http://localhost:19749", hasPublicUrl: true,
                                                 publicUrl: "http://localhost:19750")
            library = TestFixtures.makeLibrary(server: server, key: "books", name: "Books")
            try container.serverManager.addServer(server: server, libraries: [library])
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [protocolClass]
            let session = URLSession(configuration: configuration)
            for qos in [DispatchQoS.QoSClass.default, .background] {
                container.calibreServerService.metadataSessions[
                    CalibreServerURLSessionKey(server: server, timeout: 600, qos: qos)
                ] = session
            }
            try publishReachability(isPublic: false)
        }

        @MainActor
        func publishReachability(isPublic: Bool) throws {
            let server = library.server
            let url = try XCTUnwrap(URL(string: isPublic ? server.publicUrl : server.baseUrl))
            let request = CalibreProbeServerRequest(server: server, isPublic: isPublic,
                                                   updateLibrary: false, autoUpdateOnly: true)
            container.calibreServerInfoStaging = [
                request.id: CalibreServerInfo(server: server, isPublic: isPublic, url: url, reachable: true,
                                              probing: false, errorMsg: "", defaultLibrary: library.key,
                                              libraryMap: [library.key: library.name], request: request)
            ]
        }
    }

    nonisolated private static func searchResponse(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        try searchResponse(request, bookId: 456)
    }

    nonisolated private static func searchResponse(_ request: URLRequest, bookId: Int32) throws -> (HTTPURLResponse, Data) {
        let url = try XCTUnwrap(request.url)
        if url.path.contains("ajax/search") {
            return try jsonResponse(url: url, body: #"{"total_num":1,"sort_order":"asc","num_books_without_search":1,"offset":0,"num":1,"sort":"title","base_url":"","library_id":"books","book_ids":[\#(bookId)],"vl":""}"#)
        }
        if url.path.contains("ajax/books") {
            var book = CalibreBookEntry()
            book.title = "Network Book"
            book.last_modified = "2026-01-01T00:00:00+00:00"
            let data = try JSONEncoder().encode([bookId.description: book])
            return try jsonResponse(url: url, body: String(decoding: data, as: UTF8.self))
        }
        throw URLError(.unsupportedURL)
    }

    nonisolated private static func categoryResponse(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        try jsonResponse(url: XCTUnwrap(request.url), body: #"{"category_name":"Authors","base_url":"","total_num":1,"offset":0,"num":1,"sort":"name","sort_order":"asc","items":[{"name":"Author","average_rating":0,"count":1,"url":"author","has_children":false}]}"#)
    }

    nonisolated private static func jsonResponse(url: URL, body: String) throws -> (HTTPURLResponse, Data) {
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                     headerFields: ["Content-Type": "application/json"]))
        return (response, Data(body.utf8))
    }
}
