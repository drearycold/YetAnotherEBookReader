//
//  LibraryInfoView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/25.
//

import SwiftUI
import OSLog
import Combine
import RealmSwift
import struct Kingfisher.KFImage

@available(macCatalyst 14.0, *)
struct LibraryInfoView: View {
    @EnvironmentObject var modelData: ModelData
    
    @ObservedResults(CalibreUnifiedSearchObject.self) var unifiedSearches
    
    @StateObject var viewModel = ViewModel()
    
//    @State private var categoriesSelected : String? = nil
//    @State private var categoryItemSelected: String? = nil
    
//    @State private var categoryName = ""
//    @State private var categoryFilter = ""
//    @State private var categoryItems = [String]()
    
//    private let categoryItemsTooLong = ["__TOO_LONG__CATEGORY_LIST__"]
    
    @State private var searchHistoryList = [String]()
    @State private var libraryList = [CalibreLibrary]()

    @State private var lastSortCriteria = [LibrarySearchSort]()
    
    @State private var searchString = ""
    @State private var categoryFilterString = ""
    
    @State private var selectedBookIds = Set<String>()
    @State private var downloadBookList = [CalibreBook]()
    @State private var updater = 0
    
    @State private var booksListInfoPresenting = false
    @State private var searchHistoryPresenting = false
    
    @State private var alertItem: AlertItem?
    
    @State private var batchDownloadSheetPresenting = false
    
    @State private var dismissAllCancellable: AnyCancellable?
    
    @State private var categoryItemListCancellable: AnyCancellable?
    @State private var categoryItemListUpdating = false
    
    @State private var savedFilterCriteriaCategory: [String: Set<String>]? = nil
    
    private var defaultLog = Logger()
    
    var body: some View {
        NavigationView {
            List {
//                Text("realm unifiedSearches \(unifiedSearches.count)")
//                ForEach(unifiedSearches) { unifiedSearchObject in
//                    NavigationLink {
//                        LibraryInfoBookListView(unifiedSearchObject: unifiedSearchObject)
//                    } label: {
//                        Text(unifiedSearchObject.parameters)
//                    }
//                    .isDetailLink(false)
//                }
                
                combinedListView()
                
                if modelData.calibreLibraryCategoryMerged.isEmpty == false {
                    LibraryInfoCategoryListView()
                }
                
                libraryListView()
                
            }
            .padding(4)
            .navigationTitle(Text("Library Browser"))
            .environmentObject(viewModel)
        }   //NavigationView
        .navigationViewStyle(.stack)
        .listStyle(PlainListStyle())
        .onChange(of: modelData.filteredBookListPageNumber, perform: { value in
            modelData.filteredBookListMergeSubject.send(modelData.currentLibrarySearchResultKey)
        })
        .onAppear {
            libraryList = modelData.calibreLibraries.values
                .filter { $0.hidden == false }
                .sorted { $0.name < $1.name }
            
            dismissAllCancellable?.cancel()
            dismissAllCancellable = modelData.dismissAllSubject.sink { _ in
                batchDownloadSheetPresenting = false
            }
            
            categoryItemListCancellable?.cancel()
            categoryItemListCancellable = modelData.categoryItemListSubject
                .receive(on: DispatchQueue.main)
                .compactMap { categoryName -> String? in
                    guard categoryName == viewModel.categoriesSelected else { return nil }
                    
                    if categoryName == viewModel.categoryName,
                       viewModel.categoryFilter == viewModel.categoryFilterString.trimmingCharacters(in: .whitespacesAndNewlines),
                       viewModel.categoryFilter.isEmpty == false {
                        return nil
                    }
                    
                    viewModel.categoryName = categoryName
                    viewModel.categoryFilter = self.categoryFilterString.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    viewModel.categoryItems.removeAll(keepingCapacity: true)
                    self.categoryItemListUpdating = true
                    
                    return categoryName
                }
                .receive(on: DispatchQueue.global(qos: .userInitiated))
                .map { categoryName -> [String] in
                    guard var categoryItems = modelData.calibreLibraryCategoryMerged[viewModel.categoryName]
                    else { return [] }
                    
                    if viewModel.categoryFilter.isEmpty == false {
                        categoryItems = categoryItems.filter { $0.localizedCaseInsensitiveContains(viewModel.categoryFilter) }
                    }
                    
                    guard viewModel.categoryItems.count < 1000 else {
                        return viewModel.categoryItemsTooLong
                    }
                    
                    return categoryItems
                }
                .receive(on: DispatchQueue.main)
                .sink { categoryItems in
                    if categoryItems.isEmpty == false {
                        viewModel.categoryItems.append(contentsOf: categoryItems)
                    }
                    categoryItemListUpdating = false
                }
            
            modelData.filteredBookListMergeSubject.send(modelData.currentLibrarySearchResultKey)
        }
        
        //Body
    }   //View
    
    @ViewBuilder
    private func combinedListView() -> some View {
        Section {
            NavigationLink {
                bookListView()
                    .navigationTitle("All Books")
                    .onAppear {
//                        resetSearchCriteria()
                        modelData.filterCriteriaLibraries.removeAll()
                        resetToFirstPage()
                    }
                
            } label: {
                Text("All Books")
            }
            .isDetailLink(false)
        } header: {
            Text("Combined View")
        }
    }
    
    @ViewBuilder
    private func libraryListView() -> some View {
        Section {
            ForEach(libraryList, id: \.id) { library in
                NavigationLink {
                    bookListView()
                        .navigationTitle(Text(library.name))
                        .onAppear {
                            resetSearchCriteria()
                            if let savedFilterCriteriaCategory = self.savedFilterCriteriaCategory {
                                modelData.filterCriteriaCategory = savedFilterCriteriaCategory
                                self.savedFilterCriteriaCategory = nil
                            }
                            modelData.filterCriteriaLibraries.insert(library.id)
                            resetToFirstPage()
                        }
                } label: {
                    HStack {
                        Text(library.name)
                        Spacer()
                        Image(systemName: "server.rack")
                        Text(library.server.name)
                            .font(.caption)
                    }
                }
                .isDetailLink(false)
            }
        } header: {
            Text("By Library")
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
    
    func searchStringChanged(searchString: String) {
        self.searchString = searchString.trimmingCharacters(in: .whitespacesAndNewlines)
        modelData.searchString = self.searchString
        
        resetToFirstPage()
    }
    
    func updateFilterCategory(key: String, value: String) {
        if modelData.filterCriteriaCategory[key] == nil {
            modelData.filterCriteriaCategory[key] = .init()
        }
        modelData.filterCriteriaCategory[key]?.insert(value)
        
        resetToFirstPage()
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

extension LibraryInfoView : AlertDelegate {
    func alert(alertItem: AlertItem) {
        self.alertItem = alertItem
    }
}

@available(macCatalyst 14.0, *)
struct LibraryInfoView_Previews: PreviewProvider {
    static private var modelData = ModelData()
    static var previews: some View {
        LibraryInfoView()
            .environmentObject(ModelData())
    }
}
