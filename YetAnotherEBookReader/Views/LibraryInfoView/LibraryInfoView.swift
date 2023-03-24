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
    @State private var categoryItemSelected: String? = nil
    
    @State private var categoryName = ""
    @State private var categoryFilter = ""
    @State private var categoryItems = [String]()
    
    private let categoryItemsTooLong = ["__TOO_LONG__CATEGORY_LIST__"]
    
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
    
    @State private var filteredBookListRefreshingCancellable: AnyCancellable?
    @State private var filteredBookListRefreshing = false
    
    @State private var savedFilterCriteriaCategory: [String: Set<String>]? = nil
    
    private var defaultLog = Logger()
    
    var body: some View {
        NavigationView {
            List {
                combinedListView()
                
                if modelData.calibreLibraryCategoryMerged.isEmpty == false {
                    categoryListView()
                }
                
                libraryListView()
                
            }
            .padding(4)
            .navigationTitle(Text("Library Browser"))
        }   //NavigationView
        .navigationViewStyle(ColumnNavigationViewStyle.columns)
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
            
            filteredBookListRefreshingCancellable?.cancel()
            filteredBookListRefreshingCancellable = modelData.filteredBookListRefreshingSubject
                .receive(on: DispatchQueue.global())
                .map { _ -> Bool in
                    let refreshing =
                    (
                        modelData.searchCriteriaMergedResults[
                            modelData.currentLibrarySearchResultKey
                        ] == nil
                    )
                    ||
                    (
                        modelData.searchCriteriaMergedResults[
                            modelData.currentLibrarySearchResultKey
                        ]?.merging == true
                    )
                    ||
                    (
                        modelData.librarySearchManager.getCaches(
                            for: modelData.filterCriteriaLibraries,
                            of: modelData.currentLibrarySearchCriteria,
                            by: .online
                        ).filter {
                            $0.value.loading
                            &&
                            modelData.currentLibrarySearchResultMerged?.mergedPageOffsets[$0.key.libraryId]?.beenCutOff == true
                        }.isEmpty == false
                    )
                    
                    return refreshing
                }
                .receive(on: DispatchQueue.main)
                .sink(receiveValue: { refreshing in
                    if filteredBookListRefreshing != refreshing {
                        if !refreshing {
                            print("\(#function) filteredBookListRefreshing=\(filteredBookListRefreshing) refreshing=\(refreshing)")
                            modelData.librarySearchManager.getCaches(
                                for: modelData.filterCriteriaLibraries,
                                of: modelData.currentLibrarySearchCriteria
                            )
                            .forEach { entry in
                                print("\(#function) filteredBookListRefreshing=\(filteredBookListRefreshing) loadingLibrary=\(entry.key.libraryId) loading=\(entry.value.loading) offline=\(entry.value.offlineResult) error=\(entry.value.error)")
                            }
                        }
                        filteredBookListRefreshing = refreshing
                    }
                })
            
            categoryItemListCancellable?.cancel()
            categoryItemListCancellable = modelData.categoryItemListSubject
                .receive(on: DispatchQueue.main)
                .compactMap { categoryName -> String? in
                    guard categoryName == categoriesSelected else { return nil }
                    
                    if categoryName == self.categoryName,
                       categoryFilter == self.categoryFilterString.trimmingCharacters(in: .whitespacesAndNewlines),
                       categoryFilter.isEmpty == false {
                        return nil
                    }
                    
                    self.categoryName = categoryName
                    self.categoryFilter = self.categoryFilterString.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    self.categoryItems.removeAll(keepingCapacity: true)
                    self.categoryItemListUpdating = true
                    
                    return categoryName
                }
                .receive(on: DispatchQueue.global(qos: .userInitiated))
                .map { categoryName -> [String] in
                    guard var categoryItems = modelData.calibreLibraryCategoryMerged[categoryName]
                    else { return [] }
                    
                    if categoryFilter.isEmpty == false {
                        categoryItems = categoryItems.filter { $0.localizedCaseInsensitiveContains(categoryFilter) }
                    }
                    
                    guard categoryItems.count < 1000 else {
                        return categoryItemsTooLong
                    }
                    
                    return categoryItems
                }
                .receive(on: DispatchQueue.main)
                .sink { categoryItems in
                    if categoryItems.isEmpty == false {
                        self.categoryItems.append(contentsOf: categoryItems)
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
    private func categoryListView() -> some View {
        Section {
            ForEach(modelData.calibreLibraryCategoryMerged.keys.sorted(), id: \.self) { categoryName in
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
                        if categoryItems == categoryItemsTooLong {
                            VStack(alignment: .center) {
                                Spacer()
                                Text("Too many category items,")
                                Text("Please specify a filter.")
                                Spacer()
                            }
                        } else {
                            List {
                                ForEach(categoryItems, id: \.self) { categoryItem in
                                    NavigationLink(tag: categoryItem, selection: $categoryItemSelected) {
                                        bookListView()
                                            .onAppear {
                                                if modelData.filterCriteriaCategory[categoryName]?.contains(categoryItem) == true {
                                                    return
                                                }
                                                
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
                                                
                                                resetToFirstPage()
                                            }
                                            .navigationTitle("\(categoryName): \(categoryItem)")
                                    } label: {
                                        Text(categoryItem)
                                    }
                                    .isDetailLink(false)
                                }
                            }
                            .disabled(categoryItemListUpdating)
                        }
                        
                        if categoryItemListUpdating {
                            ProgressView()
                                .scaleEffect(4, anchor: .center)
                                .progressViewStyle(CircularProgressViewStyle())
                        }
                    }
                    .navigationTitle("Category: \(categoryName)")
                    .onAppear {
                        guard let categoryName = categoriesSelected,
                              categoryName != self.categoryName
                        else { return }
                        
                        categoryFilterString = ""
                        modelData.categoryItemListSubject.send(categoryName)
                    }
                    .onDisappear {
                        if categoriesSelected == nil {
                            self.categoryName = ""
                            categoryItems.removeAll(keepingCapacity: true)
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
        VStack {
            bookListViewHeader()
            
            Divider()
            if let result = modelData.currentLibrarySearchResultMerged {
                bookListViewContent(books: result.booksForPage(page: modelData.filteredBookListPageNumber, pageSize: modelData.filteredBookListPageSize))
            }
            
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
                    ForEach(modelData.filterCriteriaCategory.sorted(by: { $0.key < $1.key}), id: \.key) { categoryFilter in
                        ForEach(categoryFilter.value.filter({
                            categoryFilter.key != categoriesSelected || $0 != categoryItemSelected
                        }).sorted(), id: \.self) { categoryFilterValue in
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
                        .foregroundColor(
                            modelData.filterCriteriaCategory.filter({ categoryFilter in
                                categoryFilter.value.filter({
                                    categoryFilter.key != categoriesSelected || $0 != categoryItemSelected
                                }).isEmpty == false
                            }).isEmpty ? .gray : .accentColor
                        )
                }
            }.padding([.leading, .trailing], 4)
        }
    }
    
    @ViewBuilder
    private func bookListViewContent(books: ArraySlice<CalibreBook>) -> some View {
        ZStack {
            List(selection: $selectedBookIds) {
                ForEach(books, id: \.self) { book in
                    NavigationLink (
                        destination: BookDetailView(viewMode: .LIBRARY)
                            .onAppear {
                                self.savedFilterCriteriaCategory = modelData.filterCriteriaCategory
                            },
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
                print("LIBRARYINFOVIEW books=\(books.count)")
            }
            .disabled(filteredBookListRefreshing)
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
                        downloadBookList.removeAll(keepingCapacity: true)
                        downloadBookList = Array(books)
                        batchDownloadSheetPresenting = true
                    } label: {
                        Image(systemName: "square.and.arrow.down.on.square")
                    }
                    .disabled(filteredBookListRefreshing)
                    
                    sortMenuView()
                        .disabled(filteredBookListRefreshing)
                }
            }
            if filteredBookListRefreshing {
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
                                    } else if searchResult.1.offlineResult,
                                              !searchResult.1.library.server.isLocal {
                                        Text("Local cached result, may not up to date.")
                                    }
                                }.font(.caption)
                                    .foregroundColor(.red)
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
            if filteredBookListRefreshing {
                ProgressView()
                    .progressViewStyle(.circular)
            }
            
            Spacer()
            
            if #available(iOS 16, *),
                modelData.filteredBookListPageNumber > 1 {
                Button {
                    modelData.filteredBookListPageNumber = 0
                } label: {
                    Image(systemName: "chevron.left.to.line")
                }
            }

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
            }.disabled(filteredBookListRefreshing && modelData.currentSearchLibraryResultsCannotFurther)
        }
        .padding(4)    //bottom bar
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
            modelData.filterCriteriaCategory["Authors"]?.contains($0) != true
        }) as [String]?, authors.isEmpty == false {
            Menu("More by Author ...") {
                ForEach(authors, id: \.self) { author in
                    Button {
                        updateFilterCategory(key: "Authors", value: author)
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
                    if book.inShelf {
                        modelData.startDownloadFormat(book: book, format: format, overwrite: true)
                    } else {
                        modelData.addToShelf(book: book, formats: [format])
                    }
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
                resetToFirstPage()
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
                        resetToFirstPage()
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
                    resetToFirstPage()

                }, label: {
                    Text("Yes" + (modelData.filterCriteriaShelved == .shelvedOnly ? "✓" : ""))
                })
                Button(action: {
                    if modelData.filterCriteriaShelved == .notShelvedOnly {
                        modelData.filterCriteriaShelved = .none
                    } else {
                        modelData.filterCriteriaShelved = .notShelvedOnly
                    }
                    resetToFirstPage()

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
                    resetToFirstPage()
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
        let searchResult = modelData.librarySearchManager.getCache(
            for: library,
            of: modelData.currentLibrarySearchCriteria
        )
        let mergeResult = modelData.currentLibrarySearchResultMerged
        
        return library.name
        + " "
        + (modelData.filterCriteriaLibraries.contains(library.id) ? "✓" : "")
        + " "
        + (searchResult.description)
        + " "
        + String(describing: mergeResult?.mergedPageOffsets[library.id])
    }
    
    private func getLibrarySearchingText() -> String {
        let searchResults = modelData.librarySearchManager.getCaches(
            for: modelData.filterCriteriaLibraries,
            of: modelData.currentLibrarySearchCriteria
        )
        let searchResultsLoading = searchResults.filter { $0.value.loading }
        if searchResultsLoading.count == 1,
           let libraryId = searchResultsLoading.first?.key.libraryId,
           let library = modelData.calibreLibraries[libraryId] {
            return "Searching \(library.name)..."
        }
        if searchResultsLoading.count > 1 {
            return "Searching \(searchResultsLoading.count) libraries..."
        }
        let searchResultsError = searchResults.filter { $0.value.error }
        if searchResultsError.isEmpty == false {
            return "Result Incomplete"
        }
        
        return ""
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
