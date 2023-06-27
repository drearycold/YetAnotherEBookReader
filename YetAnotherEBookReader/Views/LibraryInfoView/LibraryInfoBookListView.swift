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
    
    @EnvironmentObject var viewModel: LibraryInfoView.ViewModel

    @ObservedRealmObject var unifiedSearchObject: CalibreUnifiedSearchObject
    
    @ObservedResults(CalibreUnifiedSearchObject.self) var unifiedSearches

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
                
                if unifiedSearchObject.loading {
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
                    searchString = viewModel.searchString
                }
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
                    ForEach(viewModel.filterCriteriaCategory.sorted(by: { $0.key < $1.key}), id: \.key) { categoryFilter in
                        ForEach(categoryFilter.value.filter({
                            categoryFilter.key != viewModel.categoriesSelected || $0 != viewModel.categoryItemSelected
                        }).sorted(), id: \.self) { categoryFilterValue in
                            Button {
                                if viewModel.filterCriteriaCategory[categoryFilter.key]?.remove(categoryFilterValue) != nil {
                                    if viewModel.filterCriteriaCategory[categoryFilter.key]?.isEmpty == true {
                                        viewModel.filterCriteriaCategory.removeValue(forKey: categoryFilter.key)
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
                            viewModel.filterCriteriaCategory.filter({ categoryFilter in
                                categoryFilter.value.filter({
                                    categoryFilter.key != viewModel.categoriesSelected || $0 != viewModel.categoryItemSelected
                                }).isEmpty == false
                            }).isEmpty ? .gray : .accentColor
                        )
                }
            }.padding([.leading, .trailing], 4)
        }
    }
    
    @ViewBuilder
    private func contentView(geometry: GeometryProxy) -> some View {
//        #if DEBUG
//        List {
//            Text("count \(unifiedSearchObject.books.count)")
//            ForEach(unifiedSearchObject.books) { bookRealm in
//                Text(bookRealm.primaryKey!)
//            }
//        }
//        #endif
        ScrollViewReader { proxy in
            List(selection: $selectedBookIds) {
                #if DEBUG
                debugView()
                #endif
                
                if unifiedSearchObject.books.isEmpty {
                    Text(getLibraryLoadingCount() > 0 ? "Loading books..." : "Found no books.")
                } else {
                    if let sectionByString = viewModel.sectionedBy?.sectionByString {
                        ForEach(unifiedSearchObject.books.sectioned(by: sectionByString)) { section in
                            Section {
                                ForEach(section) { bookRealm in
                                    listEntryView(bookRealm: bookRealm)
                                }
                            } header: {
                                Text(section.key ?? "Unknown")
                            }
                            
                        }
                    } else if let sectionByRating = viewModel.sectionedBy?.sectionByRating {
                        ForEach(unifiedSearchObject.books.sectioned(by: sectionByRating, ascending: false)) { section in
                            Section {
                                ForEach(section) { bookRealm in
                                    listEntryView(bookRealm: bookRealm)
                                }
                            } header: {
                                Text(CalibreBookRealm.RatingDescription(section.key))
                            }
                        }
                    } else {
                        ForEach(unifiedSearchObject.books) { bookRealm in
                            listEntryView(bookRealm: bookRealm)
                        }
                    }
                }
                #if DEBUG
                debugView()
                #endif
            }
            .onAppear {
                print("LIBRARYINFOVIEW books=\(unifiedSearchObject.books.count)")
            }
            .disabled(unifiedSearchObject.loading)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    downloadButton(geometry: geometry)
                        .disabled(unifiedSearchObject.loading)
                    
                    sortMenuView()
                        .disabled(unifiedSearchObject.loading)
                }
            }
        }
    }
    
    @ViewBuilder
    private func listEntryView(bookRealm: CalibreBookRealm) -> some View {
        NavigationLink (
            destination: BookDetailView(book: bookRealm, viewMode: .LIBRARY),
            tag: bookRealm.primaryKey!,
            selection: $modelData.selectedBookId
        ) {
            LibraryInfoBookRow(unifiedSearchObject: unifiedSearchObject, bookRealm: bookRealm)
        }
        .isDetailLink(true)
        .contextMenu {
            if let book = modelData.convert(bookRealm: bookRealm) {
                bookRowContextMenuView(book: book)
            } else {
                EmptyView()
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
                LibraryInfoBookListInfoView(unifiedSearchObject: unifiedSearchObject, presenting: $booksListInfoPresenting)
                    .frame(idealWidth: geometry.size.width - 50, idealHeight: geometry.size.height - 50)
            }
            .padding([.leading, .trailing], 4)

            Text(getLibrarySearchingText())
            
            if unifiedSearchObject.loading {
                ProgressView()
                    .progressViewStyle(.circular)
            }
            
            Spacer()
            
            if unifiedSearchObject.totalNumber > 0 {
                Text("\(unifiedSearchObject.books.count) / \(unifiedSearchObject.totalNumber)")
            }
            
            Button {
                guard let realm = unifiedSearchObject.realm?.thaw(),
                let thawedObject = unifiedSearchObject.thaw()
                else {
                    return
                }
                
                try! realm.write {
                    thawedObject.unifiedOffsets.forEach {
                        $0.value?.generation = .distantPast
                    }
                }
                
                modelData.librarySearchManager.refreshSearchResults(
                    libraryIds: viewModel.filterCriteriaLibraries,
                    searchCriteria: viewModel.currentLibrarySearchCriteria,
                    force: true
                )
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
        .padding(4)    //bottom bar
    }
    
    @ViewBuilder
    private func downloadButton(geometry: GeometryProxy) -> some View {
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
                    if viewModel.sortCriteria.by == sort {
                        viewModel.sortCriteria.ascending.toggle()
                    } else {
                        viewModel.sortCriteria.by = sort
                        viewModel.sortCriteria.ascending = sort == .Title ? true : false
                    }
                    resetToFirstPage()
                }) {
                    HStack {
                        if viewModel.sortCriteria.by == sort {
                            if viewModel.sortCriteria.ascending {
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
            
            if unifiedSearchObject.books.count == unifiedSearchObject.totalNumber,
               unifiedSearchObject.totalNumber > 0,
               unifiedSearchObject.totalNumber < 1000 {
                Divider()
                
                Text("Group By")
                
                ForEach(LibraryInfoView.GroupKey.allCases) { key in
                    Button {
                        if viewModel.sectionedBy != key {
                            viewModel.sectionedBy = key
                        } else {
                            viewModel.sectionedBy = nil
                        }
                    } label: {
                        Text((viewModel.sectionedBy == key ? "✓ " : "  ") + key.description)
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
    private func bookRowView(book: CalibreBook, bookRealm: CalibreBookRealm) -> some View {
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
//                #if DEBUG
//                HStack {
//                    Text("Book")
//                    Text("\(book.id)")
//                    Spacer()
//                    Text(book.inShelfId)
//                }
//                HStack {
//                    Text("BookRealm")
//                    Text("\(bookRealm.idInLib)")
//                    Spacer()
//                    Text(bookRealm.primaryKey!)
//                }
//                #endif

                Text("\(book.title)")
                    .font(.callout)
                    .lineLimit(3)
                
                Group {
                    HStack {
                        Text("\(book.authorsDescriptionShort)")
                        Spacer()
                        Text(book.lastModifiedByLocale)
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
            viewModel.filterCriteriaCategory["Authors"]?.contains($0) != true
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
            viewModel.filterCriteriaCategory["Tags"]?.contains($0) != true
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
           viewModel.filterCriteriaCategory["Series"]?.contains(book.series) != true {
            Button {
                viewModel.sortCriteria.by = .SeriesIndex
                viewModel.sortCriteria.ascending = true
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
    
    private func getLibraryLoadingCount() -> Int {
        modelData.calibreLibraries
            .sorted(by: { $0.key < $1.key })
            .filter({
                $0.value.hidden == false
                &&
                $0.value.server.removed == false
                &&
                (unifiedSearchObject.libraryIds.isEmpty || unifiedSearchObject.libraryIds.contains($0.key))
            })
            .map({
                $0.key
            })
            .reduce(0, { partialResult, libraryId in
                guard let unifiedOffsetOpt = unifiedSearchObject.unifiedOffsets[libraryId],
                      unifiedOffsetOpt != nil
                else {
                    return partialResult + 1
                }
                if let runtime = modelData.librarySearchManager.cacheSearchLibraryRuntime[.init(libraryId: libraryId, criteria: viewModel.currentLibrarySearchCriteria)],
                   runtime.loading > 0 {
                    return partialResult + 1
                }
                return partialResult
            })
    }
    
    private func getLibrarySearchingText() -> String {
        let librariesLoading = getLibraryLoadingCount()
        
        let offsets = unifiedSearchObject.unifiedOffsets.filter {
            guard let unifiedOffset = $0.value,
                  let searchSourceOpt = unifiedOffset.searchObject?.sources[unifiedOffset.searchObjectSource],
                  let searchSource = searchSourceOpt
            else {
                return false
            }
            
            return searchSource.totalNumber > 0
        }
        
        var text = ""
        
        if offsets.count < 1 {
            if librariesLoading > 0 {
                text = "Still searching \(librariesLoading) libraries"
            } else {
                text = "Cannot find in any library"
            }
        } else {
            text = "Found in \(offsets.count) \(offsets.count == 1 ? "library" : "libraries")"
            
            if librariesLoading > 0 {
                text += ", \(librariesLoading) to go"
            }
        }
        
        
        return text
    }
    
    func searchStringChanged(searchString: String) {
        self.searchString = searchString.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.searchString = self.searchString
        
        resetToFirstPage()
    }
    
    func updateFilterCategory(key: String, value: String) {
        if viewModel.filterCriteriaCategory[key] == nil {
            viewModel.filterCriteriaCategory[key] = .init()
        }
        viewModel.filterCriteriaCategory[key]?.insert(value)
        
        resetToFirstPage()
    }
    
    func resetToFirstPage() {
        let cacheObj = modelData.librarySearchManager.retrieveUnifiedSearchObject(
            viewModel.filterCriteriaLibraries,
            viewModel.currentLibrarySearchCriteria,
            unifiedSearches
        )
        
        if cacheObj.realm == nil {
            $unifiedSearches.append(cacheObj)
        }
        
        viewModel.setUnifiedSearchObject(modelData: modelData, unifiedSearchObject: cacheObj)
    }
    
    @ViewBuilder
    func debugView() -> some View {
        Group {
            Group {
                Text("Object: \(unifiedSearchObject._id) \(unifiedSearchObject.libraryIds.count) \(unifiedSearchObject.unifiedOffsets.count)")
                
                Text("Books: \(unifiedSearchObject.books.count), Total: \(unifiedSearchObject.totalNumber), Limit: \(unifiedSearchObject.limitNumber)")
                
                Button {
                    viewModel.expandSearchUnifiedBookLimit(unifiedSearchObject)
                } label: {
                    Text("Expand")
                }
                
                Button {
                    let realm = unifiedSearchObject.realm!.thaw()
                    let thawedObject = unifiedSearchObject.thaw()!
                    try! realm.write {
                        thawedObject.resetList()
                        thawedObject.limitNumber = 0
                    }
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
                    (unifiedSearchObject.libraryIds.isEmpty || unifiedSearchObject.libraryIds.contains($0.key))
                }), id: \.key
            ) { libraryId, library in
                Text("Required: \(libraryId)")
                if let unifiedOffsetOpt = unifiedSearchObject.unifiedOffsets[libraryId],
                   let unifiedOffset = unifiedOffsetOpt {
                    HStack {
                        if let runtime = modelData.librarySearchManager.cacheSearchLibraryRuntime[.init(libraryId: libraryId, criteria: viewModel.currentLibrarySearchCriteria)] {
                            Text("Loading: \(runtime.loading)")
                        } else {
                            Text("!!!Mising Search Runtime!!!")
                        }
                        Text(unifiedOffset.description)
                    }
                    if let searchObj = unifiedOffset.searchObject {
                        ForEach(searchObj.sources.sorted(by: { $0.key < $1.key }), id: \.key) { searchSourceEntry in
                            HStack {
                                Text(library.name)
                                Text("\(library.lastModified)")
                                Spacer()
                                Text(searchSourceEntry.value?.description ?? "N/A")
                            }
                            .tag(searchObj.libraryId + "|" + searchSourceEntry.key)
                        }
                        .padding([.leading, .trailing], 8)
                    } else {
                        Text("Missing searchObj & Library")
                    }
                    
                } else {
                    Text("No Unified Offset Object")
                }
                
            }
        }
        .foregroundColor(.red)
    }
}

//struct LibraryInfoBookListView_Previews: PreviewProvider {
//    static var previews: some View {
//        LibraryInfoBookListView()
//    }
//}
