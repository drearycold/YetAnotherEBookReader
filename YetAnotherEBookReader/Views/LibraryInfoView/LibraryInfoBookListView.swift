//
//  LibraryInfoBookListView.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/3/28.
//

import SwiftUI
import RealmSwift
import struct Kingfisher.KFImage

struct LibraryInfoBookListView: View {
    @EnvironmentObject var modelData: ModelData
    
    @ObservedRealmObject var unifiedSearchObject: CalibreUnifiedSearchObject
    
    @Binding var categoriesSelected : String?
    @Binding var categoryItemSelected: String?
    
    @State private var selectedBookIds = Set<String>()
    @State private var downloadBookList = [CalibreBook]()
    
    @State private var searchString = ""
    
    @State private var batchDownloadSheetPresenting = false
    @State private var booksListInfoPresenting = false
    @State private var searchHistoryPresenting = false
    
    var body: some View {
        
//        List {
//            ForEach(unifiedSearchObject.books) { book in
//                NavigationLink {
//                    BookDetailViewRealm(book: book, viewMode: .LIBRARY)
//                } label: {
//                    Text(book.title)
//                }
//            }
//        }
        ZStack {
            VStack {
                headerView()
                
                Divider()
                
                contentView()
                
                Divider()
                
                footerView()
            }
            /*
            if filteredBookListRefreshing {
                ProgressView()
                    .scaleEffect(4, anchor: .center)
                    .progressViewStyle(CircularProgressViewStyle())
            }
            */
        }
    }
    
    @ViewBuilder
    private func headerView() -> some View {
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
                                    if modelData.filterCriteriaCategory[categoryFilter.key]?.isEmpty == true {
                                        modelData.filterCriteriaCategory.removeValue(forKey: categoryFilter.key)
                                    }
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
    private func contentView() -> some View {
        List(selection: $selectedBookIds) {
            ForEach(unifiedSearchObject.books) { bookRealm in
                NavigationLink (
                    destination: BookDetailViewRealm(book: bookRealm, viewMode: .LIBRARY),
                    tag: bookRealm.primaryKey!,
                    selection: $modelData.selectedBookId
                ) {
                    if let book = modelData.convert(bookRealm: bookRealm) {
                        bookRowView(book: book)
                    } else {
                        Text(bookRealm.title)
                    }
                }
                .isDetailLink(true)
                .contextMenu {
                    if let book = modelData.convert(bookRealm: bookRealm) {
                        bookRowContextMenuView(book: book)
                    } else {
                        EmptyView()
                    }
                }
            }   //ForEach
        }
        .onAppear {
            print("LIBRARYINFOVIEW books=\(unifiedSearchObject.books.count)")
        }
        
        .disabled(unifiedSearchObject.loading)
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
                    downloadBookList = unifiedSearchObject.books.compactMap({ bookRealm in
                        modelData.convert(bookRealm: bookRealm)
                    })
                    batchDownloadSheetPresenting = true
                } label: {
                    Image(systemName: "square.and.arrow.down.on.square")
                }
                .disabled(unifiedSearchObject.loading)
                
                sortMenuView()
                    .disabled(unifiedSearchObject.loading)
            }
        }
    }
    
    @ViewBuilder
    private func footerView() -> some View {
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
            /* MARK: TODO
            if filteredBookListRefreshing {
                ProgressView()
                    .progressViewStyle(.circular)
            }
            */
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
            }.disabled(unifiedSearchObject.loading && modelData.currentSearchLibraryResultsCannotFurther)
        }
        .padding(4)    //bottom bar
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
    
    
}

//struct LibraryInfoBookListView_Previews: PreviewProvider {
//    static var previews: some View {
//        LibraryInfoBookListView()
//    }
//}
