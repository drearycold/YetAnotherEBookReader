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
        AppContainer.shared = nil
        super.tearDown()
    }
    
    func testUnifiedSearchViewModelDefaultsToAppContainerUnifiedSearchService() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        container.unifiedSearchService = unifiedSearchService
        
        let viewModel = UnifiedSearchViewModel(container: container)
        let resolved = Mirror(reflecting: viewModel).children.first { $0.label == "searchService" }?.value as AnyObject?
        
        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved === (unifiedSearchService as AnyObject))
    }
    
    func testUnifiedCategoryViewModelDefaultsToAppContainerUnifiedCategoryService() {
        let container = makeAppContainer()
        let repository = MockCategoryCacheRepository()
        let unifiedCategoryService = UnifiedCategoryService(repository: repository, libraryProvider: container)
        container.categoryCacheRepository = repository
        container.unifiedCategoryService = unifiedCategoryService
        
        let viewModel = UnifiedCategoryViewModel(container: container)
        let resolved = Mirror(reflecting: viewModel).children.first { $0.label == "unifiedCategoryService" }?.value as AnyObject?
        
        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved === (unifiedCategoryService as AnyObject))
    }

    func testUnifiedCategoryViewModelDefaultsToAppContainerCategoryCacheRepository() {
        let container = makeAppContainer()
        let repository = MockCategoryCacheRepository()
        let unifiedCategoryService = UnifiedCategoryService(repository: repository, libraryProvider: container)
        container.categoryCacheRepository = repository
        container.unifiedCategoryService = unifiedCategoryService

        let viewModel = UnifiedCategoryViewModel(container: container)
        let resolved = Mirror(reflecting: viewModel).children.first { $0.label == "categoryCacheRepository" }?.value as AnyObject?

        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved === (repository as AnyObject))
    }
    
    func testLibraryInfoViewModelFetchAvailableCategoriesUsesAppContainerCategoryCacheRepository() {
        let container = makeAppContainer()
        let repository = MockCategoryCacheRepository()
        container.categoryCacheRepository = repository
        AppContainer.shared = container
        
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

    func testLibraryInfoViewModelSetupCategoryObserverUsesRepositoryAsyncStream() async {
        let container = makeAppContainer()
        let repository = MockCategoryCacheRepository()
        container.categoryCacheRepository = repository
        AppContainer.shared = container

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

        await waitForCategorySummaries(in: viewModel) { summaries in
            summaries.first?.categoryName == "Authors" && summaries.first?.itemsCount == 1
        }
        XCTAssertTrue(repository.observeCategorySummariesCalled)
        XCTAssertEqual(viewModel.availableCategories.first?.categoryName, "Authors")
        XCTAssertEqual(viewModel.availableCategories.first?.itemsCount, 1)

        repository.sendCategorySummaries([updated])

        await waitForCategorySummaries(in: viewModel) { summaries in
            summaries == [updated]
        }
        XCTAssertEqual(viewModel.availableCategories, [updated])
    }

    func testUnifiedCategoryViewModelMergeCategoryObservesRepositoryUpdates() async throws {
        let container = makeAppContainer()
        let repository = MockCategoryCacheRepository()
        let library = TestFixtures.makeLibrary(server: TestFixtures.makeServer())
        container.libraryManager.calibreLibraries = [library.id: library]
        container.categoryCacheRepository = repository
        let unifiedCategoryService = UnifiedCategoryService(repository: repository, libraryProvider: container)
        container.unifiedCategoryService = unifiedCategoryService
        AppContainer.shared = container

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

        let viewModel = UnifiedCategoryViewModel(container: container)
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
        let container = makeAppContainer()
        let repository = MockCategoryCacheRepository()
        let library = TestFixtures.makeLibrary(server: TestFixtures.makeServer())
        container.libraryManager.calibreLibraries = [library.id: library]
        container.categoryCacheRepository = repository
        let unifiedCategoryService = UnifiedCategoryService(repository: repository, libraryProvider: container)
        container.unifiedCategoryService = unifiedCategoryService
        AppContainer.shared = container

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

        let viewModel = UnifiedCategoryViewModel(container: container)
        viewModel.mergeCategory(categoryName: "Authors", searchString: "")
        try await Task.sleep(nanoseconds: 50_000_000)
        viewModel.mergeCategory(categoryName: "Tags", searchString: "")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(repository.observeCategoryCacheUpdatesCategoryNameParam, "Tags")
        XCTAssertEqual(viewModel.unifiedCategoryResult?.categoryName, "Tags")
        XCTAssertEqual(viewModel.unifiedCategoryResult?.itemsCount, 1)
    }

    func testUnifiedCategoryViewModelForceRefreshInvalidatesActiveLibraries() {
        let container = makeAppContainer()
        let repository = MockCategoryCacheRepository()
        var activeLibrary = TestFixtures.makeLibrary(server: TestFixtures.makeServer())
        var hiddenLibrary = TestFixtures.makeLibrary(server: TestFixtures.makeServer(), key: "hidden", name: "Hidden")
        activeLibrary.hidden = false
        hiddenLibrary.hidden = true
        container.libraryManager.calibreLibraries = [
            activeLibrary.id: activeLibrary,
            hiddenLibrary.id: hiddenLibrary
        ]
        container.categoryCacheRepository = repository
        container.unifiedCategoryService = UnifiedCategoryService(repository: repository, libraryProvider: container)
        AppContainer.shared = container

        let viewModel = UnifiedCategoryViewModel(container: container)
        viewModel.forceRefreshCategory(categoryName: "Authors")

        XCTAssertTrue(repository.invalidateCategoryCacheCalled)
        XCTAssertEqual(repository.invalidateCategoryCacheParams.count, 1)
        XCTAssertEqual(repository.invalidateCategoryCacheParams.first?.libraryId, activeLibrary.id)
        XCTAssertEqual(repository.invalidateCategoryCacheParams.first?.categoryName, "Authors")
    }

    func testCalibreUpdatesStreamsReceivePublishedSignalsForMultipleSubscribers() async throws {
        let container = makeAppContainer()
        var firstSignals = [calibreUpdatedSignal]()
        var secondSignals = [calibreUpdatedSignal]()

        let firstTask = Task { @MainActor in
            for await signal in container.calibreUpdates() {
                firstSignals.append(signal)
                if firstSignals.count == 1 { break }
            }
        }
        let secondTask = Task { @MainActor in
            for await signal in container.calibreUpdates() {
                secondSignals.append(signal)
                if secondSignals.count == 1 { break }
            }
        }

        await Task.yield()
        container.publishCalibreUpdate(.shelf)
        await waitForSnapshotCount(1, in: { firstSignals.count })
        await waitForSnapshotCount(1, in: { secondSignals.count })
        firstTask.cancel()
        secondTask.cancel()

        XCTAssertEqual(firstSignals, [.shelf])
        XCTAssertEqual(secondSignals, [.shelf])
    }

    func testCalibreUpdatesStreamTerminationStopsUpdates() async throws {
        let container = makeAppContainer()
        var signals = [calibreUpdatedSignal]()

        let task = Task { @MainActor in
            for await signal in container.calibreUpdates() {
                signals.append(signal)
            }
        }

        await Task.yield()
        container.publishCalibreUpdate(.shelf)
        await waitForSnapshotCount(1, in: { signals.count })
        task.cancel()
        try await Task.sleep(nanoseconds: 50_000_000)

        container.publishCalibreUpdate(.deleted("after-cancel"))
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(signals, [.shelf])
    }

    func testPublishCalibreUpdateStillBridgesToLegacySubject() async throws {
        let container = makeAppContainer()
        let expectation = XCTestExpectation(description: "Legacy calibre subject receives signal")

        container.calibreUpdatedSubject
            .sink { signal in
                if signal == .shelf {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        container.publishCalibreUpdate(.shelf)

        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testShelfRefreshResetsActiveUnifiedSearchLimit() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        
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
        
        container.libraryManager.calibreLibraries = [library.id: library]
        container.unifiedSearchService = unifiedSearchService
        
        let key = SearchCriteriaMergedKey(
            libraryIds: [],
            criteria: SearchCriteria(
                searchString: "",
                sortCriteria: .init(),
                filterCriteriaCategory: ["Authors": ["Author A"]]
            )
        )
        
        let searchTask = Task {
            let stream = await unifiedSearchService.search(key: key)
            for await _ in stream {
                guard !Task.isCancelled else { break }
            }
        }
        defer { searchTask.cancel() }
        
        try await Task.sleep(nanoseconds: 150_000_000)
        await unifiedSearchService.setLimit(for: key, limit: 250)
        let limitBeforeRefresh = await unifiedSearchService.getActiveSearch(for: key)?.limitNumber
        XCTAssertEqual(limitBeforeRefresh, 250)
        
        container.bookManager.isShelfLoaded = false
        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)
        await shelfDataModel.seedCategoriesForTesting([
            YabrShelfDataModel.CategoryObject(type: .Author, category: "Author A")
        ])
        await shelfDataModel.refresh()

        let limitAfterRefresh = await unifiedSearchService.getActiveSearch(for: key)?.limitNumber
        XCTAssertEqual(limitAfterRefresh, 100)
    }

    func testShelfDataModelRebuildsAuthorCategoriesForBookSignal() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        container.unifiedSearchService = unifiedSearchService
        container.bookManager.isShelfLoaded = false

        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)
        let library = TestFixtures.makeLibrary(server: TestFixtures.makeServer(), key: "book-signal", name: "Book Signal")
        var book = TestFixtures.makeBook(id: 101, library: library)
        book.title = "Book Signal Title"
        book.authors = ["Signal Author"]
        book.inShelf = true

        container.libraryManager.calibreLibraries = [library.id: library]
        container.bookManager.booksInShelf = [book.inShelfId: book]
        container.bookManager.isShelfLoaded = true

        container.publishCalibreUpdate(.book(book))
        try await waitForShelfSignalProcessing(in: shelfDataModel)

        let categoryNames = await shelfDataModel.categoryNamesForTesting()
        XCTAssertEqual(categoryNames, ["Signal Author"])
    }

    func testShelfDataModelRemovesStaleAuthorCategoriesForDeletedSignal() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        container.unifiedSearchService = unifiedSearchService
        container.bookManager.isShelfLoaded = false

        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)
        await shelfDataModel.seedCategoriesForTesting([
            YabrShelfDataModel.CategoryObject(type: .Author, category: "Stale Author")
        ])

        container.bookManager.booksInShelf = [:]
        container.bookManager.isShelfLoaded = true

        container.publishCalibreUpdate(.deleted("stale-book-id"))
        try await waitForShelfSignalProcessing(in: shelfDataModel)

        let categoryNames = await shelfDataModel.categoryNamesForTesting()
        XCTAssertTrue(categoryNames.isEmpty)
    }

    func testShelfDataModelCancelsCategorySearchTaskWhenCategoryRemoved() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        container.unifiedSearchService = unifiedSearchService
        container.bookManager.isShelfLoaded = false

        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)
        let library = TestFixtures.makeLibrary(server: TestFixtures.makeServer(), key: "cancel-task", name: "Cancel Task")
        var book = TestFixtures.makeBook(id: 301, library: library)
        book.title = "Cancel Task Title"
        book.authors = ["Cancelable Author"]
        book.inShelf = true

        container.libraryManager.calibreLibraries = [library.id: library]
        container.bookManager.booksInShelf = [book.inShelfId: book]
        container.bookManager.isShelfLoaded = true

        container.publishCalibreUpdate(.book(book))
        try await waitForShelfSignalProcessing(in: shelfDataModel)
        XCTAssertEqual(shelfDataModel.categorySearchTaskKeysForTesting(), ["Author: Cancelable Author"])

        container.bookManager.booksInShelf = [:]
        container.publishCalibreUpdate(.deleted(book.inShelfId))
        try await waitForShelfSignalProcessing(in: shelfDataModel)

        XCTAssertTrue(shelfDataModel.categorySearchTaskKeysForTesting().isEmpty)
        let categoryNames = await shelfDataModel.categoryNamesForTesting()
        XCTAssertTrue(categoryNames.isEmpty)
    }

    func testShelfDataModelInitialSnapshotRebuildsWhenShelfAlreadyLoaded() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        container.unifiedSearchService = unifiedSearchService

        let library = TestFixtures.makeLibrary(server: TestFixtures.makeServer(), key: "initial-snapshot", name: "Initial Snapshot")
        var book = TestFixtures.makeBook(id: 201, library: library)
        book.title = "Initial Snapshot Title"
        book.authors = ["Initial Author"]
        book.inShelf = true

        container.libraryManager.calibreLibraries = [library.id: library]
        container.bookManager.booksInShelf = [book.inShelfId: book]
        container.bookManager.isShelfLoaded = true

        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)
        try await waitForShelfSignalProcessing(in: shelfDataModel)

        let categoryNames = await shelfDataModel.categoryNamesForTesting()
        XCTAssertEqual(categoryNames, ["Initial Author"])
    }

    func testShelfDataModelEmptyShelfSnapshotCompletesInitialLoad() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        container.unifiedSearchService = unifiedSearchService
        container.bookManager.booksInShelf = [:]
        container.bookManager.isShelfLoaded = true

        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)
        container.publishCalibreUpdate(.shelf)
        try await waitForShelfSignalProcessing(in: shelfDataModel)

        let storeInitialLoadComplete = await shelfDataModel.initialLoadCompleteForTesting()
        XCTAssertTrue(storeInitialLoadComplete)
        XCTAssertTrue(shelfDataModel.currentDiscoverSnapshotForTesting().isInitialLoadComplete)
    }

    func testShelfDataModelPendingInitialCategoryKeepsInitialLoadIncomplete() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)

        await shelfDataModel.seedCategoriesForTesting([
            YabrShelfDataModel.CategoryObject(type: .Author, category: "Pending Author")
        ])

        let storeInitialLoadComplete = await shelfDataModel.initialLoadCompleteForTesting()
        XCTAssertFalse(storeInitialLoadComplete)
        XCTAssertFalse(shelfDataModel.currentDiscoverSnapshotForTesting().isInitialLoadComplete)
    }

    func testShelfDataModelInitialLoadCompletesWhenPendingCategorySearchCompletes() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)

        await shelfDataModel.seedCategoriesForTesting([
            YabrShelfDataModel.CategoryObject(type: .Author, category: "Finished Author")
        ])

        let isComplete = await shelfDataModel.markInitialCategoryCompleteForTesting(category: "Finished Author")
        let storeInitialLoadComplete = await shelfDataModel.initialLoadCompleteForTesting()

        XCTAssertTrue(isComplete)
        XCTAssertTrue(storeInitialLoadComplete)
    }

    func testShelfDataModelDeletingPendingInitialCategoryCompletesInitialLoad() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        container.unifiedSearchService = unifiedSearchService
        container.bookManager.isShelfLoaded = false

        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)
        await shelfDataModel.seedCategoriesForTesting([
            YabrShelfDataModel.CategoryObject(type: .Author, category: "Removed Pending Author")
        ])

        container.bookManager.booksInShelf = [:]
        container.bookManager.isShelfLoaded = true
        container.publishCalibreUpdate(.deleted("removed-pending-book-id"))
        try await waitForShelfSignalProcessing(in: shelfDataModel)

        let storeInitialLoadComplete = await shelfDataModel.initialLoadCompleteForTesting()
        XCTAssertTrue(storeInitialLoadComplete)
        XCTAssertTrue(shelfDataModel.currentDiscoverSnapshotForTesting().isInitialLoadComplete)
    }

    func testShelfDataModelCompletedInitialLoadDoesNotRegressWhenCategoriesChange() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        container.unifiedSearchService = unifiedSearchService
        container.bookManager.booksInShelf = [:]
        container.bookManager.isShelfLoaded = true

        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)
        container.publishCalibreUpdate(.shelf)
        try await waitForShelfSignalProcessing(in: shelfDataModel)
        XCTAssertTrue(shelfDataModel.currentDiscoverSnapshotForTesting().isInitialLoadComplete)

        let library = TestFixtures.makeLibrary(server: TestFixtures.makeServer(), key: "terminal-state", name: "Terminal State")
        var book = TestFixtures.makeBook(id: 401, library: library)
        book.title = "Terminal State Title"
        book.authors = ["Terminal Author"]
        book.inShelf = true

        container.libraryManager.calibreLibraries = [library.id: library]
        container.bookManager.booksInShelf = [book.inShelfId: book]
        container.publishCalibreUpdate(.book(book))
        try await waitForShelfSignalProcessing(in: shelfDataModel)

        let storeInitialLoadCompleteAfterAdd = await shelfDataModel.initialLoadCompleteForTesting()
        XCTAssertTrue(storeInitialLoadCompleteAfterAdd)
        XCTAssertTrue(shelfDataModel.currentDiscoverSnapshotForTesting().isInitialLoadComplete)

        container.bookManager.booksInShelf = [:]
        container.publishCalibreUpdate(.deleted(book.inShelfId))
        try await waitForShelfSignalProcessing(in: shelfDataModel)

        let storeInitialLoadCompleteAfterDelete = await shelfDataModel.initialLoadCompleteForTesting()
        XCTAssertTrue(storeInitialLoadCompleteAfterDelete)
        XCTAssertTrue(shelfDataModel.currentDiscoverSnapshotForTesting().isInitialLoadComplete)
    }

    func testShelfDataModelDeinitStopsShelfSignalConsumption() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        container.unifiedSearchService = unifiedSearchService
        container.bookManager.isShelfLoaded = true

        weak var weakShelfDataModel: YabrShelfDataModel?
        var shelfDataModel: YabrShelfDataModel? = YabrShelfDataModel(
            unifiedSearchService: unifiedSearchService,
            container: container
        )
        weakShelfDataModel = shelfDataModel

        shelfDataModel = nil
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(weakShelfDataModel)
        container.publishCalibreUpdate(.shelf)
    }

    func testShelfDataModelSnapshotsYieldCurrentSnapshotToNewSubscriber() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)
        let section = makeShelfSection(id: "Author: Current")

        shelfDataModel.setDiscoverShelfSnapshotForTesting(
            .init(sections: [section], isInitialLoadComplete: true),
            sendLegacySubject: false
        )

        var iterator = shelfDataModel.snapshots().makeAsyncIterator()
        let snapshot = await iterator.next()

        XCTAssertEqual(snapshot?.sections, [section])
        XCTAssertEqual(snapshot?.isInitialLoadComplete, true)
    }

    func testShelfDataModelSnapshotsYieldSectionUpdates() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)
        let section = makeShelfSection(id: "Author: Updated")

        var snapshots = [YabrShelfDataModel.DiscoverShelfSnapshot]()
        let task = Task { @MainActor in
            for await snapshot in shelfDataModel.snapshots() {
                snapshots.append(snapshot)
                if snapshots.count == 2 { break }
            }
        }

        await Task.yield()
        shelfDataModel.setDiscoverShelfSnapshotForTesting(
            .init(sections: [section], isInitialLoadComplete: false),
            sendLegacySubject: false
        )
        await waitForSnapshotCount(2, in: { snapshots.count })
        task.cancel()

        XCTAssertEqual(snapshots.last?.sections, [section])
    }

    func testShelfDataModelSnapshotsYieldInitialLoadOnlyUpdates() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)

        var snapshots = [YabrShelfDataModel.DiscoverShelfSnapshot]()
        let task = Task { @MainActor in
            for await snapshot in shelfDataModel.snapshots() {
                snapshots.append(snapshot)
                if snapshots.count == 2 { break }
            }
        }

        await Task.yield()
        shelfDataModel.setDiscoverShelfSnapshotForTesting(
            .init(sections: [], isInitialLoadComplete: true),
            sendLegacySubject: false
        )
        await waitForSnapshotCount(2, in: { snapshots.count })
        task.cancel()

        XCTAssertEqual(snapshots.last?.sections, [])
        XCTAssertEqual(snapshots.last?.isInitialLoadComplete, true)
    }

    func testShelfDataModelSnapshotsDoNotYieldDuplicateSnapshots() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)

        var snapshots = [YabrShelfDataModel.DiscoverShelfSnapshot]()
        let task = Task { @MainActor in
            for await snapshot in shelfDataModel.snapshots() {
                snapshots.append(snapshot)
            }
        }

        await waitForSnapshotCount(1, in: { snapshots.count })
        shelfDataModel.setDiscoverShelfSnapshotForTesting(
            .init(sections: [], isInitialLoadComplete: false),
            sendLegacySubject: false
        )
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        XCTAssertEqual(snapshots.count, 1)
    }

    func testShelfDataModelSnapshotTerminationStopsUpdates() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)

        var snapshots = [YabrShelfDataModel.DiscoverShelfSnapshot]()
        let task = Task { @MainActor in
            for await snapshot in shelfDataModel.snapshots() {
                snapshots.append(snapshot)
            }
        }

        await waitForSnapshotCount(1, in: { snapshots.count })
        task.cancel()
        try await Task.sleep(nanoseconds: 50_000_000)

        shelfDataModel.setDiscoverShelfSnapshotForTesting(
            .init(sections: [makeShelfSection(id: "Author: Cancelled")], isInitialLoadComplete: false),
            sendLegacySubject: false
        )
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(snapshots.count, 1)
    }

    func testShelfDataModelLegacyDiscoverSubjectStillReceivesPublishedSections() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)
        let section = makeShelfSection(id: "Author: Legacy")

        let expectation = XCTestExpectation(description: "Legacy discover subject receives sections")
        container.discoverShelfItemsSubject
            .sink { sections in
                if sections == [section] {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        shelfDataModel.setDiscoverShelfSnapshotForTesting(
            .init(sections: [section], isInitialLoadComplete: false),
            sendLegacySubject: true
        )

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testShelfDataModelRecentSnapshotsYieldCurrentSnapshotToNewSubscriber() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        container.bookManager.isShelfLoaded = false
        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)
        let item = makeRecentBookItem(id: "recent-current")

        shelfDataModel.setRecentShelfSnapshotForTesting(
            .init(books: [item]),
            sendLegacySubject: false
        )

        var iterator = shelfDataModel.recentSnapshots().makeAsyncIterator()
        let snapshot = await iterator.next()

        XCTAssertEqual(snapshot?.books, [item])
    }

    func testShelfDataModelRecentSnapshotsYieldBookUpdates() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        container.bookManager.isShelfLoaded = false
        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)
        let item = makeRecentBookItem(id: "recent-updated")

        var snapshots = [YabrShelfDataModel.RecentShelfSnapshot]()
        let task = Task { @MainActor in
            for await snapshot in shelfDataModel.recentSnapshots() {
                snapshots.append(snapshot)
                if snapshots.count == 2 { break }
            }
        }

        await Task.yield()
        shelfDataModel.setRecentShelfSnapshotForTesting(
            .init(books: [item]),
            sendLegacySubject: false
        )
        await waitForSnapshotCount(2, in: { snapshots.count })
        task.cancel()

        XCTAssertEqual(snapshots.last?.books, [item])
    }

    func testShelfDataModelRecentSnapshotsDoNotYieldDuplicateSnapshots() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        container.bookManager.isShelfLoaded = false
        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)

        var snapshots = [YabrShelfDataModel.RecentShelfSnapshot]()
        let task = Task { @MainActor in
            for await snapshot in shelfDataModel.recentSnapshots() {
                snapshots.append(snapshot)
            }
        }

        await waitForSnapshotCount(1, in: { snapshots.count })
        shelfDataModel.setRecentShelfSnapshotForTesting(
            .init(books: []),
            sendLegacySubject: false
        )
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        XCTAssertEqual(snapshots.count, 1)
    }

    func testShelfDataModelRecentSnapshotTerminationStopsUpdates() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        container.bookManager.isShelfLoaded = false
        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)

        var snapshots = [YabrShelfDataModel.RecentShelfSnapshot]()
        let task = Task { @MainActor in
            for await snapshot in shelfDataModel.recentSnapshots() {
                snapshots.append(snapshot)
            }
        }

        await waitForSnapshotCount(1, in: { snapshots.count })
        task.cancel()
        try await Task.sleep(nanoseconds: 50_000_000)

        shelfDataModel.setRecentShelfSnapshotForTesting(
            .init(books: [makeRecentBookItem(id: "recent-cancelled")]),
            sendLegacySubject: false
        )
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(snapshots.count, 1)
    }

    func testShelfDataModelLegacyRecentSubjectStillReceivesPublishedBooks() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        container.bookManager.isShelfLoaded = false
        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)
        let item = makeRecentBookItem(id: "recent-legacy")

        let expectation = XCTestExpectation(description: "Legacy recent subject receives books")
        container.recentShelfItemsSubject
            .sink { books in
                if books == [item] {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        shelfDataModel.setRecentShelfSnapshotForTesting(
            .init(books: [item]),
            sendLegacySubject: true
        )

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testShelfDataModelRecentRebuildSortsAndMapsStatuses() async throws {
        let container = makeAppContainer()
        let unifiedSearchService = try await makeUnifiedSearchService(container: container)
        container.unifiedSearchService = unifiedSearchService
        container.bookManager.isShelfLoaded = false

        let reachableServer = TestFixtures.makeServer(
            uuid: UUID(),
            name: "Reachable",
            baseUrl: "http://localhost/reachable"
        )
        let unreachableServer = TestFixtures.makeServer(
            uuid: UUID(),
            name: "Unreachable",
            baseUrl: "http://localhost/unreachable"
        )
        let localServer = TestFixtures.makeServer(
            uuid: CalibreServer.LocalServerUUID,
            name: "Local",
            baseUrl: "."
        )
        let reachableLibrary = TestFixtures.makeLibrary(server: reachableServer, key: "reachable", name: "Reachable")
        let unreachableLibrary = TestFixtures.makeLibrary(server: unreachableServer, key: "unreachable", name: "Unreachable")
        let localLibrary = TestFixtures.makeLibrary(server: localServer, key: "local", name: "Local")

        var progressBook = TestFixtures.makeBook(id: 501, library: reachableLibrary)
        progressBook.title = "Progress Book"
        progressBook.lastModified = Date(timeIntervalSince1970: 10)

        var downloadingBook = TestFixtures.makeBook(id: 502, library: reachableLibrary)
        downloadingBook.title = "Downloading Book"
        downloadingBook.lastModified = Date(timeIntervalSince1970: 4_000)

        var hasUpdateBook = TestFixtures.makeBook(id: 503, library: reachableLibrary)
        hasUpdateBook.title = "Has Update Book"
        hasUpdateBook.lastModified = Date(timeIntervalSince1970: 3_000)
        hasUpdateBook.formats[Format.EPUB.rawValue] = FormatInfo(
            selected: true,
            filename: "update.epub",
            serverSize: 1,
            serverMTime: Date(timeIntervalSince1970: 2_000),
            cached: true,
            cacheSize: 1,
            cacheMTime: Date(timeIntervalSince1970: 1_000),
            manifest: nil
        )

        var noConnectBook = TestFixtures.makeBook(id: 504, library: unreachableLibrary)
        noConnectBook.title = "No Connect Book"
        noConnectBook.lastModified = Date(timeIntervalSince1970: 2_000)

        var localBook = TestFixtures.makeBook(id: 505, library: localLibrary)
        localBook.title = "Local Book"
        localBook.lastModified = Date(timeIntervalSince1970: 1_000)

        let probeRequest = CalibreProbeServerRequest(
            server: reachableServer,
            isPublic: false,
            updateLibrary: false,
            autoUpdateOnly: false,
            incremental: false
        )
        let reachableInfo = CalibreServerInfo(
            server: reachableServer,
            isPublic: false,
            url: URL(string: reachableServer.baseUrl)!,
            reachable: true,
            probing: false,
            errorMsg: "Success",
            defaultLibrary: reachableLibrary.id,
            libraryMap: [reachableLibrary.id: reachableLibrary.name],
            request: probeRequest
        )
        container.calibreServerInfoStaging[reachableServer.uuid.uuidString] = reachableInfo

        let downloadURL = URL(string: "http://localhost/download.epub")!
        container.downloadManager.activeDownloads[downloadURL] = BookFormatDownload(
            isDownloading: true,
            progress: 0,
            book: downloadingBook,
            format: .EPUB,
            startDatetime: Date(),
            sourceURL: downloadURL,
            savedURL: URL(fileURLWithPath: "/tmp/download.epub"),
            modificationDate: Date()
        )

        let position = TestFixtures.makeReadingPosition(
            id: container.deviceName,
            lastProgress: 42,
            epoch: 5_000
        )
        container.readingPositionRepository.savePosition(position, for: progressBook)

        let shelfDataModel = YabrShelfDataModel(unifiedSearchService: unifiedSearchService, container: container)
        container.bookManager.booksInShelf = [
            progressBook.inShelfId: progressBook,
            downloadingBook.inShelfId: downloadingBook,
            hasUpdateBook.inShelfId: hasUpdateBook,
            noConnectBook.inShelfId: noConnectBook,
            localBook.inShelfId: localBook
        ]
        container.bookManager.isShelfLoaded = true
        container.publishCalibreUpdate(.shelf)

        await waitForRecentBooksCount(5, in: shelfDataModel)
        let books = shelfDataModel.currentRecentSnapshotForTesting().books

        XCTAssertEqual(books.map(\.id), [
            progressBook.inShelfId,
            downloadingBook.inShelfId,
            hasUpdateBook.inShelfId,
            noConnectBook.inShelfId,
            localBook.inShelfId
        ])
        XCTAssertEqual(books.first?.progress, 42)
        XCTAssertEqual(books.first(where: { $0.id == downloadingBook.inShelfId })?.status, .downloading)
        XCTAssertEqual(books.first(where: { $0.id == hasUpdateBook.inShelfId })?.status, .hasUpdate)
        XCTAssertEqual(books.first(where: { $0.id == noConnectBook.inShelfId })?.status, .noConnect)
        XCTAssertEqual(books.first(where: { $0.id == localBook.inShelfId })?.status, .local)
    }
    
    private func makeAppContainer() -> AppContainer {
        return MockAppContainerFactory.makeContainer(testName: "V2MigrationDependencyTests")
    }

    private func waitForShelfSignalProcessing(in shelfDataModel: YabrShelfDataModel) async throws {
        try await Task.sleep(nanoseconds: 100_000_000)
        _ = await shelfDataModel.categoryNamesForTesting()
    }

    private func makeShelfSection(id: String) -> ShelfSectionItem {
        ShelfSectionItem(
            id: id,
            title: id,
            books: [
                ShelfBookItem(
                    id: "\(id)-book",
                    title: "\(id) Book",
                    coverURL: "",
                    progress: 0,
                    status: .ready,
                    libraryId: "library-id"
                )
            ]
        )
    }

    private func makeRecentBookItem(id: String) -> ShelfBookItem {
        ShelfBookItem(
            id: id,
            title: "\(id) Book",
            coverURL: "",
            progress: 0,
            status: .ready
        )
    }

    private func waitForRecentBooksCount(
        _ expectedCount: Int,
        in shelfDataModel: YabrShelfDataModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<50 {
            if shelfDataModel.currentRecentSnapshotForTesting().books.count >= expectedCount { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertGreaterThanOrEqual(
            shelfDataModel.currentRecentSnapshotForTesting().books.count,
            expectedCount,
            file: file,
            line: line
        )
    }

    private func waitForSnapshotCount(
        _ expectedCount: Int,
        in count: @escaping () -> Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<50 {
            if count() >= expectedCount { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertGreaterThanOrEqual(count(), expectedCount, file: file, line: line)
    }

    private func waitForCategorySummaries(
        in viewModel: LibraryInfoView.ViewModel,
        matching predicate: @escaping ([CategoryCacheSummary]) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<50 {
            if predicate(viewModel.availableCategories) { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(predicate(viewModel.availableCategories), file: file, line: line)
    }
    
    private func makeUnifiedSearchService(container: AppContainer) async throws -> UnifiedSearchService {
        let repository = MockSearchCacheRepository()
        let libraryProvider = MockLibraryProvider()
        let logger = CalibreActivityLogger(realmConf: container.realmConf ?? Realm.Configuration())
        let service = CalibreServerService(logger: logger, config: container, database: DatabaseService.shared)
        
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
