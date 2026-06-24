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

    func testUnifiedCategoryViewModelDefaultsToModelDataCategoryCacheRepository() {
        let modelData = makeModelData()
        let repository = MockCategoryCacheRepository()
        let unifiedCategoryService = UnifiedCategoryService(repository: repository, libraryProvider: modelData)
        modelData.categoryCacheRepository = repository
        modelData.unifiedCategoryService = unifiedCategoryService

        let viewModel = UnifiedCategoryViewModel(modelData: modelData)
        let resolved = Mirror(reflecting: viewModel).children.first { $0.label == "categoryCacheRepository" }?.value as AnyObject?

        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved === (repository as AnyObject))
    }
    
    func testLibraryInfoViewModelFetchAvailableCategoriesUsesModelDataCategoryCacheRepository() {
        let modelData = makeModelData()
        let repository = MockCategoryCacheRepository()
        modelData.categoryCacheRepository = repository
        ModelData.shared = modelData
        
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

    func testLibraryInfoViewModelSetupCategoryObserverUsesRepositoryPublisher() {
        let modelData = makeModelData()
        let repository = MockCategoryCacheRepository()
        modelData.categoryCacheRepository = repository
        ModelData.shared = modelData

        let initialResult = LibraryCategoryResult(
            libraryId: "library-id",
            categoryName: "Authors",
            items: [LibraryCategoryItem(name: "Author A", averageRating: 4.5, count: 2, url: "author-a")],
            generation: Date(),
            totalNumber: 1
        )
        let updated = CategoryCacheSummary(categoryName: "Tags", itemsCount: 3, totalNumber: 4)
        try? repository.saveLibraryCategoryResult(libraryId: initialResult.libraryId, categoryName: initialResult.categoryName, result: initialResult)

        let viewModel = LibraryInfoView.ViewModel()
        viewModel.setupCategoryObserver()

        XCTAssertTrue(repository.observeCategorySummariesCalled)
        XCTAssertEqual(viewModel.availableCategories.first?.categoryName, "Authors")
        XCTAssertEqual(viewModel.availableCategories.first?.itemsCount, 1)

        repository.sendCategorySummaries([updated])

        XCTAssertEqual(viewModel.availableCategories, [updated])
    }

    func testUnifiedCategoryViewModelMergeCategoryObservesRepositoryUpdates() async throws {
        let modelData = makeModelData()
        let repository = MockCategoryCacheRepository()
        let library = TestFixtures.makeLibrary(server: TestFixtures.makeServer())
        modelData.calibreLibraries = [library.id: library]
        modelData.categoryCacheRepository = repository
        let unifiedCategoryService = UnifiedCategoryService(repository: repository, libraryProvider: modelData)
        modelData.unifiedCategoryService = unifiedCategoryService
        ModelData.shared = modelData

        try repository.saveLibraryCategoryResult(
            libraryId: library.id,
            categoryName: "Authors",
            result: LibraryCategoryResult(
                libraryId: library.id,
                categoryName: "Authors",
                items: [LibraryCategoryItem(name: "Author A", averageRating: 4.0, count: 1, url: "a")],
                generation: Date(),
                totalNumber: 1
            )
        )

        let viewModel = UnifiedCategoryViewModel(modelData: modelData)
        viewModel.mergeCategory(categoryName: "Authors", searchString: "")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(repository.observeCategoryCacheUpdatesCalled)
        XCTAssertEqual(repository.observeCategoryCacheUpdatesCategoryNameParam, "Authors")
        XCTAssertEqual(viewModel.unifiedCategoryResult?.categoryName, "Authors")
        XCTAssertEqual(viewModel.unifiedCategoryResult?.itemsCount, 1)

        try repository.saveLibraryCategoryResult(
            libraryId: library.id,
            categoryName: "Authors",
            result: LibraryCategoryResult(
                libraryId: library.id,
                categoryName: "Authors",
                items: [
                    LibraryCategoryItem(name: "Author A", averageRating: 4.0, count: 1, url: "a"),
                    LibraryCategoryItem(name: "Author B", averageRating: 3.0, count: 2, url: "b")
                ],
                generation: Date(),
                totalNumber: 3
            )
        )
        repository.sendCategoryCacheUpdate(categoryName: "Authors")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.unifiedCategoryResult?.itemsCount, 2)
        XCTAssertEqual(viewModel.unifiedCategoryResult?.totalNumber, 3)
    }

    func testUnifiedCategoryViewModelRebindsObserverForNewCategory() async throws {
        let modelData = makeModelData()
        let repository = MockCategoryCacheRepository()
        let library = TestFixtures.makeLibrary(server: TestFixtures.makeServer())
        modelData.calibreLibraries = [library.id: library]
        modelData.categoryCacheRepository = repository
        let unifiedCategoryService = UnifiedCategoryService(repository: repository, libraryProvider: modelData)
        modelData.unifiedCategoryService = unifiedCategoryService
        ModelData.shared = modelData

        try repository.saveLibraryCategoryResult(
            libraryId: library.id,
            categoryName: "Authors",
            result: LibraryCategoryResult(
                libraryId: library.id,
                categoryName: "Authors",
                items: [LibraryCategoryItem(name: "Author A", averageRating: 4.0, count: 1, url: "a")],
                generation: Date(),
                totalNumber: 1
            )
        )
        try repository.saveLibraryCategoryResult(
            libraryId: library.id,
            categoryName: "Tags",
            result: LibraryCategoryResult(
                libraryId: library.id,
                categoryName: "Tags",
                items: [LibraryCategoryItem(name: "Tag A", averageRating: 0.0, count: 2, url: "tag-a")],
                generation: Date(),
                totalNumber: 2
            )
        )

        let viewModel = UnifiedCategoryViewModel(modelData: modelData)
        viewModel.mergeCategory(categoryName: "Authors", searchString: "")
        try await Task.sleep(nanoseconds: 50_000_000)
        viewModel.mergeCategory(categoryName: "Tags", searchString: "")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(repository.observeCategoryCacheUpdatesCategoryNameParam, "Tags")
        XCTAssertEqual(viewModel.unifiedCategoryResult?.categoryName, "Tags")
        XCTAssertEqual(viewModel.unifiedCategoryResult?.itemsCount, 1)
    }

    func testUnifiedCategoryViewModelForceRefreshInvalidatesActiveLibraries() {
        let modelData = makeModelData()
        let repository = MockCategoryCacheRepository()
        var activeLibrary = TestFixtures.makeLibrary(server: TestFixtures.makeServer())
        var hiddenLibrary = TestFixtures.makeLibrary(server: TestFixtures.makeServer(), key: "hidden", name: "Hidden")
        activeLibrary.hidden = false
        hiddenLibrary.hidden = true
        modelData.calibreLibraries = [
            activeLibrary.id: activeLibrary,
            hiddenLibrary.id: hiddenLibrary
        ]
        modelData.categoryCacheRepository = repository
        modelData.unifiedCategoryService = UnifiedCategoryService(repository: repository, libraryProvider: modelData)
        ModelData.shared = modelData

        let viewModel = UnifiedCategoryViewModel(modelData: modelData)
        viewModel.forceRefreshCategory(categoryName: "Authors")

        XCTAssertTrue(repository.invalidateCategoryCacheCalled)
        XCTAssertEqual(repository.invalidateCategoryCacheParams.count, 1)
        XCTAssertEqual(repository.invalidateCategoryCacheParams.first?.libraryId, activeLibrary.id)
        XCTAssertEqual(repository.invalidateCategoryCacheParams.first?.categoryName, "Authors")
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
        let logger = CalibreActivityLogger(realmConf: modelData.realmConf ?? Realm.Configuration())
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
