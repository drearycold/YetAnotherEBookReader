//
//  LibraryInfoViewModel.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/3/30.
//

import Foundation
import SwiftUI

extension LibraryInfoView {
    enum GroupKey: String, CaseIterable, Identifiable, CustomStringConvertible {
        var id: String {
            self.rawValue
        }
        
        var description: String {
            self.rawValue
        }
        
     
        case Library
        case Author
        case Tag
        case Rating
        
        var groupString: ((CalibreBook) -> String?)? {
            switch(self) {
            case .Library:
                return { $0.library.name }
            case .Author:
                return { $0.authors.first }
            case .Tag:
                return { $0.tags.first }
            default:
                return nil
            }
        }
        
        var groupRating: ((CalibreBook) -> Int)? {
            switch(self) {
            case .Rating:
                return { $0.rating }
            default:
                return nil
            }
        }
    }

    
    @MainActor class ViewModel: ObservableObject {
        struct VisibleFilterItem: Identifiable, Equatable {
            let key: String
            let value: String

            var id: String {
                "\(key)\u{0}\(value)"
            }
        }

        struct HeaderCategoryMenuItem: Identifiable, Equatable {
            let name: String
            let itemsCount: Int
            let totalNumber: Int

            var id: String {
                name
            }
        }

        var calibreLibraries: [String: CalibreLibrary] = [:]
        
        //booklist group
        @Published var sectionedBy: GroupKey?
        
        //booklist filters
        @Published var searchString = ""
        @Published var sortCriteria = LibrarySearchSort(by: SortCriteria.Modified, ascending: false)
        @Published var filterCriteriaCategory = [String: Set<String>]()

        @Published var filterCriteriaLibraries = Set<String>()

        var currentLibrarySearchCriteria: SearchCriteria {
            SearchCriteria(
                searchString: self.searchString,
                sortCriteria: self.sortCriteria,
                filterCriteriaCategory: self.filterCriteriaCategory
            )
        }
        
        var currentLibrarySearchResultKey: SearchCriteriaMergedKey {
            .init(
                libraryIds: filterCriteriaLibraries.isEmpty ? self.calibreLibraries.reduce(into: Set<String>(), { partialResult, entry in
                    if entry.value.hidden == false,
                       entry.value.server.removed == false {
                        partialResult.insert(entry.key)
                    }
                }) : filterCriteriaLibraries,
                criteria: .init(
                    searchString: self.searchString,
                    sortCriteria: self.sortCriteria,
                    filterCriteriaCategory: self.filterCriteriaCategory
                )
            )
        }
        
        //category filters
        @Published var categoriesSelected: String? = nil
        @Published var categoryItemSelected: String? = nil
        
        @Published var categoryName: String = ""
        @Published var categoryFilter: String = ""
        
        @Published var lastSortCriteria: [LibrarySearchSort] = []
        
        @Published var categoryFilterString: String = ""
        
        @Published var availableCategories: [CategoryCacheSummary] = []
        @Published var headerCategorySelected: String? = nil

        private var preservesFilterCriteriaOnNextBookListAppear = false
        
        private var categoryObserverTask: Task<Void, Never>?

        var visibleFilterItems: [VisibleFilterItem] {
            filterCriteriaCategory
                .flatMap { key, values in
                    values.map { VisibleFilterItem(key: key, value: $0) }
                }
                .sorted {
                    if $0.key == $1.key {
                        return $0.value < $1.value
                    }
                    return $0.key < $1.key
                }
        }

        var availableCategoryMenuItems: [HeaderCategoryMenuItem] {
            availableCategories
                .map {
                    HeaderCategoryMenuItem(
                        name: $0.categoryName,
                        itemsCount: $0.itemsCount,
                        totalNumber: $0.totalNumber
                    )
                }
                .sorted { $0.name < $1.name }
        }

        var hasHeaderCategoryMenuContent: Bool {
            !availableCategoryMenuItems.isEmpty
        }
        
        func fetchAvailableCategories() {
            guard let container = AppContainer.shared else { return }
            let repository = container.categoryCacheRepository
            if let summaries = try? repository.fetchCategorySummaries() {
                self.availableCategories = summaries
            }
        }
        
        func setupCategoryObserver() {
            guard let container = AppContainer.shared, categoryObserverTask == nil else { return }

            categoryObserverTask = Task { @MainActor [weak self, repository = container.categoryCacheRepository] in
                for await summaries in repository.observeCategorySummaries() {
                    guard !Task.isCancelled else { break }
                    self?.availableCategories = summaries
                }
            }
        }
        
        deinit {
            categoryObserverTask?.cancel()
        }
        
