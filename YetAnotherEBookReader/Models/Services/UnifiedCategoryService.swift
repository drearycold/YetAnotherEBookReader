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
    
    func mergeCategory(
        categoryName: String,
        searchString: String,
        libraryIds: Set<String> = []
    ) async -> UnifiedCategoryResult {
        let calibreLibraries = await libraryProvider.getLibraries()
        let activeLibraries = calibreLibraries.values.filter { library in
            !library.hidden
                && !library.server.removed
                && (libraryIds.isEmpty || libraryIds.contains(library.id))
        }
        
        var results: [LibraryCategoryResult] = []
        for library in activeLibraries {
            if let result = try? repository.fetchLibraryCategoryResult(libraryId: library.id, categoryName: categoryName) {
                results.append(result)
            }
        }
        
        return mergeService.merge(categoryName: categoryName, searchString: searchString, results: results)
    }

    func mergeCategoryPage(
        categoryName: String,
        searchString: String,
        libraryIds: Set<String> = [],
        offset: Int,
        limit: Int
    ) async -> UnifiedCategoryPageResult {
        let calibreLibraries = await libraryProvider.getLibraries()
        let activeLibraryIds = Set(calibreLibraries.values.compactMap { library -> String? in
            guard !library.hidden,
                  !library.server.removed,
                  (libraryIds.isEmpty || libraryIds.contains(library.id)) else {
                return nil
            }
            return library.id
        })

        guard !activeLibraryIds.isEmpty else {
            return UnifiedCategoryPageResult(
                categoryName: categoryName,
                search: searchString.trimmingCharacters(in: .whitespacesAndNewlines),
                totalNumber: 0,
                itemsCount: 0,
                items: [],
                hasMore: false,
                nextOffset: 0
            )
        }

        return (try? repository.fetchUnifiedCategoryItemsPage(
            categoryName: categoryName,
            searchString: searchString,
            libraryIds: activeLibraryIds,
            offset: offset,
            limit: limit
        )) ?? UnifiedCategoryPageResult(
            categoryName: categoryName,
            search: searchString.trimmingCharacters(in: .whitespacesAndNewlines),
            totalNumber: 0,
            itemsCount: 0,
            items: [],
            hasMore: false,
            nextOffset: 0
        )
    }
}
