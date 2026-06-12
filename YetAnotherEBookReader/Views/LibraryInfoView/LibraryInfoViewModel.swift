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
        
        //category filters
        @Published var categoriesSelected: String? = nil
        @Published var categoryItemSelected: String? = nil
        
        @Published var categoryName: String = ""
        @Published var categoryFilter: String = ""
        
        @Published var lastSortCriteria: [LibrarySearchSort] = []
        
        @Published var categoryFilterString: String = ""
        
        @Published var availableCategories: [CategoryCacheSummary] = []
        
        private var databaseObserver: AnyCancellable?
        
        func fetchAvailableCategories() {
            guard let modelData = ModelData.shared else { return }
            let repository = modelData.librarySearchManager.categoryCacheRepository
            if let summaries = try? repository?.fetchCategorySummaries() {
                self.availableCategories = summaries
            }
        }
        
        func setupDatabaseObserver() {
            guard let modelData = ModelData.shared, databaseObserver == nil else { return }
            
            fetchAvailableCategories()
            
            databaseObserver = modelData.realm.objects(CalibreLibraryCategoryObject.self)
                .changesetPublisher(keyPaths: ["items"])
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.fetchAvailableCategories()
                }
        }
    }
}
