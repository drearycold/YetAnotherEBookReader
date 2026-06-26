//
//  UnifiedSearchIntegrationTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-11.
//

import XCTest
import Combine
import RealmSwift
@testable import YetAnotherEBookReader

func debugLog(_ message: String) {
    print("[DEBUG_LOG] \(message)")
}

class UnifiedSearchIntegrationTests: XCTestCase {

    var modelData: ModelData!
    var unifiedSearchService: UnifiedSearchService!
    var mockServer: CalibreServer!
    var mockLibrary: CalibreLibrary!
    var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        try super.setUpWithError()
        cancellables = Set<AnyCancellable>()

        // Setup logger

        debugLog("setUpWithError started")

        // Setup in-memory Realm for testing
        let config = Realm.Configuration(inMemoryIdentifier: "UnifiedSearchIntegrationTests-\(UUID().uuidString)")
        modelData = ModelData(mock: true)
        modelData.realmConf = config

        // Setup DatabaseService singleton
        DatabaseService.shared.setup(conf: config)

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

        // Inject library into ModelData using library.id as the key
        modelData.calibreLibraries = [mockLibrary.id: mockLibrary]

        // Mock server reachability staging
        let probeRequest = CalibreProbeServerRequest(
            server: mockServer,
            isPublic: false,
            updateLibrary: false,
            autoUpdateOnly: false,
            incremental: false
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
        modelData.calibreServerInfoStaging = [mockServer.uuid.uuidString: serverInfo]

        // Setup ephemeral URLSession with MockURLProtocol
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)

        // Create test services and pre-populate metadataSessions
        let logger = CalibreActivityLogger(realmConf: config)
        let service = CalibreServerService(
            logger: logger,
            config: modelData,
            database: DatabaseService.shared
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

        let cacheRepository = RealmSearchCacheStore(config: config, modelData: modelData)
        let librarySearchService = LibrarySearchService(service: service, repository: cacheRepository)
        let unifiedSearchService = UnifiedSearchService(
            repository: cacheRepository,
            librarySearchService: librarySearchService,
            libraryProvider: modelData
        )

        modelData.calibreServerService = service
        modelData.searchCacheRepository = cacheRepository
        modelData.librarySearchService = librarySearchService
        modelData.unifiedSearchService = unifiedSearchService
        modelData.categoryCacheRepository = cacheRepository
        modelData.libraryCategoryService = LibraryCategoryService(service: service, repository: cacheRepository)
        modelData.unifiedCategoryService = UnifiedCategoryService(repository: cacheRepository, libraryProvider: modelData)

        self.unifiedSearchService = unifiedSearchService
        debugLog("setUpWithError finished")
    }

    override func tearDownWithError() throws {
        cancellables = nil
        unifiedSearchService = nil
        modelData = nil
        mockServer = nil
        mockLibrary = nil
        try super.tearDownWithError()
    }

    func testUnifiedSearchEndToEndWithMockServer() throws {
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

        debugLog("subscribing to publisher")
        // Observe search manager publisher
        unifiedSearchService.publisher(for: key)
            .sink { result in
                debugLog("publisher emitted result with \(result.books.count) books")
                if result.books.count > 0 {
                    finalResult = result
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        debugLog("waiting for expectations")
        // Verify wait
        waitForExpectations(timeout: 5.0)

        debugLog("test finished. result: \(String(describing: finalResult))")

        XCTAssertNotNil(finalResult)
        XCTAssertEqual(finalResult?.books.count, 1)
        XCTAssertEqual(finalResult?.books.first?.title, "Quick Start Guide")
        XCTAssertEqual(finalResult?.books.first?.authors.first, "John Schember")
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
