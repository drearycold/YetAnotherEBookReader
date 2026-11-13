//
//  UnifiedSearchViewModel.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-11.
//

import Foundation
import SwiftUI

@MainActor
class UnifiedSearchViewModel: ObservableObject {
    @Published private(set) var unifiedSearchResult: UnifiedSearchResult?
    @Published private(set) var libraryStatuses = [String: LibrarySearchStatus]()
    @Published private(set) var isSearchLoading = false
    
    private let searchService: UnifiedSearchService
    private let container: AppContainer
    private var searchTask: Task<Void, Never>?
    private var libraryTask: Task<Void, Never>?
    private var databaseTask: Task<Void, Never>?
    private var reachabilityTask: Task<Void, Never>?
    private var bookTask: Task<Void, Never>?
    private var remoteBookTask: Task<Void, Never>?
    private var observationId = UUID()
    private var libraries: [String: CalibreLibrary] = [:]
    
    private var currentSearchKey: SearchCriteriaMergedKey?
    
    init(searchService: UnifiedSearchService? = nil, container: AppContainer? = nil) {
        guard let resolvedAppContainer = container ?? AppContainer.shared else {
            fatalError("AppContainer.shared must be initialized before creating UnifiedSearchViewModel")
        }
        self.container = resolvedAppContainer
        self.searchService = searchService ?? resolvedAppContainer.unifiedSearchService
    }
    
    func resumeSearch(key: SearchCriteriaMergedKey) {
        guard currentSearchKey != key else { return }
        startSearch(key: key)
    }

    func startSearch(key: SearchCriteriaMergedKey) {
        stopSearch()
        currentSearchKey = key
        unifiedSearchResult = nil
        libraryStatuses = [:]
        isSearchLoading = true
        let id = observationId
        libraries = activeBrowseLibraries(container.getLibraries(), in: key.libraryIds)
        observeBooks(for: key, id: id)
        observeScope(for: key, id: id)

        searchTask = Task { [weak self, searchService] in
            let stream = await searchService.search(key: key)
            for await update in stream {
                guard !Task.isCancelled, let self, self.observationId == id else { return }
                self.unifiedSearchResult = update.result
                self.libraryStatuses = update.statuses
                self.isSearchLoading = update.statuses.values.contains { $0.loading }
            }
            if !Task.isCancelled, let self, self.observationId == id {
                self.isSearchLoading = false
            }
        }
    }

    func stopSearch() {
        observationId = UUID()
        currentSearchKey = nil
        cancelObservations()
        isSearchLoading = false
    }

    deinit {
        searchTask?.cancel()
        libraryTask?.cancel()
        databaseTask?.cancel()
        reachabilityTask?.cancel()
        bookTask?.cancel()
        remoteBookTask?.cancel()
    }

    private func cancelObservations() {
        searchTask?.cancel()
        libraryTask?.cancel()
        databaseTask?.cancel()
        reachabilityTask?.cancel()
        bookTask?.cancel()
        remoteBookTask?.cancel()
    }

    private func observeScope(for key: SearchCriteriaMergedKey, id: UUID) {
        let snapshots = container.libraryManager.librarySnapshots(bufferingPolicy: .bufferingNewest(1))
        libraryTask = Task { [weak self] in
            for await _ in snapshots {
                guard !Task.isCancelled, let self, self.observationId == id else { return }
                let current = activeBrowseLibraries(self.container.getLibraries(), in: key.libraryIds)
                guard !sameBrowseScope(self.libraries, current) else { continue }
                self.libraries = current
                self.observeBooks(for: key, id: id)
                await self.searchService.refreshVisibleSearch(for: key, onlyWhenIdle: true)
            }
        }

        let configuration = container.databaseService.cacheConfigurationChanges()
        let initialEpoch = container.databaseService.cacheConfigurationSnapshot?.id
        databaseTask = Task { [weak self] in
            var epoch = initialEpoch
            for await _ in configuration {
                guard !Task.isCancelled, let self, self.observationId == id else { return }
                let current = self.container.databaseService.cacheConfigurationSnapshot?.id
                guard current != epoch else { continue }
                epoch = current
                self.unifiedSearchResult = nil
                self.libraryStatuses = [:]
                self.observeBooks(for: key, id: id)
                await self.searchService.refreshVisibleSearch(for: key)
            }
        }

        let staging = container.serverManager.serverInfoStagingSnapshots(bufferingPolicy: .bufferingNewest(1))
        let initialSources = reachableSources()
        reachabilityTask = Task { [weak self] in
            var sources = initialSources
            for await _ in staging {
                guard !Task.isCancelled, let self, self.observationId == id else { return }
                let current = self.reachableSources()
                let relevant = Set(self.libraries.values.map { $0.server.id })
                let changed = relevant.contains { sources[$0] != current[$0] }
                sources = current
                if changed { await self.searchService.refreshVisibleSearch(for: key, force: true) }
            }
        }
    }

    private func reachableSources() -> [String: String] {
        var sources: [String: String] = [:]
        for info in container.serverManager.calibreServerInfoStaging.values where info.reachable {
            if !info.isPublic || sources[info.server.id] == nil {
                sources[info.server.id] = info.url.absoluteString
            }
        }
        return sources
    }

    private func observeBooks(for key: SearchCriteriaMergedKey, id: UUID) {
        bookTask?.cancel()
        remoteBookTask?.cancel()
        let repository = container.searchCacheRepository
        let local = repository.observeBookChanges(in: libraries.values.filter { $0.server.isLocal })
        let remote = repository.observeBookChanges(in: libraries.values.filter { !$0.server.isLocal })
        bookTask = Task { [weak self] in
            for await _ in local {
                guard !Task.isCancelled, let self, self.observationId == id else { return }
                await self.searchService.refreshVisibleSearch(for: key)
            }
        }
        remoteBookTask = Task { [weak self] in
            for await _ in remote {
                guard !Task.isCancelled, let self, self.observationId == id else { return }
                await self.searchService.refreshVisibleBookValues(for: key)
            }
        }
    }
    
    func expandSearchUnifiedBookLimit() {
        guard !isSearchLoading, let result = unifiedSearchResult, result.limitNumber < result.totalNumber,
              let key = currentSearchKey else { return }
        isSearchLoading = true
        Task { [weak self, observationId] in
            guard let self, self.observationId == observationId else { return }
            await self.searchService.expandLimit(for: key)
        }
    }
    
    func resetSearch(force: Bool) {
        guard let key = currentSearchKey else { return }
        Task { [weak self, observationId] in
            guard let self, self.observationId == observationId else { return }
            await self.searchService.resetSearch(for: key, force: force)
        }
    }

    func refreshAfterForeground() {
        guard let key = currentSearchKey, libraryStatuses.values.contains(where: { $0.failure != nil }) else { return }
        Task { [weak self, observationId] in
            guard let self, self.observationId == observationId else { return }
            await self.searchService.refreshVisibleSearch(for: key)
        }
    }
}
