//
//  UnifiedSearchViewModel.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-11.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class UnifiedSearchViewModel: ObservableObject {
    @Published var searchString = ""
    @Published var sortCriteria = LibrarySearchSort(by: .Modified, ascending: false)
    @Published var filterCriteriaCategory = [String: Set<String>]()
    @Published var filterCriteriaLibraries = Set<String>()
    
    @Published var sectionedBy: LibraryInfoView.GroupKey?
    @Published var categoriesSelected: String? = nil
    @Published var categoryItemSelected: String? = nil
    
    @Published private(set) var unifiedSearchResult: UnifiedSearchResult?
    @Published private(set) var isSearchLoading = false
    
    private let searchService: UnifiedSearchService
    private let modelData: ModelData
    private var searchTask: Task<Void, Never>?
    
    var currentLibrarySearchResultKey: SearchCriteriaMergedKey {
        let activeLibraries = filterCriteriaLibraries.isEmpty ? modelData.calibreLibraries.reduce(into: Set<String>(), { partialResult, entry in
            if entry.value.hidden == false,
               entry.value.server.removed == false {
                partialResult.insert(entry.key)
            }
        }) : filterCriteriaLibraries
        
        return .init(
            libraryIds: activeLibraries,
            criteria: .init(
                searchString: self.searchString,
                sortCriteria: self.sortCriteria,
                filterCriteriaCategory: self.filterCriteriaCategory
            )
        )
    }
    
    init(searchService: UnifiedSearchService? = nil, modelData: ModelData? = nil) {
        guard let resolvedModelData = modelData ?? ModelData.shared else {
            fatalError("ModelData.shared must be initialized before creating UnifiedSearchViewModel")
        }
        self.modelData = resolvedModelData
        self.searchService = searchService ?? resolvedModelData.librarySearchManager.unifiedSearchService
    }
    
    func startSearch() {
        searchTask?.cancel()
        isSearchLoading = true
        
        let key = currentLibrarySearchResultKey
        
        searchTask = Task {
            let stream = await searchService.search(key: key)
            for await result in stream {
                guard !Task.isCancelled else { break }
                self.unifiedSearchResult = result
                self.isSearchLoading = result.libraryStatuses.values.contains { $0.loading }
            }
            if !Task.isCancelled {
                self.isSearchLoading = false
            }
        }
    }
    
    func expandSearchUnifiedBookLimit() {
        guard let result = unifiedSearchResult, result.limitNumber < result.totalNumber else { return }
        let key = currentLibrarySearchResultKey
        
        Task {
            await searchService.expandLimit(for: key)
        }
    }
    
    func resetSearch(force: Bool) {
        let key = currentLibrarySearchResultKey
        Task {
            await searchService.resetSearch(for: key, force: force)
        }
    }
}
