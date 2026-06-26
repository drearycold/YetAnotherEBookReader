//
//  LibraryInfoCategoryListView.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/3/29.
//

import SwiftUI

struct LibraryInfoCategoryListView: View {
    @EnvironmentObject var modelData: ModelData
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
    @EnvironmentObject var modelData: ModelData
    @EnvironmentObject var viewModel: LibraryInfoView.ViewModel
    @EnvironmentObject var unifiedSearchViewModel: UnifiedSearchViewModel
    @StateObject private var categoryViewModel = UnifiedCategoryViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                TextField("Filter \(categoryName)", text: $viewModel.categoryFilterString, onCommit: {
                    triggerMerge()
                })
                .keyboardType(.webSearch)
                .padding([.leading, .trailing], 24)
                .onChange(of: viewModel.categoryFilterString) { newValue in
                    viewModel.categoryFilter = viewModel.categoryFilterString.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                HStack {
                    Spacer()
                    Button {
                        viewModel.categoryFilterString = ""
                        viewModel.categoryFilter = ""
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
            
            LibraryInfoCategoryItemsView(categoryName: categoryName, categoryViewModel: categoryViewModel)
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
            if viewModel.categoriesSelected == nil {
                viewModel.categoryName = ""
            }
        }
    }
    
    private func triggerMerge() {
        viewModel.categoryName = categoryName
        categoryViewModel.mergeCategory(categoryName: categoryName, searchString: viewModel.categoryFilter)
    }
}
