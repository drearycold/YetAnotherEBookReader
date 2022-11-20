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
    
    @State private var categoriesSelected : String? = nil
    @State private var categoryItems = [String]()
    @State private var categoryItemSelected: String? = nil
    
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
    
    @State private var booksListCancellable: AnyCancellable?
    @State private var booksListQueryCancellable: AnyCancellable?
    
    @State private var dismissAllCancellable: AnyCancellable?

    private var errBook = CalibreBook(id: -1, library: CalibreLibrary(server: CalibreServer(uuid: .init(), name: "Error", baseUrl: "Error", hasPublicUrl: false, publicUrl: "Error", hasAuth: false, username: "Error", password: "Error"), key: "Error", name: "Error"))
    
    private var defaultLog = Logger()
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    NavigationLink {
                        bookListView()
                            .navigationTitle("All Books")
                            .onAppear {
                                resetSearchCriteria()
                                modelData.filteredBookListMergeSubject.send(LibrarySearchKey(libraryId: "", criteria: modelData.currentLibrarySearchCriteria))
                            }
                        
                    } label: {
                        Text("All Books")
                    }
                    .isDetailLink(false)
                } header: {
                    Text("Combined View")
                }
                
                Section {
                    ForEach(modelData.calibreLibraryCategoryMerged.keys.sorted(), id: \.self) { categoryName in
                        NavigationLink(tag: categoryName, selection: $categoriesSelected) {
                            ZStack {
                                TextField("Filter \(categoryName)", text: $categoryFilterString, onCommit: {
                                    updateCategoryItems(categoryName)
                                })
                                .keyboardType(.webSearch)
                                .padding([.leading, .trailing], 24)
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        categoryFilterString = ""
                                        updateCategoryItems(categoryName)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }.disabled(categoryFilterString.isEmpty)
                                }.padding([.leading, .trailing], 4)
                            }
                            
                            Divider()
                            
                            List {
                                ForEach(categoryItems, id: \.self) { categoryItem in
                                    NavigationLink(tag: categoryItem, selection: $categoryItemSelected) {
                                        bookListView()
                                            .onAppear {
                                                modelData.filteredBookList.removeAll()
                                                
                                                resetSearchCriteria()
                                                
                                                modelData.filterCriteriaCategory[categoryName] = categoryItem
                                                
                                                if categoriesSelected == "Series" {
                                                    if modelData.sortCriteria.by != .SeriesIndex {
                                                        lastSortCriteria.append(modelData.sortCriteria)
                                                    }
                                                    
                                                    modelData.sortCriteria.by = .SeriesIndex
                                                    modelData.sortCriteria.ascending = true
                                                } else if categoriesSelected == "Publisher" {
                                                    if modelData.sortCriteria.by != .Publication {
                                                        lastSortCriteria.append(modelData.sortCriteria)
                                                    }
                                                    
                                                    modelData.sortCriteria.by = .Publication
                                                    modelData.sortCriteria.ascending = false
                                                }
                                                else {
//                                                    if let lastSort = lastSortCriteria.popLast() {
//                                                        modelData.sortCriteria = lastSort
//                                                    }
                                                    modelData.sortCriteria.by = .Modified
                                                    modelData.sortCriteria.ascending = false
                                                }
                                                modelData.filteredBookListMergeSubject.send(LibrarySearchKey(libraryId: "", criteria: modelData.currentLibrarySearchCriteria))
                                            }
                                            .navigationTitle("\(categoryName): \(categoryItem)")
                                    } label: {
                                        Text(categoryItem)
                                    }
                                    .isDetailLink(false)
                                }
                            }
                            .navigationTitle("Category: \(categoryName)")
                        } label: {
                            Text(categoryName)
                        }
                        .isDetailLink(false)
                        .onChange(of: categoriesSelected) { categoryName in
                            guard let categoryName = categoryName else { return }
                            
                            categoryFilterString = ""
                            updateCategoryItems(categoryName)
                        }
                    }
                } header: {
                    Text("By Category")
                }
                
                Section {
                    ForEach(libraryList, id: \.id) { library in
                        NavigationLink {
                            bookListView()
                                .navigationTitle(Text(library.name))
                                .onAppear {
                                    resetSearchCriteria()
                                    modelData.filterCriteriaLibraries.insert(library.id)
                                    modelData.filteredBookListMergeSubject.send(.init(libraryId: library.id, criteria: modelData.currentLibrarySearchCriteria))
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
            .padding(4)
            .navigationTitle(Text("Library Browser"))
        }   //NavigationView
        .navigationViewStyle(ColumnNavigationViewStyle.columns)
        .listStyle(PlainListStyle())
        .onChange(of: modelData.filteredBookListPageNumber, perform: { value in
            NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
        })
        .onAppear {
            dismissAllCancellable?.cancel()
            dismissAllCancellable = modelData.dismissAllPublisher.sink { _ in
                batchDownloadSheetPresenting = false
            }
            
            booksListCancellable?.cancel()
            booksListCancellable = modelData.libraryBookListNeedUpdate
                .receive(on: DispatchQueue.global(qos: .userInitiated))
                .flatMap { _ -> AnyPublisher<Int, Never> in
                    updateBooksList()
                    return Just<Int>(0).setFailureType(to: Never.self).eraseToAnyPublisher()
                }
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    if modelData.activeTab == 2, modelData.readingBook == nil {
                        modelData.readingBookInShelfId = modelData.filteredBookList.first
                    }
                }
            
            NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
        }
        
        //Body
    }   //View
    
    @ViewBuilder
    private func bookListView() -> some View {
        VStack {
            bookListViewHeader()
            
            Divider()
            
            bookListViewContent()
            
            Divider()
            
            bookListViewFooter()
            
        }
        
        .statusBar(hidden: false)
    }
    
    @ViewBuilder
    private func bookListViewHeader() -> some View {
        ZStack {
            TextField("Search Title & Authors", text: $searchString, onCommit: {
                modelData.searchString = searchString
                if modelData.filteredBookListPageNumber > 0 {
                    modelData.filteredBookListPageNumber = 0
                } else {
                    NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
                }
            })
            .keyboardType(.webSearch)
            .padding([.leading, .trailing], 24)
            HStack {
                Button {
                    searchHistoryPresenting = true
                } label: {
                    Image(systemName: "chevron.down")
                }
                .popover(isPresented: $searchHistoryPresenting) {
                    Text("Search History")
                }

                Spacer()
                Button(action: {
                    guard modelData.searchString.count > 0 || searchString.count > 0 else { return }
                    modelData.searchString = ""
                    searchString = ""
                    if modelData.filteredBookListPageNumber > 0 {
                        modelData.filteredBookListPageNumber = 0
                    } else {
                        NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }.disabled(searchString.isEmpty)
            }.padding([.leading, .trailing], 4)
        }
    }
    
    @ViewBuilder
    private func bookListViewContent() -> some View {
        ZStack {
            List(selection: $selectedBookIds) {
                //ForEach(modelData.filteredBookList, id: \.self) { bookInShelfId in
                ForEach(modelData.searchCriteriaResults[modelData.currentLibrarySearchCriteria]?.books ?? [], id: \.self) { book in
                    NavigationLink (
                        destination: BookDetailView(viewMode: .LIBRARY),
                        tag: book.inShelfId,
                        selection: $modelData.selectedBookId
                    ) {
                        bookRowView(book: book)
                    }
                    .isDetailLink(true)
                    .contextMenu {
                        bookRowContextMenuView(book: book)
                    }
                }   //ForEach
            }
            .onAppear {
                print("LIBRARYINFOVIEW books=\(modelData.searchCriteriaResults[modelData.currentLibrarySearchCriteria]?.books.count)")
            }
            .disabled(modelData.filteredBookListRefreshing)
            .popover(isPresented: $batchDownloadSheetPresenting,
                     attachmentAnchor: .rect(.bounds),
                     arrowEdge: .top
            ) {
                LibraryInfoBatchDownloadSheet(
                    presenting: $batchDownloadSheetPresenting,
                    downloadBookList: $downloadBookList
                )
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        guard let books = modelData.searchCriteriaResults[modelData.currentLibrarySearchCriteria]?.books else { return }
                        
                        downloadBookList.removeAll(keepingCapacity: true)
                        downloadBookList = books
                        batchDownloadSheetPresenting = true
                    } label: {
                        Image(systemName: "square.and.arrow.down.on.square")
                    }
                    .disabled(modelData.filteredBookListRefreshing)
                    
                    sortMenuView()
                        .disabled(modelData.filteredBookListRefreshing)
                }
            }
            if modelData.filteredBookListRefreshing {
                ProgressView()
                    .scaleEffect(4, anchor: .center)
                    .progressViewStyle(CircularProgressViewStyle())
            }
        }
    }
    
    @ViewBuilder
    private func bookListViewFooter() -> some View {
        HStack {
            Button {
                booksListInfoPresenting = true
            } label: {
                Image(systemName: "info.circle")
            }.popover(isPresented: $booksListInfoPresenting) {
                NavigationView {
                    List {
                        ForEach(modelData.currentSearchLibraryResults
                            .map({ (modelData.calibreLibraries[$0.key.libraryId]!, $0.value) })
                            .sorted(by: { $0.0.id < $1.0.id}),
                                id: \.0.id) { searchResult in
                            Section {
                                HStack {
                                    Text("Books")
                                    Spacer()
                                    Text("\(searchResult.1.totalNumber)")
                                }
                            } header: {
                                HStack {
                                    Text(searchResult.0.name)
                                    Spacer()
                                    Text(searchResult.0.server.name)
                                }
                            } footer: {
                                HStack {
                                    Spacer()
                                    if searchResult.1.loading {
                                        Text("Searching for more, result incomplete.")
                                    } else if searchResult.1.error {
                                        Text("Error occured, result incomplete.")
                                    } else if searchResult.1.offlineResult {
                                        Text("Local cached result, may not up to date.")
                                    }
                                }.font(.caption)
                                    .foregroundColor(.red    )
                            }
                            
                        }
                    }
                    .navigationTitle("Libraries")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                booksListInfoPresenting = false
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                let searchCriteria = modelData.currentLibrarySearchCriteria
                                
                                modelData.currentSearchLibraryResults
                                    .filter {
                                        $0.key.criteria == searchCriteria
                                    }
                                    .forEach {
                                        modelData.librarySearchResetSubject.send($0.key)
                                    }
                                
                                modelData.librarySearchResetSubject.send(.init(libraryId: "", criteria: searchCriteria))
                                
                                if modelData.filteredBookListPageNumber > 0 {
                                    modelData.filteredBookListPageNumber = 0
                                } else {
                                    NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
                                }
                                
                                booksListInfoPresenting = false
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                    }
                }
                .navigationViewStyle(.stack)
            }

            Text(getLibrarySearchingText())
            if modelData.filteredBookListRefreshing {
                ProgressView()
                    .progressViewStyle(.circular)
            }
            
            Spacer()
            
            Button(action:{
                if modelData.filteredBookListPageNumber > 0 {
                    modelData.filteredBookListPageNumber -= 1
                }
            }) {
                Image(systemName: "chevron.backward")
            }
            Text("\(modelData.filteredBookListPageCount == 0 ? 0 : modelData.filteredBookListPageNumber+1) / \(modelData.filteredBookListPageCount)")
            Button(action:{
                if modelData.filteredBookListPageNumber + 1 < modelData.filteredBookListPageCount {
                    modelData.filteredBookListPageNumber += 1
                }
            }) {
                Image(systemName: "chevron.forward")
            }.disabled(modelData.filteredBookListRefreshing && modelData.currentSearchLibraryResultsCannotFurther)
        }
        .padding(4)    //bottom bar
        .disabled(modelData.filteredBookListRefreshing)
    }
    
    func resetSearchCriteria() {
        modelData.filterCriteriaCategory.removeAll()
        modelData.filterCriteriaRating.removeAll()
        modelData.filterCriteriaFormat.removeAll()
        modelData.filterCriteriaIdentifier.removeAll()
        modelData.filterCriteriaSeries.removeAll()
        modelData.filterCriteriaTags.removeAll()
        modelData.filterCriteriaLibraries.removeAll()
        
        modelData.filterCriteriaShelved = .none
    }
    
    func updateCategoryItems(_ categoryName: String) {
        self.categoryItems.removeAll()
        guard let categoryItems = modelData.calibreLibraryCategoryMerged[categoryName]
        else { return }
        
        let filterString = categoryFilterString.trimmingCharacters(in: .whitespacesAndNewlines)
        if filterString.isEmpty {
            self.categoryItems = categoryItems
        } else {
            self.categoryItems = categoryItems.filter { $0.localizedCaseInsensitiveContains(filterString) }
        }
    }
    
    func updateBooksList() {
        let fbURL = URL(fileURLWithPath: "/")
        let searchCriteria = modelData.currentLibrarySearchCriteria
        
        if modelData.searchString.isEmpty == false {
            var set = Set<String>(searchHistoryList)
            set.insert(modelData.searchString)
            searchHistoryList = set.sorted()
        }
        
        libraryList = modelData.calibreLibraries.values
            .filter { $0.hidden == false }
            .sorted { $0.name < $1.name }
        
        modelData.filteredBookListMergeSubject.send(LibrarySearchKey(libraryId: "", criteria: searchCriteria))
        
//        return;
        
//        booksListQueryCancellable?.cancel()
//        booksListQueryCancellable =
        libraryList.filter {
            modelData.filterCriteriaLibraries.isEmpty || modelData.filterCriteriaLibraries.contains($0.id)
        }
        .compactMap({ library -> CalibreBooksTask? in
//            modelData.librarySearchSubject.send(.init(libraryId: library.id, criteria: searchCriteria))
            
            return nil
            
            /*
             return modelData.calibreServerService.buildBooksMetadataTask(
                library: library,
                books: [],
                searchCriteria: searchCriteria
            ) ?? .init(
                library: library,
                books: [],
                metadataUrl: fbURL,
                lastReadPositionUrl: fbURL,
                annotationsUrl: fbURL,
                booksListUrl: fbURL
            )
             */
        })
        .publisher
        .subscribe(on: DispatchQueue.main)
//        .flatMap { task -> AnyPublisher<CalibreBooksTask, Never> in
//            let searchKey = LibrarySearchKey(libraryId: task.library.id, criteria: searchCriteria)
//            if modelData.searchLibraryResults[searchKey] == nil {
//                modelData.searchLibraryResults[searchKey] = .init(library: task.library)
//            }
//            modelData.searchLibraryResults[searchKey]?.loading = true
//
//            self.booksListRefreshing = modelData.searchLibraryResults.filter { $0.key.criteria == searchCriteria && $0.value.loading }.isEmpty == false
//
//            var errorTask = task
//            errorTask.ajaxSearchError = true
//            return modelData.calibreServerService.listLibraryBooks(task: task)
//                .replaceError(with: errorTask)
//                .eraseToAnyPublisher()
//        }
//        .subscribe(on: DispatchQueue.global(qos: .userInitiated))
//        .map { task -> CalibreBooksTask in
//            var newTask = modelData.calibreServerService.buildBooksMetadataTask(
//                library: task.library,
//                books: task.ajaxSearchResult?.book_ids.map({ CalibreBook(id: $0, library: task.library) }) ?? []
//            ) ?? .init(library: task.library, books: [], metadataUrl: fbURL, lastReadPositionUrl: fbURL, annotationsUrl: fbURL, booksListUrl: fbURL)
//            newTask.ajaxSearchResult = task.ajaxSearchResult
//            newTask.ajaxSearchError = task.ajaxSearchError
//            return newTask
//        }
//        .flatMap { task -> AnyPublisher<CalibreBooksTask, Never> in
//            modelData.calibreServerService.getBooksMetadata(task: task)
//                .replaceError(with: task)
//                .eraseToAnyPublisher()
//        }
        .sink { completion in
            print("\(#function) completion=\(completion)")
            switch completion {
            case .finished:
                break
            case .failure(_):
                break
            }
        } receiveValue: { task in
            print("\(#function) library=\(task.library.key) task.data=\(task.data?.count)")
        }
    }
    
    @ViewBuilder
    private func bookRowView(book: CalibreBook) -> some View {
        HStack(alignment: .bottom) {
            ZStack {
                KFImage(book.coverURL)
                    .placeholder {
                        ProgressView().progressViewStyle(CircularProgressViewStyle())
                    }
                    .resizable()
                    .frame(width: 72, height: 96, alignment: .center)
                
                if book.inShelf {
                    Image(systemName: "books.vertical")
                        .frame(width: 64 - 8, height: 96 - 8, alignment: .bottomTrailing)
                        .foregroundColor(.primary)
                        .opacity(0.8)
                }
                
                if let download = modelData.activeDownloads.filter( { $1.book.id == book.id && ($1.isDownloading || $1.resumeData != nil) } ).first?.value {
                    ZStack {
                        Rectangle()
                            .frame(width: 64, height: 64, alignment: .center)
                            .foregroundColor(.gray)
                            .cornerRadius(4.0)
                            .opacity(0.8)
                        ProgressView(value: download.progress)
                            .frame(width: 56, height: 64, alignment: .center)
                            .progressViewStyle(.linear)
                            .foregroundColor(.primary)
                    }
                    .frame(width: 64, height: 96 - 8, alignment: .bottom)
                }
            }
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(book.title)")
                    .font(.callout)
                    .lineLimit(3)
                
                Group {
                    HStack {
                        Text("\(book.authorsDescriptionShort)")
                        Spacer()
                    }
                    
                    HStack {
                        Text(book.tags.first ?? "")
                        Spacer()
                        Text(book.library.name)
                    }
                }
                .font(.caption)
                .lineLimit(1)
                
                Spacer()
                
                HStack {
                    if book.identifiers["goodreads"] != nil {
                        Image("icon-goodreads")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 16, alignment: .center)
                    } else {
                        Image("icon-goodreads")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 16, alignment: .center)
                            .hidden()
                    }
                    if book.identifiers["amazon"] != nil {
                        Image("icon-amazon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 16, alignment: .center)
                    } else {
                        Image("icon-amazon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 16, alignment: .center)
                            .hidden()
                    }
                    Spacer()
                    
                    Text(book.ratingDescription).font(.caption)
                    
                    Spacer()
                    if book.formats["PDF"] != nil {
                        Image("PDF")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 16, alignment: .center)
                    } else {
                        Image("PDF")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 16, alignment: .center)
                            .hidden()
                    }
                    
                    if book.formats["EPUB"] != nil {
                        Image("EPUB")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 16, alignment: .center)
                    } else {
                        Image("EPUB")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 16, alignment: .center)
                            .hidden()
                    }
                    
                    if book.formats["CBZ"] != nil {
                        Image("CBZ")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 16, alignment: .center)
                    } else {
                        Image("CBZ")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 16, alignment: .center)
                            .hidden()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func bookRowContextMenuView(book: CalibreBook) -> some View {
        Menu("More by Author ...") {
            ForEach(book.authors, id: \.self) { author in
                Button {
                    resetSearchCriteria()
                    searchString = "author:\"=\(author)\""
                    modelData.searchString = searchString
                    NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
                } label: {
                    Text(author)
                }
            }
        }
        
        Menu("More of Tag ...") {
            ForEach(book.tags, id: \.self) { tag in
                Button {
                    resetSearchCriteria()
                    searchString = "tag:\"=\(tag)\""
                    modelData.searchString = searchString
                    NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
                } label: {
                    Text(tag)
                }
            }
        }
        
        if book.series.isEmpty == false {
            Button {
                resetSearchCriteria()
                searchString = "series:\"=\(book.series)\""
                modelData.searchString = searchString
                modelData.sortCriteria.by = .SeriesIndex
                modelData.sortCriteria.ascending = true
                NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
            } label: {
                Text("More in Series: \(book.series)")
            }
        }
        Menu("Download ...") {
            ForEach(book.formats.keys.compactMap{ Format.init(rawValue: $0) }, id:\.self) { format in
                Button {
                    modelData.clearCache(book: book, format: format)
                    modelData.startDownloadFormat(book: book, format: format, overwrite: true)
                } label: {
                    Text(
                        format.rawValue
                        + "\t\t\t"
                        + ByteCountFormatter.string(
                            fromByteCount: Int64(book.formats[format.rawValue]?.serverSize ?? 0),
                            countStyle: .file
                        )
                    )
                }
            }
        }
    }
    
    @ViewBuilder
    private func filterMenuView() -> some View {
        Menu {
            Button(action: {
                resetSearchCriteria()
                NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
            }) {
                Text("Reset")
            }
            
            Menu("Libraries ...") {
                ForEach(libraryList, id: \.self) { library in
                    Button(action: {
                        if modelData.filterCriteriaLibraries.contains(library.id) {
                            modelData.filterCriteriaLibraries.remove(library.id)
                        } else {
                            modelData.filterCriteriaLibraries.insert(library.id)
                        }
                        NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
                    }, label: {
                        VStack(alignment: .leading) {
                            Text(getLibraryFilterText(library: library))
                            Text(library.server.name).font(.caption)
                        }
                    })
                }
            }
            
            Menu("Shelved ...") {
                Button(action: {
                    if modelData.filterCriteriaShelved == .shelvedOnly {
                        modelData.filterCriteriaShelved = .none
                    } else {
                        modelData.filterCriteriaShelved = .shelvedOnly
                    }
                    NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))

                }, label: {
                    Text("Yes" + (modelData.filterCriteriaShelved == .shelvedOnly ? "✓" : ""))
                })
                Button(action: {
                    if modelData.filterCriteriaShelved == .notShelvedOnly {
                        modelData.filterCriteriaShelved = .none
                    } else {
                        modelData.filterCriteriaShelved = .notShelvedOnly
                    }
                    NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))

                }, label: {
                    Text("No" + (modelData.filterCriteriaShelved == .notShelvedOnly ? "✓" : ""))
                })
            }
            
            
        } label: {
            Image(systemName: "line.horizontal.3.decrease")
        }
    }
    
    @ViewBuilder
    private func sortMenuView() -> some View {
        Menu {
            ForEach(SortCriteria.allCases, id: \.self) { sort in
                Button(action: {
                    if modelData.sortCriteria.by == sort {
                        modelData.sortCriteria.ascending.toggle()
                    } else {
                        modelData.sortCriteria.by = sort
                        modelData.sortCriteria.ascending = sort == .Title ? true : false
                    }
                    NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
                }) {
                    HStack {
                        if modelData.sortCriteria.by == sort {
                            if modelData.sortCriteria.ascending {
                                Image(systemName: "arrow.down")
                            } else {
                                Image(systemName: "arrow.up")
                            }
                        } else {
                            Image(systemName: "arrow.down").hidden()
                        }
                        Text(sort.rawValue)
                    }
                }
            }
            
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }
    
    private func getLibraryFilterText(library: CalibreLibrary) -> String {
        let searchResult = modelData.searchLibraryResults[LibrarySearchKey(libraryId: library.id, criteria: modelData.currentLibrarySearchCriteria)]
        
        return library.name
        + " "
        + (modelData.filterCriteriaLibraries.contains(library.id) ? "✓" : "")
        + " "
        + (searchResult?.description ?? "")
        + " "
        + (searchResult?.pageOffset[modelData.filteredBookListPageNumber]?.description ?? "0")
        + "/"
        + (searchResult?.pageOffset[modelData.filteredBookListPageNumber+1]?.description ?? "0")
    }
    
    private func getLibrarySearchingText() -> String {
        let searchCriteria = modelData.currentLibrarySearchCriteria
        
        let searchResultsLoading = modelData.searchLibraryResults.filter { $0.key.criteria == searchCriteria && $0.value.loading }
        if searchResultsLoading.count == 1,
           let libraryId = searchResultsLoading.first?.key.libraryId,
           let library = modelData.calibreLibraries[libraryId] {
            return "Searching \(library.name)..."
        }
        if searchResultsLoading.count > 1 {
            return "Searching \(searchResultsLoading.count) libraries..."
        }
        let searchResultsError = modelData.searchLibraryResults.filter { $0.key.criteria == searchCriteria && $0.value.error }
        if searchResultsError.isEmpty == false {
            return "Result Incomplete"
        }
        
        return ""
    }
    
    private func hasLibrarySearchError() -> Bool {
        let searchCriteria = modelData.currentLibrarySearchCriteria
        
        return modelData.searchLibraryResults.filter { $0.key.criteria == searchCriteria && $0.value.error }.isEmpty == false
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
