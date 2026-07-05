//
//  LibraryInfoCategoryListView.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/3/29.
//

import SwiftUI

struct LibraryInfoCategoryListView: View {
    @Environment(\.appContainer) var container
    @EnvironmentObject var viewModel: LibraryInfoView.ViewModel
    @EnvironmentObject var unifiedSearchViewModel: UnifiedSearchViewModel

    var body: some View {
        Section {
            ForEach(viewModel.availableCategories) { summary in
                NavigationLink(tag: summary.categoryName, selection: $viewModel.categoriesSelected) {
                    CategoryDetailView(categoryName: summary.categoryName)
                        .environmentObject(viewModel)
                        .environmentObject(unifiedSearchViewModel)
                } label: {
                    #if DEBUG
                    HStack {
                        Text(summary.categoryName)
                        Spacer()
                        Text("\(summary.itemsCount) (\(summary.totalNumber))")
                    }
                    #else
                    Text(summary.categoryName)
                    #endif
                }
                .isDetailLink(false)
            }
        } header: {
            Text("Browse by Category")
        }
    }
}

struct CategoryDetailView: View {
    let categoryName: String
    let preservesLibraryScope: Bool
    @Environment(\.appContainer) var container
    @EnvironmentObject var viewModel: LibraryInfoView.ViewModel
    @EnvironmentObject var unifiedSearchViewModel: UnifiedSearchViewModel
    @StateObject private var categoryViewModel = UnifiedCategoryViewModel()
    @State private var filterReloadTask: Task<Void, Never>?

    init(categoryName: String, preservesLibraryScope: Bool = false) {
        self.categoryName = categoryName
        self.preservesLibraryScope = preservesLibraryScope
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                TextField("Filter \(categoryName)", text: $viewModel.categoryFilterString, onCommit: {
                    filterReloadTask?.cancel()
                    triggerMerge()
                })
                .keyboardType(.webSearch)
                .padding([.leading, .trailing], 24)
                .onChange(of: viewModel.categoryFilterString) { newValue in
                    viewModel.categoryFilter = viewModel.categoryFilterString.trimmingCharacters(in: .whitespacesAndNewlines)
                    scheduleFilterReload()
                }
                HStack {
                    Spacer()
                    Button {
                        viewModel.categoryFilterString = ""
                        viewModel.categoryFilter = ""
                        filterReloadTask?.cancel()
                        triggerMerge()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .disabled(viewModel.categoryFilterString.isEmpty)
                    
                }.padding([.leading, .trailing], 4)
            }
            .frame(height: 44)
            
            Divider()
            
            LibraryInfoCategoryItemsView(
                categoryName: categoryName,
                preservesLibraryScope: preservesLibraryScope,
                categoryViewModel: categoryViewModel
            )
                .environmentObject(viewModel)
                .environmentObject(unifiedSearchViewModel)
        }
        .navigationTitle("Category: \(categoryName)")
        .onAppear {
            viewModel.categoryFilterString = ""
            viewModel.categoryFilter = ""
            triggerMerge()
        }
        .onDisappear {
            filterReloadTask?.cancel()
            if viewModel.categoriesSelected == nil {
                viewModel.categoryName = ""
            }
        }
    }
    
    private func triggerMerge() {
        viewModel.categoryName = categoryName
        let scopedLibraryIds = preservesLibraryScope ? viewModel.filterCriteriaLibraries : []
        categoryViewModel.reloadCategory(
            categoryName: categoryName,
            searchString: viewModel.categoryFilter,
            libraryIds: scopedLibraryIds
        )
    }

    private func scheduleFilterReload() {
        filterReloadTask?.cancel()
        filterReloadTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                triggerMerge()
            }
        }
    }
}
