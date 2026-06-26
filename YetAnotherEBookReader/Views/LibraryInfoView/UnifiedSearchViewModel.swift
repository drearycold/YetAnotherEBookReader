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
    @Published private(set) var unifiedSearchResult: UnifiedSearchResult?
    @Published private(set) var libraryStatuses = [String: LibrarySearchStatus]()
    @Published private(set) var isSearchLoading = false
    
    private let searchService: UnifiedSearchService
    private let container: AppContainer
    private var searchTask: Task<Void, Never>?
    
    private var currentSearchKey: SearchCriteriaMergedKey?
    
    init(searchService: UnifiedSearchService? = nil, container: AppContainer? = nil) {
        guard let resolvedAppContainer = container ?? AppContainer.shared else {
            fatalError("AppContainer.shared must be initialized before creating UnifiedSearchViewModel")
        }
        self.container = resolvedAppContainer
        self.searchService = searchService ?? resolvedAppContainer.unifiedSearchService
    }
    
    func startSearch(key: SearchCriteriaMergedKey) {
        searchTask?.cancel()
        currentSearchKey = key
        isSearchLoading = true
        
        searchTask = Task {
            let stream = await searchService.search(key: key)
            for await update in stream {
                guard !Task.isCancelled else { break }
                self.unifiedSearchResult = update.result
                self.libraryStatuses = update.statuses
                self.isSearchLoading = update.statuses.values.contains { $0.loading }
            }
            if !Task.isCancelled {
                self.isSearchLoading = false
            }
        }
    }
    
    func expandSearchUnifiedBookLimit() {
        guard let result = unifiedSearchResult, result.limitNumber < result.totalNumber, let key = currentSearchKey else { return }
        
        Task {
            await searchService.expandLimit(for: key)
        }
    }
    
    func resetSearch(force: Bool) {
        guard let key = currentSearchKey else { return }
        Task {
            await searchService.resetSearch(for: key, force: force)
        }
    }
}
