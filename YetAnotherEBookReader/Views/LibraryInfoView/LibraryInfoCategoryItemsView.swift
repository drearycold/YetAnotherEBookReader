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
                            if viewModel.filterCriteriaCategory[unifiedCategory.categoryName]?.contains(categoryItem.name) == true {
                                return
                            }
                            
                            resetSearchCriteria()
                            
                            viewModel.filterCriteriaCategory[unifiedCategory.categoryName] = .init([categoryItem.name])
                            
                            if viewModel.categoriesSelected == "Series" {
                                if viewModel.sortCriteria.by != .SeriesIndex {
                                    viewModel.lastSortCriteria.append(viewModel.sortCriteria)
                                }
                                
                                viewModel.sortCriteria.by = .SeriesIndex
                                viewModel.sortCriteria.ascending = true
                            } else if viewModel.categoriesSelected == "Publisher" || viewModel.categoriesSelected == "Authors" {
                                if viewModel.sortCriteria.by != .Publication {
                                    viewModel.lastSortCriteria.append(viewModel.sortCriteria)
                                }
                                
                                viewModel.sortCriteria.by = .Publication
                                viewModel.sortCriteria.ascending = false
                            }
                            else {
                                viewModel.sortCriteria.by = .Modified
                                viewModel.sortCriteria.ascending = false
                            }
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
            if let objectId = modelData.librarySearchManager.getUnifiedResultObjectIdForSwiftUI(libraryIds: viewModel.filterCriteriaLibraries, searchCriteria: viewModel.currentLibrarySearchCriteria),
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
    
    func resetSearchCriteria() {
        viewModel.filterCriteriaCategory.removeAll()
        viewModel.filterCriteriaLibraries.removeAll()
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
