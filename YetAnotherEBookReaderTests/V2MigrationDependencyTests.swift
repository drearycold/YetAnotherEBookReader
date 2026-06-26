//
//  V2MigrationDependencyTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Codex on 2026-06-17.
//

import XCTest
import Combine
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
final class V2MigrationDependencyTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()
    
    override func tearDown() {
        cancellables.removeAll()
        ModelData.shared = nil
        super.tearDown()
    }
    
    func testUnifiedSearchViewModelDefaultsToModelDataUnifiedSearchService() async throws {
        let modelData = makeModelData()
        let unifiedSearchService = try await makeUnifiedSearchService(modelData: modelData)
        modelData.unifiedSearchService = unifiedSearchService
        
        let viewModel = UnifiedSearchViewModel(modelData: modelData)
        let resolved = Mirror(reflecting: viewModel).children.first { $0.label == "searchService" }?.value as AnyObject?
        
        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved === (unifiedSearchService as AnyObject))
    }
    
    func testUnifiedCategoryViewModelDefaultsToModelDataUnifiedCategoryService() {
        let modelData = makeModelData()
        let repository = MockCategoryCacheRepository()
        let unifiedCategoryService = UnifiedCategoryService(repository: repository, libraryProvider: modelData)
        modelData.categoryCacheRepository = repository
        modelData.unifiedCategoryService = unifiedCategoryService
        
        let viewModel = UnifiedCategoryViewModel(modelData: modelData)
        let resolved = Mirror(reflecting: viewModel).children.first { $0.label == "unifiedCategoryService" }?.value as AnyObject?
        
        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved === (unifiedCategoryService as AnyObject))
    }
    
    func testLibraryInfoViewModelFetchAvailableCategoriesUsesModelDataCategoryCacheRepository() {
        let modelData = makeModelData()
        let repository = MockCategoryCacheRepository()
        modelData.categoryCacheRepository = repository
        
        let result = LibraryCategoryResult(
            libraryId: "library-id",
            categoryName: "Authors",
            items: [LibraryCategoryItem(name: "Author A", averageRating: 4.5, count: 2, url: "author-a")],
            generation: Date(),
            totalNumber: 1
        )
        try? repository.saveLibraryCategoryResult(libraryId: result.libraryId, categoryName: result.categoryName, result: result)
        
        let viewModel = LibraryInfoView.ViewModel()
        viewModel.fetchAvailableCategories()
        
        XCTAssertEqual(viewModel.availableCategories.count, 1)
        XCTAssertEqual(viewModel.availableCategories.first?.categoryName, "Authors")
        XCTAssertEqual(viewModel.availableCategories.first?.itemsCount, 1)
    }
    
    func testShelfRefreshResetsActiveUnifiedSearchLimit() async throws {
        let modelData = makeModelData()
        let unifiedSearchService = try await makeUnifiedSearchService(modelData: modelData)
        
        let server = CalibreServer(
            uuid: UUID(),
            name: "Shelf Server",
            baseUrl: "http://localhost:8080",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        let library = CalibreLibrary(server: server, key: "lib1", name: "Library 1")
        
        modelData.calibreLibraries = [library.id: library]
        modelData.unifiedSearchService = unifiedSearchService
        
        let key = SearchCriteriaMergedKey(
            libraryIds: [],
            criteria: SearchCriteria(
                searchString: "",
                sortCriteria: .init(),
                filterCriteriaCategory: ["Authors": ["Author A"]]
            )
        )
        
        unifiedSearchService.publisher(for: key)
            .sink { _ in }
            .store(in: &cancellables)
        
        try await Task.sleep(nanoseconds: 150_000_000)
        await unifiedSearchService.setLimit(for: key, limit: 250)
        let limitBeforeRefresh = await unifiedSearchService.getActiveSearch(for: key)?.limitNumber
        XCTAssertEqual(limitBeforeRefresh, 250)
        
        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, modelData: modelData)
        shelfDataModel.categories = [YabrShelfDataModel.CategoryObject(type: .Author, category: "Author A")]
        shelfDataModel.refresh()
        
        try await Task.sleep(nanoseconds: 150_000_000)
        let limitAfterRefresh = await unifiedSearchService.getActiveSearch(for: key)?.limitNumber
        XCTAssertEqual(limitAfterRefresh, 100)
    }
    
    private func makeModelData() -> ModelData {
        let config = Realm.Configuration(inMemoryIdentifier: "V2MigrationDependencyTests-\(UUID().uuidString)")
        DatabaseService.shared.setup(conf: config)
        let modelData = ModelData(mock: true)
        modelData.realmConf = config
        return modelData
    }
    
    private func makeUnifiedSearchService(modelData: ModelData) async throws -> UnifiedSearchService {
        let repository = MockSearchCacheRepository()
        let libraryProvider = MockLibraryProvider()
        let logger = CalibreActivityLogger(realmConf: modelData.realmConf)
        let service = CalibreServerService(logger: logger, config: modelData, database: DatabaseService.shared)
        
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        
        let server = CalibreServer(
            uuid: UUID(),
            name: "Mock Server",
            baseUrl: "http://localhost:8080",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        
        for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
            let key = CalibreServerURLSessionKey(server: server, timeout: 600, qos: qos)
            service.metadataSessions[key] = mockSession
        }
        
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            
            if url.path.contains("ajax/search") {
                let libraryId = url.path.components(separatedBy: "/").last ?? "lib1"
                let json = """
                {
                    "total_num": 0,
                    "sort_order": "asc",
                    "num_books_without_search": 0,
                    "offset": 0,
                    "num": 0,
                    "sort": "title",
                    "base_url": "/ajax/search/\(libraryId)",
                    "query": "",
                    "library_id": "\(libraryId)",
                    "book_ids": [],
                    "vl": ""
                }
                """
                return (response, Data(json.utf8))
            }
            
            if url.path.contains("ajax/books") {
                return (response, Data("{}".utf8))
            }
            
            throw URLError(.badURL)
        }
        
        let librarySearchService = LibrarySearchService(service: service, repository: repository)
        let unifiedSearchService = UnifiedSearchService(
            repository: repository,
            librarySearchService: librarySearchService,
            libraryProvider: libraryProvider
        )
        await unifiedSearchService.setReachabilityProviders(
            reachable: { _, _ in true },
            reachableNoPublic: { _ in true }
        )
        
        return unifiedSearchService
    }
}
