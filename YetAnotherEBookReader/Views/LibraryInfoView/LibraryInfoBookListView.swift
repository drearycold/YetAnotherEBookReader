//
//  LibraryInfoBookListView.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/3/28.
//

import SwiftUI
import KingfisherSwiftUI

struct LibraryInfoBookListView: View {
    @EnvironmentObject var modelData: ModelData
    @EnvironmentObject var downloadManager: BookDownloadManager
    @EnvironmentObject var libraryInfoViewModel: LibraryInfoView.ViewModel
    @EnvironmentObject var viewModel: UnifiedSearchViewModel

    @State private var selectedBookIds = Set<String>()
    @State private var downloadBookList = [CalibreBook]()
    
    @State private var searchString = ""
    
    @State private var batchDownloadSheetPresenting = false
    @State private var booksListInfoPresenting = false
    @State private var searchHistoryPresenting = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack {
                    headerView(geometry: geometry)
                    
                    Divider()
                    
                    contentView(geometry: geometry)
                    
                    Divider()
                    
                    footerView(geometry: geometry)
                }
                
                if viewModel.isSearchLoading {
                    ProgressView()
                        .scaleEffect(4, anchor: .center)
                        .progressViewStyle(CircularProgressViewStyle())
                }
            }
        }
    }
    
    @ViewBuilder
    private func headerView(geometry: GeometryProxy) -> some View {
        ZStack {
            TextField("Search Title & Authors", text: $searchString)
                .onAppear {
                    searchString = libraryInfoViewModel.searchString
                }
                .onSubmit {
                    libraryInfoViewModel.searchStringChanged(searchString: searchString, searchViewModel: viewModel)
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
                .padding(.leading, 4)

                Spacer()
                Button {
                    libraryInfoViewModel.searchStringChanged(searchString: "", searchViewModel: viewModel)
                    searchString = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }.disabled(searchString.isEmpty)
                
                Menu {
                    ForEach(libraryInfoViewModel.filterCriteriaCategory.sorted(by: { $0.key < $1.key}), id: \.key) { categoryFilter in
                        ForEach(categoryFilter.value.filter({
                            categoryFilter.key != libraryInfoViewModel.categoriesSelected || $0 != libraryInfoViewModel.categoryItemSelected
                        }).sorted(), id: \.self) { categoryFilterValue in
                            Button {
                                if libraryInfoViewModel.filterCriteriaCategory[categoryFilter.key]?.remove(categoryFilterValue) != nil {
                                    if libraryInfoViewModel.filterCriteriaCategory[categoryFilter.key]?.isEmpty == true {
                                        libraryInfoViewModel.filterCriteriaCategory.removeValue(forKey: categoryFilter.key)
                                    }
                                    libraryInfoViewModel.searchStringChanged(searchString: self.searchString, searchViewModel: viewModel)
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
                            libraryInfoViewModel.filterCriteriaCategory.filter({ categoryFilter in
                                categoryFilter.value.filter({
                                    categoryFilter.key != libraryInfoViewModel.categoriesSelected || $0 != libraryInfoViewModel.categoryItemSelected
                                }).isEmpty == false
                            }).isEmpty ? .gray : .accentColor
                        )
                }
                .padding(.trailing, 4)
            }
        }
    }
    
    @ViewBuilder
    private func contentView(geometry: GeometryProxy) -> some View {
        ScrollViewReader { proxy in
            List(selection: $selectedBookIds) {
                #if DEBUG
                debugView()
                #endif
                
                let books = viewModel.unifiedSearchResult?.books ?? []
                if books.isEmpty {
                    Text(libraryInfoViewModel.getLibraryLoadingCount(modelData: modelData, searchResult: viewModel.unifiedSearchResult, libraryStatuses: viewModel.libraryStatuses) > 0 ? "Loading books..." : "Found no books.")
                } else {
                    if let groupString = libraryInfoViewModel.sectionedBy?.groupString {
                        let grouped = Dictionary(grouping: Array(books.enumerated()), by: { groupString($0.element) })
                        let sortedKeys = grouped.keys.compactMap { $0 }.sorted()
                        ForEach(sortedKeys, id: \.self) { key in
                            Section {
                                ForEach(grouped[key] ?? [], id: \.element.id) { index, book in
                                    listEntryView(book: book, index: index)
                                }
                            } header: {
                                Text(key)
                            }
                        }
                    } else if let groupRating = libraryInfoViewModel.sectionedBy?.groupRating {
                        let grouped = Dictionary(grouping: Array(books.enumerated()), by: { groupRating($0.element) })
                        let sortedKeys = grouped.keys.sorted(by: >)
                        ForEach(sortedKeys, id: \.self) { key in
                            Section {
                                ForEach(grouped[key] ?? [], id: \.element.id) { index, book in
                                    listEntryView(book: book, index: index)
                                }
                            } header: {
                                Text(CalibreBookRealm.RatingDescription(key))
                            }
                        }
                    } else {
                        ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                            listEntryView(book: book, index: index)
                        }
                    }
                }
                #if DEBUG
                debugView()
                #endif
            }
            .onAppear {
                print("LIBRARYINFOVIEW books=\(viewModel.unifiedSearchResult?.books.count ?? 0)")
            }
            .disabled(viewModel.isSearchLoading)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    downloadButton(geometry: geometry)
                        .disabled(viewModel.isSearchLoading)
                    
                    sortMenuView()
                        .disabled(viewModel.isSearchLoading)
                }
            }
        }
    }
    
    @ViewBuilder
    private func listEntryView(book: CalibreBook, index: Int) -> some View {
        Group {
            if modelData.bookExists(forPrimaryKey: book.inShelfId) {
                NavigationLink (
                    destination: BookDetailView(bookId: book.inShelfId, viewMode: .LIBRARY),
                    tag: book.inShelfId,
                    selection: $modelData.selectedBookId
                ) {
                    LibraryInfoBookRow(book: book, index: index)
                }
                .isDetailLink(true)
                .contextMenu {
                    bookRowContextMenuView(book: book)
                }
            } else {
                LibraryInfoBookRow(book: book, index: index)
                    .contextMenu {
                        bookRowContextMenuView(book: book)
                    }
            }
        }
    }
    
    @ViewBuilder
    private func footerView(geometry: GeometryProxy) -> some View {
        HStack {
            Button {
                booksListInfoPresenting = true
            } label: {
                Image(systemName: "info.circle")
            }
            .popover(isPresented: $booksListInfoPresenting) {
                LibraryInfoBookListInfoView(presenting: $booksListInfoPresenting)
                    .frame(idealWidth: geometry.size.width - 50, idealHeight: geometry.size.height - 50)
            }
            .padding([.leading, .trailing], 4)

            Text(libraryInfoViewModel.getLibrarySearchingText(modelData: modelData, searchResult: viewModel.unifiedSearchResult, libraryStatuses: viewModel.libraryStatuses))
            
            if viewModel.isSearchLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            }
            
            Spacer()
            
            if let result = viewModel.unifiedSearchResult, result.totalNumber > 0 {
                Text("\(result.books.count) / \(result.totalNumber)")
            }
            
            Button {
                viewModel.resetSearch(force: true)
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
        .padding(4)
    }
    
    @ViewBuilder
    private func downloadButton(geometry: GeometryProxy) -> some View {
        Button {
            downloadBookList.removeAll(keepingCapacity: true)
            downloadBookList = viewModel.unifiedSearchResult?.books ?? []
            batchDownloadSheetPresenting = true
        } label: {
            Image(systemName: "square.and.arrow.down.on.square")
        }
        .disabled(viewModel.isSearchLoading)
        .popover(isPresented: $batchDownloadSheetPresenting,
                 attachmentAnchor: .point(.bottom),
                 arrowEdge: .bottom
        ) {
            LibraryInfoBatchDownloadSheet(
                presenting: $batchDownloadSheetPresenting,
                downloadBookList: $downloadBookList
            )
            .frame(idealWidth: geometry.size.width - 50, idealHeight: geometry.size.height - 50)
        }
    }
    
    @ViewBuilder
    private func sortMenuView() -> some View {
        Menu {
            ForEach(SortCriteria.allCases, id: \.self) { sort in
                Button(action: {
                    if libraryInfoViewModel.sortCriteria.by == sort {
                        libraryInfoViewModel.sortCriteria.ascending.toggle()
                    } else {
                        libraryInfoViewModel.sortCriteria.by = sort
                        libraryInfoViewModel.sortCriteria.ascending = sort == .Title ? true : false
                    }
                    libraryInfoViewModel.resetToFirstPage(searchViewModel: viewModel)
                }) {
                    HStack {
                        if libraryInfoViewModel.sortCriteria.by == sort {
                            if libraryInfoViewModel.sortCriteria.ascending {
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
            
            if let result = viewModel.unifiedSearchResult,
               result.books.count == result.totalNumber,
               result.totalNumber > 0,
               result.totalNumber < 1000 {
                Divider()
                
                Text("Group By")
                
                ForEach(LibraryInfoView.GroupKey.allCases) { key in
                    Button {
                        if libraryInfoViewModel.sectionedBy != key {
                            libraryInfoViewModel.sectionedBy = key
                        } else {
                            libraryInfoViewModel.sectionedBy = nil
                        }
                    } label: {
                        Text((libraryInfoViewModel.sectionedBy == key ? "✓ " : "  ") + key.description)
                    }
                }
            } else {
                EmptyView()
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }
    
    @ViewBuilder
    private func bookRowContextMenuView(book: CalibreBook) -> some View {
        if let authors = book.authors.filter({
            libraryInfoViewModel.filterCriteriaCategory["Authors"]?.contains($0) != true
        }) as [String]?, authors.isEmpty == false {
            Menu("More by Author ...") {
                ForEach(authors, id: \.self) { author in
                    Button {
                        libraryInfoViewModel.updateFilterCategory(key: "Authors", value: author, searchViewModel: viewModel)
                    } label: {
                        Text(author)
                    }
                }
            }
        }
        
        if let tags = book.tags.filter({
            libraryInfoViewModel.filterCriteriaCategory["Tags"]?.contains($0) != true
        }) as [String]?, tags.isEmpty == false {
            Menu("More of Tags ...") {
                ForEach(tags, id: \.self) { tag in
                    Button {
                        libraryInfoViewModel.updateFilterCategory(key: "Tags", value: tag, searchViewModel: viewModel)
                    } label: {
                        Text(tag)
                    }
                }
            }
        }
        
        if book.series.isEmpty == false,
           libraryInfoViewModel.filterCriteriaCategory["Series"]?.contains(book.series) != true {
            Button {
                libraryInfoViewModel.sortCriteria.by = .SeriesIndex
                libraryInfoViewModel.sortCriteria.ascending = true
                libraryInfoViewModel.updateFilterCategory(key: "Series", value: book.series, searchViewModel: viewModel)
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
    func debugView() -> some View {
        Group {
            if let result = viewModel.unifiedSearchResult {
                Group {
                    Text("Object: \(result.libraryIds.count) \(result.unifiedOffsets.count)")
                    
                    Text("Books: \(result.books.count), Total: \(result.totalNumber), Limit: \(result.limitNumber)")
                    
                    Button {
                        viewModel.expandSearchUnifiedBookLimit()
                    } label: {
                        Text("Expand")
                    }
                    
                    Button {
                        viewModel.resetSearch(force: false)
                    } label: {
                        Text("Reset")
                    }
                }
                
                ForEach(modelData.calibreLibraries
                    .sorted(by: { $0.key < $1.key })
                    .filter({
                        $0.value.hidden == false
                        &&
                        $0.value.server.removed == false
                        &&
                        (result.libraryIds.isEmpty || result.libraryIds.contains($0.key))
                    }), id: \.key
                ) { libraryId, library in
                    Text("Required: \(libraryId)")
                    if let unifiedOffset = result.unifiedOffsets[libraryId] {
                        HStack {
                            Text("Loading: \(viewModel.libraryStatuses[libraryId]?.loading == true ? 1 : 0)")
                            Text("offset: \(unifiedOffset.offset)")
                        }
                    } else {
                        Text("No Unified Offset Object")
                     }
                }
            } else {
                Text("No Unified Search Result")
            }
        }
        .foregroundColor(.red)
    }
}
