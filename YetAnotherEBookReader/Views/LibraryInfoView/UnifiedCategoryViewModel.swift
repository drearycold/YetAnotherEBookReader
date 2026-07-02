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
    @Published private(set) var unifiedCategoryResult: UnifiedCategoryResult? = nil
    @Published private(set) var isLoading = false
    
    private let unifiedCategoryService: UnifiedCategoryService
    private let categoryCacheRepository: CategoryCacheRepository
    private let container: AppContainer
    private var mergeTask: Task<Void, Never>?
    
    private var currentCategoryName: String?
    private var currentSearchString: String = ""
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
    
    func mergeCategory(categoryName: String, searchString: String) {
        self.currentCategoryName = categoryName
        self.currentSearchString = searchString
        
        setupCategoryObserver(for: categoryName)
        
        mergeTask?.cancel()
        isLoading = true
        
        mergeTask = Task {
            let result = await unifiedCategoryService.mergeCategory(categoryName: categoryName, searchString: searchString)
            guard !Task.isCancelled else { return }
            self.unifiedCategoryResult = result
            self.isLoading = false
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
        mergeTask = Task {
            let result = await unifiedCategoryService.mergeCategory(categoryName: categoryName, searchString: self.currentSearchString)
            guard !Task.isCancelled else { return }
            self.unifiedCategoryResult = result
        }
    }
    
    func forceRefreshCategory(categoryName: String) {
        let calibreLibraries = container.libraryManager.calibreLibraries.values
        let activeLibraries = calibreLibraries.filter { !$0.hidden && !$0.server.removed }
        let repository = container.categoryCacheRepository

        for library in activeLibraries {
            try? repository.invalidateCategoryCache(libraryId: library.id, categoryName: categoryName)

            Task {
                await container.libraryManager.syncLibrary(request: .init(library: library, autoUpdateOnly: true, incremental: true))
            }
        }
    }
}
