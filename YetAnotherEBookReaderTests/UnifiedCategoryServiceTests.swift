//
//  UnifiedCategoryServiceTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-12.
//

import XCTest
import Combine
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
class UnifiedCategoryServiceTests: XCTestCase {
    
    var repository: MockCategoryCacheRepository!
    var libraryProvider: MockLibraryProvider!
    var serverService: CalibreServerService!
    var libraryCategoryService: LibraryCategoryService!
    var unifiedCategoryService: UnifiedCategoryService!
    var mergeService: UnifiedCategoryMergeService!
    
    var mockLibrary1: CalibreLibrary!
    var mockLibrary2: CalibreLibrary!
    
    override func setUp() async throws {
        try await super.setUp()
        
        let config = Realm.Configuration(inMemoryIdentifier: "UnifiedCategoryServiceTests-\(UUID().uuidString)")
        DatabaseService.shared.setup(conf: config)
        let modelData = ModelData(mock: true)
        modelData.realmConf = config
        
        let server1 = CalibreServer(uuid: UUID(), name: "Server1", baseUrl: "http://localhost/1", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        mockLibrary1 = CalibreLibrary(server: server1, key: "lib1", name: "Library 1")
        
        let server2 = CalibreServer(uuid: UUID(), name: "Server2", baseUrl: "http://localhost/2", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        mockLibrary2 = CalibreLibrary(server: server2, key: "lib2", name: "Library 2")
        
        repository = MockCategoryCacheRepository()
        libraryProvider = MockLibraryProvider()
        libraryProvider.libraries = [
            mockLibrary1.id: mockLibrary1,
            mockLibrary2.id: mockLibrary2
        ]
        
        // Setup reachability staging in modelData
        let probeRequest1 = CalibreProbeServerRequest(server: server1, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        let info1 = CalibreServerInfo(server: server1, isPublic: false, url: URL(string: "http://localhost/1")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: mockLibrary1.id, libraryMap: [mockLibrary1.id: "Library 1"], request: probeRequest1)
        
        let probeRequest2 = CalibreProbeServerRequest(server: server2, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        let info2 = CalibreServerInfo(server: server2, isPublic: false, url: URL(string: "http://localhost/2")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: mockLibrary2.id, libraryMap: [mockLibrary2.id: "Library 2"], request: probeRequest2)
        
        modelData.calibreServerInfoStaging = [
            server1.uuid.uuidString: info1,
            server2.uuid.uuidString: info2
        ]
        
        serverService = modelData.calibreServerService
        mergeService = UnifiedCategoryMergeService()
        
        libraryCategoryService = LibraryCategoryService(service: serverService, repository: repository)
        unifiedCategoryService = UnifiedCategoryService(mergeService: mergeService, repository: repository, libraryProvider: libraryProvider)
        
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
    }
    
    override func tearDown() async throws {
        repository = nil
        libraryProvider = nil
        serverService = nil
        libraryCategoryService = nil
        unifiedCategoryService = nil
        mergeService = nil
        mockLibrary1 = nil
        mockLibrary2 = nil
        try await super.tearDown()
    }
    
    // MARK: - Merge Service Tests
    
    func testMergeEmptyResults() {
        let results: [LibraryCategoryResult] = []
        let merged = mergeService.merge(categoryName: "Authors", searchString: "", results: results)
        
        XCTAssertEqual(merged.categoryName, "Authors")
        XCTAssertEqual(merged.search, "")
        XCTAssertEqual(merged.itemsCount, 0)
        XCTAssertEqual(merged.totalNumber, 0)
        XCTAssertTrue(merged.items.isEmpty)
    }
    
    func testMergeAndAggregateMultipleLibraries() {
        let item1 = LibraryCategoryItem(name: "Author A", averageRating: 4.0, count: 5, url: "urlA1")
        let item2 = LibraryCategoryItem(name: "Author B", averageRating: 5.0, count: 2, url: "urlB1")
        let result1 = LibraryCategoryResult(libraryId: "lib1", categoryName: "Authors", items: [item1, item2], generation: Date(), totalNumber: 2)
        
        let item3 = LibraryCategoryItem(name: "Author A", averageRating: 2.0, count: 5, url: "urlA2")
        let item4 = LibraryCategoryItem(name: "Author C", averageRating: 3.0, count: 3, url: "urlC2")
        let result2 = LibraryCategoryResult(libraryId: "lib2", categoryName: "Authors", items: [item3, item4], generation: Date(), totalNumber: 2)
        
        let merged = mergeService.merge(categoryName: "Authors", searchString: "", results: [result1, result2])
        
        XCTAssertEqual(merged.itemsCount, 3)
        // Total books: 5 (Author A lib1) + 2 (Author B lib1) + 5 (Author A lib2) + 3 (Author C lib2) = 15
        XCTAssertEqual(merged.totalNumber, 15)
        
        // Items must be sorted alphabetically: Author A, Author B, Author C
        XCTAssertEqual(merged.items[0].name, "Author A")
        XCTAssertEqual(merged.items[1].name, "Author B")
        XCTAssertEqual(merged.items[2].name, "Author C")
        
        // Author A count: 5 + 5 = 10. Rating: (4.0*5 + 2.0*5)/10 = 3.0
        XCTAssertEqual(merged.items[0].count, 10)
        XCTAssertEqual(merged.items[0].averageRating, 3.0)
        XCTAssertEqual(merged.items[0].libraryItems.count, 2)
        XCTAssertEqual(merged.items[0].libraryItems["lib1"]?.url, "urlA1")
        XCTAssertEqual(merged.items[0].libraryItems["lib2"]?.url, "urlA2")
        
        // Author B count: 2. Rating: 5.0
        XCTAssertEqual(merged.items[1].count, 2)
        XCTAssertEqual(merged.items[1].averageRating, 5.0)
        
        // Author C count: 3. Rating: 3.0
        XCTAssertEqual(merged.items[2].count, 3)
        XCTAssertEqual(merged.items[2].averageRating, 3.0)
    }
    
    func testMergeWithFilter() {
        let item1 = LibraryCategoryItem(name: "Stephen King", averageRating: 4.5, count: 10, url: "sk")
        let item2 = LibraryCategoryItem(name: "J.K. Rowling", averageRating: 4.8, count: 7, url: "jkr")
        let result = LibraryCategoryResult(libraryId: "lib1", categoryName: "Authors", items: [item1, item2], generation: Date(), totalNumber: 2)
        
        let merged = mergeService.merge(categoryName: "Authors", searchString: "rowling", results: [result])
        
        XCTAssertEqual(merged.itemsCount, 1)
        XCTAssertEqual(merged.items[0].name, "J.K. Rowling")
    }
    
    // MARK: - Fetch and Cache Concurrency Tests
    
    func testFetchAndCacheCategorySuccess() async throws {
        let category = CalibreLibraryCategory(name: "Authors", url: "http://localhost/1/ajax/category/Authors", icon: "user", is_category: true)
        
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            
            let responseJSON = """
            {
                "category_name": "Authors",
                "base_url": "/ajax/category/Authors",
                "total_num": 2,
                "offset": 0,
                "num": 2,
                "sort": "name",
                "sort_order": "asc",
                "items": [
                    {
                        "name": "Author X",
                        "average_rating": 4.5,
                        "count": 3,
                        "url": "urlX",
                        "has_children": false
                    },
                    {
                        "name": "Author Y",
                        "average_rating": 3.8,
                        "count": 1,
                        "url": "urlY",
                        "has_children": false
                    }
                ]
            }
            """
            return (response, responseJSON.data(using: .utf8)!)
        }
        
        let result = try await libraryCategoryService.fetchAndCacheCategory(library: mockLibrary1, category: category)
        
        XCTAssertEqual(result.libraryId, mockLibrary1.id)
        XCTAssertEqual(result.categoryName, "Authors")
        XCTAssertEqual(result.totalNumber, 2)
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items[0].name, "Author X")
        XCTAssertEqual(result.items[1].name, "Author Y")
        
        // Check repository cache
        let cached = try repository.fetchLibraryCategoryResult(libraryId: mockLibrary1.id, categoryName: "Authors")
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.totalNumber, 2)
    }
    
    func testFetchAndCacheCategoryPagination() async throws {
        let category = CalibreLibraryCategory(name: "Authors", url: "http://localhost/1/ajax/category/Authors", icon: "user", is_category: true)
        
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url,
                  let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  let offsetStr = queryItems.first(where: { $0.name == "offset" })?.value,
                  let offset = Int(offsetStr) else {
                throw URLError(.badURL)
            }
            
            requestCount += 1
            
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            
            let responseJSON: String
            if offset == 0 {
                responseJSON = """
                {
                    "category_name": "Authors",
                    "base_url": "/ajax/category/Authors",
                    "total_num": 3,
                    "offset": 0,
                    "num": 2,
                    "sort": "name",
                    "sort_order": "asc",
                    "items": [
                        { "name": "Author 1", "average_rating": 4.0, "count": 1, "url": "url1", "has_children": false },
                        { "name": "Author 2", "average_rating": 4.1, "count": 2, "url": "url2", "has_children": false }
                    ]
                }
                """
            } else {
                responseJSON = """
                {
                    "category_name": "Authors",
                    "base_url": "/ajax/category/Authors",
                    "total_num": 3,
                    "offset": 2,
                    "num": 1,
                    "sort": "name",
                    "sort_order": "asc",
                    "items": [
                        { "name": "Author 3", "average_rating": 4.2, "count": 3, "url": "url3", "has_children": false }
                    ]
                }
                """
            }
            
            return (response, responseJSON.data(using: .utf8)!)
        }
        
        let result = try await libraryCategoryService.fetchAndCacheCategory(library: mockLibrary1, category: category)
        
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(result.items.count, 3)
        XCTAssertEqual(result.totalNumber, 3)
        XCTAssertEqual(result.items[0].name, "Author 1")
        XCTAssertEqual(result.items[1].name, "Author 2")
        XCTAssertEqual(result.items[2].name, "Author 3")
    }
    
