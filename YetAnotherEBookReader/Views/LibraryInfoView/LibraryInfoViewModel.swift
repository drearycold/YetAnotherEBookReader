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
    @MainActor class ViewModel: ObservableObject {
        var calibreLibraries: [String: CalibreLibrary] = [:]
        
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
        
        @Published var unifiedSearchObject: CalibreUnifiedSearchObject?
        
        var libraryUpdateCancellable: AnyCancellable?
        
        //category filters
        @Published var categoriesSelected: String? = nil
        @Published var categoryItemSelected: String? = nil
        
        @Published var categoryName: String = ""
        @Published var categoryFilter: String = ""
        
        @Published var lastSortCriteria: [LibrarySearchSort] = []
        
        @Published var categoryFilterString: String = ""
        
        let categoryItemsTooLong = ["__TOO_LONG__CATEGORY_LIST__"]
        
        func updateUnifiedSearchObject(modelData: ModelData, unifiedSearches: Results<CalibreUnifiedSearchObject>) {
            let searchCriteria = currentLibrarySearchCriteria
            if let objectId = modelData.librarySearchManager.getUnifiedResultObjectIdForSwiftUI(libraryIds: filterCriteriaLibraries, searchCriteria: searchCriteria) {
                unifiedSearchObject = unifiedSearches.where { $0._id == objectId }.first
            } else {
                unifiedSearchObject = nil
            }
            
            libraryUpdateCancellable?.cancel()
            libraryUpdateCancellable = nil
            
            if let unifiedSearchObject = unifiedSearchObject {
                libraryUpdateCancellable = modelData.calibreUpdatedSubject.receive(on: DispatchQueue.main)
                    .sink(receiveValue: { calibreUpdatedSignal in
                        switch calibreUpdatedSignal {
                        case .shelf:
                            break
                        case .deleted(_):
                            break
                        case .book(_):
                            break
                        case .library(let library):
                            if unifiedSearchObject.unifiedOffsets[library.id] != nil {
                                modelData.librarySearchManager.refreshSearchResult(libraryIds: [library.id], searchCriteria: searchCriteria)
                            }
                            break
                        case .server(_):
                            break
                        }
                    })
            }
        }
    }
}
