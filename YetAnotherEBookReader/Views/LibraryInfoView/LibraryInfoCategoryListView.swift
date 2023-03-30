//
//  LibraryInfoCategoryListView.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/3/29.
//

import SwiftUI
import RealmSwift

struct LibraryInfoCategoryListView: View {
    @EnvironmentObject var modelData: ModelData
    
    @EnvironmentObject var viewModel: LibraryInfoView.ViewModel

    @ObservedResults(CalibreUnifiedSearchObject.self) var unifiedSearches
    
    var body: some View {
        Section {
            ForEach(modelData.calibreLibraryCategoryMerged.keys.sorted(), id: \.self) { categoryName in
                NavigationLink(tag: categoryName, selection: $viewModel.categoriesSelected) {
                    ZStack {
                        TextField("Filter \(categoryName)", text: $viewModel.categoryFilterString, onCommit: {
                            modelData.categoryItemListSubject.send(categoryName)
                        })
                        .keyboardType(.webSearch)
                        .padding([.leading, .trailing], 24)
                        HStack {
                            Spacer()
                            Button(action: {
                                viewModel.categoryFilterString = ""
                                modelData.categoryItemListSubject.send(categoryName)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }.disabled(viewModel.categoryFilterString.isEmpty)
                        }.padding([.leading, .trailing], 4)
                    }
                    
                    Divider()
                    
                    ZStack {
                        if viewModel.categoryItems == viewModel.categoryItemsTooLong {
                            VStack(alignment: .center) {
                                Spacer()
                                Text("Too many category items,")
                                Text("Please specify a filter.")
                                Spacer()
                            }
                        } else {
                            List {
                                ForEach(viewModel.categoryItems, id: \.self) { categoryItem in
                                    NavigationLink(tag: categoryItem, selection: $viewModel.categoryItemSelected) {
                                        bookListView()
                                            .onAppear {
                                                if modelData.filterCriteriaCategory[categoryName]?.contains(categoryItem) == true {
                                                    return
                                                }
                                                
                                                resetSearchCriteria()
                                                
                                                modelData.filterCriteriaCategory[categoryName] = .init([categoryItem])
                                                
                                                if viewModel.categoriesSelected == "Series" {
                                                    if modelData.sortCriteria.by != .SeriesIndex {
                                                        viewModel.lastSortCriteria.append(modelData.sortCriteria)
                                                    }
                                                    
                                                    modelData.sortCriteria.by = .SeriesIndex
                                                    modelData.sortCriteria.ascending = true
                                                } else if viewModel.categoriesSelected == "Publisher" {
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
                                            .navigationTitle("\(categoryName): \(categoryItem)")
                                    } label: {
                                        Text(categoryItem)
                                    }
                                    .isDetailLink(false)
                                }
                            }
                            //.disabled(categoryItemListUpdating) MARK: TODO
                        }
                        
                        /* MARK: TODO
                        if categoryItemListUpdating {
                            ProgressView()
                                .scaleEffect(4, anchor: .center)
                                .progressViewStyle(CircularProgressViewStyle())
                        }
                         */
                    }
                    .navigationTitle("Category: \(categoryName)")
                    .onAppear {
                        guard let categoryName = viewModel.categoriesSelected,
                              categoryName != viewModel.categoryName
                        else { return }
                        
                        viewModel.categoryFilterString = ""
                        modelData.categoryItemListSubject.send(categoryName)
                    }
                    .onDisappear {
                        if viewModel.categoriesSelected == nil {
                            viewModel.categoryName = ""
                            viewModel.categoryItems.removeAll(keepingCapacity: true)
                        }
                    }
                } label: {
                    Text(categoryName)
                }
                .isDetailLink(false)
            }
        } header: {
            Text("By Category")
        }
    }
    
    @ViewBuilder
    private func bookListView() -> some View {
        Group {
            if let objectId = modelData.librarySearchManager.getUnifiedResultObjectIdForSwiftUI(libraryIds: modelData.filterCriteriaLibraries, searchCriteria: modelData.currentLibrarySearchCriteria),
                let unifiedSearch = unifiedSearches.where({
                $0._id == objectId
            }).first {
                LibraryInfoBookListView(
                    unifiedSearchObject: unifiedSearch,
                    categoriesSelected: $viewModel.categoriesSelected,
                    categoryItemSelected: $viewModel.categoryItemSelected
                )
            } else {
                Text("Cannot get unified search")
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
        
        modelData.filterCriteriaShelved = .none
    }
    
    
}

//struct LibraryInfoCategoryListView_Previews: PreviewProvider {
//    static var previews: some View {
//        LibraryInfoCategoryListView()
//    }
//}
