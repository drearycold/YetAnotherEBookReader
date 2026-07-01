//
//  ShelfDataManager.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/11/30.
//

import Foundation
import Combine
import OSLog

private actor ShelfCategoryStore {
    struct CategoryDescriptor: Hashable {
        let category: String

        var categoryKey: String {
            "Author: \(category)"
        }

        var searchKey: SearchCriteriaMergedKey {
            SearchCriteriaMergedKey(
                libraryIds: [],
                criteria: SearchCriteria(
                    searchString: "",
                    sortCriteria: .init(),
                    filterCriteriaCategory: ["Authors": Set([category])]
                )
            )
        }
    }

    struct RebuildResult {
        let categoriesToStart: [CategoryDescriptor]
        let categoryKeysToCancel: Set<String>
        let sectionIdsToRemove: Set<String>
        let initialLoadComplete: Bool
    }

    struct UpdateResult {
        let sectionItem: ShelfSectionItem
        let initialLoadComplete: Bool
    }

    struct CategorySeed: Sendable {
        let category: String
        let inShelfBookIds: Set<String>
        let unifiedSearchResult: UnifiedSearchResult?
    }

    private struct CategoryState {
        let category: String
        var inShelfBookIds: Set<String>
        var unifiedSearchResult: UnifiedSearchResult?

        var descriptor: CategoryDescriptor {
            CategoryDescriptor(category: category)
        }

        var sectionId: String {
            descriptor.categoryKey
        }
    }

    private var categories = [String: CategoryState]()
    private var initialCategories = Set<String>()
    private var completedInitialCategories = Set<String>()
    private var shelfSnapshotComplete = false
    private var isInitialLoadComplete = false

    func rebuild(from booksInShelf: [String: CalibreBook]) -> RebuildResult {
        var categoryBookIds = [String: Set<String>]()
        for (inShelfId, book) in booksInShelf {
            for categoryName in authorCategories(for: book) {
                categoryBookIds[categoryName, default: []].insert(inShelfId)
            }
        }

        let existingCategoryNames = Set(categories.keys)
        let desiredCategoryNames = Set(categoryBookIds.keys)
        let categoryNamesToRemove = existingCategoryNames.subtracting(desiredCategoryNames)
        let categoryNamesToStart = desiredCategoryNames.subtracting(existingCategoryNames)

        for categoryName in categoryNamesToRemove {
            categories.removeValue(forKey: categoryName)
        }

        for categoryName in desiredCategoryNames {
            let bookIds = categoryBookIds[categoryName] ?? []
            if var state = categories[categoryName] {
                state.inShelfBookIds = bookIds
                categories[categoryName] = state
            } else {
                categories[categoryName] = CategoryState(category: categoryName, inShelfBookIds: bookIds)
            }
        }

        let initialKeys = Set(desiredCategoryNames.map { CategoryDescriptor(category: $0).categoryKey })
        initialCategories = initialKeys
        completedInitialCategories.formIntersection(initialKeys)
        shelfSnapshotComplete = true

        let initialLoadComplete = computeInitialLoadComplete()
        return RebuildResult(
            categoriesToStart: categoryNamesToStart.sorted().map { CategoryDescriptor(category: $0) },
            categoryKeysToCancel: Set(categoryNamesToRemove.map { CategoryDescriptor(category: $0).categoryKey }),
            sectionIdsToRemove: Set(categoryNamesToRemove.map { CategoryDescriptor(category: $0).categoryKey }),
            initialLoadComplete: initialLoadComplete
        )
    }

    func apply(update: SearchUpdate, category: String, activeLibraryIds: Set<String>) -> UpdateResult? {
        guard var state = categories[category] else { return nil }
        state.unifiedSearchResult = update.result
        categories[category] = state

        let isDone: Bool = {
            if activeLibraryIds.isEmpty {
                return true
            }
            if update.statuses.isEmpty {
                return false
            }
            return update.statuses.values.allSatisfy { !$0.loading }
        }()

        if isDone && initialCategories.contains(state.sectionId) {
            completedInitialCategories.insert(state.sectionId)
        }

        return UpdateResult(
            sectionItem: buildShelfSectionItem(from: state),
            initialLoadComplete: computeInitialLoadComplete()
        )
    }

    func categoryKeysForRefresh() -> [SearchCriteriaMergedKey] {
        categories.values
            .sorted {
                $0.category < $1.category
            }
            .map { $0.descriptor.searchKey }
    }

    func seedCategoriesForTesting(_ seeds: [CategorySeed]) {
        categories = Dictionary(
            uniqueKeysWithValues: seeds.map { seed in
                (
                    seed.category,
                    CategoryState(
                        category: seed.category,
                        inShelfBookIds: seed.inShelfBookIds,
                        unifiedSearchResult: seed.unifiedSearchResult
                    )
                )
            }
        )
        initialCategories = Set(categories.values.map(\.sectionId))
        completedInitialCategories = []
        shelfSnapshotComplete = true
        isInitialLoadComplete = categories.isEmpty
    }

    func categoryNamesForTesting() -> Set<String> {
        Set(categories.keys)
    }

    private func computeInitialLoadComplete() -> Bool {
        guard shelfSnapshotComplete else { return false }
        guard !isInitialLoadComplete else { return true }
        if initialCategories.subtracting(completedInitialCategories).isEmpty {
            isInitialLoadComplete = true
        }
        return isInitialLoadComplete
    }

    private func authorCategories(for book: CalibreBook) -> [String] {
        let authors = book.authors.isEmpty ? ["Unknown"] : book.authors
        return Array(authors.prefix(3))
    }

    private func buildShelfSectionItem(from state: CategoryState) -> ShelfSectionItem {
        let books: [ShelfBookItem] = state.unifiedSearchResult?.books.map {
            ShelfBookItem(
                id: $0.inShelfId,
                title: $0.title,
                coverURL: $0.coverURL?.absoluteString ?? "",
                progress: 0,
                status: .ready,
                libraryId: $0.library.id
            )
        } ?? []

        return ShelfSectionItem(id: state.sectionId, title: state.sectionId, books: books)
    }
}

