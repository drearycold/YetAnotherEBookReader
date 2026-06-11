//
//  UnifiedSearchManager.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-10.
//

import Foundation
import Combine

class UnifiedSearchManager {
    
    private let mergeService: UnifiedSearchMergeService
    private let repository: SearchCacheRepository
    
    // In-memory active searches
    private var activeSearches: [SearchCriteriaMergedKey: ActiveSearch] = [:]
    
    // Combine publishers per search key
    private var resultSubjects: [SearchCriteriaMergedKey: CurrentValueSubject<UnifiedSearchResult, Never>] = [:]
    
    // Subscriptions to library cached results
    private var librarySubscriptions: [SearchCriteriaMergedKey: Set<AnyCancellable>] = [:]
    
    private let queue = DispatchQueue(label: "com.antigravity.UnifiedSearchManager", qos: .userInitiated)
    
    private func getTargetLibraryIds(for key: SearchCriteriaMergedKey) -> Set<String> {
        if !key.libraryIds.isEmpty {
            return key.libraryIds
        }
        guard let calibreLibraries = ModelData.shared?.calibreLibraries else {
            return []
        }
        let activeLibraryIds = calibreLibraries.filter { !$0.value.hidden && !$0.value.server.removed }.map { $0.key }
        return Set(activeLibraryIds)
    }
    
    // Providers for reachability checks to support unit testing without full ModelData setup
    var isServerReachableProvider: ((CalibreServer, Bool) -> Bool?)?
    var isServerReachableNoPublicProvider: ((CalibreServer) -> Bool)?
    
    // Callback to trigger a library search in the network coordinator (CalibreLibrarySearchManager)
    var searchTriggerHandler: ((Set<String>, SearchCriteria, Bool) -> Void)?
    
    init(
        mergeService: UnifiedSearchMergeService = UnifiedSearchMergeService(),
        repository: SearchCacheRepository
    ) {
        self.mergeService = mergeService
        self.repository = repository
    }
    
    /// Returns a publisher for the unified search result corresponding to the given key.
    /// This will automatically initialize active search tracking and subscribe to updates from the libraries.
    func publisher(for key: SearchCriteriaMergedKey) -> AnyPublisher<UnifiedSearchResult, Never> {
        var subject: CurrentValueSubject<UnifiedSearchResult, Never>?
        var isNew = false
        
        queue.sync {
            if let existing = resultSubjects[key] {
                subject = existing
                isNew = false
            } else {
                // Try to load cached unified search result, or initialize an empty one
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
                
                let newSubject = CurrentValueSubject<UnifiedSearchResult, Never>(initialResult)
                resultSubjects[key] = newSubject
                subject = newSubject
                
                var initialStatuses: [String: LibrarySearchStatus] = [:]
                let targetLibraryIds = self.getTargetLibraryIds(for: key)
                for libraryId in targetLibraryIds {
                    initialStatuses[libraryId] = LibrarySearchStatus(loading: false, error: nil)
                }
                
                let activeSearch = ActiveSearch(
                    criteria: key.criteria,
                    libraryIds: key.libraryIds,
                    currentResult: initialResult,
                    libraryStatuses: initialStatuses
                )
                activeSearches[key] = activeSearch
                isNew = true
            }
        }
        
        if isNew {
            queue.async { [weak self] in
                guard let self = self else { return }
                self.setupLibrarySubscriptions(for: key)
            }
        }
        
        // Always trigger search cache check / refresh when requesting a publisher
        queue.async { [weak self] in
            guard let self = self else { return }
            self.searchTriggerHandler?(key.libraryIds, key.criteria, false)
        }
        
        return subject!.eraseToAnyPublisher()
    }
    
    func getActiveSearch(for key: SearchCriteriaMergedKey) -> ActiveSearch? {
        queue.sync {
            activeSearches[key]
        }
    }
    
    /// Increments the limit number for a specific search key.
    func expandLimit(for key: SearchCriteriaMergedKey, by increment: Int = 100) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard var activeSearch = self.activeSearches[key] else { return }
            activeSearch.currentResult.limitNumber += increment
            self.activeSearches[key] = activeSearch
            
