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
    
    struct Query: Sendable {
        let cache: CategoryCacheRepository
        let requestedLibraryIds: Set<String>
        let libraries: [String: CalibreLibrary]
    }

    func prepareQuery(libraryIds: Set<String>, cache: CategoryCacheRepository? = nil) async throws -> Query {
        let database = try (cache ?? repository.snapshot())
        let libraries = await activeLibraries(for: libraryIds)
        try Task.checkCancellation()
        try database.checkCurrent()
        return Query(cache: database, requestedLibraryIds: libraryIds, libraries: libraries)
    }

    func mergeCategory(
        categoryName: String,
        searchString: String,
        libraryIds: Set<String> = []
    ) async throws -> UnifiedCategoryResult {
        let query = try await prepareQuery(libraryIds: libraryIds)
        let results = try query.libraries.keys.compactMap {
            try query.cache.fetchLibraryCategoryResult(libraryId: $0, categoryName: categoryName)
        }
        try query.cache.checkCurrent()
        return mergeService.merge(categoryName: categoryName, searchString: searchString, results: results)
    }

    func mergeCategoryPage(
        categoryName: String, searchString: String, libraryIds: Set<String> = [], offset: Int, limit: Int
    ) async throws -> UnifiedCategoryPageResult {
        let query = try await prepareQuery(libraryIds: libraryIds)
        return try readPage(categoryName: categoryName, searchString: searchString, query: query,
                            offset: offset, limit: limit)
    }

    func mergeCategoryPage(
        categoryName: String, searchString: String, query: Query, offset: Int, limit: Int
    ) async throws -> UnifiedCategoryPageResult {
        let current = await activeLibraries(for: query.requestedLibraryIds)
        guard current.count == query.libraries.count, query.libraries.allSatisfy({ id, library in
            current[id].map { $0.hasSameCacheScope(as: library) } == true
        }) else { throw CacheContextError.superseded }
        return try readPage(categoryName: categoryName, searchString: searchString, query: query,
                            offset: offset, limit: limit)
    }

    private func readPage(
        categoryName: String, searchString: String, query: Query, offset: Int, limit: Int
    ) throws -> UnifiedCategoryPageResult {
        try Task.checkCancellation()
        try query.cache.checkCurrent()
        guard !query.libraries.isEmpty else {
            return UnifiedCategoryPageResult(
                categoryName: categoryName, search: searchString.trimmingCharacters(in: .whitespacesAndNewlines),
                totalNumber: 0, itemsCount: 0, items: [], hasMore: false, nextOffset: 0
            )
        }
        let page = try query.cache.fetchUnifiedCategoryItemsPage(
            categoryName: categoryName, searchString: searchString,
            libraryIds: Set(query.libraries.keys), offset: offset, limit: limit
        )
        try query.cache.checkCurrent()
        return page
    }

    private func activeLibraries(for libraryIds: Set<String>) async -> [String: CalibreLibrary] {
        let libraries = await libraryProvider.getLibraries()
        return libraries.filter { id, library in
            !library.hidden && !library.server.removed && (libraryIds.isEmpty || libraryIds.contains(id))
        }
    }
}
