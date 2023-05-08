//
//  LibraryInfoCategoryItemsView.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/5/8.
//

import SwiftUI
import RealmSwift

struct LibraryInfoCategoryItemsView: View {
    @EnvironmentObject var modelData: ModelData
    
    @EnvironmentObject var viewModel: LibraryInfoView.ViewModel
    
    @ObservedRealmObject var unifiedCategory: CalibreUnifiedCategoryObject
    
    @ObservedResults(CalibreUnifiedSearchObject.self) var unifiedSearches
    
    var body: some View {
        List {
            ForEach(unifiedCategory.items.filter({ viewModel.categoryFilter.isEmpty || $0.name.localizedCaseInsensitiveContains(viewModel.categoryFilter) })) { categoryItem in
                NavigationLink(tag: categoryItem.name, selection: $viewModel.categoryItemSelected) {
                    bookListView()
                        .onAppear {
                            if modelData.filterCriteriaCategory[unifiedCategory.categoryName]?.contains(categoryItem.name) == true {
                                return
                            }
                            
                            resetSearchCriteria()
                            
                            modelData.filterCriteriaCategory[unifiedCategory.categoryName] = .init([categoryItem.name])
                            
                            if viewModel.categoriesSelected == "Series" {
                                if modelData.sortCriteria.by != .SeriesIndex {
                                    viewModel.lastSortCriteria.append(modelData.sortCriteria)
                                }
                                
                                modelData.sortCriteria.by = .SeriesIndex
                                modelData.sortCriteria.ascending = true
                            } else if viewModel.categoriesSelected == "Publisher" || viewModel.categoriesSelected == "Authors" {
                                if modelData.sortCriteria.by != .Publication {
                                    viewModel.lastSortCriteria.append(modelData.sortCriteria)
                                }
                                
                                modelData.sortCriteria.by = .Publication
                                modelData.sortCriteria.ascending = false
                            }
                            else {
                                modelData.sortCriteria.by = .Modified
                                modelData.sortCriteria.ascending = false
                            }
                            
                            resetToFirstPage()
                        }
                        .navigationTitle("\(unifiedCategory.categoryName): \(categoryItem.name)")
                } label: {
                    Text(categoryItem.name)
                }
                .isDetailLink(false)
            }
        }
    }
    
    @ViewBuilder
    private func bookListView() -> some View {
        Group {
            if let objectId = modelData.librarySearchManager.getUnifiedResultObjectIdForSwiftUI(libraryIds: modelData.filterCriteriaLibraries, searchCriteria: modelData.currentLibrarySearchCriteria),
                let unifiedSearch = unifiedSearches.where({
                $0._id == objectId
            }).first {
                LibraryInfoBookListView(unifiedSearchObject: unifiedSearch)
                    .environmentObject(viewModel)
            } else {
                Text("Preparing Book List")
            }
        }
        .statusBar(hidden: false)
    }
    
    func resetToFirstPage() {
        if modelData.filteredBookListPageNumber > 0 {
            modelData.filteredBookListPageNumber = 0
        } else {
            modelData.filteredBookListMergeSubject.send(modelData.currentLibrarySearchResultKey)
        }
    }
    
    func resetSearchCriteria() {
        modelData.filterCriteriaCategory.removeAll()
        modelData.filterCriteriaLibraries.removeAll()
    }
    
}

struct LibraryInfoCategoryItemsView_Previews: PreviewProvider {
    @ObservedResults(CalibreUnifiedCategoryObject.self, sortDescriptor: .init(keyPath: "categoryName")) static var unifiedCategories
    
    static var previews: some View {
        if let unifiedCategoryObject = unifiedCategories.first {
            LibraryInfoCategoryItemsView(unifiedCategory: unifiedCategoryObject)
        }
    }
}
