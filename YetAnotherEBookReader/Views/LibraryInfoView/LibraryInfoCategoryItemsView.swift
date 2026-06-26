//
//  LibraryInfoCategoryItemsView.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/5/8.
//

import SwiftUI

struct LibraryInfoCategoryItemsView: View {
    @EnvironmentObject var container: AppContainer
    
    @EnvironmentObject var viewModel: LibraryInfoView.ViewModel
    @EnvironmentObject var unifiedSearchViewModel: UnifiedSearchViewModel
    
    let categoryName: String
    @ObservedObject var categoryViewModel: UnifiedCategoryViewModel

    var body: some View {
        VStack {

            if let result = categoryViewModel.unifiedCategoryResult {
                if result.items.isEmpty,
                   result.itemsCount > 999,
                   result.totalNumber > 999 {
                    VStack {
                        Text("Found \(result.itemsCount) items, too many to list them all, please use filter")
                    }
                } else {
                    List {
                        ForEach(result.items) { categoryItem in
                            NavigationLink(tag: categoryItem.name, selection: $viewModel.categoryItemSelected) {
                                bookListView()
                                    .onAppear {
                                        if viewModel.filterCriteriaCategory[categoryName]?.contains(categoryItem.name) == true {
                                            return
                                        }
                                        
                                        resetSearchCriteria()
                                        
                                        viewModel.filterCriteriaCategory[categoryName] = .init([categoryItem.name])
                                        
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
                                        
                                        resetToFirstPage()
                                    }
                                    .navigationTitle("\(categoryName): \(categoryItem.name)")
                            } label: {
                                Text(categoryItem.name)
                            }
                            .isDetailLink(false)
                        }
                    }
                }
            } else if categoryViewModel.isLoading {
                ProgressView("Loading items...")
            } else {
                Text("No items")
            }
        }
        .toolbar {
            Button {
                categoryViewModel.forceRefreshCategory(categoryName: categoryName)
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
    }
    
    @ViewBuilder
    private func bookListView() -> some View {
        Group {
            if unifiedSearchViewModel.unifiedSearchResult != nil {
                LibraryInfoBookListView()
                    .environmentObject(unifiedSearchViewModel)
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
    
    func resetToFirstPage() {
        unifiedSearchViewModel.startSearch(key: viewModel.currentLibrarySearchResultKey)
    }
}