            self.triggerMerge(for: key)
        }
    }
    
    /// Explicitly sets the limit number for a specific search key.
    func setLimit(for key: SearchCriteriaMergedKey, limit: Int) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard var activeSearch = self.activeSearches[key] else { return }
            guard activeSearch.currentResult.limitNumber != limit else { return }
            activeSearch.currentResult.limitNumber = limit
            self.activeSearches[key] = activeSearch
            
            self.triggerMerge(for: key)
        }
    }
    
    /// Resets the merged list for a search key.
    func resetSearch(for key: SearchCriteriaMergedKey) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard var activeSearch = self.activeSearches[key] else { return }
            activeSearch.currentResult.books.removeAll()
            activeSearch.currentResult.limitNumber = 100
            for libraryId in activeSearch.currentResult.libraryIds {
                activeSearch.currentResult.unifiedOffsets[libraryId] = MergeOffset(
                    beenCutOff: false,
                    beenConsumed: false,
                    offset: 0
                )
            }
            self.activeSearches[key] = activeSearch
            
            self.triggerMerge(for: key)
        }
    }
    
    /// Manually updates a library's loading and error status.
    func updateLibraryStatus(
        key: SearchCriteriaMergedKey,
        libraryId: String,
        loading: Bool,
        error: SearchError?
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard var activeSearch = self.activeSearches[key] else { return }
            activeSearch.libraryStatuses[libraryId] = LibrarySearchStatus(loading: loading, error: error)
            self.activeSearches[key] = activeSearch
            
            if let subject = self.resultSubjects[key] {
                subject.send(activeSearch.currentResult)
            }
        }
    }
    
    private func setupLibrarySubscriptions(for key: SearchCriteriaMergedKey) {
        var subscriptionSet = Set<AnyCancellable>()
        
        let targetLibraryIds = self.getTargetLibraryIds(for: key)
        for libraryId in targetLibraryIds {
            repository.libraryCachedResultPublisher(
                libraryId: libraryId,
                search: key.criteria.searchString,
                sortBy: key.criteria.sortCriteria.by,
                sortAsc: key.criteria.sortCriteria.ascending,
                filters: key.criteria.filterCriteriaCategory
            )
            .receive(on: queue)
            .sink { completion in
                if case .failure(let error) = completion {
                    self.updateLibraryStatus(key: key, libraryId: libraryId, loading: false, error: SearchError.database(error.localizedDescription))
                }
            } receiveValue: { cachedResult in
                self.handleLibraryCachedResultUpdate(key: key, libraryId: libraryId, cachedResult: cachedResult)
            }
            .store(in: &subscriptionSet)
        }
        
        librarySubscriptions[key] = subscriptionSet
    }
    
    private func handleLibraryCachedResultUpdate(
        key: SearchCriteriaMergedKey,
        libraryId: String,
        cachedResult: LibraryCachedResult
    ) {
        guard var activeSearch = activeSearches[key] else { return }
        
        // Select active source result from sources
        if let selectResult = selectActiveSource(for: libraryId, sources: cachedResult.sources) {
            if let lastProcessed = activeSearch.lastProcessedSources[libraryId],
               lastProcessed == selectResult.result {
                return
            }
            activeSearch.lastProcessedSources[libraryId] = selectResult.result
            
            var unifiedOffsets = activeSearch.currentResult.unifiedOffsets
            var offset = unifiedOffsets[libraryId] ?? MergeOffset()
            offset.searchObjectSource = selectResult.key
            unifiedOffsets[libraryId] = offset
            activeSearch.currentResult.unifiedOffsets = unifiedOffsets
            
            activeSearches[key] = activeSearch
            
            // Trigger merge with the updated results
            triggerMerge(for: key)
        }
    }
    
    private func triggerMerge(for key: SearchCriteriaMergedKey) {
        guard var activeSearch = activeSearches[key] else { return }
        
        var libraryResults: [String: LibrarySourceSearchResult] = [:]
        
        let targetLibraryIds = self.getTargetLibraryIds(for: key)
        for libraryId in targetLibraryIds {
            if let cached = try? repository.fetchLibraryCachedResult(
                libraryId: libraryId,
                search: key.criteria.searchString,
                sortBy: key.criteria.sortCriteria.by,
                sortAsc: key.criteria.sortCriteria.ascending,
                filters: key.criteria.filterCriteriaCategory
            ), let activeSource = selectActiveSource(for: libraryId, sources: cached.sources) {
                libraryResults[libraryId] = activeSource.result
            }
        }
        
        // Run the merge service
        let mergedResult = mergeService.merge(
            libraryResults: libraryResults,
            currentResult: activeSearch.currentResult
        )
        
        activeSearch.currentResult = mergedResult
        activeSearches[key] = activeSearch
        

        // Emit updated result
        if let subject = resultSubjects[key] {
            subject.send(mergedResult)
        }
    }
    
    private func selectActiveSource(
        for libraryId: String,
        sources: [String: LibrarySourceSearchResult]
    ) -> (key: String, result: LibrarySourceSearchResult)? {
        let modelData = ModelData.shared
        let library = modelData?.calibreLibraries[libraryId]
        
        if library == nil,
           isServerReachableProvider != nil,
           isServerReachableNoPublicProvider != nil {
            guard let bestEntry = sources.sorted(by: { $0.key < $1.key }).first else { return nil }
            return (key: bestEntry.key, result: bestEntry.value)
        }
        
        guard let modelData = modelData, let library = library else {
            return nil
        }
        
        let reachabilityCheck: (CalibreServer, Bool) -> Bool? = isServerReachableProvider ?? { server, isPublic in
            modelData.isServerReachable(server: server, isPublic: isPublic)
        }
        let reachabilityNoPublicCheck: (CalibreServer) -> Bool = isServerReachableNoPublicProvider ?? { server in
            modelData.isServerReachable(server: server)
        }
        
        let filtered = sources.filter { entry in
            if entry.key == library.server.publicUrl.replacingOccurrences(of: ".", with: "_"),
               reachabilityCheck(library.server, true) == true {
                return true
            }
            if entry.key == library.server.baseUrl.replacingOccurrences(of: ".", with: "_"),
               reachabilityCheck(library.server, false) == true {
                return true
            }
            if entry.key == URL(fileURLWithPath: "/realm").absoluteString,
               reachabilityNoPublicCheck(library.server) == false {
                return true
            }
            return false
        }
        
        guard let bestEntry = filtered.sorted(by: {
            if $0.value.books.count != $1.value.books.count {
                return $0.value.books.count > $1.value.books.count
            }
            return $0.key < $1.key
        }).first else {
            return nil
        }
        
        return (key: bestEntry.key, result: bestEntry.value)
    }
}