@MainActor
class YabrShelfDataModel: ObservableObject {

    struct DiscoverShelfSnapshot: Equatable, Sendable {
        let sections: [ShelfSectionItem]
        let isInitialLoadComplete: Bool
    }

    enum CategoryType: String {
        case Last
        case Author
        case Series
        case Tag
    }

    class CategoryObject: ObservableObject, Hashable {

        let type: CategoryType
        let category: String

        var inShelfBookIds: Set<String> = []

        var unifiedSearchResult: UnifiedSearchResult?

        init(type: CategoryType, category: String) {
            self.type = type
            self.category = category
        }

        func hash(into: inout Hasher) {
            into.combine(type)
            into.combine(category)
        }

        static func == (lhs: YabrShelfDataModel.CategoryObject, rhs: YabrShelfDataModel.CategoryObject) -> Bool {
            lhs.type == rhs.type && lhs.category == rhs.category
        }

    }
    private let unifiedSearchService: UnifiedSearchService
    private let container: AppContainerProtocol
    private let categoryStore = ShelfCategoryStore()

    @Published var discoverShelfItems = [String: ShelfSectionItem]()

    private var eventTask: Task<Void, Never>?
    private var initialSnapshotTask: Task<Void, Never>?
    private var categorySearchTasks = [String: Task<Void, Never>]()
    private var snapshotContinuations = [UUID: AsyncStream<DiscoverShelfSnapshot>.Continuation]()
    private var lastPublishedSnapshot: DiscoverShelfSnapshot?

    @Published var isInitialLoadComplete = false