    // MARK: - Unified Category Service Tests
    
    func testUnifiedCategoryServiceMerge() async throws {
        // Seed cache directly using correct library IDs
        let item1 = LibraryCategoryItem(name: "Tag A", averageRating: 0.0, count: 5, url: "tagA")
        let result1 = LibraryCategoryResult(libraryId: mockLibrary1.id, categoryName: "Tags", items: [item1], generation: Date(), totalNumber: 1)
        try repository.saveLibraryCategoryResult(libraryId: mockLibrary1.id, categoryName: "Tags", result: result1)
        
        let item2 = LibraryCategoryItem(name: "Tag A", averageRating: 0.0, count: 10, url: "tagA")
        let item3 = LibraryCategoryItem(name: "Tag B", averageRating: 0.0, count: 2, url: "tagB")
        let result2 = LibraryCategoryResult(libraryId: mockLibrary2.id, categoryName: "Tags", items: [item2, item3], generation: Date(), totalNumber: 2)
        try repository.saveLibraryCategoryResult(libraryId: mockLibrary2.id, categoryName: "Tags", result: result2)
        
        let merged = await unifiedCategoryService.mergeCategory(categoryName: "Tags", searchString: "")
        
        XCTAssertEqual(merged.itemsCount, 2)
        XCTAssertEqual(merged.items[0].name, "Tag A")
        XCTAssertEqual(merged.items[0].count, 15)
        XCTAssertEqual(merged.items[1].name, "Tag B")
        XCTAssertEqual(merged.items[1].count, 2)
    }
}

