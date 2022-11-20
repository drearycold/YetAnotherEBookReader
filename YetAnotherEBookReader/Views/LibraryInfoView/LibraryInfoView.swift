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
    
    @State private var dismissAllCancellable: AnyCancellable?
    
    @State private var categoryItemListCancellable: AnyCancellable?
    @State private var categoryItemListUpdating = false
    
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
                    ForEach(modelData.calibreLibraryCategoryMerged.filter({ categoryMerged in
                        categoryMerged.value.count < 10000
                        && modelData.calibreLibraryCategories
                            .filter { $0.key.categoryName == categoryMerged.key }
                            .reduce(0) { result, libraryCategory in
                                result + libraryCategory.value.totalNumber
                            } < 10000
                    }).keys.sorted(), id: \.self) { categoryName in
                        NavigationLink(tag: categoryName, selection: $categoriesSelected) {
                            ZStack {
                                TextField("Filter \(categoryName)", text: $categoryFilterString, onCommit: {
                                    modelData.categoryItemListSubject.send(categoryName)
                                })
                                .keyboardType(.webSearch)
                                .padding([.leading, .trailing], 24)
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        categoryFilterString = ""
                                        modelData.categoryItemListSubject.send(categoryName)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }.disabled(categoryFilterString.isEmpty)
                                }.padding([.leading, .trailing], 4)
                            }
                            
                            Divider()
                            
                            ZStack {
                                List {
                                    ForEach(categoryItems, id: \.self) { categoryItem in
                                        NavigationLink(tag: categoryItem, selection: $categoryItemSelected) {
                                            bookListView()
                                                .onAppear {
                                                    resetSearchCriteria()
                                                    
                                                    modelData.filterCriteriaCategory[categoryName] = .init([categoryItem])
                                                    
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
                                .disabled(categoryItemListUpdating)
                                .onAppear {
                                    guard let categoryName = categoriesSelected
                                    else { return }
                                    
                                    categoryFilterString = ""
                                    modelData.categoryItemListSubject.send(categoryName)
                                }
                                .onDisappear {
                                    categoryItems.removeAll(keepingCapacity: true)
                                }
                                
                                if categoryItemListUpdating {
                                    ProgressView()
                                        .scaleEffect(4, anchor: .center)
                                        .progressViewStyle(CircularProgressViewStyle())
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
            libraryList = modelData.calibreLibraries.values
                .filter { $0.hidden == false }
                .sorted { $0.name < $1.name }
            
            dismissAllCancellable?.cancel()
            dismissAllCancellable = modelData.dismissAllPublisher.sink { _ in
                batchDownloadSheetPresenting = false
            }
            
            booksListCancellable?.cancel()
            booksListCancellable = modelData.libraryBookListNeedUpdate
                .sink { _ in
                    modelData.filteredBookListMergeSubject.send(LibrarySearchKey(libraryId: "", criteria: modelData.currentLibrarySearchCriteria))
                }
            
            categoryItemListCancellable?.cancel()
            categoryItemListCancellable = modelData.categoryItemListSubject
                .receive(on: DispatchQueue.main)
                .subscribe(on: DispatchQueue.main)
                .map { categoryName -> String in
                    guard categoryName == categoriesSelected else {
                        return ""
                    }
                    
                    self.categoryItems.removeAll(keepingCapacity: true)
                    self.categoryItemListUpdating = true
                    
                    return categoryName
                }
                .subscribe(on: DispatchQueue.global(qos: .userInitiated))
                .map { categoryName -> [String] in
                    guard var categoryItems = modelData.calibreLibraryCategoryMerged[categoryName]
                    else { return [] }
                    
                    let filterString = categoryFilterString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if filterString.isEmpty == false {
                        categoryItems = categoryItems.filter { $0.localizedCaseInsensitiveContains(filterString) }
                    }
                    
                    return categoryItems
                }
                .subscribe(on: DispatchQueue.main)
                .sink { categoryItems in
                    self.categoryItems.append(contentsOf: categoryItems)
                    categoryItemListUpdating = false
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
            TextField("Search Title & Authors", text: $searchString)
            .onSubmit {
                searchStringChanged(searchString: searchString)
            }
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
                Button {
                    searchStringChanged(searchString: "")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }.disabled(searchString.isEmpty)
                
                Menu {
                    ForEach(modelData.filterCriteriaCategory.filter({ $0.key != categoriesSelected }).sorted(by: { $0.key < $1.key}), id: \.key) { categoryFilter in
                        ForEach(categoryFilter.value.sorted(), id: \.self) { categoryFilterValue in
                            Button {
                                if modelData.filterCriteriaCategory[categoryFilter.key]?.remove(categoryFilterValue) != nil {
                                    searchStringChanged(searchString: self.searchString)
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
                        .foregroundColor(.gray)
                }
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
                                
                                searchStringChanged(searchString: self.searchString)
                                
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
    
    func searchStringChanged(searchString: String) {
        self.searchString = searchString.trimmingCharacters(in: .whitespacesAndNewlines)
        modelData.searchString = self.searchString
        
        if modelData.filteredBookListPageNumber > 0 {
            modelData.filteredBookListPageNumber = 0
        } else {
            NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
        }
    }
    
    func updateFilterCategory(key: String, value: String) {
        if modelData.filterCriteriaCategory[key] == nil {
            modelData.filterCriteriaCategory[key] = .init()
        }
        modelData.filterCriteriaCategory[key]?.insert(value)
        
        if modelData.filteredBookListPageNumber > 0 {
            modelData.filteredBookListPageNumber = 0
        } else {
            NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
        }
    }
    
    
    func resetSearchCriteria() {
        modelData.filterCriteriaCategory.removeAll()
        modelData.filterCriteriaFormat.removeAll()
        modelData.filterCriteriaIdentifier.removeAll()
        modelData.filterCriteriaLibraries.removeAll()
        
        modelData.filterCriteriaShelved = .none
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
        if let authors = book.authors.filter({
            modelData.filterCriteriaCategory["Author"]?.contains($0) != true
        }) as [String]?, authors.isEmpty == false {
            Menu("More by Author ...") {
                ForEach(authors, id: \.self) { author in
                    Button {
                        updateFilterCategory(key: "Author", value: author)
                    } label: {
                        Text(author)
                    }
                }
            }
        }
        
        if let tags = book.tags.filter({
            modelData.filterCriteriaCategory["Tags"]?.contains($0) != true
        }) as [String]?, tags.isEmpty == false {
            Menu("More of Tags ...") {
                ForEach(tags, id: \.self) { tag in
                    Button {
                        updateFilterCategory(key: "Tags", value: tag)
                    } label: {
                        Text(tag)
                    }
                }
            }
        }
        
        if book.series.isEmpty == false,
           modelData.filterCriteriaCategory["Series"]?.contains(book.series) != true {
            Button {
                modelData.sortCriteria.by = .SeriesIndex
                modelData.sortCriteria.ascending = true
                updateFilterCategory(key: "Series", value: book.series)
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
        let a = modelData.calibreLibraryCategoryMerged.filter({ categoryMerged in
            categoryMerged.value.count < 10000
            && modelData.calibreLibraryCategories
                .filter { $0.key.categoryName == categoryMerged.key }
                .reduce(0) { result, libraryCategory in
                    result + libraryCategory.value.totalNumber
                } < 10000
        }).keys.sorted()
        
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
