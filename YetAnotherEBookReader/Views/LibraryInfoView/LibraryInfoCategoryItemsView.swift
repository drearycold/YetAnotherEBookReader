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
    @State private var draftSelectedItemNames = Set<String>()
    @State private var didInitializeDraftSelection = false

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
            if !categoryViewModel.items.isEmpty {
                List {
                    ForEach(categoryViewModel.items) { categoryItem in
                        categoryItemRow(categoryItem)
                            .onAppear {
                                categoryViewModel.loadNextPageIfNeeded(currentItem: categoryItem)
                            }
                    }

                    if categoryViewModel.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("\(LibraryInfoAccessibilityID.category(categoryName)).items")
            } else if categoryViewModel.isLoading {
                ProgressView("Loading items...")
            } else {
                Text("No items")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    let scopedLibraryIds = preservesLibraryScope ? viewModel.filterCriteriaLibraries : []
                    categoryViewModel.forceRefreshCategory(
                        categoryName: categoryName,
                        libraryIds: scopedLibraryIds
                    )
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("\(LibraryInfoAccessibilityID.category(categoryName)).refresh")

                if preservesLibraryScope {
                    Button("Done") {
                        applyHeaderCategorySelection()
                    }
                    .accessibilityIdentifier("\(LibraryInfoAccessibilityID.category(categoryName)).done")
                }
            }
        }
        .onAppear {
            initializeHeaderDraftSelectionIfNeeded()
        }
    }

    @ViewBuilder
    private func categoryItemRow(_ categoryItem: UnifiedCategoryItem) -> some View {
        if preservesLibraryScope {
            Button {
                toggleDraftCategoryItem(categoryItem.name)
            } label: {
                HStack {
                    Text(categoryItem.name)
                    Spacer()
                    if draftSelectedItemNames.contains(categoryItem.name) {
                        Image(systemName: "checkmark")
                    }
                }
                .accessibilityIdentifier(LibraryInfoAccessibilityID.categoryItem(categoryName, itemName: categoryItem.name))
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
            .accessibilityIdentifier(LibraryInfoAccessibilityID.categoryItem(categoryName, itemName: categoryItem.name))
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

    private func initializeHeaderDraftSelectionIfNeeded() {
        guard preservesLibraryScope, !didInitializeDraftSelection else { return }
        draftSelectedItemNames = viewModel.filterCriteriaCategory[categoryName] ?? []
        didInitializeDraftSelection = true
    }

    private func toggleDraftCategoryItem(_ itemName: String) {
        if draftSelectedItemNames.contains(itemName) {
            draftSelectedItemNames.remove(itemName)
        } else {
            draftSelectedItemNames.insert(itemName)
        }
    }

    private func applyHeaderCategorySelection() {
        viewModel.applyCategoryValuesSelection(
            categoryName: categoryName,
            itemNames: draftSelectedItemNames,
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
