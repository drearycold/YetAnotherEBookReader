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
        
        var sectionByString: KeyPath<CalibreBookRealm, String?>? {
            switch(self) {
            case .Library:
                return \CalibreBookRealm.libraryName
            case .Author:
                return \CalibreBookRealm.authorFirst
            case .Tag:
                return \CalibreBookRealm.tagFirst
            default:
                return nil
            }
        }
        
        var sectionByRating: KeyPath<CalibreBookRealm, Int>? {
            switch(self) {
            case .Rating:
                return \CalibreBookRealm.rating
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
        
        @Published private(set) var unifiedSearchObject: CalibreUnifiedSearchObject?
        
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
        
        func expandSearchUnifiedBookLimit(_ unifiedSearchObject: CalibreUnifiedSearchObject) {
            guard unifiedSearchObject.limitNumber < unifiedSearchObject.totalNumber,
                  let realm = unifiedSearchObject.realm?.thaw(),
                  let thawedObject = unifiedSearchObject.thaw()
            else {
                return
            }
            try! realm.write {
                thawedObject.limitNumber = min(unifiedSearchObject.limitNumber + 100, unifiedSearchObject.totalNumber)
            }
        }
        
        func setUnifiedSearchObject(modelData: ModelData, unifiedSearchObject: CalibreUnifiedSearchObject?) {
            unifiedSearchUpdateCancellable?.cancel()
            unifiedSearchUpdateCancellable = nil
            
            self.unifiedSearchObject = unifiedSearchObject
            
            guard let unifiedSearchObject = unifiedSearchObject
            else {
                return
            }
            
            let searchCriteria = SearchCriteria(
                searchString: unifiedSearchObject.search,
                sortCriteria: .init(by: unifiedSearchObject.sortBy, ascending: unifiedSearchObject.sortAsc),
                filterCriteriaCategory: unifiedSearchObject.filters.reduce(into: [:], { partialResult, filter in
                    if let values = filter.value?.values {
                        partialResult[filter.key] = Set(values)
                    }
                })
            )
            unifiedSearchUpdateCancellable = modelData.calibreUpdatedSubject.receive(on: DispatchQueue.main)
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
                            modelData.librarySearchManager.refreshSearchResults(libraryIds: [library.id], searchCriteria: searchCriteria)
                        }
                        break
                    case .server(_):
                        break
                    }
                })
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
