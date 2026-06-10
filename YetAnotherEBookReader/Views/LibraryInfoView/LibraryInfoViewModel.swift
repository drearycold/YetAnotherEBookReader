//
//  LibraryInfoViewModel.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/3/30.
//

import Foundation
import RealmSwift
import Combine

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
        
        @Published private(set) var unifiedSearchResult: UnifiedSearchResult?
        @Published var isSearchLoading: Bool = false
        
        var unifiedSearchUpdateCancellable: AnyCancellable?
        
        //category filters
        @Published var categoriesSelected: String? = nil
        @Published var categoryItemSelected: String? = nil
        
        @Published var categoryName: String = ""
        @Published var categoryFilter: String = ""
        
        @Published var lastSortCriteria: [LibrarySearchSort] = []
        
        @Published var categoryFilterString: String = ""
        
        @Published private(set) var unifiedCategoryObject: CalibreUnifiedCategoryObject?
        
        var unifiedCategoryUpdateCancellable: AnyCancellable?
        
        func expandSearchUnifiedBookLimit() {
            guard let result = unifiedSearchResult, result.limitNumber < result.totalNumber else { return }
            ModelData.shared?.librarySearchManager.unifiedSearchManager.expandLimit(for: currentLibrarySearchResultKey)
        }
        
        func startSearch(modelData: ModelData) {
            unifiedSearchUpdateCancellable?.cancel()
            unifiedSearchUpdateCancellable = nil
            
            let key = currentLibrarySearchResultKey
            unifiedSearchUpdateCancellable = modelData.librarySearchManager.unifiedSearchManager.publisher(for: key)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] result in
                    self?.unifiedSearchResult = result
                    
                    if let activeSearch = modelData.librarySearchManager.unifiedSearchManager.getActiveSearch(for: key) {
                        self?.isSearchLoading = activeSearch.libraryStatuses.values.contains { $0.loading }
                    } else {
                        self?.isSearchLoading = false
                    }
                }
        }
        
        func setUnifiedCategoryObject(_ modelData: ModelData, _ unifiedCategoryObject: CalibreUnifiedCategoryObject?) {
            unifiedCategoryUpdateCancellable?.cancel()
            unifiedCategoryUpdateCancellable = nil
            
            self.unifiedCategoryObject = unifiedCategoryObject
            
            guard let unifiedCategoryObject = unifiedCategoryObject
            else {
                return
            }
            
            self.unifiedCategoryUpdateCancellable =  modelData.realm.objects(CalibreLibraryCategoryObject.self)
                .where {
                    $0.categoryName == unifiedCategoryObject.categoryName
                }
                .changesetPublisher(keyPaths: ["items"])
                .sink { changes in
                    switch changes {
                    case .initial(_), .error(_):
                        break
                    case .update(_, deletions: let deletions, insertions: let insertions, modifications: let modifications):
                        modelData.librarySearchManager.refreshUnifiedCategoryResult(unifiedCategoryObject.key)
                    }
                }
        }
    }
}
