//
//  CategoryCacheRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-12.
//

import Foundation

protocol CategoryCacheRepository: Sendable {
    func fetchLibraryCategoryResult(
        libraryId: String,
        categoryName: String
    ) throws -> LibraryCategoryResult?
    
    func saveLibraryCategoryResult(
        libraryId: String,
        categoryName: String,
        result: LibraryCategoryResult
    ) throws
    
    func fetchCategorySummaries() throws -> [CategoryCacheSummary]
    
    func invalidateCategoryCache(libraryId: String, categoryName: String) throws
}
