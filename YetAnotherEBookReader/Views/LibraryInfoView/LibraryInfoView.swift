//
//  LibraryInfoView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/25.
//

import SwiftUI
import OSLog
//import struct Kingfisher.KFImage
import KingfisherSwiftUI

@available(macCatalyst 14.0, *)
struct LibraryInfoView: View {
    @Environment(\.appContainer) var container
    
    @StateObject var viewModel = ViewModel()
    @StateObject var unifiedSearchViewModel = UnifiedSearchViewModel()
    
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
    
    @State private var savedFilterCriteriaCategory: [String: Set<String>]? = nil
    
    private var defaultLog = Logger()
    
    var body: some View {
        NavigationView {
            List {
                combinedListView()
                
                if viewModel.availableCategories.isEmpty == false {
                    LibraryInfoCategoryListView()
                }
                
                libraryListView()
            }
            .padding(4)
            .navigationTitle(Text("Library Browser"))
            .environmentObject(viewModel)
            .environmentObject(unifiedSearchViewModel)
        }   //NavigationView
        .navigationViewStyle(.stack)
        .listStyle(PlainListStyle())
        .onAppear {
            viewModel.calibreLibraries = container.libraryManager.calibreLibraries
            viewModel.setupCategoryObserver()

            libraryList = container.libraryManager.calibreLibraries.values
                .filter { $0.hidden == false }
                .sorted { $0.name < $1.name }
        }
        .task {
            for await _ in container.dismissAllEvents() {
                guard !Task.isCancelled else { return }
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
    
    func updateFilterCategory(key: String, value: String) {
        if viewModel.filterCriteriaCategory[key] == nil {
            viewModel.filterCriteriaCategory[key] = .init()
        }
        viewModel.filterCriteriaCategory[key]?.insert(value)
        
        resetToFirstPage()
    }
    
    func resetToFirstPage() {
        unifiedSearchViewModel.startSearch(key: viewModel.currentLibrarySearchResultKey)
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
    static private var container = AppContainer()
    static var previews: some View {
        LibraryInfoView()
            .environment(\.appContainer, container)
    }
}