// MARK: - Mocking Classes

class MockCategoryCacheRepository: CategoryCacheRepository {
    var cache: [String: LibraryCategoryResult] = [:]
    
    func fetchLibraryCategoryResult(libraryId: String, categoryName: String) throws -> LibraryCategoryResult? {
        return cache["\(libraryId)-\(categoryName)"]
    }
    
    func saveLibraryCategoryResult(libraryId: String, categoryName: String, result: LibraryCategoryResult) throws {
        cache["\(libraryId)-\(categoryName)"] = result
    }
    
    func fetchCategorySummaries() throws -> [CategoryCacheSummary] {
        var summariesByName: [String: (itemsCount: Int, totalNumber: Int)] = [:]
        for result in cache.values {
            let name = result.categoryName
            let current = summariesByName[name] ?? (0, 0)
            summariesByName[name] = (
                current.itemsCount + result.items.count,
                current.totalNumber + result.totalNumber
            )
        }
        return summariesByName.map { name, stats in
            CategoryCacheSummary(
                categoryName: name,
                itemsCount: stats.itemsCount,
                totalNumber: stats.totalNumber
            )
        }.sorted { $0.categoryName < $1.categoryName }
    }
    
    func invalidateCategoryCache(libraryId: String, categoryName: String) throws {
        if let result = cache["\(libraryId)-\(categoryName)"] {
            let staleResult = LibraryCategoryResult(
                libraryId: result.libraryId,
                categoryName: result.categoryName,
                items: result.items,
                generation: Date(timeIntervalSince1970: 0),
                totalNumber: result.totalNumber
            )
            cache["\(libraryId)-\(categoryName)"] = staleResult
        }
    }
}