    init(unifiedSearchService: UnifiedSearchService, container: AppContainerProtocol) {
        self.unifiedSearchService = unifiedSearchService
        self.container = container

        startEventTask()
        initialSnapshotTask = Task { [weak self] in
            await Task.yield()
            guard let self = self else { return }
            guard let snapshot = self.booksInShelfSnapshotIfNeeded(for: .shelf) else { return }
            await self.rebuildShelfCategories(from: snapshot)
        }
    }

    private func booksInShelfSnapshotIfNeeded(for signal: calibreUpdatedSignal) -> [String: CalibreBook]? {
        switch signal {
        case .shelf, .book, .deleted:
            guard container.bookManager.isShelfLoaded else { return nil }
            return container.bookManager.booksInShelf
        case .library, .server:
            return nil
        }
    }

    deinit {
        eventTask?.cancel()
        initialSnapshotTask?.cancel()
        categorySearchTasks.values.forEach { $0.cancel() }
        snapshotContinuations.values.forEach { $0.finish() }
    }

    func snapshots() -> AsyncStream<DiscoverShelfSnapshot> {
        let id = UUID()
        let initialSnapshot = currentSnapshot()

        return AsyncStream { [weak self] continuation in
            continuation.yield(initialSnapshot)
            self?.snapshotContinuations[id] = continuation

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.snapshotContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    private func startEventTask() {
        let signals = container.calibreUpdatedSubject.values
        eventTask = Task { [weak self] in
            for await signal in signals {
                guard !Task.isCancelled else { return }
                await self?.handleCalibreUpdated(signal)
            }
        }
    }

    private func handleCalibreUpdated(_ signal: calibreUpdatedSignal) async {
        guard let snapshot = booksInShelfSnapshotIfNeeded(for: signal) else { return }
        await rebuildShelfCategories(from: snapshot)
    }

    private func rebuildShelfCategories(from booksInShelf: [String: CalibreBook]) async {
        let result = await categoryStore.rebuild(from: booksInShelf)
        synchronizeCategorySearchTasks(with: result)
        removeDiscoverSections(ids: result.sectionIdsToRemove)
        if result.initialLoadComplete {
            markInitialLoadComplete()
        }
    }

    private func synchronizeCategorySearchTasks(with result: ShelfCategoryStore.RebuildResult) {
        for categoryKey in result.categoryKeysToCancel {
            categorySearchTasks.removeValue(forKey: categoryKey)?.cancel()
        }
        for descriptor in result.categoriesToStart where categorySearchTasks[descriptor.categoryKey] == nil {
            startCategorySearchTask(for: descriptor)
        }
    }

    private func startCategorySearchTask(for descriptor: ShelfCategoryStore.CategoryDescriptor) {
        let searchService = unifiedSearchService
        categorySearchTasks[descriptor.categoryKey] = Task { [weak self] in
            let stream = await searchService.search(key: descriptor.searchKey)
            for await update in stream {
                guard !Task.isCancelled else { return }
                await self?.handleCategorySearchUpdate(update, descriptor: descriptor)
            }
        }
    }

    private func handleCategorySearchUpdate(
        _ update: SearchUpdate,
        descriptor: ShelfCategoryStore.CategoryDescriptor
    ) async {
        let activeLibraryIds = Set(
            container.libraryManager.calibreLibraries
                .filter { !$0.value.hidden && !$0.value.server.removed }
                .keys
        )
        guard let result = await categoryStore.apply(
            update: update,
            category: descriptor.category,
            activeLibraryIds: activeLibraryIds
        ) else {
            return
        }

        applyDiscoverSectionUpdate(result.sectionItem)
        if result.initialLoadComplete {
            markInitialLoadComplete()
        }
    }

    private func applyDiscoverSectionUpdate(_ sectionItem: ShelfSectionItem) {
        if sectionItem.books.count > 1 {
            if discoverShelfItems[sectionItem.id] != sectionItem {
                discoverShelfItems[sectionItem.id] = sectionItem
                notifyDiscoverShelfChanged()
            }
        } else if discoverShelfItems.removeValue(forKey: sectionItem.id) != nil {
            notifyDiscoverShelfChanged()
        }
    }

    private func removeDiscoverSections(ids: Set<String>) {
        var didRemove = false
        for id in ids {
            if discoverShelfItems.removeValue(forKey: id) != nil {
                didRemove = true
            }
        }
        if didRemove {
            notifyDiscoverShelfChanged()
        }
    }

    private func markInitialLoadComplete() {
        guard !isInitialLoadComplete else { return }
        isInitialLoadComplete = true
        publishDiscoverShelfSnapshot(sendLegacySubject: false)
    }

    func seedCategoriesForTesting(_ categories: [CategoryObject]) async {
        let seeds = categories.map {
            ShelfCategoryStore.CategorySeed(
                category: $0.category,
                inShelfBookIds: $0.inShelfBookIds,
                unifiedSearchResult: $0.unifiedSearchResult
            )
        }
        await categoryStore.seedCategoriesForTesting(seeds)
    }

    func categoryNamesForTesting() async -> Set<String> {
        await categoryStore.categoryNamesForTesting()
    }

    func categorySearchTaskKeysForTesting() -> Set<String> {
        Set(categorySearchTasks.keys)
    }

    func setDiscoverShelfSnapshotForTesting(_ snapshot: DiscoverShelfSnapshot, sendLegacySubject: Bool = true) {
        discoverShelfItems = Dictionary(uniqueKeysWithValues: snapshot.sections.map { ($0.id, $0) })
        isInitialLoadComplete = snapshot.isInitialLoadComplete
        publishDiscoverShelfSnapshot(sendLegacySubject: sendLegacySubject)
    }

    func buildShelfSectionItem(category: CategoryObject) -> ShelfSectionItem {
        let sectionName = "\(category.type.rawValue): \(category.category)"

        let books: [ShelfBookItem] = category.unifiedSearchResult?.books.map {
            ShelfBookItem(
                id: $0.inShelfId,
                title: $0.title,
                coverURL: $0.coverURL?.absoluteString ?? "",
                progress: 0,
                status: .ready,
                libraryId: $0.library.id
            )
        } ?? []

        return ShelfSectionItem(id: sectionName, title: sectionName, books: books)
    }

    private func notifyDiscoverShelfChanged() {
        publishDiscoverShelfSnapshot(sendLegacySubject: true)
    }

    private func currentSnapshot() -> DiscoverShelfSnapshot {
        DiscoverShelfSnapshot(
            sections: discoverShelfItems.values.sorted(by: { $0.title < $1.title }),
            isInitialLoadComplete: isInitialLoadComplete
        )
    }

    private func publishDiscoverShelfSnapshot(sendLegacySubject: Bool) {
        let snapshot = currentSnapshot()
        if lastPublishedSnapshot != snapshot {
            lastPublishedSnapshot = snapshot
            for continuation in snapshotContinuations.values {
                continuation.yield(snapshot)
            }
        }
        if sendLegacySubject {
            container.discoverShelfItemsSubject.send(snapshot.sections)
        }
    }

    func refresh() async {
        let keys = await categoryStore.categoryKeysForRefresh()
        for key in keys {
            guard !Task.isCancelled else { return }
            await unifiedSearchService.resetSearchAndWait(for: key, force: true)
        }
    }
}

extension AppContainerProtocol where Self: ObservableObject {
    func registerRecentShelfUpdater() {
        let queue = DispatchQueue(label: "recent-shelf-updater", qos: .userInitiated)
        let box = RecentShelfFirstPublishBox()
        calibreUpdatedSubject
            .receive(on: RunLoop.main)
            .compactMap { [weak self] _ -> ([String: CalibreBook], OSSignpostIntervalState)? in
                guard let self = self else { return nil }
                guard self.bookManager.isShelfLoaded else {
                    return nil
                }
                let snapshot = self.bookManager.booksInShelf
                let state = AppPerformanceSignpost.begin("RecentShelfRebuild")
                return (snapshot, state)
            }
            .receive(on: queue)
            .map { [weak self] (booksInShelf: [String: CalibreBook], state: OSSignpostIntervalState) -> ([ShelfBookItem], OSSignpostIntervalState) in
                guard let self = self else { return ([], state) }
                let readingPositionRepository = self.readingPositionRepository
                var booksWithTS: [(key: String, value: CalibreBook, ts: Date, positions: [BookDeviceReadingPosition])] = []
                for (key, book) in booksInShelf {
                    let positions = readingPositionRepository.getPositions(for: book)
                    let maxEpoch: Date? = positions.map { p in Date(timeIntervalSince1970: p.epoch) }.max()
                    let ts: Date = max(book.lastModified, maxEpoch ?? book.lastUpdated)
                    booksWithTS.append((key, book, ts, positions))
                }

                let sorted = booksWithTS.sorted { lhs, rhs in
                    return lhs.ts > rhs.ts
                }

                let items = sorted.map { entry in
                    self.buildShelfBookItem(entry: entry)
                }
                return (items, state)
            }
            .receive(on: RunLoop.main)
            .sink(receiveValue: { (displayBooks, state) in
                AppPerformanceSignpost.end("RecentShelfRebuild", state)
                if box.isFirstPublish {
                    box.isFirstPublish = false
                    AppPerformanceSignpost.emit("FirstRecentShelfPublish")
                }
                self.recentShelfItemsSubject.send(displayBooks)
            })
            .store(in: &calibreCancellables)
    }
}

extension AppContainerProtocol where Self: ObservableObject {
    private func buildShelfBookItem(entry: (key: String, value: CalibreBook, ts: Date, positions: [BookDeviceReadingPosition])) -> ShelfBookItem {
        let inShelfId = entry.key
        let book = entry.value
        let positions = entry.positions

        let formats: [String: FormatInfo] = book.formats
        let formatArray: [(String, FormatInfo)] = Array(formats)

        var bookUptoDate = true
        for (_, formatInfo) in formatArray {
            if !(formatInfo.cached == false || (formatInfo.cached && formatInfo.cacheUptoDate)) {
                bookUptoDate = false
                break
            }
        }

        var missingFormats: [String: FormatInfo] = [:]
        for (key, formatInfo) in formatArray where formatInfo.selected == true && formatInfo.cached == false {
            missingFormats[key] = formatInfo
        }

        var status = ShelfBookStatus.ready
        if self.calibreServerService.getServerUrlByReachability(server: book.library.server) == nil {
            status = .noConnect
        } else {
            missingFormats.forEach {
                guard let format = Format(rawValue: $0.key) else { return }
                self.downloadManager.bookFormatDownloadSubject.send((book: book, format: format))
            }

            if !bookUptoDate {
                status = .hasUpdate
            }
            if self.downloadManager.activeDownloads.contains(where: { (url, download) in
                download.isDownloading && download.book.inShelfId == inShelfId
            }) {
                status = .downloading
            }
        }
        if book.library.server.isLocal {
            status = .local
        }

        var lastProgress = 0.0
        if let position = ReadingPositionSelectionPolicy.latestForDevice(self.deviceName).select(from: positions) {
            lastProgress = position.lastProgress
        } else if let position = ReadingPositionSelectionPolicy.latest.select(from: positions) {
            lastProgress = position.lastProgress
        }

        return ShelfBookItem(
            id: inShelfId,
            title: book.title,
            coverURL: book.coverURL?.absoluteString ?? "",
            progress: Int(floor(lastProgress)),
            status: status
        )
    }
}

class RecentShelfFirstPublishBox {
    var isFirstPublish = true
}
