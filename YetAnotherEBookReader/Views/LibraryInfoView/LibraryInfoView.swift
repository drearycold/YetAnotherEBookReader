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
    let importBook: () -> Void
    @Binding var libraryToBrowse: String?

    init(importBook: @escaping () -> Void = {}, libraryToBrowse: Binding<String?> = .constant(nil)) {
        self.importBook = importBook
        self._libraryToBrowse = libraryToBrowse
    }
    
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
    @State private var preparedBrowseLibraryID: String?

    @State private var lastSortCriteria = [LibrarySearchSort]()
    
//    @State private var categoryFilterString = ""
    
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
            .background(
                NavigationLink(isActive: Binding(
                    get: { libraryToBrowse != nil },
                    set: { if !$0 { libraryToBrowse = nil } }
                )) {
                    if let libraryID = libraryToBrowse,
                       let library = container.libraryManager.calibreLibraries[libraryID] {
                        libraryBookListView(library, fromConnection: true)
                    }
                } label: {
                    EmptyView()
                }
                .isDetailLink(false)
            )
            .navigationTitle(Text("Library Browser"))
            .environmentObject(viewModel)
            .environmentObject(unifiedSearchViewModel)
        }   //NavigationView
        .accessibilityIdentifier("screen.browse")
        .navigationViewStyle(.stack)
        .listStyle(PlainListStyle())
        .onAppear {
            viewModel.calibreLibraries = container.libraryManager.calibreLibraries
            viewModel.setupCategoryObserver()

            libraryList = container.libraryManager.calibreLibraries.values
                .filter { $0.hidden == false }
                .sorted { $0.name < $1.name }
        }
        .onDisappear {
            viewModel.stopCategoryObserver()
        }
        .onChange(of: libraryToBrowse) { libraryID in
            if libraryID == nil { preparedBrowseLibraryID = nil }
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
                        _ = viewModel.consumePreserveFilterCriteriaOnNextBookListAppear()
                        viewModel.filterCriteriaLibraries = []
                        viewModel.fetchAvailableCategories()
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
                    libraryBookListView(library)
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
                .accessibilityIdentifier(library.name == "UI Test Library" ? "browse.library.ui-test" : "browse.library.\(library.id)")
            }
        } header: {
            Text("By Library")
        }
    }

    private func libraryBookListView(_ library: CalibreLibrary, fromConnection: Bool = false) -> some View {
        bookListView()
            .navigationTitle(Text(library.name))
            .onAppear {
                viewModel.calibreLibraries = container.libraryManager.calibreLibraries
                let preserveFilters = viewModel.consumePreserveFilterCriteriaOnNextBookListAppear()
                let startsConnectedLibrary = fromConnection && preparedBrowseLibraryID != library.id
                if startsConnectedLibrary || !preserveFilters {
                    resetSearchCriteria()
                    if !startsConnectedLibrary, let savedFilterCriteriaCategory = self.savedFilterCriteriaCategory {
                        viewModel.restoreFilterCriteriaCategory(savedFilterCriteriaCategory)
                    }
                    self.savedFilterCriteriaCategory = nil
                }
                if fromConnection { preparedBrowseLibraryID = library.id }
                viewModel.filterCriteriaLibraries = [library.id]
                viewModel.fetchAvailableCategories()
                resetToFirstPage()
            }
    }
    
    @ViewBuilder
    private func bookListView() -> some View {
        Group {
            if unifiedSearchViewModel.unifiedSearchResult != nil {
                LibraryInfoBookListView(importBook: importBook)
                    .environmentObject(unifiedSearchViewModel)
                    .environmentObject(viewModel)
            } else {
                Text("Preparing Book List")
            }
        }
        .statusBar(hidden: false)
    }
    
    func updateFilterCategory(key: String, value: String) {
        viewModel.addFilterCategory(key: key, value: value)
        resetToFirstPage()
    }
    
    func resetToFirstPage() {
        unifiedSearchViewModel.startSearch(key: viewModel.currentLibrarySearchResultKey)
    }
    
    func resetSearchCriteria() {
        viewModel.clearFilterCriteria()
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
