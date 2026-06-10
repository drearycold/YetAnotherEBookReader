//
//  ActiveSearch.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-10.
//

import Foundation

struct ActiveSearch: Equatable {
    let searchId: UUID
    let criteria: SearchCriteria
    let libraryIds: Set<String>
    var currentResult: UnifiedSearchResult
    var libraryStatuses: [String: LibrarySearchStatus]
    var lastProcessedSources: [String: LibrarySourceSearchResult]
    
    var isLoading: Bool {
        libraryStatuses.values.contains { $0.loading }
    }
    
    var error: SearchError? {
        libraryStatuses.values.compactMap { $0.error }.first
    }
    
    init(
        searchId: UUID = UUID(),
        criteria: SearchCriteria,
        libraryIds: Set<String>,
        currentResult: UnifiedSearchResult? = nil,
        libraryStatuses: [String: LibrarySearchStatus] = [:],
        lastProcessedSources: [String: LibrarySourceSearchResult] = [:]
    ) {
        self.searchId = searchId
        self.criteria = criteria
        self.libraryIds = libraryIds
        self.libraryStatuses = libraryStatuses
        self.lastProcessedSources = lastProcessedSources
        
        if let currentResult = currentResult {
            self.currentResult = currentResult
        } else {
            self.currentResult = UnifiedSearchResult(
                search: criteria.searchString,
                sortBy: criteria.sortCriteria.by,
                sortAsc: criteria.sortCriteria.ascending,
                filters: criteria.filterCriteriaCategory,
                libraryIds: libraryIds,
                unifiedOffsets: [:],
                totalNumber: 0,
                limitNumber: 100,
                books: []
            )
        }
    }
}
