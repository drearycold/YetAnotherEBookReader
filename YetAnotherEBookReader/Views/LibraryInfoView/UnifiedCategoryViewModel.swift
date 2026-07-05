//
//  UnifiedCategoryViewModel.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-12.
//

import Foundation
import SwiftUI

@MainActor
class UnifiedCategoryViewModel: ObservableObject {
    static let defaultPageSize = 100

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
    private var observedCategoryName: String?
    
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
        
        setupCategoryObserver(for: categoryName)
        
        mergeTask?.cancel()
        isLoading = true
        isLoadingMore = false
        hasMore = false
        nextOffset = 0
        items = []
        unifiedCategoryResult = nil
        let pageSize = self.currentPageSize
        
        mergeTask = Task {
            let result = await unifiedCategoryService.mergeCategoryPage(
                categoryName: categoryName,
                searchString: searchString,
                libraryIds: libraryIds,
                offset: 0,
                limit: pageSize
            )
            guard !Task.isCancelled else { return }
            self.applyPage(result, replacing: true)
            self.isLoading = false
        }
    }

    func loadNextPageIfNeeded(currentItem: UnifiedCategoryItem?) {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        if let currentItem,
           currentItem.id != items.last?.id {
            return
        }
        guard let categoryName = currentCategoryName else { return }

        let searchString = currentSearchString
        let libraryIds = currentLibraryIds
        let offset = nextOffset
        let limit = currentPageSize

        isLoadingMore = true
        mergeTask = Task {
            let result = await unifiedCategoryService.mergeCategoryPage(
                categoryName: categoryName,
                searchString: searchString,
                libraryIds: libraryIds,
                offset: offset,
                limit: limit
            )
            guard !Task.isCancelled else { return }
            self.applyPage(result, replacing: false)
            self.isLoadingMore = false
        }
    }
    
    private func setupCategoryObserver(for categoryName: String) {
        guard observedCategoryName != categoryName || cacheUpdateTask == nil else { return }

        cacheUpdateTask?.cancel()
        observedCategoryName = categoryName
        cacheUpdateTask = Task { [weak self, categoryCacheRepository] in
            for await _ in categoryCacheRepository.observeCategoryCacheUpdates(categoryName: categoryName) {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self?.retriggerMerge()
                }
            }
        }
    }
    
    private func retriggerMerge() {
        guard let categoryName = currentCategoryName else { return }
        mergeTask?.cancel()
        let searchString = currentSearchString
        let libraryIds = currentLibraryIds
        let pageSize = currentPageSize
        isLoading = true
        isLoadingMore = false
        hasMore = false
        nextOffset = 0
        items = []
        mergeTask = Task {
            let result = await unifiedCategoryService.mergeCategoryPage(
                categoryName: categoryName,
                searchString: searchString,
                libraryIds: libraryIds,
                offset: 0,
                limit: pageSize
            )
            guard !Task.isCancelled else { return }
            self.applyPage(result, replacing: true)
            self.isLoading = false
        }
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
        let repository = container.categoryCacheRepository

        for library in activeLibraries {
            try? repository.invalidateCategoryCache(libraryId: library.id, categoryName: categoryName)

            Task {
                await container.libraryManager.syncLibrary(request: .init(library: library, autoUpdateOnly: true, incremental: true))
            }
        }
    }
}
