//
//  LibraryInfoBookListHeader.swift
//  YetAnotherEBookReader
//

import SwiftUI

struct LibraryInfoBookListHeader: View {
    @ObservedObject var listViewModel: LibraryInfoBookListViewModel
    @ObservedObject var libraryInfoViewModel: LibraryInfoView.ViewModel
    @ObservedObject var viewModel: UnifiedSearchViewModel
    let geometry: GeometryProxy

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    listViewModel.searchHistoryPresenting = true
                } label: {
                    Image(systemName: "chevron.down")
                }
                .popover(isPresented: $listViewModel.searchHistoryPresenting) {
                    Text("Search History")
                }

                TextField("Search Title & Authors", text: $listViewModel.searchString)
                    .onAppear {
                        listViewModel.syncDraftFromCriteria(libraryInfoViewModel.searchString)
                    }
                    .onSubmit {
                        listViewModel.submitSearch(libraryInfoViewModel: libraryInfoViewModel, searchViewModel: viewModel)
                    }
                    .keyboardType(.webSearch)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !listViewModel.searchString.isEmpty {
                    Button {
                        listViewModel.clearSearch(libraryInfoViewModel: libraryInfoViewModel, searchViewModel: viewModel)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }

                let categoryMenuItems = libraryInfoViewModel.availableCategoryMenuItems
                Group {
                    if categoryMenuItems.isEmpty {
                        Button {} label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .foregroundColor(.gray)
                        }
                        .disabled(true)
                    } else {
                        Menu {
                            ForEach(categoryMenuItems) { categoryItem in
                                Button {
                                    libraryInfoViewModel.headerCategorySelected = categoryItem.name
                                } label: {
                                    HStack {
                                        Text(categoryItem.name)
                                        Text("\(categoryItem.itemsCount)")
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .padding(.trailing, 4)
            }

            let filterItems = libraryInfoViewModel.visibleFilterItems
            if !filterItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button {
                            libraryInfoViewModel.clearCategoryFilters(searchViewModel: viewModel)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        .foregroundColor(.secondary)

                        ForEach(filterItems) { filterItem in
                            HStack(spacing: 4) {
                                Text("\(filterItem.key): \(filterItem.value)")
                                    .font(.caption)

                                Button {
                                    libraryInfoViewModel.removeFilterCategory(
                                        key: filterItem.key,
                                        value: filterItem.value,
                                        searchViewModel: viewModel
                                    )
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                            .foregroundColor(.accentColor)
                        }
                    }
                }
            }

            NavigationLink(
                isActive: Binding(
                    get: {
                        libraryInfoViewModel.headerCategorySelected != nil
                    },
                    set: { isActive in
                        if !isActive {
                            libraryInfoViewModel.headerCategorySelected = nil
                        }
                    }
                )
            ) {
                if let categoryName = libraryInfoViewModel.headerCategorySelected {
                    CategoryDetailView(categoryName: categoryName, preservesLibraryScope: true)
                        .environmentObject(libraryInfoViewModel)
                        .environmentObject(viewModel)
                } else {
                    EmptyView()
                }
            } label: {
                EmptyView()
            }
            .hidden()
        }
    }
}
