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

    //@State private var booksList = [CalibreBook]()
    @State private var booksList = [String]()
    
    @State private var libraryList = [CalibreLibrary]()
    @State private var seriesList = [String]()
    @State private var ratingList = ["Not Rated", "★★★★★", "★★★★", "★★★", "★★", "★"]
    @State private var formatList = [String]()
    @State private var identifierList = [String]()
    
    @State private var sortCriteria = (by: SortCriteria.Added, ascending: false)
    
    @State private var booksListRefreshing = false
    @State private var searchString = ""
    @State private var selectedBookIds = Set<String>()
    @State private var editMode: EditMode = .inactive
    @State private var pageNo = 0
    @State private var pageSize = 100
    @State private var pageCount = 0
    @State private var updater = 0
    
    @State private var alertItem: AlertItem?
    
    @State private var batchDownloadSheetPresenting = false
    
    @State private var bookUpdateCancellable: AnyCancellable?
    @State private var booksListCancellable: AnyCancellable?
    @State private var dismissAllCancellable: AnyCancellable?

    private var errBook = CalibreBook(id: -1, library: CalibreLibrary(server: CalibreServer(name: "Error", baseUrl: "Error", hasPublicUrl: false, publicUrl: "Error", hasAuth: false, username: "Error", password: "Error"), key: "Error", name: "Error"))
    
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
                    HStack {
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
                    }
                }
                
                Divider()
                
                ZStack {
                    List(selection: $selectedBookIds) {
                        ForEach(booksList, id: \.self) { bookInShelfId in
                            NavigationLink (
                                destination: BookDetailView(viewMode: .LIBRARY),
                                tag: bookInShelfId,
                                selection: $modelData.selectedBookId
                            ) {
//                                LibraryInfoBookRow(book: Binding<CalibreBook>(get: {
//                                    book
//                                }, set: { newBook in
//                                    //dummy
//                                }))
                                bookRowView(book: getBook(for: bookInShelfId) ?? errBook)
                            }
                            .isDetailLink(true)
                            .contextMenu {
                                bookRowContextMenuView(book: getBook(for: bookInShelfId) ?? errBook)
                            }
                        }   //ForEach
                        //                        .onDelete(perform: deleteFromList)
                    }
                    .disabled(booksListRefreshing)
                    .popover(isPresented: $batchDownloadSheetPresenting,
                             attachmentAnchor: .rect(.bounds),
                             arrowEdge: .top
                    ) {
                        LibraryInfoBatchDownloadSheet(presenting: $batchDownloadSheetPresenting, editMode: $editMode, selectedBookIds: $selectedBookIds)
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
                    ToolbarItem(placement: .confirmationAction) {
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
                }
                
                Divider()
                
                HStack {
                    Spacer()
                    
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
                    Button(action:{
                        if pageNo > 0 {
                            pageNo -= 1
                        }
                    }) {
                        Image(systemName: "chevron.backward")
                    }
                    //                        Text("\(pageNo+1) / \(Int((Double(modelData.filteredBookList.count) / Double(pageSize)).rounded(.up)))")
                    Text("\(pageNo+1) / \(pageCount)")
                    Button(action:{
                        if pageNo + 1 < pageCount {
                            pageNo += 1
                        }
                    }) {
                        Image(systemName: "chevron.forward")
                    }
                    Button(action:{
                        if pageNo + 10 < pageCount {
                            pageNo += 10
                        } else {
                            pageNo = pageCount - 1
                        }
                    }) {
                        Image(systemName: "chevron.forward.2")
                    }
                }.padding(4)    //bottom bar
            }
            .padding(4)
            .navigationTitle("By \(sortCriteria.by.rawValue)")
            .navigationBarTitleDisplayMode(.automatic)
            .statusBar(hidden: false)
            //                .toolbar {
            //                    toolbarContent()
            //                }   //List.toolbar
            .environment(\.editMode, self.$editMode)  //TODO
        }   //NavigationView
        .navigationViewStyle(DefaultNavigationViewStyle())
        .listStyle(PlainListStyle())
        .onChange(of: pageNo, perform: { value in
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
                        modelData.readingBookInShelfId = booksList.first
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
        guard let realm = try? Realm(configuration: modelData.realmConf) else { return }
        
        booksListRefreshing = true
        var booksList = [String]()
        var libraryList = [CalibreLibrary]()
        var seriesList = [String]()
        var pageCount = 1
        defer {
            DispatchQueue.main.async {
                self.booksList.replaceSubrange(self.booksList.indices, with: booksList)
                self.seriesList.replaceSubrange(self.seriesList.indices, with: seriesList)
                self.formatList.replaceSubrange(self.formatList.indices, with: formatList)
                self.libraryList.replaceSubrange(self.libraryList.indices, with: libraryList)
                self.pageCount = pageCount
                booksListRefreshing = false
            }
        }
        
        var predicates = [String]()
        let searchTerms = searchString.trimmingCharacters(in: .whitespacesAndNewlines).split { $0.isWhitespace }
        if searchTerms.isEmpty == false {
            predicates.append(contentsOf:
                searchTerms.map {
                    "title CONTAINS[c] '\($0)' OR authorFirst CONTAINS[c] '\($0)'"
                }
            )
        }

        if modelData.filterCriteriaLibraries.isEmpty == false {
            predicates.append(
                " ( " +
                    modelData.filterCriteriaLibraries.compactMap {
                        guard let library = modelData.calibreLibraries[$0] else { return nil }
                        return "( libraryName == '\(library.name)' AND serverUrl == '\(library.server.baseUrl)' AND serverUsername == '\(library.server.username)' )"
                    }.joined(separator: " || ")
                    + " ) "
            )
        }
        
        if modelData.filterCriteriaSeries.isEmpty == false {
            predicates.append(" ( " + modelData.filterCriteriaSeries.map { "series == '\($0)'" }.joined(separator: " || ")  + " ) ")
        }
        
        if modelData.filterCriteriaRating.isEmpty == false {
            predicates.append(
                " ( " +
                    modelData.filterCriteriaRating.map {
                        if $0.count <= 5 {
                            return "rating == \($0.count * 2)"
                        } else {
                            return "rating == 0"
                        }
                    }.joined(separator: " || ")
                    + " ) ")
        }
        
        if modelData.filterCriteriaShelved != .none {
            predicates.append("inShelf == \(modelData.filterCriteriaShelved == .shelvedOnly ? true : false)")
        }
//        guard filterCriteriaRating.isEmpty || filterCriteriaRating.contains(book.ratingDescription) else { return false }
//        guard filterCriteriaFormat.isEmpty || filterCriteriaFormat.intersection(book.formats.compactMap { $0.key }).isEmpty == false else { return false }
//        guard filterCriteriaIdentifier.isEmpty || filterCriteriaIdentifier.intersection(book.identifiers.compactMap { $0.key }).isEmpty == false else { return false }
//        guard filterCriteriaSeries.isEmpty || filterCriteriaSeries.contains(book.seriesDescription) else { return false }
//        guard filterCriteriaShelved == .none || (filterCriteriaShelved == .shelvedOnly && book.inShelf) || (filterCriteriaShelved == .notShelvedOnly && !book.inShelf) else { return false }
        
        let predicateFormat = predicates.isEmpty
            ? ""
            : (
                predicates.count == 1
                    ? predicates[0]
                    : "( " + predicates.joined(separator: " ) AND ( ") + " )"
            )
        let predicateArgs = [Any]()
        
        print("\(#function) predicateFormat=\(predicateFormat) \(predicateArgs)")
        
        let allbooks = realm.objects(CalibreBookRealm.self)
        
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
        
        var objects = allbooks
        if predicateFormat.isEmpty == false {
            objects = objects.filter(predicateFormat, predicateArgs)
        }
        let count = objects.count
        
        pageCount = Int((Double(count) / Double(pageSize)).rounded(.up))
        
        guard pageNo*pageSize < count else { return }
        
        let sortKeyPath = { () -> String in
            switch(sortCriteria.by) {
            case .Title:
                return "title"
            case .Added:
                return "timestamp"
            case .Publication:
                return "pubDate"
            case .Modified:
                return "lastModified"
            }
        }()
        booksList = objects.sorted(byKeyPath: sortKeyPath, ascending: sortCriteria.ascending)[(pageNo*pageSize) ..< Swift.min((pageNo+1)*pageSize, count)]
            .compactMap {
                $0.primaryKey
            }
        
        libraryList = modelData.calibreLibraries.map { $0.value }.sorted { $0.name < $1.name }
    }
    
    private func getBook(for primaryKey: String) -> CalibreBook? {
        guard let obj = modelData.getBookRealm(forPrimaryKey: primaryKey),
              let book = modelData.convert(bookRealm: obj) else { return nil }
        return book
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
                            Text(library.name + (modelData.filterCriteriaLibraries.contains(library.id) ? "✓" : ""))
                            Text(library.server.name).font(.caption)
                        }
                    })
                }
            }
            
            Menu("Series ...") {
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
                    if sortCriteria.by == sort {
                        sortCriteria.ascending.toggle()
                    } else {
                        sortCriteria.by = sort
                        sortCriteria.ascending = sort == .Title ? true : false
                    }
                    NotificationCenter.default.post(Notification(name: .YABR_LibraryBookListNeedUpdate))
                }) {
                    HStack {
                        if sortCriteria.by == sort {
                            if sortCriteria.ascending {
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
    
    func deleteFromList(at offsets: IndexSet) {
        modelData.filteredBookList.remove(atOffsets: offsets)
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

enum SortCriteria: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }
    
    case Title
    case Added
    case Publication
    case Modified
}

@available(macCatalyst 14.0, *)
struct LibraryInfoView_Previews: PreviewProvider {
    static private var modelData = ModelData()
    static var previews: some View {
        LibraryInfoView()
            .environmentObject(ModelData())
    }
}
