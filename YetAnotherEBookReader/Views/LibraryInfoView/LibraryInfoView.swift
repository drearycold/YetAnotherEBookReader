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

    @State private var viewByCategory = false
    //@State private var booksList = [CalibreBook]()
    @State private var categoriesList = [String]()
    @State private var categoriesSelected : String? = nil
    @State private var categoryItems = [String]()
    @State private var categoryItemSelected: String? = nil
    
    @State private var booksList = [String]()
    
    @State private var searchHistoryList = [String]()
    @State private var libraryList = [CalibreLibrary]()
    @State private var seriesList = [String]()
    @State private var tagsList = [String]()

    @State private var ratingList = ["Not Rated", "★★★★★", "★★★★", "★★★", "★★", "★"]
    @State private var formatList = [String]()
    @State private var identifierList = [String]()
    
    @State private var booksListRefreshing = false
    @State private var booksListQuerying = false
    @State private var searchString = ""
    @State private var selectedBookIds = Set<String>()
    @State private var editMode: EditMode = .inactive
    @State private var pageNo = 0
    @State private var pageSize = 100
    @State private var pageCount = 0
    @State private var updater = 0
    @State private var booksListInfoPresenting = false
    @State private var searchHistoryPresenting = false
    
    @State private var alertItem: AlertItem?
    
    @State private var batchDownloadSheetPresenting = false
    
    @State private var bookUpdateCancellable: AnyCancellable?
    @State private var booksListCancellable: AnyCancellable?
    @State private var booksListQueryCancellable: AnyCancellable?
    
    @State private var dismissAllCancellable: AnyCancellable?

    private var errBook = CalibreBook(id: -1, library: CalibreLibrary(server: CalibreServer(uuid: .init(), name: "Error", baseUrl: "Error", hasPublicUrl: false, publicUrl: "Error", hasAuth: false, username: "Error", password: "Error"), key: "Error", name: "Error"))
    
    private var defaultLog = Logger()
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                ZStack {
                    TextField("Search Title & Authors", text: $searchString, onCommit: {
                        modelData.searchString = searchString
                        if pageNo > 0 {
                            pageNo = 0
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
                            if pageNo > 0 {
                                pageNo = 0
                            } else {
                                NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }.disabled(searchString.isEmpty)
                    }.padding([.leading, .trailing], 4)
                }
                
                Divider()
                
                ZStack {
                    if viewByCategory {
                        List {
                            ForEach(categoriesList, id: \.self) { categoryName in
                                NavigationLink(tag: categoryName, selection: $categoriesSelected) {
                                    List {
                                        ForEach(categoryItems, id: \.self) { categoryItem in
                                            NavigationLink(tag: categoryItem, selection: $categoryItemSelected) {
                                                List(selection: $selectedBookIds) {
                                                    ForEach(modelData.filteredBookList, id: \.self) { bookInShelfId in
                                                        NavigationLink (
                                                            destination: BookDetailView(viewMode: .LIBRARY),
                                                            tag: bookInShelfId,
                                                            selection: $modelData.selectedBookId
                                                        ) {
                                                            bookRowView(book: modelData.getBook(for: bookInShelfId) ?? errBook)
                                                        }
                                                        .isDetailLink(true)
                                                        .contextMenu {
                                                            bookRowContextMenuView(book: modelData.getBook(for: bookInShelfId) ?? errBook)
                                                        }
                                                    }   //ForEach
                                                }
                                                .navigationTitle("\(categoryName): \(categoryItem)")
                                            } label: {
                                                Text(categoryItem)
                                            }
                                            .isDetailLink(false)
                                            .onChange(of: categoryItemSelected) { categoryItem in
                                                guard let categoriesSelected = categoriesSelected,
                                                      let categoryItem = categoryItem else { return }
                                                
                                                let filterItems = [modelData.filterCriteriaRating,
                                                                   modelData.filterCriteriaFormat,
                                                                   modelData.filterCriteriaIdentifier,
                                                                   modelData.filterCriteriaSeries,
                                                                   modelData.filterCriteriaTags,
                                                                   modelData.filterCriteriaLibraries].flatMap { $0 }
                                                if filterItems == [categoryItem] {
                                                    return
                                                }
                                                
                                                modelData.filteredBookList.removeAll()
                                                
                                                modelData.filterCriteriaRating.removeAll()
                                                modelData.filterCriteriaFormat.removeAll()
                                                modelData.filterCriteriaIdentifier.removeAll()
                                                modelData.filterCriteriaSeries.removeAll()
                                                modelData.filterCriteriaTags.removeAll()
                                                modelData.filterCriteriaLibraries.removeAll()
                                                
                                                modelData.filterCriteriaShelved = .none
                                                
                                                
                                                switch categoriesSelected {
                                                case "Series":
                                                    modelData.filterCriteriaSeries.insert(categoryItem)
                                                    modelData.sortCriteria.by = .SeriesIndex
                                                    modelData.sortCriteria.ascending = true
                                                case "Tags":
                                                    modelData.filterCriteriaTags.insert(categoryItem)
                                                default:
                                                    break
                                                }
                                                
                                                NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
                                                
                                            }
                                        }
                                    }
                                    .navigationTitle("Category: \(categoryName)")
                                } label: {
                                    Text(categoryName)
                                }
                                .isDetailLink(false)
                            }
                        }
                        .onChange(of: categoriesSelected) { categoryName in
                            categoryItems = Set<String>(
                                modelData.calibreLibraryCategories
                                    .filter { $0.key.categoryName == categoryName }
                                    .flatMap({ $0.value.items })
                                    .map { $0.name }
                            ).sorted()
                        }
                    } else {
                        List(selection: $selectedBookIds) {
                            ForEach(modelData.filteredBookList, id: \.self) { bookInShelfId in
                                NavigationLink (
                                    destination: BookDetailView(viewMode: .LIBRARY),
                                    tag: bookInShelfId,
                                    selection: $modelData.selectedBookId
                                ) {
                                    bookRowView(book: modelData.getBook(for: bookInShelfId) ?? errBook)
                                }
                                .isDetailLink(true)
                                .contextMenu {
                                    bookRowContextMenuView(book: modelData.getBook(for: bookInShelfId) ?? errBook)
                                }
                            }   //ForEach
                        }
                        .disabled(booksListRefreshing)
                        .popover(isPresented: $batchDownloadSheetPresenting,
                                 attachmentAnchor: .rect(.bounds),
                                 arrowEdge: .top
                        ) {
                            LibraryInfoBatchDownloadSheet(presenting: $batchDownloadSheetPresenting, editMode: $editMode, selectedBookIds: $selectedBookIds)
                        }
                    }
                    
                    if booksListRefreshing {
                        ProgressView()
                            .scaleEffect(4, anchor: .center)
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        if editMode == .inactive {
                            sortMenuView()
                        } else {
                            Button(action: {
                                defaultLog.info("selected \(selectedBookIds.description)")
                                selectedBookIds.forEach { bookId in
                                    modelData.clearCache(inShelfId: bookId)
                                }
                                selectedBookIds.removeAll()
                                editMode = .inactive
                            }) {
                                Image(systemName: "star.slash")
                            }.disabled(selectedBookIds.isEmpty)
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if editMode == .inactive {
                            filterMenuView()
                        } else {
                            Button(action: {
                                guard selectedBookIds.isEmpty == false else { return }
                                
                                defaultLog.info("selected \(selectedBookIds.description)")
                                batchDownloadSheetPresenting = true
                                //selectedBookIds.removeAll()
                            }
                            ) {
                                Image(systemName: "star")
                            }.disabled(selectedBookIds.isEmpty)
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        editButton
                        //editButtonView()
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            viewByCategory.toggle()
                        } label: {
                            if viewByCategory {
                                Image(systemName: "list.bullet.indent")
                            } else {
                                Image(systemName: "list.bullet")
                            }
                        }

                    }
                }
                
                Divider()
                
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
                                        if searchResult.1.loading {
                                            Text("Searching for more, results incomplete.")
                                        } else if searchResult.1.error {
                                            Text("Error occured, results incomplete.")
                                        }
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
                                        let serverIds = modelData.currentSearchLibraryResults
                                            .filter { $0.value.error }
                                            .compactMap { modelData.calibreLibraries[$0.key.libraryId]?.server.id }
                                        if serverIds.isEmpty == false {
                                            modelData.probeServersReachability(with: .init(serverIds)) { serverId in
                                                modelData.currentSearchLibraryResults
                                                    .filter { $0.value.error && modelData.calibreLibraries[$0.key.libraryId]?.server.id == serverId }
                                                    .forEach {
                                                        modelData.librarySearchSubject.send($0.key)
                                                    }
                                            }
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
                    
                    /*
                     Button(action:{
                        if pageNo > 10 {
                            pageNo -= 10
                        } else {
                            pageNo = 0
                        }
                        NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
                    }) {
                        Image(systemName: "chevron.backward.2")
                    }
                     */
                    Button(action:{
                        if modelData.filteredBookListPageNumber > 0 {
                            modelData.filteredBookListPageNumber -= 1
                        }
                    }) {
                        Image(systemName: "chevron.backward")
                    }
                    //                        Text("\(pageNo+1) / \(Int((Double(modelData.filteredBookList.count) / Double(pageSize)).rounded(.up)))")
                    Text("\(modelData.filteredBookListPageNumber+1) / \(modelData.filteredBookListPageCount)")
                    Button(action:{
                        if modelData.filteredBookListPageNumber + 1 < modelData.filteredBookListPageCount {
                            modelData.filteredBookListPageNumber += 1
                        }
                    }) {
                        Image(systemName: "chevron.forward")
                    }.disabled(modelData.filteredBookListRefreshing && modelData.currentSearchLibraryResultsCannotFurther)
                    /*
                     Button(action:{
                        if pageNo + 10 < pageCount {
                            pageNo += 10
                        } else {
                            pageNo = pageCount - 1
                        }
                    }) {
                        Image(systemName: "chevron.forward.2")
                    }
                     */
                }
                .padding(4)    //bottom bar
                .disabled(booksListRefreshing)
            }
            .padding(4)
            .navigationTitle("By \(modelData.sortCriteria.by.rawValue)")
            .navigationBarTitleDisplayMode(.automatic)
            .statusBar(hidden: false)
            //                .toolbar {
            //                    toolbarContent()
            //                }   //List.toolbar
            .environment(\.editMode, self.$editMode)  //TODO
        }   //NavigationView
        .navigationViewStyle(ColumnNavigationViewStyle.columns)
        .listStyle(PlainListStyle())
        .onChange(of: modelData.filteredBookListPageNumber, perform: { value in
            NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
        })
        .onAppear {
            modelData.calibreServerService.registerLibrarySearchHandler()
            modelData.calibreServerService.registerFilteredBookListMergeHandler()
            
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
            
            bookUpdateCancellable?.cancel()
            bookUpdateCancellable = modelData.bookUpdatedSubject
                .subscribe(on: DispatchQueue.main)
                .sink(receiveValue: { book in
//                    guard let index = booksList.firstIndex(where: { $0.inShelf == book.inShelf }) else { return }
//                    booksList[index] = book
                    updater += 1
                })
            
            NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
        }
        
        //Body
    }   //View
    
    private var editButton: some View {
        Button(action: {
            self.editMode.toggle()
            selectedBookIds.removeAll()
        }) {
            //Text(self.editMode.title)
            Image(systemName: self.editMode.systemName)
        }
    }
    
    private var addDelButton: some View {
        if editMode == .inactive {
            return Button(action: {}) {
                Image(systemName: "star")
            }
        } else {
            return Button(action: {}) {
                Image(systemName: "trash")
            }
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
        
        libraryList = modelData.calibreLibraries
            .filter { $0.value.hidden == false }
            .map { $0.value }
            .sorted { $0.name < $1.name }
        
        modelData.filteredBookListMergeSubject.send(LibrarySearchKey(libraryId: "", criteria: searchCriteria))
        
        categoriesList = Set<String>(modelData.calibreLibraryCategories.map { $0.key.categoryName }).sorted()
        
        seriesList = Set<String>(modelData.calibreLibraryCategories.filter { $0.key.categoryName == "Series" }.flatMap({ $0.value.items }).map { $0.name }).sorted()
        
        tagsList = Set<String>(modelData.calibreLibraryCategories.filter { $0.key.categoryName == "Tags" }.flatMap({ $0.value.items }).map { $0.name }).sorted()
        
        return;
        
        booksListQueryCancellable?.cancel()
        booksListQueryCancellable =
        modelData.calibreLibraries.values.filter({
            $0.hidden == false
            && (modelData.filterCriteriaLibraries.isEmpty || modelData.filterCriteriaLibraries.contains($0.id))
        })
        .compactMap({ library -> CalibreBooksTask? in
            modelData.librarySearchSubject.send(.init(libraryId: library.id, criteria: searchCriteria))
            
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
            
            self.booksListQuerying = true
            var booksList = [String]()
            var libraryList = modelData.calibreLibraries
                .filter { $0.value.hidden == false }
                .map { $0.value }
                .sorted { $0.name < $1.name }
            var seriesList = [String]()
            var pageCount = 1
            defer {
                DispatchQueue.main.async {
                    //self.booksList.replaceSubrange(self.booksList.indices, with: booksList)
                    self.seriesList.replaceSubrange(self.seriesList.indices, with: seriesList)
                    self.formatList.replaceSubrange(self.formatList.indices, with: formatList)
                    self.libraryList.replaceSubrange(self.libraryList.indices, with: libraryList)
                    //self.pageCount = pageCount
                    
                   
                }
            }
            
            var predicates = [NSPredicate]()
            predicates.append(
                NSCompoundPredicate(orPredicateWithSubpredicates: modelData.filterCriteriaLibraries.compactMap {
                    guard let library = modelData.calibreLibraries[$0] else { return nil }
                    return NSCompoundPredicate(andPredicateWithSubpredicates: [
                        NSPredicate(format: "serverUUID = %@", library.server.uuid.uuidString),
                        NSPredicate(format: "libraryName = %@", library.name)
                    ])
                })
            )
            
            let searchTerms = searchString
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split { $0.isWhitespace }
                .map { String($0) }
            if searchTerms.isEmpty == false {
                predicates.append(contentsOf:
                    searchTerms.map {
                        NSCompoundPredicate(orPredicateWithSubpredicates: [
                            NSPredicate(format: "title CONTAINS[c] %@", $0),
                            NSPredicate(format: "authorFirst CONTAINS[c] %@", $0),
                            NSPredicate(format: "authorSecond CONTAINS[c] %@", $0)
                        ])
                    }
                )
            }

            if modelData.filterCriteriaSeries.isEmpty == false {
                predicates.append(
                    NSCompoundPredicate(
                        orPredicateWithSubpredicates:
                            modelData.filterCriteriaSeries.map {
                                NSPredicate(format: "series = %@", $0)
                            }
                    )
                )
            }
            
            if modelData.filterCriteriaRating.isEmpty == false {
                predicates.append(
                    NSCompoundPredicate(
                        orPredicateWithSubpredicates:
                            modelData.filterCriteriaRating.map {
                                NSPredicate(format: "rating = %@", NSNumber(value: $0.count <= 5 ? $0.count * 2 : 0))
                            }
                    )
                )
            }
            
            if modelData.filterCriteriaShelved != .none {
                predicates.append(
                    NSPredicate(format: "inShelf = %@", modelData.filterCriteriaShelved == .shelvedOnly)
                )
            }
            
            if let realm = try? Realm(configuration: modelData.realmConf) {
                let allbooks = realm.objects(CalibreBookRealm.self)//.filter("serverUUID != nil")
                
                var seriesSet = Set<String>(allbooks.map{ $0.series })
                seriesSet.insert("Not in a Series")
                seriesSet.remove("")
                seriesList = seriesSet.sorted { lhs, rhs in
                    if lhs == "Not in a Series" {
                        return false
                    }
                    if rhs == "Not in a Series" {
                        return true
                    }
                    return lhs < rhs
                }
                
                let objects = allbooks.filter(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))
                
                let count = objects.count
                
                pageCount = Int((Double(count) / Double(pageSize)).rounded(.up))
                
                if pageNo*pageSize < count {
                    booksList = objects.sorted(
                        byKeyPath: modelData.sortCriteria.by.sortKeyPath,
                        ascending: modelData.sortCriteria.ascending
                    )[(pageNo*pageSize) ..< min((pageNo+1)*pageSize, count)]
                        .compactMap {
                            $0.primaryKey
                        }
                }
            }
            
            let serverUUID = task.library.server.uuid.uuidString
            let librarySearchKey = LibrarySearchKey(libraryId: task.library.id, criteria: searchCriteria)
            
            DispatchQueue.main.async {
                if modelData.searchLibraryResults[librarySearchKey] == nil {
                    modelData.searchLibraryResults[librarySearchKey] = .init(library: task.library)
                }
                
                
            }
            
            if let searchResult = task.ajaxSearchResult,
               let booksMetadataEntry = task.booksMetadataEntry,
               let booksMetadataJSON = task.booksMetadataJSON,
               let searchLibraryResultsRealm = modelData.searchLibraryResultsRealmLocalThread {
                
                let realmBooks = booksMetadataEntry.compactMap { metadataEntry -> CalibreBookRealm? in
                    guard let entry = metadataEntry.value,
                          let bookId = Int32(metadataEntry.key)
                    else { return nil }
                    
                    let obj = CalibreBookRealm()
                    obj.serverUUID = serverUUID
                    obj.libraryName = task.library.name
                    obj.id = bookId
                    
                    modelData.calibreServerService.handleLibraryBookOne(library: task.library, bookRealm: obj, entry: entry, root: booksMetadataJSON)
                    
                    return obj
                }
                
                try? searchLibraryResultsRealm.write{
                    searchLibraryResultsRealm.add(realmBooks, update: .modified)
                }
                
                let idSet = Set<String>(booksList)
                booksList.append(
                    contentsOf:
                        searchResult.book_ids.map {
                            CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: task.library.name, id: $0.description)
                        }.filter { idSet.contains($0) == false }
                )
            }
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
                            .frame(width: 64, height: 10, alignment: .center)
                            .foregroundColor(.gray)
                            .cornerRadius(4.0)
                            .opacity(0.8)
                        ProgressView(value: download.progress)
                            .frame(width: 56, height: 10, alignment: .center)
                            .progressViewStyle(LinearProgressViewStyle())
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
        Menu("Download ...") {
            ForEach(book.formats.keys.compactMap{ Format.init(rawValue: $0) }, id:\.self) { format in
                Button(format.rawValue) {
                    // MARK:  - TODO
//                    modelData.clearCache(book: book, format: format)
//                    modelData.downloadFormat(
//                        book: book,
//                        format: format
//                    ) { success in
//                        DispatchQueue.main.async {
//                            if book.inShelf == false {
//                                modelData.addToShelf(book.id, shelfName: book.tags.first ?? "Untagged")
//                            }
//
//                            if format == Format.EPUB {
//                                removeFolioCache(book: book, format: format)
//                            }
//                        }
//                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func filterMenuView() -> some View {
        Menu {
            Button(action: {
                modelData.filterCriteriaRating.removeAll()
                modelData.filterCriteriaFormat.removeAll()
                modelData.filterCriteriaIdentifier.removeAll()
                modelData.filterCriteriaShelved = .none
                modelData.filterCriteriaSeries.removeAll()
                modelData.filterCriteriaTags.removeAll()
                modelData.filterCriteriaLibraries.removeAll()
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
            
            Menu("Series ... (\(seriesList.count))") {
                ForEach(seriesList, id: \.self) { id in
                    Button(action: {
                        if modelData.filterCriteriaSeries.contains(id) {
                            modelData.filterCriteriaSeries.remove(id)
                        } else {
                            modelData.filterCriteriaSeries.insert(id)
                        }
                        NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
                    }, label: {
                        Text(id + (modelData.filterCriteriaSeries.contains(id) ? "✓" : ""))
                    })
                }
            }
            
            Menu("Tags ... (\(tagsList.count))") {
                ForEach(tagsList, id: \.self) { id in
                    Button(action: {
                        if modelData.filterCriteriaTags.contains(id) {
                            modelData.filterCriteriaTags.remove(id)
                        } else {
                            modelData.filterCriteriaTags.insert(id)
                        }
                        NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
                    }, label: {
                        Text(id + (modelData.filterCriteriaTags.contains(id) ? "✓" : ""))
                    })
                }
            }
            
            Menu("Rating ...") {
                ForEach(ratingList, id: \.self) { id in
                    Button(action: {
                        if modelData.filterCriteriaRating.contains(id) {
                            modelData.filterCriteriaRating.remove(id)
                        } else {
                            modelData.filterCriteriaRating.insert(id)
                        }
                        NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
                    }, label: {
                        Text(id + (modelData.filterCriteriaRating.contains(id) ? "✓" : ""))
                    })
                }
            }
            if false {  //MARK: TODO
            Menu("Format ...") {
                ForEach(formatList, id: \.self) { id in
                    Button(action: {
                        if modelData.filterCriteriaFormat.contains(id) {
                            modelData.filterCriteriaFormat.remove(id)
                        } else {
                            modelData.filterCriteriaFormat.insert(id)
                        }
                        NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))

                    }, label: {
                        Text(id + (modelData.filterCriteriaFormat.contains(id) ? "✓" : ""))
                    })
                }
            }
            Menu("Linked with ...") {
                ForEach(identifierList, id: \.self) { id in
                    Button(action: {
                        if modelData.filterCriteriaIdentifier.contains(id) {
                            modelData.filterCriteriaIdentifier.remove(id)
                        } else {
                            modelData.filterCriteriaIdentifier.insert(id)
                        }
                        NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))

                    }, label: {
                        Text(id + (modelData.filterCriteriaIdentifier.contains(id) ? "✓" : ""))
                    })
                }
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

extension Array {
    func forPage(pageNo: Int, pageSize: Int) -> ArraySlice<Element> {
        guard pageNo*pageSize < count else { return [] }
        return self[(pageNo*pageSize) ..< Swift.min((pageNo+1)*pageSize, count)]
    }
}

extension EditMode {
    var title: String {
        self == .active ? "Done" : "Select"
    }
    
    var systemName: String {
        self == .active ? "xmark.circle" : "checkmark.circle"
    }

    mutating func toggle() {
        self = self == .active ? .inactive : .active
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
