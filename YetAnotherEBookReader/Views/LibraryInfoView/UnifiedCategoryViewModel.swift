//
//  UnifiedCategoryViewModel.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-12.
//

import Foundation
import SwiftUI
import OSLog

@MainActor
class UnifiedCategoryViewModel: ObservableObject {
    nonisolated static let defaultPageSize = 100

    @Published private(set) var unifiedCategoryResult: UnifiedCategoryResult? = nil
    @Published private(set) var items: [UnifiedCategoryItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var nextOffset = 0
    
    private let unifiedCategoryService: UnifiedCategoryService
    private let categoryCacheRepository: CategoryCacheRepository
    private let container: AppContainer
    private var mergeTask: Task<Void, Never>?
    
    private var currentCategoryName: String?
    private var currentSearchString: String = ""
    private var currentLibraryIds = Set<String>()
    private var currentPageSize = UnifiedCategoryViewModel.defaultPageSize
    private var cacheUpdateTask: Task<Void, Never>?
    private var query: UnifiedCategoryService.Query?
    private let logger = Logger(subsystem: "io.github.drearycold.DSReader", category: "CategoryCache")
    
    init(
        unifiedCategoryService: UnifiedCategoryService? = nil,
        categoryCacheRepository: CategoryCacheRepository? = nil,
        container: AppContainer? = nil
    ) {
        guard let resolvedAppContainer = container ?? AppContainer.shared else {
            fatalError("AppContainer.shared must be initialized before creating UnifiedCategoryViewModel")
        }
        self.container = resolvedAppContainer
        self.unifiedCategoryService = unifiedCategoryService ?? resolvedAppContainer.unifiedCategoryService
        self.categoryCacheRepository = categoryCacheRepository ?? resolvedAppContainer.categoryCacheRepository
    }

    deinit {
        mergeTask?.cancel()
        cacheUpdateTask?.cancel()
    }

    func stopObserving() {
        mergeTask?.cancel()
        mergeTask = nil
        cacheUpdateTask?.cancel()
        cacheUpdateTask = nil
        query = nil
        isLoading = false
        isLoadingMore = false
    }
    
    func mergeCategory(
        categoryName: String,
        searchString: String,
        libraryIds: Set<String> = []
    ) {
        reloadCategory(categoryName: categoryName, searchString: searchString, libraryIds: libraryIds)
    }

    func reloadCategory(
        categoryName: String,
        searchString: String,
        libraryIds: Set<String> = [],
        pageSize: Int = UnifiedCategoryViewModel.defaultPageSize
    ) {
        self.currentCategoryName = categoryName
        self.currentSearchString = searchString
        self.currentLibraryIds = libraryIds
        self.currentPageSize = max(1, pageSize)
        
        cacheUpdateTask?.cancel()
        cacheUpdateTask = nil
        do {
            let cache = try categoryCacheRepository.snapshot()
            setupCategoryObserver(for: categoryName, cache: cache)
            loadFirstPage(cache: cache)
        } catch {
            mergeTask?.cancel()
            query = nil
            isLoading = false
            isLoadingMore = false
            hasMore = false
            nextOffset = 0
            items = []
            unifiedCategoryResult = nil
            reportCacheError(error)
        }
    }

    func loadNextPageIfNeeded(currentItem: UnifiedCategoryItem?) {
        guard hasMore, !isLoading, !isLoadingMore, let query, let categoryName = currentCategoryName else { return }
        if let currentItem, currentItem.id != items.last?.id { return }

        let search = currentSearchString
        let offset = nextOffset
        let limit = currentPageSize
        isLoadingMore = true
        mergeTask = Task {
            defer { if !Task.isCancelled { self.isLoadingMore = false } }
            do {
                let result = try await unifiedCategoryService.mergeCategoryPage(
                    categoryName: categoryName, searchString: search, query: query, offset: offset, limit: limit
                )
                try Task.checkCancellation()
                try query.cache.checkCurrent()
                self.applyPage(result, replacing: false)
            } catch {
                guard !Task.isCancelled else { return }
                if error as? CacheContextError == .superseded { self.hasMore = false }
                self.reportCacheError(error)
            }
        }
    }

    private func setupCategoryObserver(for categoryName: String, cache: CategoryCacheRepository) {
        let scope = currentLibraryIds.isEmpty ? nil : currentLibraryIds
        cacheUpdateTask = Task { [weak self] in
            for await _ in cache.observeCategoryCacheUpdates(categoryName: categoryName, libraryIds: scope) {
                guard !Task.isCancelled, (try? cache.checkCurrent()) != nil else { break }
                self?.loadFirstPage(cache: cache)
            }
        }
    }

    private func loadFirstPage(cache: CategoryCacheRepository) {
        guard let categoryName = currentCategoryName else { return }
        mergeTask?.cancel()
        let search = currentSearchString
        let libraryIds = currentLibraryIds
        let limit = currentPageSize
        query = nil
        isLoading = true
        isLoadingMore = false
        hasMore = false
        nextOffset = 0
        items = []
        unifiedCategoryResult = nil
        mergeTask = Task {
            defer { if !Task.isCancelled { self.isLoading = false } }
            do {
                let query = try await unifiedCategoryService.prepareQuery(libraryIds: libraryIds, cache: cache)
                let result = try await unifiedCategoryService.mergeCategoryPage(
                    categoryName: categoryName, searchString: search, query: query, offset: 0, limit: limit
                )
                try Task.checkCancellation()
                try query.cache.checkCurrent()
                self.query = query
                self.applyPage(result, replacing: true)
            } catch {
                guard !Task.isCancelled else { return }
                self.reportCacheError(error)
            }
        }
    }

    private func reportCacheError(_ error: Error) {
        guard !(error is CancellationError), error as? CacheContextError != .superseded else { return }
        logger.error("Could not read category cache: \(error.localizedDescription)")
    }

    private func applyPage(_ page: UnifiedCategoryPageResult, replacing: Bool) {
        if replacing {
            items = page.items
        } else {
            let existingIds = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !existingIds.contains($0.id) })
        }

        hasMore = page.hasMore
        nextOffset = page.nextOffset
        unifiedCategoryResult = UnifiedCategoryResult(
            categoryName: page.categoryName,
            search: page.search,
            totalNumber: page.totalNumber,
            itemsCount: page.itemsCount,
            items: items
        )
    }
    
    func forceRefreshCategory(categoryName: String, libraryIds: Set<String> = []) {
        let calibreLibraries = container.libraryManager.calibreLibraries.values
        let activeLibraries = calibreLibraries.filter { library in
            !library.hidden
                && !library.server.removed
                && (libraryIds.isEmpty || libraryIds.contains(library.id))
        }
        guard let cache = try? container.categoryCacheRepository.snapshot() else { return }

        for library in activeLibraries {
            do {
                let lifetime = try container.calibreServerService.cacheLifetime(for: library)
                let scoped = try cache.scoped(to: library, lifetime: lifetime)
                try scoped.invalidateCategoryCache(libraryId: library.id, categoryName: categoryName)
            } catch {
                reportCacheError(error)
                continue
            }

            Task {
                await container.libraryManager.syncLibrary(request: .init(library: library), cache: cache)
            }
        }
    }
}
