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
        ZStack {
            TextField("Search Title & Authors", text: $listViewModel.searchString)
                .onAppear {
                    listViewModel.syncDraftFromCriteria(libraryInfoViewModel.searchString)
                }
                .onSubmit {
                    listViewModel.submitSearch(libraryInfoViewModel: libraryInfoViewModel, searchViewModel: viewModel)
                }
                .keyboardType(.webSearch)
                .padding([.leading, .trailing], 24)
            HStack {
                Button {
                    listViewModel.searchHistoryPresenting = true
                } label: {
                    Image(systemName: "chevron.down")
                }
                .popover(isPresented: $listViewModel.searchHistoryPresenting) {
                    Text("Search History")
                }
                .padding(.leading, 4)

                Spacer()
                Button {
                    listViewModel.clearSearch(libraryInfoViewModel: libraryInfoViewModel, searchViewModel: viewModel)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }.disabled(listViewModel.searchString.isEmpty)
                
                Menu {
                    ForEach(libraryInfoViewModel.filterCriteriaCategory.sorted(by: { $0.key < $1.key}), id: \.key) { categoryFilter in
                        ForEach(categoryFilter.value.filter({
                            categoryFilter.key != libraryInfoViewModel.categoriesSelected || $0 != libraryInfoViewModel.categoryItemSelected
                        }).sorted(), id: \.self) { categoryFilterValue in
                            Button {
                                if libraryInfoViewModel.filterCriteriaCategory[categoryFilter.key]?.remove(categoryFilterValue) != nil {
                                    if libraryInfoViewModel.filterCriteriaCategory[categoryFilter.key]?.isEmpty == true {
                                        libraryInfoViewModel.filterCriteriaCategory.removeValue(forKey: categoryFilter.key)
                                    }
                                    libraryInfoViewModel.searchStringChanged(searchString: listViewModel.searchString, searchViewModel: viewModel)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                    Text("\(categoryFilter.key): \(categoryFilterValue)")
                                }
                            }
                        }
                    }
                    
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(
                            libraryInfoViewModel.filterCriteriaCategory.filter({ categoryFilter in
                                categoryFilter.value.filter({
                                    categoryFilter.key != libraryInfoViewModel.categoriesSelected || $0 != libraryInfoViewModel.categoryItemSelected
                                }).isEmpty == false
                            }).isEmpty ? .gray : .accentColor
                        )
                }
                .padding(.trailing, 4)
            }
        }
    }
}