        func getLibraryLoadingCount(container: AppContainer, searchResult: UnifiedSearchResult?, libraryStatuses: [String: LibrarySearchStatus]) -> Int {
            guard let result = searchResult else { return 0 }
            return container.libraryManager.calibreLibraries
                .filter({
                    $0.value.hidden == false
                    &&
                    $0.value.server.removed == false
                    &&
                    (result.libraryIds.isEmpty || result.libraryIds.contains($0.key))
                })
                .map({
                    $0.key
                })
                .reduce(0, { partialResult, libraryId in
                    if result.unifiedOffsets[libraryId] == nil {
                        return partialResult + 1
                    }
                    if libraryStatuses[libraryId]?.loading == true {
                        return partialResult + 1
                    }
                    return partialResult
                })
        }
        
        func getLibrarySearchingText(container: AppContainer, searchResult: UnifiedSearchResult?, libraryStatuses: [String: LibrarySearchStatus]) -> String {
            let librariesLoading = getLibraryLoadingCount(container: container, searchResult: searchResult, libraryStatuses: libraryStatuses)
            
            guard let result = searchResult else { return "Preparing Book List" }
            
            let offsets = result.unifiedOffsets.filter {
                $0.value.searchObjectSource.isEmpty == false
            }
            
            var text = ""
            
            if offsets.count < 1 {
                if librariesLoading > 0 {
                    text = "Still searching \(librariesLoading) libraries"
                } else {
                    text = "Cannot find in any library"
                }
            } else {
                text = "From \(offsets.count) \(offsets.count == 1 ? "library" : "libraries")"
                
                if librariesLoading > 0 {
                    text += ", \(librariesLoading) to go"
                }
            }
            
            return text
        }
        
        func searchStringChanged(searchString: String, searchViewModel: UnifiedSearchViewModel) {
            let trimmed = searchString.trimmingCharacters(in: .whitespacesAndNewlines)
            self.searchString = trimmed
            searchViewModel.startSearch(key: self.currentLibrarySearchResultKey)
        }

        func restoreFilterCriteriaCategory(_ filters: [String: Set<String>]) {
            filterCriteriaCategory = filters
        }

        func replaceFilterCategory(key: String, value: String, preservingLibraryScope: Bool = false) {
            filterCriteriaCategory = [key: Set([value])]
            if !preservingLibraryScope {
                filterCriteriaLibraries = []
            }
        }

        func applyCategoryItemSelection(
            categoryName: String,
            itemName: String,
            preservingLibraryScope: Bool = false
        ) {
            replaceFilterCategory(
                key: categoryName,
                value: itemName,
                preservingLibraryScope: preservingLibraryScope
            )

            if categoryName == "Series" {
                if sortCriteria.by != .SeriesIndex {
                    lastSortCriteria.append(sortCriteria)
                }

                sortCriteria.by = .SeriesIndex
                sortCriteria.ascending = true
            } else if categoryName == "Publisher" || categoryName == "Authors" {
                if sortCriteria.by != .Publication {
                    lastSortCriteria.append(sortCriteria)
                }

                sortCriteria.by = .Publication
                sortCriteria.ascending = false
            } else {
                sortCriteria.by = .Modified
                sortCriteria.ascending = false
            }
        }

        func preserveFilterCriteriaOnNextBookListAppear() {
            preservesFilterCriteriaOnNextBookListAppear = true
        }

        func consumePreserveFilterCriteriaOnNextBookListAppear() -> Bool {
            let shouldPreserve = preservesFilterCriteriaOnNextBookListAppear
            preservesFilterCriteriaOnNextBookListAppear = false
            return shouldPreserve
        }

        func addFilterCategory(key: String, value: String) {
            var filters = filterCriteriaCategory
            var values = filters[key] ?? Set<String>()
            values.insert(value)
            filters[key] = values
            filterCriteriaCategory = filters
        }

        func removeFilterCategory(key: String, value: String) {
            var filters = filterCriteriaCategory
            guard var values = filters[key] else { return }
            values.remove(value)
            if values.isEmpty {
                filters.removeValue(forKey: key)
            } else {
                filters[key] = values
            }
            filterCriteriaCategory = filters
        }

        func clearFilterCriteria() {
            filterCriteriaCategory = [:]
            filterCriteriaLibraries = []
        }

        func updateFilterCategory(key: String, value: String, searchViewModel: UnifiedSearchViewModel) {
            addFilterCategory(key: key, value: value)
            searchViewModel.startSearch(key: self.currentLibrarySearchResultKey)
        }

        func removeFilterCategory(key: String, value: String, searchViewModel: UnifiedSearchViewModel) {
            removeFilterCategory(key: key, value: value)
            searchViewModel.startSearch(key: self.currentLibrarySearchResultKey)
        }
        
        func resetToFirstPage(searchViewModel: UnifiedSearchViewModel) {
            searchViewModel.startSearch(key: self.currentLibrarySearchResultKey)
        }
    }
}
