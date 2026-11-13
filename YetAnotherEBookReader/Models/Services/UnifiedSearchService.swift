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
        var libraryScopes: [String: CalibreLibrary] = [:]
        var cache: SearchCacheRepository?
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
        guard let search = activeSearches[key], let cache = search.cache,
              (try? cache.checkCurrent()) != nil else { return nil }
        return search.currentResult
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
        searchTasks[key]?.cancel()
        let task = Task { await runSearch(for: key, force: force) }
        searchTasks[key] = task
        return task
    }

    private func runSearch(for key: SearchCriteriaMergedKey, force: Bool) async {
        let database = Result { try repository.snapshot() }
        let libraries = await getLibraries()
        let targetLibraries = activeLibraries(in: libraries, for: key)
        let activeLibraryIds = Set(targetLibraries.keys)
        var requests: [String: Result<LibrarySearchService.Request, Error>] = [:]
        for (id, library) in targetLibraries {
            do {
                try Task.checkCancellation()
                requests[id] = .success(try await librarySearchService.prepareRequest(library: library, cache: database.get()))
            } catch {
                requests[id] = .failure(error)
            }
        }
        guard !Task.isCancelled else { return }

        var activeSearch = activeSearches[key] ?? ActiveSearch(
            criteria: key.criteria, libraryIds: key.libraryIds,
            currentResult: UnifiedSearchResult(
                search: key.criteria.searchString, sortBy: key.criteria.sortCriteria.by,
                sortAsc: key.criteria.sortCriteria.ascending, filters: key.criteria.filterCriteriaCategory,
                libraryIds: key.libraryIds, unifiedOffsets: [:], totalNumber: 0, limitNumber: 100, books: []
            ),
            libraryStatuses: [:], forceMetadataRefreshForLoadedBooks: false
        )
        if activeSearch.cache.map({ (try? $0.checkCurrent()) != nil }) != true {
            activeSearch.libraryResults.removeAll()
            activeSearch.currentResult.unifiedOffsets.removeAll()
        }
        activeSearch.libraryResults = activeSearch.libraryResults.filter { id, _ in
            guard let old = activeSearch.libraryScopes[id], let current = targetLibraries[id] else { return false }
            return old.hasSameCacheScope(as: current)
        }
        activeSearch.libraryScopes = targetLibraries
        activeSearch.cache = try? database.get()
        activeSearch.libraryStatuses = [:]

        // Until each library answers, show the cache mapped with its captured library value.
        for (id, preparation) in requests where activeSearch.libraryResults[id] == nil {
            if case .success(let request) = preparation {
                activeSearch.libraryResults[id] = try? cachedResult(for: request, key: key)
            }
        }

        if force {
            activeSearch.forceMetadataRefreshForLoadedBooks = true
        } else if activeSearch.currentResult.books.isEmpty {
            activeSearch.forceMetadataRefreshForLoadedBooks = false
        }

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

        typealias Answer = (id: String, request: LibrarySearchService.Request?,
                            result: Result<LibraryCachedResult, Error>, restarted: Bool)
        let load: @Sendable (String, Result<LibrarySearchService.Request, Error>, Bool) async -> Answer = {
            id, preparation, restarted in
            let request = try? preparation.get()
            do {
                let result = try await self.librarySearchService.searchAndFetchMetadata(
                    request: preparation.get(), criteria: key.criteria, limit: limit,
                    force: force || restarted, forceMetadataRefresh: forceMetadataRefresh
                )
                return (id, request, .success(result), restarted)
            } catch {
                return (id, request, .failure(error), restarted)
            }
        }

        await withTaskGroup(of: Answer.self) { group in
            for (id, preparation) in requests {
                group.addTask { await load(id, preparation, false) }
            }

            for await answer in group {
                guard !Task.isCancelled else { break }
                if let replacement = await handleLibrarySearchResult(
                    key: key, searchId: searchId, libraryId: answer.id, request: answer.request,
                    result: answer.result, canRestart: !answer.restarted
                ) {
                    group.addTaskUnlessCancelled { await load(answer.id, .success(replacement), true) }
                }
            }
        }
        if !Task.isCancelled { finishSearch(for: key, searchId: searchId) }
    }

    private func handleLibrarySearchResult(
        key: SearchCriteriaMergedKey, searchId: UUID, libraryId: String,
        request: LibrarySearchService.Request?, result: Result<LibraryCachedResult, Error>, canRestart: Bool
    ) async -> LibrarySearchService.Request? {
        let libraries = activeLibraries(in: await getLibraries(), for: key)
        guard !Task.isCancelled, var activeSearch = activeSearches[key], activeSearch.searchId == searchId
        else { return nil }

        if let cache = activeSearch.cache, (try? cache.checkCurrent()) == nil {
            activeSearch.libraryResults.removeAll()
            activeSearch.libraryStatuses = activeSearch.libraryStatuses.mapValues { _ in .init(error: .superseded) }
        } else if let captured = activeSearch.libraryScopes[libraryId], let current = libraries[libraryId],
                  captured.hasSameCacheScope(as: current),
                  request.map({ (try? $0.cache.checkCurrent()) != nil }) != false {
            var searchError: SearchError?
            switch result {
            case .success(let cached):
                if let request, let source = cached.sources[request.source] {
                    activeSearch.libraryResults[libraryId] = SourcedResult(source: request.source, result: source)
                }
            case .failure(let error):
                searchError = Self.searchError(error)
                let failedOnNetwork: Bool
                if case .network? = searchError { failedOnNetwork = true }
                else { failedOnNetwork = false }
                if let request, failedOnNetwork || activeSearch.libraryResults[libraryId] == nil || searchError == .superseded {
                    do {
                        if let fallback = try cachedResult(for: request, key: key) {
                            activeSearch.libraryResults[libraryId] = fallback
                        }
                    } catch {
                        // Keep the network failure that triggered fallback. A superseded result
                        // has no failure to report unless reading the replacement itself fails.
                        if searchError == .superseded { searchError = Self.searchError(error) }
                    }
                }
            }
            activeSearch.libraryStatuses[libraryId] = LibrarySearchStatus(
                error: searchError, fromCache: searchError != nil && activeSearch.libraryResults[libraryId] != nil
            )
        } else if let current = libraries[libraryId], let cache = activeSearch.cache {
            return await prepareReplacement(for: current, key: key, searchId: searchId,
                                            cache: cache, canRestart: canRestart)
        } else {
            activeSearch.libraryResults.removeValue(forKey: libraryId)
            activeSearch.libraryStatuses[libraryId] = .init(error: .superseded)
        }

        publish(activeSearch, for: key, libraryIds: Set(libraries.keys))
        return nil
    }

    private func prepareReplacement(
        for library: CalibreLibrary, key: SearchCriteriaMergedKey, searchId: UUID,
        cache: SearchCacheRepository, canRestart: Bool
    ) async -> LibrarySearchService.Request? {
        let preparation: Result<LibrarySearchService.Request, Error>
        do {
            preparation = .success(try await librarySearchService.prepareRequest(library: library, cache: cache))
        } catch {
            preparation = .failure(error)
        }
        let libraries = activeLibraries(in: await getLibraries(), for: key)
        guard !Task.isCancelled, var activeSearch = activeSearches[key], activeSearch.searchId == searchId
        else { return nil }

        let id = library.id
        var replacement: LibrarySearchService.Request?
        if (try? cache.checkCurrent()) == nil {
            activeSearch.libraryResults.removeAll()
            activeSearch.libraryStatuses = activeSearch.libraryStatuses.mapValues { _ in .init(error: .superseded) }
        } else {
            activeSearch.libraryResults.removeValue(forKey: id)
            do {
                guard libraries[id]?.hasSameCacheScope(as: library) == true else { throw CacheContextError.superseded }
                let request = try preparation.get()
                try request.cache.checkCurrent()
                let cached = try cachedResult(for: request, key: key)
                activeSearch.libraryScopes[id] = library
                activeSearch.libraryResults[id] = cached
                // A second scope change can still use the newest cache. Limit each library to
                // one replacement request per search so periodic updates cannot keep it loading.
                activeSearch.libraryStatuses[id] = canRestart
                    ? .init(loading: true)
                    : .init(error: .superseded, fromCache: cached != nil)
                if canRestart { replacement = request }
            } catch {
                activeSearch.libraryStatuses[id] = .init(error: Self.searchError(error))
            }
        }

        publish(activeSearch, for: key, libraryIds: Set(libraries.keys))
        return replacement
    }

    private func publish(_ search: ActiveSearch, for key: SearchCriteriaMergedKey, libraryIds: Set<String>) {
        var activeSearch = search
        activeSearch.currentResult = merge(activeSearch, libraryIds: libraryIds)
        activeSearches[key] = activeSearch
        emitUpdate(for: key)
    }

    private static func searchError(_ error: Error) -> SearchError {
        if let searchError = error as? SearchError { return searchError }
        if error is CancellationError { return .cancelled }
        switch error as? CacheContextError {
        case .superseded: return .superseded
        case .databaseUnavailable: return .database("The search database is not ready.")
        case nil: return .database(error.localizedDescription)
        }
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
            if let status = activeSearch.libraryStatuses[libraryId],
               status.failure != nil || (status.error == .superseded && status.fromCache) {
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
    private func cachedResult(
        for request: LibrarySearchService.Request, key: SearchCriteriaMergedKey
    ) throws -> SourcedResult? {
        guard let cached = try request.cache.fetchLibraryCachedResult(
            library: request.library,
            search: key.criteria.searchString,
            sortBy: key.criteria.sortCriteria.by,
            sortAsc: key.criteria.sortCriteria.ascending,
            filters: key.criteria.filterCriteriaCategory
        ) else { return nil }

        if let result = cached.sources[request.source] {
            return SourcedResult(source: request.source, result: result)
        }
        return cached.sources
            .max { ($0.value.generation, $0.value.books.count) < ($1.value.generation, $1.value.books.count) }
            .map { SourcedResult(source: $0.key, result: $0.value) }
    }

    private func activeLibraries(
        in libraries: [String: CalibreLibrary], for key: SearchCriteriaMergedKey
    ) -> [String: CalibreLibrary] {
        libraries.filter { id, library in
            !library.hidden && !library.server.removed && (key.libraryIds.isEmpty || key.libraryIds.contains(id))
        }
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
