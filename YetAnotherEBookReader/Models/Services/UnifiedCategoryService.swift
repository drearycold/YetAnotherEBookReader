//
//  UnifiedCategoryService.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-12.
//

import Foundation

actor UnifiedCategoryService {
    private let mergeService: UnifiedCategoryMergeService
    private let repository: CategoryCacheRepository
    private let libraryProvider: LibraryProvider
    
    init(
        mergeService: UnifiedCategoryMergeService = UnifiedCategoryMergeService(),
        repository: CategoryCacheRepository,
        libraryProvider: LibraryProvider
    ) {
        self.mergeService = mergeService
        self.repository = repository
        self.libraryProvider = libraryProvider
    }
    
    func mergeCategory(categoryName: String, searchString: String) async -> UnifiedCategoryResult {
        let calibreLibraries = await libraryProvider.getLibraries()
        let activeLibraries = calibreLibraries.values.filter { !$0.hidden && !$0.server.removed }
        
        var results: [LibraryCategoryResult] = []
        for library in activeLibraries {
            if let result = try? repository.fetchLibraryCategoryResult(libraryId: library.id, categoryName: categoryName) {
                results.append(result)
            }
        }
        
        return mergeService.merge(categoryName: categoryName, searchString: searchString, results: results)
    }
}
