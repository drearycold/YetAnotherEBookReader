//
//  LibraryInfoCategoryItemsView.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/5/8.
//

import SwiftUI

struct LibraryInfoCategoryItemsView: View {
    @Environment(\.appContainer) var container
    
    @EnvironmentObject var viewModel: LibraryInfoView.ViewModel
    @EnvironmentObject var unifiedSearchViewModel: UnifiedSearchViewModel
    
    let categoryName: String
    let preservesLibraryScope: Bool
    @ObservedObject var categoryViewModel: UnifiedCategoryViewModel

    init(
        categoryName: String,
        preservesLibraryScope: Bool = false,
        categoryViewModel: UnifiedCategoryViewModel
    ) {
        self.categoryName = categoryName
        self.preservesLibraryScope = preservesLibraryScope
        self.categoryViewModel = categoryViewModel
    }

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
                            categoryItemRow(categoryItem)
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
                categoryViewModel.forceRefreshCategory(
                    categoryName: categoryName,
                    libraryIds: viewModel.filterCriteriaLibraries
                )
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
    }

    @ViewBuilder
    private func categoryItemRow(_ categoryItem: UnifiedCategoryItem) -> some View {
        if preservesLibraryScope {
            Button {
                selectHeaderCategoryItem(categoryItem.name)
            } label: {
                Text(categoryItem.name)
            }
        } else {
            NavigationLink(tag: categoryItem.name, selection: $viewModel.categoryItemSelected) {
                bookListView()
                    .onAppear {
                        selectRootCategoryItem(categoryItem.name)
                    }
                    .navigationTitle("\(categoryName): \(categoryItem.name)")
            } label: {
                Text(categoryItem.name)
            }
            .isDetailLink(false)
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
        viewModel.clearFilterCriteria()
    }
    
    func resetToFirstPage() {
        unifiedSearchViewModel.startSearch(key: viewModel.currentLibrarySearchResultKey)
    }

    private func selectHeaderCategoryItem(_ itemName: String) {
        viewModel.applyCategoryItemSelection(
            categoryName: categoryName,
            itemName: itemName,
            preservingLibraryScope: true
        )
        resetToFirstPage()
        viewModel.preserveFilterCriteriaOnNextBookListAppear()
        viewModel.headerCategorySelected = nil
    }

    private func selectRootCategoryItem(_ itemName: String) {
        if viewModel.filterCriteriaCategory[categoryName]?.contains(itemName) == true {
            return
        }

        viewModel.applyCategoryItemSelection(
            categoryName: categoryName,
            itemName: itemName,
            preservingLibraryScope: false
        )
        resetToFirstPage()
    }
}
