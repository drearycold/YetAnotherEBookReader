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
    
    @ObservedResults(CalibreUnifiedCategoryObject.self, where: { $0.items.count > 0 }) var unifiedCategories
    
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
    
//    @State private var categoryFilterString = ""
    
    @State private var selectedBookIds = Set<String>()
    
    @State private var booksListInfoPresenting = false
    @State private var searchHistoryPresenting = false
    
    @State private var alertItem: AlertItem?
    
    @State private var batchDownloadSheetPresenting = false
    
    @State private var dismissAllCancellable: AnyCancellable?
    
    @State private var savedFilterCriteriaCategory: [String: Set<String>]? = nil
    
    private var defaultLog = Logger()
    
    var body: some View {
        NavigationView {
            List {
                combinedListView()
                
                if unifiedCategories.isEmpty == false {
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
        .onAppear {
            viewModel.calibreLibraries = modelData.calibreLibraries
            
            libraryList = modelData.calibreLibraries.values
                .filter { $0.hidden == false }
                .sorted { $0.name < $1.name }
            
            dismissAllCancellable?.cancel()
            dismissAllCancellable = modelData.dismissAllSubject.sink { _ in
                batchDownloadSheetPresenting = false
            }
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
                        viewModel.filterCriteriaLibraries.removeAll()
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
                                viewModel.filterCriteriaCategory = savedFilterCriteriaCategory
                                self.savedFilterCriteriaCategory = nil
                            }
                            viewModel.filterCriteriaLibraries.insert(library.id)
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
//            if let objectId = modelData.librarySearchManager.getUnifiedResultObjectIdForSwiftUI(libraryIds: viewModel.filterCriteriaLibraries, searchCriteria: viewModel.currentLibrarySearchCriteria),
//                let unifiedSearch = unifiedSearches.where({
//                $0._id == objectId
//            }).first {
            if let unifiedSearch = viewModel.unifiedSearchObject {
                LibraryInfoBookListView(unifiedSearchObject: unifiedSearch)
                    .environmentObject(viewModel)
            } else {
                Text("Preparing Book List")
            }
        }
        .statusBar(hidden: false)
    }
    
    func updateFilterCategory(key: String, value: String) {
        if viewModel.filterCriteriaCategory[key] == nil {
            viewModel.filterCriteriaCategory[key] = .init()
        }
        viewModel.filterCriteriaCategory[key]?.insert(value)
        
        resetToFirstPage()
    }
    
    func resetToFirstPage() {
        guard let cacheObj = viewModel.retrieveUnifiedSearchObject(modelData: modelData, unifiedSearches: unifiedSearches)
        else {
            return
            
        }
        
        if cacheObj.realm == nil {
            $unifiedSearches.append(cacheObj)
        }
        
        viewModel.setUnifiedSearchObject(modelData: modelData, unifiedSearchObject: cacheObj)
    }
    
    func resetSearchCriteria() {
        viewModel.filterCriteriaCategory.removeAll()
        viewModel.filterCriteriaLibraries.removeAll()
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
