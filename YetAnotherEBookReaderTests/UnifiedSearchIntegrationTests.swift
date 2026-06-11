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
    var searchManager: CalibreLibrarySearchManager!
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
        
        // Create search manager and pre-populate metadataSessions
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
        
        searchManager = CalibreLibrarySearchManager(service: service, modelData: modelData)
        modelData.librarySearchManager = searchManager
        debugLog("setUpWithError finished")
    }
    
    override func tearDownWithError() throws {
        cancellables = nil
        searchManager = nil
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
            "base_url": "",
            "library_id": "lib1",
            "book_ids": [123],
            "vl": ""
        }
        """
        
        // Mock metadata response JSON
        let metadataJSON = """
        {
            "123": {
                "title": "Integration Test Book",
                "authors": ["Test Author"],
                "timestamp": "2026-06-11T02:00:00Z",
                "pubdate": "2026-06-11T02:00:00Z",
                "last_modified": "2026-06-11T02:00:00Z",
                "uuid": "test-book-uuid-123",
                "formats": [],
                "format_metadata": {},
                "user_metadata": {},
                "tags": [],
                "author_sort": "Test Author",
                "title_sort": "Integration Test Book",
                "thumbnail": "",
                "user_categories": {},
                "cover": "",
                "application_id": 123,
                "author_sort_map": {},
                "identifiers": {},
                "languages": ["en"],
                "rating": 0.0,
                "category_urls": {}
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
        searchManager.unifiedSearchManager.publisher(for: key)
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
        XCTAssertEqual(finalResult?.books.first?.title, "Integration Test Book")
        XCTAssertEqual(finalResult?.books.first?.authors.first, "Test Author")
    }
}

// MockURLProtocol implementation for intercepting requests
class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    
    override class func canInit(with request: URLRequest) -> Bool {
        debugLog("MockURLProtocol.canInit: \(request.url?.absoluteString ?? "nil")")
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        debugLog("MockURLProtocol.startLoading: \(request.url?.absoluteString ?? "nil")")
        guard let handler = MockURLProtocol.requestHandler else {
            return
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {}
}