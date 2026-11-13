//
//  CategoryCacheRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-12.
//

import Foundation

protocol CategoryCacheRepository: CacheRepository {
    func fetchLibraryCategoryResult(
        libraryId: String,
        categoryName: String
    ) throws -> LibraryCategoryResult?
    
    func saveLibraryCategoryResult(
        libraryId: String,
        categoryName: String,
        result: LibraryCategoryResult,
        expecting: CacheWriteExpectation<LibraryCategoryResult>
    ) throws
    
    func fetchCategorySummaries() throws -> [CategoryCacheSummary]

    func fetchCategorySummaries(libraryIds: Set<String>) throws -> [CategoryCacheSummary]

    func fetchUnifiedCategoryItemsPage(
        categoryName: String,
        searchString: String,
        libraryIds: Set<String>,
        offset: Int,
        limit: Int
    ) throws -> UnifiedCategoryPageResult

    func observeCategorySummaries() -> AsyncStream<[CategoryCacheSummary]>

    func observeCategoryCacheUpdates(categoryName: String, libraryIds: Set<String>?) -> AsyncStream<Void>
    
    func invalidateCategoryCache(libraryId: String, categoryName: String) throws

    func removeLibraryCategoryResultsNotIn(
        libraryId: String,
        activeCategoryNames: Set<String>
    ) throws
}

extension CategoryCacheRepository {
    func observeCategoryCacheUpdates(categoryName: String) -> AsyncStream<Void> {
        observeCategoryCacheUpdates(categoryName: categoryName, libraryIds: nil)
    }

    func saveLibraryCategoryResult(libraryId: String, categoryName: String, result: LibraryCategoryResult) throws {
        try saveLibraryCategoryResult(libraryId: libraryId, categoryName: categoryName,
                                      result: result, expecting: .unconditional)
    }
}
