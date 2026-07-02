//
//  ShelfDataManager.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/11/30.
//

import Foundation
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

    private enum InitialLoadState {
        case waitingForShelfSnapshot
        case loading(pendingCategoryKeys: Set<String>)
        case complete

        var isComplete: Bool {
            if case .complete = self {
                return true
            }
            return false
        }

        mutating func observeShelfSnapshot(categoryKeys: Set<String>) {
            switch self {
            case .waitingForShelfSnapshot:
                self = categoryKeys.isEmpty ? .complete : .loading(pendingCategoryKeys: categoryKeys)
            case .loading(let pendingCategoryKeys):
                let remaining = pendingCategoryKeys.intersection(categoryKeys)
                self = remaining.isEmpty ? .complete : .loading(pendingCategoryKeys: remaining)
            case .complete:
                break
            }
        }

        mutating func markCategoryComplete(_ categoryKey: String) {
            guard case .loading(let pendingCategoryKeys) = self else { return }
            let remaining = pendingCategoryKeys.subtracting([categoryKey])
            self = remaining.isEmpty ? .complete : .loading(pendingCategoryKeys: remaining)
        }
    }

    private var categories = [String: CategoryState]()
    private var initialLoadState: InitialLoadState = .waitingForShelfSnapshot

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

        let desiredCategoryKeys = Set(desiredCategoryNames.map { CategoryDescriptor(category: $0).categoryKey })
        initialLoadState.observeShelfSnapshot(categoryKeys: desiredCategoryKeys)
        return RebuildResult(
            categoriesToStart: categoryNamesToStart.sorted().map { CategoryDescriptor(category: $0) },
            categoryKeysToCancel: Set(categoryNamesToRemove.map { CategoryDescriptor(category: $0).categoryKey }),
            sectionIdsToRemove: Set(categoryNamesToRemove.map { CategoryDescriptor(category: $0).categoryKey }),
            initialLoadComplete: initialLoadState.isComplete
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

        if isDone {
            initialLoadState.markCategoryComplete(state.sectionId)
        }

        return UpdateResult(
            sectionItem: buildShelfSectionItem(from: state),
            initialLoadComplete: initialLoadState.isComplete
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
        let categoryKeys = Set(categories.values.map(\.sectionId))
        initialLoadState = categoryKeys.isEmpty ? .complete : .loading(pendingCategoryKeys: categoryKeys)
    }

    func categoryNamesForTesting() -> Set<String> {
        Set(categories.keys)
    }

    func initialLoadCompleteForTesting() -> Bool {
        initialLoadState.isComplete
    }

    func markInitialCategoryCompleteForTesting(category: String) -> Bool {
        initialLoadState.markCategoryComplete(CategoryDescriptor(category: category).categoryKey)
        return initialLoadState.isComplete
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

private actor RecentShelfBuilder {
    struct BuildContext: Sendable {
        let deviceName: String
        let reachableServerIds: Set<String>
        let downloadingBookIds: Set<String>
    }

    struct AutoDownloadRequest: Hashable, Sendable {
        let inShelfId: String
        let formatRawValue: String
    }

    struct BuildResult: Sendable {
        let books: [ShelfBookItem]
        let autoDownloadRequests: [AutoDownloadRequest]
    }

    func rebuild(
        booksInShelf: [String: CalibreBook],
        readingPositionRepository: ReadingPositionRepositoryProtocol,
        context: BuildContext
    ) throws -> BuildResult {
        var booksWithTS: [(key: String, value: CalibreBook, ts: Date, positions: [BookDeviceReadingPosition])] = []
        for (key, book) in booksInShelf {
            try Task.checkCancellation()
            let positions = readingPositionRepository.getPositions(for: book)
            let maxEpoch = positions.map { Date(timeIntervalSince1970: $0.epoch) }.max()
            let ts = max(book.lastModified, maxEpoch ?? book.lastUpdated)
            booksWithTS.append((key, book, ts, positions))
        }

        try Task.checkCancellation()
        var autoDownloadRequests = [AutoDownloadRequest]()
        var books = [ShelfBookItem]()
        for entry in booksWithTS.sorted(by: { $0.ts > $1.ts }) {
            try Task.checkCancellation()
            books.append(
                buildShelfBookItem(
                    entry: entry,
                    context: context,
                    autoDownloadRequests: &autoDownloadRequests
                )
            )
        }
        return BuildResult(books: books, autoDownloadRequests: autoDownloadRequests)
    }

    private func buildShelfBookItem(
        entry: (key: String, value: CalibreBook, ts: Date, positions: [BookDeviceReadingPosition]),
        context: BuildContext,
        autoDownloadRequests: inout [AutoDownloadRequest]
    ) -> ShelfBookItem {
        let inShelfId = entry.key
        let book = entry.value
        let positions = entry.positions
        let formatArray = Array(book.formats)

        let bookUptoDate = formatArray.allSatisfy { _, formatInfo in
            formatInfo.cached == false || (formatInfo.cached && formatInfo.cacheUptoDate)
        }
        let missingFormats = formatArray.filter { _, formatInfo in
            formatInfo.selected == true && formatInfo.cached == false
        }

        var status = ShelfBookStatus.ready
        if !context.reachableServerIds.contains(book.library.server.id) {
            status = .noConnect
        } else {
            for (formatRawValue, _) in missingFormats {
                autoDownloadRequests.append(.init(inShelfId: inShelfId, formatRawValue: formatRawValue))
            }

            if !bookUptoDate {
                status = .hasUpdate
            }
            if context.downloadingBookIds.contains(inShelfId) {
                status = .downloading
            }
        }
        if book.library.server.isLocal {
            status = .local
        }

        var lastProgress = 0.0
        if let position = ReadingPositionSelectionPolicy.latestForDevice(context.deviceName).select(from: positions) {
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

@MainActor
private final class ShelfSnapshotBroadcaster<Snapshot: Equatable> {
    private var continuations = [UUID: AsyncStream<Snapshot>.Continuation]()
    private var lastPublishedSnapshot: Snapshot?

    func stream(initialSnapshot: Snapshot) -> AsyncStream<Snapshot> {
        let id = UUID()
        lastPublishedSnapshot = initialSnapshot

        return AsyncStream { [weak self] continuation in
            continuation.yield(initialSnapshot)
            self?.continuations[id] = continuation

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    func publish(_ snapshot: Snapshot) {
        guard lastPublishedSnapshot != snapshot else { return }
        lastPublishedSnapshot = snapshot
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    func finish() {
        continuations.values.forEach { $0.finish() }
        continuations.removeAll()
    }
}

@MainActor
final class YabrShelfDataModel {

    struct RecentShelfSnapshot: Equatable, Sendable {
        let books: [ShelfBookItem]
    }

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

    final class CategoryObject: Hashable {

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
    private let recentShelfBuilder = RecentShelfBuilder()

    private var recentShelfItems = [ShelfBookItem]()
    private var discoverShelfItemsById = [String: ShelfSectionItem]()

    private var eventTask: Task<Void, Never>?
    private var initialSnapshotTask: Task<Void, Never>?
    private var recentRebuildTask: Task<Void, Never>?
    private var categorySearchTasks = [String: Task<Void, Never>]()
    private let recentSnapshotBroadcaster = ShelfSnapshotBroadcaster<RecentShelfSnapshot>()
    private let discoverSnapshotBroadcaster = ShelfSnapshotBroadcaster<DiscoverShelfSnapshot>()
    private var isFirstRecentShelfPublish = true

    private var isInitialLoadComplete = false

    init(unifiedSearchService: UnifiedSearchService, container: AppContainerProtocol) {
        self.unifiedSearchService = unifiedSearchService
        self.container = container

        startEventTask()
        initialSnapshotTask = Task { [weak self] in
            await Task.yield()
            guard let self = self else { return }
            if let snapshot = self.booksInShelfSnapshotIfNeeded(for: .shelf) {
                await self.rebuildShelfCategories(from: snapshot)
            }
            self.scheduleRecentShelfRebuildIfNeeded()
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
        recentRebuildTask?.cancel()
        categorySearchTasks.values.forEach { $0.cancel() }
        MainActor.assumeIsolated {
            recentSnapshotBroadcaster.finish()
            discoverSnapshotBroadcaster.finish()
        }
    }

    func recentSnapshots() -> AsyncStream<RecentShelfSnapshot> {
        recentSnapshotBroadcaster.stream(initialSnapshot: currentRecentSnapshot())
    }

    func snapshots() -> AsyncStream<DiscoverShelfSnapshot> {
        discoverSnapshotBroadcaster.stream(initialSnapshot: currentSnapshot())
    }

    private func startEventTask() {
        let signals = container.calibreUpdates()
        eventTask = Task { [weak self] in
            for await signal in signals {
                guard !Task.isCancelled else { return }
                await self?.handleCalibreUpdated(signal)
            }
        }
    }

    private func handleCalibreUpdated(_ signal: calibreUpdatedSignal) async {
        if let snapshot = booksInShelfSnapshotIfNeeded(for: signal) {
            await rebuildShelfCategories(from: snapshot)
        }
        scheduleRecentShelfRebuildIfNeeded()
    }

    private func scheduleRecentShelfRebuildIfNeeded() {
        guard container.bookManager.isShelfLoaded else { return }

        let booksInShelf = container.bookManager.booksInShelf
        let context = makeRecentShelfBuildContext(booksInShelf: booksInShelf)
        let readingPositionRepository = container.readingPositionRepository
        let builder = recentShelfBuilder
        let state = AppPerformanceSignpost.begin("RecentShelfRebuild")

        recentRebuildTask?.cancel()
        recentRebuildTask = Task { [weak self, booksInShelf, context, readingPositionRepository, builder, state] in
            do {
                let result = try await builder.rebuild(
                    booksInShelf: booksInShelf,
                    readingPositionRepository: readingPositionRepository,
                    context: context
                )
                guard !Task.isCancelled else {
                    AppPerformanceSignpost.end("RecentShelfRebuild", state)
                    return
                }
                self?.applyRecentShelfBuildResult(result, booksInShelf: booksInShelf, state: state)
            } catch is CancellationError {
                AppPerformanceSignpost.end("RecentShelfRebuild", state)
            } catch {
                AppPerformanceSignpost.end("RecentShelfRebuild", state)
            }
        }
    }

    private func makeRecentShelfBuildContext(booksInShelf: [String: CalibreBook]) -> RecentShelfBuilder.BuildContext {
        let reachableServerIds = Set(
            booksInShelf.values.compactMap { book in
                container.calibreServerService.getServerUrlByReachability(server: book.library.server) == nil
                    ? nil
                    : book.library.server.id
            }
        )
        let downloadingBookIds = Set(
            container.downloadManager.activeDownloads.values.compactMap { download in
                download.isDownloading ? download.book.inShelfId : nil
            }
        )
        return .init(
            deviceName: container.deviceName,
            reachableServerIds: reachableServerIds,
            downloadingBookIds: downloadingBookIds
        )
    }

    private func applyRecentShelfBuildResult(
        _ result: RecentShelfBuilder.BuildResult,
        booksInShelf: [String: CalibreBook],
        state: OSSignpostIntervalState
    ) {
        AppPerformanceSignpost.end("RecentShelfRebuild", state)
        if isFirstRecentShelfPublish {
            isFirstRecentShelfPublish = false
            AppPerformanceSignpost.emit("FirstRecentShelfPublish")
        }

        for request in result.autoDownloadRequests {
            guard let book = booksInShelf[request.inShelfId],
                  let format = Format(rawValue: request.formatRawValue)
            else { continue }
            container.downloadManager.requestDownload(book: book, format: format)
        }

        recentShelfItems = result.books
        publishRecentShelfSnapshot(sendLegacySubject: true)
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
            if discoverShelfItemsById[sectionItem.id] != sectionItem {
                discoverShelfItemsById[sectionItem.id] = sectionItem
                notifyDiscoverShelfChanged()
            }
        } else if discoverShelfItemsById.removeValue(forKey: sectionItem.id) != nil {
            notifyDiscoverShelfChanged()
        }
    }

    private func removeDiscoverSections(ids: Set<String>) {
        var didRemove = false
        for id in ids {
            if discoverShelfItemsById.removeValue(forKey: id) != nil {
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

    func initialLoadCompleteForTesting() async -> Bool {
        await categoryStore.initialLoadCompleteForTesting()
    }

    func markInitialCategoryCompleteForTesting(category: String) async -> Bool {
        await categoryStore.markInitialCategoryCompleteForTesting(category: category)
    }

    func categorySearchTaskKeysForTesting() -> Set<String> {
        Set(categorySearchTasks.keys)
    }

    func setDiscoverShelfSnapshotForTesting(_ snapshot: DiscoverShelfSnapshot, sendLegacySubject: Bool = true) {
        discoverShelfItemsById = Dictionary(uniqueKeysWithValues: snapshot.sections.map { ($0.id, $0) })
        isInitialLoadComplete = snapshot.isInitialLoadComplete
        publishDiscoverShelfSnapshot(sendLegacySubject: sendLegacySubject)
    }

    func setRecentShelfSnapshotForTesting(_ snapshot: RecentShelfSnapshot, sendLegacySubject: Bool = true) {
        recentShelfItems = snapshot.books
        publishRecentShelfSnapshot(sendLegacySubject: sendLegacySubject)
    }

    func currentRecentSnapshotForTesting() -> RecentShelfSnapshot {
        currentRecentSnapshot()
    }

    func currentDiscoverSnapshotForTesting() -> DiscoverShelfSnapshot {
        currentSnapshot()
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

    private func currentRecentSnapshot() -> RecentShelfSnapshot {
        RecentShelfSnapshot(books: recentShelfItems)
    }

    private func currentSnapshot() -> DiscoverShelfSnapshot {
        DiscoverShelfSnapshot(
            sections: discoverShelfItemsById.values.sorted(by: { $0.title < $1.title }),
            isInitialLoadComplete: isInitialLoadComplete
        )
    }

    private func publishRecentShelfSnapshot(sendLegacySubject: Bool) {
        let snapshot = currentRecentSnapshot()
        recentSnapshotBroadcaster.publish(snapshot)
        if sendLegacySubject {
            container.publishLegacyRecentShelfItems(snapshot.books)
        }
    }

    private func publishDiscoverShelfSnapshot(sendLegacySubject: Bool) {
        let snapshot = currentSnapshot()
        discoverSnapshotBroadcaster.publish(snapshot)
        if sendLegacySubject {
            container.publishLegacyDiscoverShelfItems(snapshot.sections)
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
