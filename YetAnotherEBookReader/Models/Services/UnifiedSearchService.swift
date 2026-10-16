//
//  UnifiedSearchService.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-11.
//

import Foundation

actor UnifiedSearchService {
    private let mergeService: UnifiedSearchMergeService
    private let repository: SearchCacheRepository
    private let librarySearchService: LibrarySearchService
    private let libraryProvider: LibraryProvider

    // In-memory active searches
    private var activeSearches: [SearchCriteriaMergedKey: ActiveSearch] = [:]

    // Continuations to yield updates
    private var resultContinuations: [SearchCriteriaMergedKey: [UUID: AsyncStream<SearchUpdate>.Continuation]] = [:]

    // Active search tasks
    private var searchTasks: [SearchCriteriaMergedKey: Task<Void, Never>] = [:]

    private var isServerReachableProvider: (@Sendable (CalibreServer, Bool) -> Bool?)?
    private var isServerReachableNoPublicProvider: (@Sendable (CalibreServer) -> Bool)?

    struct ActiveSearch {
        let criteria: SearchCriteria
        let libraryIds: Set<String>
        var currentResult: UnifiedSearchResult
        var libraryStatuses: [String: LibrarySearchStatus]
        var forceMetadataRefreshForLoadedBooks: Bool
        /// Each library's books as last read: this search's answer, or the library's search cache
        /// until the answer arrives, and when the search fails.
        var libraryResults: [String: SourcedResult] = [:]
        /// The latest search for the key. A replaced search's results are dropped.
        var searchId = UUID()
    }

    /// A library's books, and the search cache source (the server URL) they were read through.
    struct SourcedResult: Equatable {
        let source: String
        let result: LibrarySourceSearchResult
    }

    init(
        mergeService: UnifiedSearchMergeService = UnifiedSearchMergeService(),
        repository: SearchCacheRepository,
        librarySearchService: LibrarySearchService,
        libraryProvider: LibraryProvider
    ) {
        self.mergeService = mergeService
        self.repository = repository
        self.librarySearchService = librarySearchService
        self.libraryProvider = libraryProvider
    }

    func setReachabilityProviders(
        reachable: @escaping @Sendable (CalibreServer, Bool) -> Bool?,
        reachableNoPublic: @escaping @Sendable (CalibreServer) -> Bool
    ) {
        self.isServerReachableProvider = reachable
        self.isServerReachableNoPublicProvider = reachableNoPublic
    }

    func search(key: SearchCriteriaMergedKey, force: Bool = false) -> AsyncStream<SearchUpdate> {
        let id = UUID()
        return AsyncStream { continuation in
            let continuationWrapper = continuation

            continuation.onTermination = { [weak self, id, key] _ in
                Task { [self, id, key] in
                    await self?.removeContinuation(key: key, id: id)
                }
            }

            Task {
                await self.addContinuation(key: key, id: id, continuation: continuationWrapper)
                await self.triggerSearch(for: key, force: force)
            }
        }
    }

    func getActiveSearch(for key: SearchCriteriaMergedKey) -> UnifiedSearchResult? {
        return activeSearches[key]?.currentResult
    }

    func expandLimit(for key: SearchCriteriaMergedKey, by increment: Int = 100) {
        guard var activeSearch = activeSearches[key] else { return }
        activeSearch.currentResult.limitNumber += increment
        activeSearches[key] = activeSearch

        Task {
            await triggerSearch(for: key, force: false)
        }
    }

    func setLimit(for key: SearchCriteriaMergedKey, limit: Int) {
        guard var activeSearch = activeSearches[key] else { return }
        guard activeSearch.currentResult.limitNumber != limit else { return }
        activeSearch.currentResult.limitNumber = limit
        activeSearches[key] = activeSearch

        Task {
            await triggerSearch(for: key, force: false)
        }
    }

    func resetSearch(for key: SearchCriteriaMergedKey, force: Bool = false) {
        guard prepareSearchReset(for: key) else { return }

        Task {
            _ = await triggerSearch(for: key, force: force)
        }
    }

    func resetSearchAndWait(for key: SearchCriteriaMergedKey, force: Bool = false) async {
        guard prepareSearchReset(for: key) else { return }

        let task = await triggerSearch(for: key, force: force)
        await task.value
    }

    private func prepareSearchReset(for key: SearchCriteriaMergedKey) -> Bool {
        guard var activeSearch = activeSearches[key] else { return false }
        activeSearch.currentResult.books.removeAll()
        activeSearch.currentResult.limitNumber = 100
        for libraryId in activeSearch.currentResult.libraryIds {
            activeSearch.currentResult.unifiedOffsets[libraryId] = MergeOffset(
                beenCutOff: false,
                beenConsumed: false,
                offset: 0
            )
        }
        activeSearches[key] = activeSearch
        return true
    }

    // MARK: - Private Coordination

    private func addContinuation(
        key: SearchCriteriaMergedKey,
        id: UUID,
        continuation: AsyncStream<SearchUpdate>.Continuation
    ) {
        var list = resultContinuations[key] ?? [:]
        list[id] = continuation
        resultContinuations[key] = list
    }

    private func removeContinuation(key: SearchCriteriaMergedKey, id: UUID) {
        var list = resultContinuations[key] ?? [:]
        list.removeValue(forKey: id)
        if list.isEmpty {
            resultContinuations.removeValue(forKey: key)
            searchTasks[key]?.cancel()
            searchTasks.removeValue(forKey: key)
        } else {
            resultContinuations[key] = list
        }
    }

    private func emitUpdate(for key: SearchCriteriaMergedKey) {
        guard let activeSearch = activeSearches[key] else { return }
        let update = SearchUpdate(result: activeSearch.currentResult, statuses: activeSearch.libraryStatuses)

        guard let continuations = resultContinuations[key] else { return }
        for continuation in continuations.values {
            continuation.yield(update)
        }
    }

    @discardableResult
    private func triggerSearch(for key: SearchCriteriaMergedKey, force: Bool) async -> Task<Void, Never> {
        let activeLibraryIds = await getTargetLibraryIds(for: key)
        let libraries = await getLibraries()
        let targetLibraries = activeLibraryIds.compactMap { libraries[$0] }

        // Until a library answers, show what its search cache has.
        var cachedResults = [String: SourcedResult]()
        for library in targetLibraries where activeSearches[key]?.libraryResults[library.id] == nil {
            cachedResults[library.id] = await cachedResult(for: library, key: key)
        }

        // Nothing suspends from here on, so no other call changes the search meanwhile.
        searchTasks[key]?.cancel()

        var activeSearch = activeSearches[key] ?? {
            var initialStatuses: [String: LibrarySearchStatus] = [:]
            for libraryId in activeLibraryIds {
                initialStatuses[libraryId] = LibrarySearchStatus(loading: false, error: nil)
            }
            let initialResult = UnifiedSearchResult(
                search: key.criteria.searchString,
                sortBy: key.criteria.sortCriteria.by,
                sortAsc: key.criteria.sortCriteria.ascending,
                filters: key.criteria.filterCriteriaCategory,
                libraryIds: key.libraryIds,
                unifiedOffsets: [:],
                totalNumber: 0,
                limitNumber: 100,
                books: []
            )
            return ActiveSearch(
                criteria: key.criteria,
                libraryIds: key.libraryIds,
                currentResult: initialResult,
                libraryStatuses: initialStatuses,
                forceMetadataRefreshForLoadedBooks: false
            )
        }()

        if force {
            activeSearch.forceMetadataRefreshForLoadedBooks = true
        } else if activeSearch.currentResult.books.isEmpty {
            activeSearch.forceMetadataRefreshForLoadedBooks = false
        }

        activeSearch.libraryResults.merge(cachedResults) { current, _ in current }
        for libraryId in activeLibraryIds {
            activeSearch.libraryStatuses[libraryId] = LibrarySearchStatus(loading: true, error: nil)
        }
        let searchId = UUID()
        activeSearch.searchId = searchId
        activeSearch.currentResult = merge(activeSearch, libraryIds: activeLibraryIds)
        activeSearches[key] = activeSearch
        emitUpdate(for: key)

        let limit = activeSearch.currentResult.limitNumber
        let forceMetadataRefresh = activeSearch.forceMetadataRefreshForLoadedBooks

        let searchTask = Task {
            await withTaskGroup(of: (String, Result<LibraryCachedResult, Error>).self) { group in
                for library in targetLibraries {
                    group.addTask {
                        do {
                            let result = try await self.librarySearchService.searchAndFetchMetadata(
                                library: library,
                                criteria: key.criteria,
                                limit: limit,
                                force: force,
                                forceMetadataRefresh: forceMetadataRefresh
                            )
                            return (library.id, .success(result))
                        } catch {
                            return (library.id, .failure(error))
                        }
                    }
                }

                for await (libraryId, result) in group {
                    guard !Task.isCancelled else { break }
                    await self.handleLibrarySearchResult(key: key, searchId: searchId, libraryId: libraryId, result: result)
                }
            }

            await self.finishSearch(for: key, searchId: searchId)
        }

        searchTasks[key] = searchTask
        return searchTask
    }

    private func handleLibrarySearchResult(
        key: SearchCriteriaMergedKey,
        searchId: UUID,
        libraryId: String,
        result: Result<LibraryCachedResult, Error>
    ) async {
        let library = await getLibraries()[libraryId]
        let targetLibraryIds = await getTargetLibraryIds(for: key)

        var answer: SourcedResult?
        var searchError: SearchError?
        switch result {
        case .success(let cachedResult):
            if let library {
                let source = await librarySearchService.getTargetSource(for: library)
                answer = cachedResult.sources[source].map { SourcedResult(source: source, result: $0) }
            }
        case .failure(let error):
            if let sErr = error as? SearchError {
                searchError = sErr
            } else if error is CancellationError {
                searchError = .cancelled
            } else {
                searchError = .invalidState(error.localizedDescription)
            }
        }

        // A library whose search failed shows what its search cache has.
        var fallback: SourcedResult?
        if searchError != nil, activeSearches[key]?.libraryResults[libraryId] == nil, let library {
            fallback = await cachedResult(for: library, key: key)
        }

        // Nothing suspends from here on, so no other call changes the search meanwhile.
        guard var activeSearch = activeSearches[key], activeSearch.searchId == searchId else { return }

        if let sourced = answer ?? fallback {
            activeSearch.libraryResults[libraryId] = sourced
        }
        activeSearch.libraryStatuses[libraryId] = LibrarySearchStatus(
            loading: false,
            error: searchError,
            fromCache: searchError != nil && activeSearch.libraryResults[libraryId] != nil
        )
        activeSearch.currentResult = merge(activeSearch, libraryIds: targetLibraryIds)

        activeSearches[key] = activeSearch
        emitUpdate(for: key)
    }

    private func finishSearch(for key: SearchCriteriaMergedKey, searchId: UUID) {
        // A replaced search leaves the statuses to the one that replaced it.
        guard var activeSearch = activeSearches[key], activeSearch.searchId == searchId else { return }
        for libraryId in activeSearch.libraryStatuses.keys {
            if activeSearch.libraryStatuses[libraryId]?.loading == true {
                activeSearch.libraryStatuses[libraryId]?.loading = false
            }
        }
        activeSearches[key] = activeSearch
        emitUpdate(for: key)
    }

    /// Merges the target libraries' books. A library whose search failed has no more to give, so
    /// the books its cache had don't hold back the others': `UnifiedSearchMergeService` stops at a
    /// library with more to load.
    private func merge(_ activeSearch: ActiveSearch, libraryIds: Set<String>) -> UnifiedSearchResult {
        var libraryResults = [String: LibrarySourceSearchResult]()
        var librarySources = [String: String]()
        for libraryId in libraryIds {
            guard let sourced = activeSearch.libraryResults[libraryId] else { continue }
            var result = sourced.result
            if activeSearch.libraryStatuses[libraryId]?.failure != nil {
                result.totalNumber = result.books.count
            }
            libraryResults[libraryId] = result
            librarySources[libraryId] = sourced.source
        }
        return mergeService.merge(
            libraryResults: libraryResults,
            librarySources: librarySources,
            currentResult: activeSearch.currentResult
        )
    }

    /// The library's search cache for `key`, read through the URL its server is reached by, or else
    /// the newest of its other URLs': a server that can't be reached is looked up by its base URL,
    /// though its books may have been read through its public one.
    private func cachedResult(for library: CalibreLibrary, key: SearchCriteriaMergedKey) async -> SourcedResult? {
        guard let cached = try? repository.fetchLibraryCachedResult(
            libraryId: library.id,
            search: key.criteria.searchString,
            sortBy: key.criteria.sortCriteria.by,
            sortAsc: key.criteria.sortCriteria.ascending,
            filters: key.criteria.filterCriteriaCategory
        ) else {
            return nil
        }

        let targetSource = await librarySearchService.getTargetSource(for: library)
        if let result = cached.sources[targetSource] {
            return SourcedResult(source: targetSource, result: result)
        }
        return cached.sources
            .max { ($0.value.generation, $0.value.books.count) < ($1.value.generation, $1.value.books.count) }
            .map { SourcedResult(source: $0.key, result: $0.value) }
    }

    private func getTargetLibraryIds(for key: SearchCriteriaMergedKey) async -> Set<String> {
        if !key.libraryIds.isEmpty {
            return key.libraryIds
        }
        let calibreLibraries = await getLibraries()
        let activeLibraryIds = calibreLibraries.filter { !$0.value.hidden && !$0.value.server.removed }.map { $0.key }
        return Set(activeLibraryIds)
    }

    // MARK: - LibraryProvider Thread-safe Wrappers

    private func getLibraries() async -> [String: CalibreLibrary] {
        await self.libraryProvider.getLibraries()
    }

    private func isServerReachable(server: CalibreServer, isPublic: Bool) async -> Bool? {
        if let provider = isServerReachableProvider {
            return provider(server, isPublic)
        }
        return await self.libraryProvider.isServerReachable(server: server, isPublic: isPublic)
    }

    private func isServerReachable(server: CalibreServer) async -> Bool {
        if let provider = isServerReachableNoPublicProvider {
            return provider(server)
        }
        return await self.libraryProvider.isServerReachable(server: server)
    }
}
