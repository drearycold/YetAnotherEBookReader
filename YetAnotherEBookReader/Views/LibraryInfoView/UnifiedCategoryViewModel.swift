//
//  UnifiedCategoryViewModel.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-12.
//

import Foundation
import SwiftUI
import Combine
import RealmSwift

@MainActor
class UnifiedCategoryViewModel: ObservableObject {
    @Published private(set) var unifiedCategoryResult: UnifiedCategoryResult? = nil
    @Published private(set) var isLoading = false
    
    private let unifiedCategoryService: UnifiedCategoryService
    private let modelData: ModelData
    private var mergeTask: Task<Void, Never>?
    
    private var currentCategoryName: String?
    private var currentSearchString: String = ""
    private var databaseObserver: AnyCancellable?
    
    init(unifiedCategoryService: UnifiedCategoryService? = nil, modelData: ModelData? = nil) {
        guard let resolvedModelData = modelData ?? ModelData.shared else {
            fatalError("ModelData.shared must be initialized before creating UnifiedCategoryViewModel")
        }
        self.modelData = resolvedModelData
        self.unifiedCategoryService = unifiedCategoryService ?? resolvedModelData.unifiedCategoryService
    }
    
    func mergeCategory(categoryName: String, searchString: String) {
        self.currentCategoryName = categoryName
        self.currentSearchString = searchString
        
        setupDatabaseObserver(for: categoryName)
        
        mergeTask?.cancel()
        isLoading = true
        
        mergeTask = Task {
            let result = await unifiedCategoryService.mergeCategory(categoryName: categoryName, searchString: searchString)
            guard !Task.isCancelled else { return }
            self.unifiedCategoryResult = result
            self.isLoading = false
        }
    }
    
    private func setupDatabaseObserver(for categoryName: String) {
        guard databaseObserver == nil else { return }
        
        databaseObserver = modelData.realm.objects(CalibreLibraryCategoryObject.self)
            .where {
                $0.categoryName == categoryName
            }
            .changesetPublisher(keyPaths: ["items"])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] changes in
                guard let self = self else { return }
                switch changes {
                case .initial(_):
                    break
                case .update(_, deletions: _, insertions: _, modifications: _):
                    self.retriggerMerge()
                case .error(_):
                    break
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
        let calibreLibraries = modelData.calibreLibraries.values
        let activeLibraries = calibreLibraries.filter { !$0.hidden && !$0.server.removed }
        let repository = modelData.categoryCacheRepository
        
        for library in activeLibraries {
            try? repository.invalidateCategoryCache(libraryId: library.id, categoryName: categoryName)
            
            Task {
                await modelData.syncLibrary(request: .init(library: library, autoUpdateOnly: true, incremental: true))
            }
        }
    }
}
