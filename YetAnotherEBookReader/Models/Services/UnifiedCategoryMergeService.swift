//
//  UnifiedCategoryMergeService.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-12.
//

import Foundation

struct UnifiedCategoryMergeService: Sendable {
    func merge(
        categoryName: String,
        searchString: String,
        results: [LibraryCategoryResult]
    ) -> UnifiedCategoryResult {
        var grouped: [String: [String: LibraryCategoryItem]] = [:] // Name -> [LibraryId -> Item]
        
        for result in results {
            let libraryId = result.libraryId
            for item in result.items {
                if !searchString.isEmpty {
                    guard item.name.localizedCaseInsensitiveContains(searchString) else { continue }
                }
                
                var entry = grouped[item.name] ?? [:]
                entry[libraryId] = item
                grouped[item.name] = entry
            }
        }
        
        var unifiedItems: [UnifiedCategoryItem] = []
        var totalNumber = 0
        
        for (name, libItems) in grouped {
            let stats = libItems.values.reduce((0, 0.0)) { partialResult, item in
                (partialResult.0 + item.count, partialResult.1 + item.averageRating * Double(item.count))
            }
            let totalCount = stats.0
            let avgRating = totalCount > 0 ? stats.1 / Double(totalCount) : 0.0
            
            let unifiedItem = UnifiedCategoryItem(
                categoryName: categoryName,
                name: name,
                averageRating: avgRating,
                count: totalCount,
                libraryItems: libItems
            )
            unifiedItems.append(unifiedItem)
            totalNumber += totalCount
        }
        
        // Sort items alphabetically by name
        unifiedItems.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        
        return UnifiedCategoryResult(
            categoryName: categoryName,
            search: searchString,
            totalNumber: totalNumber,
            itemsCount: unifiedItems.count,
            items: unifiedItems
        )
    }
}
