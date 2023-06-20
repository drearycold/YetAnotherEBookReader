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
    
    @ObservedResults(CalibreLibraryCategoryObject.self, sortDescriptor: .init(keyPath: "libraryId")) var libraryCategories

    var body: some View {
        VStack {
            #if DEBUG
            List {
                ForEach(libraryCategories.where({ $0.categoryName == unifiedCategory.categoryName})) { libraryCategory in
                    VStack {
                        HStack {
                            Text(libraryCategory.libraryId)
                            Spacer()
                        }
                        HStack {
                            Text("\(libraryCategory.generation)")
                            Spacer()
                            Text("\(libraryCategory.items.count)")
                        }
                    }
                }
            }
            #endif

            if unifiedCategory.items.isEmpty,
               unifiedCategory.itemsCount > 999,
               unifiedCategory.totalNumber > 999 {
                VStack {
                    Text("Found \(unifiedCategory.itemsCount) items, too many to list them all, please use filter")
                }
            } else {
                List {
                    ForEach(unifiedCategory.items) { categoryItem in
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
        }
        .toolbar {
            Button {
//                modelData.librarySearchManager.refreshUnifiedCategoryResult(unifiedCategory.key)
                libraryCategories
                    .where({ $0.categoryName == unifiedCategory.categoryName}).forEach { libraryCategory in
                        
                        guard let library = modelData.calibreLibraries[libraryCategory.libraryId],
                            let realm = libraryCategory.realm?.thaw(),
                            let thawed = libraryCategory.thaw()
                        else {
                            return
                        }
                        
                        try! realm.write {
                            thawed.generation = .distantPast
                        }
                        
                        modelData.syncLibrarySubject.send(.init(library: library, autoUpdateOnly: true, incremental: true))
                    }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }

        }
    }
    
    @ViewBuilder
    private func bookListView() -> some View {
        Group {
//            if let objectId = modelData.librarySearchManager.getUnifiedResultObjectIdForSwiftUI(libraryIds: viewModel.filterCriteriaLibraries, searchCriteria: viewModel.currentLibrarySearchCriteria),
//                let unifiedSearch = unifiedSearches.where({
//                $0._id == objectId
//            }).first {
            if let unifiedSearch = viewModel.unifiedSearchObject {
//                if unifiedSearch.books.isEmpty {
//                    Text("Found 0 books")
//                } else {
                    LibraryInfoBookListView(unifiedSearchObject: unifiedSearch)
                        .environmentObject(viewModel)
//                }
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
        let cacheObj = modelData.librarySearchManager.retrieveUnifiedSearchObject(
            viewModel.filterCriteriaLibraries,
            viewModel.currentLibrarySearchCriteria,
            unifiedSearches
        )
        
        if cacheObj.realm == nil {
            $unifiedSearches.append(cacheObj)
        }
        
        viewModel.setUnifiedSearchObject(modelData: modelData, unifiedSearchObject: cacheObj)
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
