//
//  UnifiedCategoryServiceTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-12.
//

import XCTest
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
    var container: AppContainer!

    var mockLibrary1: CalibreLibrary!
    var mockLibrary2: CalibreLibrary!
    override func setUp() async throws {
        try await super.setUp()

        container = MockAppContainerFactory.makeContainer(testName: "UnifiedCategoryServiceTests")

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

        // Setup reachability staging in container
        let probeRequest1 = CalibreProbeServerRequest(server: server1, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        let info1 = CalibreServerInfo(server: server1, isPublic: false, url: URL(string: "http://localhost/1")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: mockLibrary1.id, libraryMap: [mockLibrary1.id: "Library 1"], request: probeRequest1)

        let probeRequest2 = CalibreProbeServerRequest(server: server2, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        let info2 = CalibreServerInfo(server: server2, isPublic: false, url: URL(string: "http://localhost/2")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: mockLibrary2.id, libraryMap: [mockLibrary2.id: "Library 2"], request: probeRequest2)

        container.calibreServerInfoStaging = [
            server1.uuid.uuidString: info1,
            server2.uuid.uuidString: info2
        ]

        serverService = container.calibreServerService
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

    func testUnifiedCategoryServiceMergeCanScopeToRequestedLibraries() async throws {
        let result1 = LibraryCategoryResult(
            libraryId: mockLibrary1.id,
            categoryName: "Tags",
            items: [
                LibraryCategoryItem(name: "Shared", averageRating: 0.0, count: 5, url: "tag-shared-lib1"),
                LibraryCategoryItem(name: "Lib One Only", averageRating: 0.0, count: 1, url: "tag-one")
            ],
            generation: Date(),
            totalNumber: 2
        )
        try repository.saveLibraryCategoryResult(libraryId: mockLibrary1.id, categoryName: "Tags", result: result1)

        let result2 = LibraryCategoryResult(
            libraryId: mockLibrary2.id,
            categoryName: "Tags",
            items: [
                LibraryCategoryItem(name: "Shared", averageRating: 0.0, count: 10, url: "tag-shared-lib2"),
                LibraryCategoryItem(name: "Lib Two Only", averageRating: 0.0, count: 2, url: "tag-two")
            ],
            generation: Date(),
            totalNumber: 2
        )
        try repository.saveLibraryCategoryResult(libraryId: mockLibrary2.id, categoryName: "Tags", result: result2)

        let merged = await unifiedCategoryService.mergeCategory(
            categoryName: "Tags",
            searchString: "",
            libraryIds: [mockLibrary1.id]
        )

        XCTAssertEqual(merged.items.map(\.name), ["Lib One Only", "Shared"])
        XCTAssertEqual(merged.items.first { $0.name == "Shared" }?.count, 5)
        XCTAssertNil(merged.items.first { $0.name == "Lib Two Only" })
    }

    func testUnifiedCategoryServiceMergeCategoryPageAggregatesAndPages() async throws {
        try repository.saveLibraryCategoryResult(
            libraryId: mockLibrary1.id,
            categoryName: "Authors",
            result: LibraryCategoryResult(
                libraryId: mockLibrary1.id,
                categoryName: "Authors",
                items: [
                    LibraryCategoryItem(name: "Author A", averageRating: 4.0, count: 2, url: "a-lib1"),
                    LibraryCategoryItem(name: "Author B", averageRating: 2.0, count: 1, url: "b-lib1")
                ],
                generation: Date(),
                totalNumber: 3
            )
        )
        try repository.saveLibraryCategoryResult(
            libraryId: mockLibrary2.id,
            categoryName: "Authors",
            result: LibraryCategoryResult(
                libraryId: mockLibrary2.id,
                categoryName: "Authors",
                items: [
                    LibraryCategoryItem(name: "Author A", averageRating: 2.0, count: 2, url: "a-lib2"),
                    LibraryCategoryItem(name: "Author C", averageRating: 5.0, count: 1, url: "c-lib2")
                ],
                generation: Date(),
                totalNumber: 3
            )
        )

        let firstPage = await unifiedCategoryService.mergeCategoryPage(
            categoryName: "Authors",
            searchString: "",
            offset: 0,
            limit: 2
        )

        XCTAssertEqual(firstPage.items.map(\.name), ["Author A", "Author B"])
        XCTAssertTrue(firstPage.hasMore)
        XCTAssertEqual(firstPage.nextOffset, 2)
        XCTAssertEqual(firstPage.totalNumber, 6)
        XCTAssertEqual(firstPage.items.first?.count, 4)
        XCTAssertEqual(firstPage.items.first?.averageRating, 3.0)
        XCTAssertEqual(firstPage.items.first?.libraryItems.count, 2)

        let secondPage = await unifiedCategoryService.mergeCategoryPage(
            categoryName: "Authors",
            searchString: "",
            offset: firstPage.nextOffset,
            limit: 2
        )

        XCTAssertEqual(secondPage.items.map(\.name), ["Author C"])
        XCTAssertFalse(secondPage.hasMore)
    }

    func testUnifiedCategoryServiceMergeCategoryPageCanScopeAndFilter() async throws {
        try repository.saveLibraryCategoryResult(
            libraryId: mockLibrary1.id,
            categoryName: "Authors",
            result: LibraryCategoryResult(
                libraryId: mockLibrary1.id,
                categoryName: "Authors",
                items: [
                    LibraryCategoryItem(name: "Author One", averageRating: 4.0, count: 1, url: "one"),
                    LibraryCategoryItem(name: "Shared Author", averageRating: 4.0, count: 1, url: "shared-one")
                ],
                generation: Date(),
                totalNumber: 2
            )
        )
        try repository.saveLibraryCategoryResult(
            libraryId: mockLibrary2.id,
            categoryName: "Authors",
            result: LibraryCategoryResult(
                libraryId: mockLibrary2.id,
                categoryName: "Authors",
                items: [
                    LibraryCategoryItem(name: "Author Two", averageRating: 3.0, count: 1, url: "two"),
                    LibraryCategoryItem(name: "Shared Author", averageRating: 3.0, count: 1, url: "shared-two")
                ],
                generation: Date(),
                totalNumber: 2
            )
        )

        let scopedPage = await unifiedCategoryService.mergeCategoryPage(
            categoryName: "Authors",
            searchString: "author",
            libraryIds: [mockLibrary1.id],
            offset: 0,
            limit: 10
        )

        XCTAssertEqual(scopedPage.items.map(\.name), ["Author One", "Shared Author"])
        XCTAssertEqual(scopedPage.items.first { $0.name == "Shared Author" }?.count, 1)
        XCTAssertNil(scopedPage.items.first { $0.name == "Author Two" })
    }

    func testUnifiedCategoryViewModelReloadAndLoadMorePages() async throws {
        try repository.saveLibraryCategoryResult(
            libraryId: mockLibrary1.id,
            categoryName: "Authors",
            result: LibraryCategoryResult(
                libraryId: mockLibrary1.id,
                categoryName: "Authors",
                items: [
                    LibraryCategoryItem(name: "Author A", averageRating: 4.0, count: 1, url: "a"),
                    LibraryCategoryItem(name: "Author B", averageRating: 4.0, count: 1, url: "b"),
                    LibraryCategoryItem(name: "Author C", averageRating: 4.0, count: 1, url: "c")
                ],
                generation: Date(),
                totalNumber: 3
            )
        )

        let viewModel = UnifiedCategoryViewModel(
            unifiedCategoryService: unifiedCategoryService,
            categoryCacheRepository: repository,
            container: container
        )

        viewModel.reloadCategory(categoryName: "Authors", searchString: "", pageSize: 2)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.items.map(\.name), ["Author A", "Author B"])
        XCTAssertTrue(viewModel.hasMore)
        XCTAssertEqual(viewModel.nextOffset, 2)
        XCTAssertEqual(viewModel.unifiedCategoryResult?.items.map(\.name), ["Author A", "Author B"])

        viewModel.loadNextPageIfNeeded(currentItem: viewModel.items.last)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.items.map(\.name), ["Author A", "Author B", "Author C"])
        XCTAssertFalse(viewModel.hasMore)
        XCTAssertEqual(viewModel.nextOffset, 3)
    }

    func testUnifiedCategoryViewModelCacheObserverReloadsFirstPageWithScopeAndSearch() async throws {
        try repository.saveLibraryCategoryResult(
            libraryId: mockLibrary1.id,
            categoryName: "Authors",
            result: LibraryCategoryResult(
                libraryId: mockLibrary1.id,
                categoryName: "Authors",
                items: [LibraryCategoryItem(name: "Scoped Author", averageRating: 4.0, count: 1, url: "scoped")],
                generation: Date(),
                totalNumber: 1
            )
        )
        try repository.saveLibraryCategoryResult(
            libraryId: mockLibrary2.id,
            categoryName: "Authors",
            result: LibraryCategoryResult(
                libraryId: mockLibrary2.id,
                categoryName: "Authors",
                items: [LibraryCategoryItem(name: "Other Author", averageRating: 4.0, count: 1, url: "other")],
                generation: Date(),
                totalNumber: 1
            )
        )

        let viewModel = UnifiedCategoryViewModel(
            unifiedCategoryService: unifiedCategoryService,
            categoryCacheRepository: repository,
            container: container
        )

        viewModel.reloadCategory(
            categoryName: "Authors",
            searchString: "Scoped",
            libraryIds: [mockLibrary1.id],
            pageSize: 1
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(viewModel.items.map(\.name), ["Scoped Author"])

        try repository.saveLibraryCategoryResult(
            libraryId: mockLibrary1.id,
            categoryName: "Authors",
            result: LibraryCategoryResult(
                libraryId: mockLibrary1.id,
                categoryName: "Authors",
                items: [
                    LibraryCategoryItem(name: "Scoped Author", averageRating: 4.0, count: 1, url: "scoped"),
                    LibraryCategoryItem(name: "Scoped Writer", averageRating: 5.0, count: 1, url: "scoped-writer")
                ],
                generation: Date(),
                totalNumber: 2
            )
        )
        repository.sendCategoryCacheUpdate(categoryName: "Authors")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.items.map(\.name), ["Scoped Author"])
        XCTAssertTrue(viewModel.hasMore)
        XCTAssertNil(viewModel.items.first { $0.name == "Other Author" })
    }

    func testFetchAndCacheCategoryFailureHttpStatus() async throws {
        let category = CalibreLibraryCategory(name: "Authors", url: "http://localhost/1/ajax/category/Authors", icon: "user", is_category: true)

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!

            return (response, Data())
        }

        do {
            let _ = try await libraryCategoryService.fetchAndCacheCategory(library: mockLibrary1, category: category)
            XCTFail("Expected fetch to throw an error, but it succeeded")
        } catch {
            guard let apiError = error as? CalibreAPIError else {
                XCTFail("Expected CalibreAPIError, but got \(error)")
                return
            }
            if case .httpStatus(let statusCode, _) = apiError {
                XCTAssertEqual(statusCode, 404)
            } else {
                XCTFail("Expected HTTP status error, but got \(apiError)")
            }
        }

        // Assert that nothing was written to the repository cache
        let cached = try repository.fetchLibraryCategoryResult(libraryId: mockLibrary1.id, categoryName: "Authors")
        XCTAssertNil(cached, "Cache should remain empty/nil on failure")
    }

    func testRealmSearchCacheStoreObserveCategorySummariesPublishesInitialAndUpdatedSnapshots() async throws {
        let (container, store) = makeRealmSearchCacheStore()

        let initialResult = LibraryCategoryResult(
            libraryId: mockLibrary1.id,
            categoryName: "Authors",
            items: [LibraryCategoryItem(name: "Author A", averageRating: 4.0, count: 1, url: "a")],
            generation: Date(),
            totalNumber: 1
        )
        try store.saveLibraryCategoryResult(libraryId: mockLibrary1.id, categoryName: "Authors", result: initialResult)

        var iterator = store.observeCategorySummaries().makeAsyncIterator()

        let initialSummaries = await iterator.next() ?? []
        let initialSummary = initialSummaries.first { $0.categoryName == "Authors" }
        XCTAssertEqual(initialSummary?.categoryName, "Authors")
        XCTAssertEqual(initialSummary?.itemsCount, 1)

        let updatedResult = LibraryCategoryResult(
            libraryId: mockLibrary2.id,
            categoryName: "Authors",
            items: [
                LibraryCategoryItem(name: "Author B", averageRating: 5.0, count: 2, url: "b"),
                LibraryCategoryItem(name: "Author C", averageRating: 3.0, count: 1, url: "c")
            ],
            generation: Date(),
            totalNumber: 2
        )
        try store.saveLibraryCategoryResult(libraryId: mockLibrary2.id, categoryName: "Authors", result: updatedResult)

        let updatedSummaries = await iterator.next() ?? []
        let updatedSummary = updatedSummaries.first { $0.categoryName == "Authors" }
        XCTAssertEqual(updatedSummary?.categoryName, "Authors")
        XCTAssertEqual(updatedSummary?.itemsCount, 3)
        XCTAssertEqual(updatedSummary?.totalNumber, 3)
        _ = container
    }

    func testRealmSearchCacheStoreFetchCategorySummariesCanScopeToLibraries() async throws {
        let (_, store) = makeRealmSearchCacheStore()

        try store.saveLibraryCategoryResult(
            libraryId: mockLibrary1.id,
            categoryName: "Authors",
            result: LibraryCategoryResult(
                libraryId: mockLibrary1.id,
                categoryName: "Authors",
                items: [LibraryCategoryItem(name: "Author A", averageRating: 4.0, count: 1, url: "author-a-lib1")],
                generation: Date(),
                totalNumber: 1
            )
        )
        try store.saveLibraryCategoryResult(
            libraryId: mockLibrary2.id,
            categoryName: "Tags",
            result: LibraryCategoryResult(
                libraryId: mockLibrary2.id,
                categoryName: "Tags",
                items: [
                    LibraryCategoryItem(name: "Tag B", averageRating: 0.0, count: 2, url: "tag-b-lib2"),
                    LibraryCategoryItem(name: "Tag C", averageRating: 0.0, count: 1, url: "tag-c-lib2")
                ],
                generation: Date(),
                totalNumber: 2
            )
        )

        let scoped = try store.fetchCategorySummaries(libraryIds: [mockLibrary1.id])
        XCTAssertEqual(scoped.map(\.categoryName), ["Authors"])
        XCTAssertEqual(scoped.first?.itemsCount, 1)

        let global = try store.fetchCategorySummaries(libraryIds: [])
        XCTAssertEqual(global.map(\.categoryName), ["Authors", "Tags"])
    }

    func testRealmSearchCacheStoreFetchUnifiedCategoryItemsPageHandlesLargeAuthors() throws {
        let (_, store) = makeRealmSearchCacheStore()
        let items = (0..<50_000).map { index in
            LibraryCategoryItem(
                name: String(format: "Author %05d", index),
                averageRating: 0.0,
                count: 1,
                url: "author-\(index)"
            )
        }

        try store.saveLibraryCategoryResult(
            libraryId: mockLibrary1.id,
            categoryName: "Authors",
            result: LibraryCategoryResult(
                libraryId: mockLibrary1.id,
                categoryName: "Authors",
                items: items,
                generation: Date(),
                totalNumber: items.count
            )
        )

        let page = try store.fetchUnifiedCategoryItemsPage(
            categoryName: "Authors",
            searchString: "",
            libraryIds: [mockLibrary1.id],
            offset: 0,
            limit: 100
        )

        XCTAssertEqual(page.items.count, 100)
        XCTAssertEqual(page.items.first?.name, "Author 00000")
        XCTAssertEqual(page.items.last?.name, "Author 00099")
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextOffset, 100)
    }

    func testRealmSearchCacheStoreFetchUnifiedCategoryItemsPageFiltersScopesAndAggregates() throws {
        let (_, store) = makeRealmSearchCacheStore()

        try store.saveLibraryCategoryResult(
            libraryId: mockLibrary1.id,
            categoryName: "Authors",
            result: LibraryCategoryResult(
                libraryId: mockLibrary1.id,
                categoryName: "Authors",
                items: [
                    LibraryCategoryItem(name: "Alpha", averageRating: 4.0, count: 2, url: "alpha-one"),
                    LibraryCategoryItem(name: "Shared", averageRating: 5.0, count: 1, url: "shared-one")
                ],
                generation: Date(),
                totalNumber: 3
            )
        )
        try store.saveLibraryCategoryResult(
            libraryId: mockLibrary2.id,
            categoryName: "Authors",
            result: LibraryCategoryResult(
                libraryId: mockLibrary2.id,
                categoryName: "Authors",
                items: [
                    LibraryCategoryItem(name: "Beta", averageRating: 2.0, count: 1, url: "beta-two"),
                    LibraryCategoryItem(name: "Shared", averageRating: 3.0, count: 3, url: "shared-two")
                ],
                generation: Date(),
                totalNumber: 4
            )
        )

        let globalPage = try store.fetchUnifiedCategoryItemsPage(
            categoryName: "Authors",
            searchString: "sha",
            libraryIds: [],
            offset: 0,
            limit: 10
        )

        XCTAssertEqual(globalPage.items.map(\.name), ["Shared"])
        XCTAssertEqual(globalPage.items.first?.count, 4)
        XCTAssertEqual(globalPage.items.first?.averageRating, 3.5)
        XCTAssertEqual(globalPage.items.first?.libraryItems.count, 2)
        XCTAssertFalse(globalPage.hasMore)

        let scopedPage = try store.fetchUnifiedCategoryItemsPage(
            categoryName: "Authors",
            searchString: "",
            libraryIds: [mockLibrary1.id],
            offset: 0,
            limit: 10
        )

        XCTAssertEqual(scopedPage.items.map(\.name), ["Alpha", "Shared"])
        XCTAssertEqual(scopedPage.totalNumber, 3)
        XCTAssertNil(scopedPage.items.first { $0.name == "Beta" })
    }

    func testRealmSearchCacheStoreObserveCategoryCacheUpdatesSkipsInitialAndGenerationInvalidation() async throws {
        let (_, store) = makeRealmSearchCacheStore()

        let noInitialExpectation = expectation(description: "no initial event")
        noInitialExpectation.isInverted = true
        let updateExpectation = expectation(description: "real cache update")
        var updateCount = 0

        let task = Task { @MainActor in
            for await _ in store.observeCategoryCacheUpdates(categoryName: "Authors") {
                updateCount += 1
                updateExpectation.fulfill()
                break
            }
        }

        await fulfillment(of: [noInitialExpectation], timeout: 0.2)

        let seededResult = LibraryCategoryResult(
            libraryId: mockLibrary1.id,
            categoryName: "Authors",
            items: [LibraryCategoryItem(name: "Author A", averageRating: 4.0, count: 1, url: "a")],
            generation: Date(),
            totalNumber: 1
        )
        try store.saveLibraryCategoryResult(libraryId: mockLibrary1.id, categoryName: "Authors", result: seededResult)
        await fulfillment(of: [updateExpectation], timeout: 1.0)
        XCTAssertEqual(updateCount, 1)
        task.cancel()

        let noInvalidationExpectation = expectation(description: "generation invalidation does not publish")
        noInvalidationExpectation.isInverted = true
        try store.invalidateCategoryCache(libraryId: mockLibrary1.id, categoryName: "Authors")
        await fulfillment(of: [noInvalidationExpectation], timeout: 0.2)
        XCTAssertEqual(updateCount, 1)
    }

    private func makeRealmSearchCacheStore() -> (AppContainer, RealmSearchCacheStore) {
        let identifier = "UnifiedCategoryServiceTests-RealmStore"
        let config = Realm.Configuration(inMemoryIdentifier: identifier)
        let container = MockAppContainerFactory.makeContainer(
            mainRealmConfiguration: config,
            testName: identifier
        )
        container.libraryManager.calibreLibraries = [
            mockLibrary1.id: mockLibrary1,
            mockLibrary2.id: mockLibrary2
        ]
        if let realm = try? Realm(configuration: config) {
            try? realm.write {
                realm.delete(realm.objects(CalibreLibraryCategoryObject.self))
                realm.delete(realm.objects(CalibreLibraryCategoryItemObject.self))
            }
        }
        return (container, RealmSearchCacheStore(container: container))
    }
}
