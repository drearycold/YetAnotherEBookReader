//
//  ShelfDataManager.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/11/30.
//

import Foundation
import Combine
import ShelfView
import RealmSwift

class YabrShelfDataModel: ObservableObject {
    
    enum CategoryType: String {
        case Last
        case Author
        case Series
        case Tag
    }
    
    class CategoryObject: ObservableObject, Hashable {
        
        let type: CategoryType
        let category: String
        
        var inShelfBookIds: Set<String> = []
        
        var unifiedSearchObject: CalibreUnifiedSearchObject?
        
        init(type: CategoryType, category: String) {
            self.type = type
            self.category = category
        }
        
        func hash(into: inout Hasher) {
            into.combine(type)
            into.combine(category)
        }
        
        static func == (lhs: YabrShelfDataModel.CategoryObject, rhs: YabrShelfDataModel.CategoryObject) -> Bool {
            lhs.type == rhs.type && lhs.category == rhs.category
        }
        
    }
    private let service: CalibreServerService
    private let searchManager: CalibreLibrarySearchManager
    
    @Published var categories: Set<CategoryObject> = []
    
    @Published var discoverShelf = [String: ShelfModelSection]()
    
    var cancellables: Set<AnyCancellable> = []
    
    let dispatchQueue = DispatchQueue(label: "test-queue")
    
    init(service: CalibreServerService, searchManager: CalibreLibrarySearchManager) {
        self.service = service
        self.searchManager = searchManager
        
        service.modelData.$booksInShelf
            .receive(on: DispatchQueue.main)
            .sink { books in
                books.forEach {
                    self.addToShelf(book: $0.value)
                }
            }
            .store(in: &cancellables)
        
        service.modelData.booksInShelf.forEach {
            self.addToShelf(book: $0.value)
        }
        
        Timer.publish(every: 60, on: .main, in: .default)
            .autoconnect()
            .receive(on: self.searchManager.cacheRealmQueue)
            .sink { timer in
                self.searchManager.refreshSearchResults()
            }
            .store(in: &cancellables)
    }
    
    func addToShelf(book: CalibreBook) {
        for categoryName in book.authors.prefix(3) {
            let category = CategoryObject(type: .Author, category: categoryName)
            if let index = categories.firstIndex(of: category) {
                categories[index].inShelfBookIds.insert(book.inShelfId)
            } else {
                category.inShelfBookIds.insert(book.inShelfId)
                
                searchManager.cacheRealmQueue.async { [self] in
                    let unifiedSearchObject = searchManager.getUnifiedResult(
                        libraryIds: [],
                        searchCriteria: .init(
                            searchString: "",
//                            sortCriteria: .init(by: .Title, ascending: true),
                            sortCriteria: .init(),
                            filterCriteriaCategory: ["Authors" : Set([categoryName])]
                        )
                    )
                    
                    category.unifiedSearchObject = unifiedSearchObject
                    
                    unifiedSearchObject.books.changesetPublisher
                        .subscribe(on: searchManager.cacheRealmQueue)
                        .map { changeset -> ShelfModelSection in
                            switch changeset {
                            case .initial(_), .error(_):
                                print("unifiedSearchObject changeset initial  \(unifiedSearchObject.books.count)")
                                break
                            case .update(_, deletions: let deletions, insertions: let insertions, modifications: let modifications):
                                print("unifiedSearchObject changeset update \(unifiedSearchObject.books.count)")
                                break
                            }
                            
                            return self.buildShelfModelSection(category: category)
                        }
                        .receive(on: DispatchQueue.main)
                        .sink { discoverShelfSection in
                            if discoverShelfSection.sectionShelf.count > 1 {
                                self.discoverShelf[discoverShelfSection.sectionId] = discoverShelfSection
                            }
                        }
                        .store(in: &cancellables)
                }
                
                categories.insert(category)
            }
        }
    }
    
    
    func buildShelfModelSection(category: CategoryObject) -> ShelfModelSection {
        let sectionName = "\(category.type.rawValue): \(category.category)"
        
        let sectionShelf: [ShelfModel] = category.unifiedSearchObject?.books.map {
            var coverSource = ""
            if let serverUUID = $0.serverUUID,
               let server = self.service.modelData.calibreServers[serverUUID],
               let serverUrl = service.getServerUrlByReachability(server: server) ?? URL(string: server.serverUrl),
               let libraryName = $0.libraryName,
               let library = self.service.modelData.calibreLibraries[CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName)] {
                
                var coverRelativeURLComponent = URLComponents()
                coverRelativeURLComponent.path = "get/thumb/\($0.idInLib)/\(library.key)"
                coverRelativeURLComponent.queryItems = [
                    .init(name: "sz", value: "300x400"),
                    .init(name: "username", value: server.username)
                ]
                
                coverSource = coverRelativeURLComponent.url(relativeTo: serverUrl)?.absoluteString ?? ""
            }
            return ShelfModel(bookCoverSource: coverSource, bookId: $0.primaryKey!, bookTitle: $0.title, bookProgress: 0, bookStatus: .READY, sectionId: sectionName)
        } ?? []
        
        return .init(sectionName: sectionName, sectionId: sectionName, sectionShelf: sectionShelf)
    }
}

extension ModelData {
    func registerRecentShelfUpdater() {
        let queue = DispatchQueue(label: "recent-shelf-updater", qos: .userInitiated)
        calibreUpdatedSubject.receive(on: queue)
            .collect(.byTime(RunLoop.main, .seconds(1)))
            .map { signals -> [(key: String, value: CalibreBook)] in
                self.booksInShelf
                    .sorted {
                        max($0.value.lastModified,
                            $0.value.readPos.getDevices().map{p in Date(timeIntervalSince1970: p.epoch)}.max() ?? $0.value.lastUpdated
                        ) > max(
                            $1.value.lastModified,
                            $1.value.readPos.getDevices().map{p in Date(timeIntervalSince1970: p.epoch)}.max() ?? $1.value.lastUpdated
                        )
                    }
            }
            .map { books -> [BookModel] in
                books
                    .map { (inShelfId, book) -> BookModel in
                        let readerInfo = self.prepareBookReading(book: book)
                        
                        let bookUptoDate = book.formats.allSatisfy {
                            $1.cached == false ||
                            ($1.cached && $1.cacheUptoDate)
                        }
                        let missingFormats = book.formats.filter {
                            $1.selected == true && $1.cached == false
                        }
                        
                        var bookStatus = BookModel.BookStatus.READY
                        if self.calibreServerService.getServerUrlByReachability(server: book.library.server) == nil {
                            bookStatus = .NOCONNECT
                        } else {
                            missingFormats.forEach {
                                guard let format = Format(rawValue: $0.key) else { return }
                                self.bookFormatDownloadSubject.send((book: book, format: format))
                            }
                            
                            if !bookUptoDate {
                                bookStatus = .HASUPDATE
                            }
                            if self.activeDownloads.contains(where: { (url, download) in
                                download.isDownloading && download.book.inShelfId == inShelfId
                            }) {
                                bookStatus = .DOWNLOADING
                            }
                        }
                        if book.library.server.isLocal {
                            bookStatus = .LOCAL
                        }
                        
                        return BookModel(
                            bookCoverSource: book.coverURL?.absoluteString ?? "",
                            bookId: inShelfId,
                            bookTitle: book.title,
                            bookProgress: Int(floor(readerInfo.position.lastProgress)),
                            bookStatus: bookStatus
                        )
                    }
            }
            .receive(on: RunLoop.main)
            .sink(receiveValue: { result in
//                self.books = result.0
//                self.shelfView.reloadBooks(bookModel: result.1)
                self.recentShelfModelSubject.send(result)
            })
            .store(in: &calibreCancellables)
    }
    
    func registerDiscoverShelfUpdater() {
        return;
        
        //MARK: TODO
        calibreUpdatedSubject
            .collect(.byTime(RunLoop.main, .seconds(1)))
            .receive(on: ModelData.SearchLibraryResultsRealmQueue)
            .sink { signals in
                let signalSet = Set<calibreUpdatedSignal>(signals)
                let librarySearchKeys = self.calibreLibraries.reduce(into: Set<LibrarySearchKey>()) { partialResult, libraryEntry in
                    guard libraryEntry.value.hidden == false,
                          libraryEntry.value.discoverable == true, self.calibreServers[libraryEntry.value.server.id]?.removed == false
                    else { return }
                    
                    partialResult.insert(
                        .init(
                            libraryId: libraryEntry.key,
                            criteria: .init(
                                searchString: "",
                                sortCriteria: .init(by: .Modified, ascending: false),
                                filterCriteriaCategory: [:]
                            )
                        )
                    )
                    partialResult.insert(
                        .init(
                            libraryId: libraryEntry.key,
                            criteria: .init(
                                searchString: "",
                                sortCriteria: .init(by: .Added, ascending: false),
                                filterCriteriaCategory: [:]
                            )
                        )
                    )
                    partialResult.insert(
                        .init(
                            libraryId: libraryEntry.key,
                            criteria: .init(
                                searchString: "",
                                sortCriteria: .init(by: .Publication, ascending: false),
                                filterCriteriaCategory: [:]
                            )
                        )
                    )
                }
                
                self.booksInShelf.values.filter({ book in
                    book.library.server.isLocal == false
                    && self.calibreLibraries[book.library.id]?.hidden == false
                    && self.calibreLibraries[book.library.id]?.discoverable == true
                    && self.calibreServers[book.library.server.id]?.removed == false
                    && (
                        signalSet.contains(.shelf) ||
                        signalSet.contains(.deleted(book.inShelfId)) ||
                        signalSet.contains(.book(book)) ||
                        signalSet.contains(.library(book.library)) ||
                        signalSet.contains(.server(book.library.server))
                    )
                }).reduce(into: librarySearchKeys) { libraryKeys, book in
                    if let author = book.authors.first {
                        libraryKeys.insert(.init(
                            libraryId: book.library.id,
                            criteria: .init(
                                searchString: "",
                                sortCriteria: .init(by: .Title, ascending: true),
                                filterCriteriaCategory: ["Authors": Set<String>([author])]
                            )
                        ))
                    }
                    book.tags.forEach { tag in
                        libraryKeys.insert(.init(
                            libraryId: book.library.id,
                            criteria: .init(
                                searchString: "",
                                sortCriteria: .init(by: .Modified, ascending: false),
                                filterCriteriaCategory: ["Tags": Set<String>([tag])]
                            )
                        ))
                    }
                    if book.series.isEmpty == false {
                        libraryKeys.insert(.init(
                            libraryId: book.library.id,
                            criteria: .init(
                                searchString: "",
                                sortCriteria: .init(by: .SeriesIndex, ascending: true),
                                filterCriteriaCategory: ["Series": Set<String>([book.series])]
                            )
                        ))
                    }
                }.forEach {
                    if let library = self.calibreLibraries[$0.libraryId],
                       let task = self.calibreServerService.buildLibrarySearchTask(library: library, searchCriteria: $0.criteria) {
                        self.librarySearchRequestSubject.send(task)
                    }
                }
            }
            .store(in: &calibreCancellables)
        
        librarySearchResultSubject.receive(on: DispatchQueue.main)
            .map { librarySearchTask -> (LibrarySearchKey, LibrarySearchResult?) in
                let librarySearchKey = LibrarySearchKey(libraryId: librarySearchTask.library.id, criteria: librarySearchTask.searchCriteria)
                guard let library = self.calibreLibraries[librarySearchKey.libraryId],
                      library.hidden == false,
                      library.discoverable == true,
                      let realm = try? Realm(configuration: self.realmConf)
                else { return (librarySearchKey, nil) }
                
                let result = self.librarySearchManager.getCache(
                    for: library,
                    of: librarySearchTask.searchCriteria
                )
                
                return (librarySearchKey, result)
            }
            .receive(on: ModelData.SearchLibraryResultsRealmQueue)
            .map { librarySearchKey, result -> ShelfModelSection in
                let emptyShelf = ShelfModelSection(sectionName: "", sectionId: "", sectionShelf: [])
                
                guard let result = result else { return emptyShelf }
                
//                let librarySearchKey = LibrarySearchKey(libraryId: result.library.id, criteria: result.searchCriteria)
                guard let library = self.calibreLibraries[librarySearchKey.libraryId],
                      library.hidden == false,
                      library.discoverable == true,
                      let realm = try? Realm(configuration: self.realmConf)
                else { return emptyShelf }
//
//                let result = self.librarySearchManager.getCache(
//                    for: library,
//                    of: librarySearchTask.searchCriteria
//                )

                if librarySearchKey.criteria.searchString == "",
                   librarySearchKey.criteria.hasEmptyFilter {
                    let sectionId = "\(librarySearchKey.description)"
                    
                    let serverUUID = library.server.uuid.uuidString
                    
                    let sectionShelf = result.bookIds.compactMap { bookId -> ShelfModel? in
                        let primaryKey = CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: library.name, id: bookId.description)
                        
                        guard realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)?.inShelf != true else { return nil }
                        
                        guard let bookRealm = self.searchLibraryResultsRealmQueue?.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey) ?? realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
                        else { return nil }
                        
                        let book = self.convert(library: library, bookRealm: bookRealm)
                        
                        return ShelfModel(
                            bookCoverSource: book.coverURL?.absoluteString ?? ".",
                            bookId: book.inShelfId,
                            bookTitle: book.title,
                            bookProgress: Int(
                                book.readPos.getDevices().max { lhs, rhs in
                                    lhs.lastProgress < rhs.lastProgress
                                }?.lastProgress ?? 0.0),
                            bookStatus: .READY,
                            sectionId: sectionId
                        )
                    }
                    
                    let sectionName = "\(librarySearchKey.criteria.sortCriteria.description) in \(library.name)"
                    
                    return ShelfModelSection(sectionName: sectionName, sectionId: sectionId, sectionShelf: sectionShelf)
                }
                guard librarySearchKey.criteria.filterCriteriaCategory.count == 1,
                      let categoryFilter = librarySearchKey.criteria.filterCriteriaCategory.first,
                      categoryFilter.value.count == 1,
                      let categoryFilterValue = categoryFilter.value.first
                else { return emptyShelf }
                
                switch categoryFilter.key {
                case "Tags":
                    guard self.booksInShelf.first(where: { $0.value.tags.firstIndex(of: categoryFilterValue) != nil }) != nil
                    else { return emptyShelf }
                case "Authors":
                    guard self.booksInShelf.first(where: { $0.value.authors.firstIndex(of: categoryFilterValue) != nil }) != nil
                    else { return emptyShelf }
                case "Series":
                    guard self.booksInShelf.first(where: { $0.value.series == categoryFilterValue }) != nil
                    else { return emptyShelf }
                default:    //unrecognized
                    return emptyShelf
                }
                
                let sectionId = "\(librarySearchKey.description)"
                
                let serverUUID = library.server.uuid.uuidString
                var bookIds = Set<String>()
                
                let sectionShelf = result.bookIds.compactMap { bookId -> ShelfModel? in
                    let primaryKey = CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: library.name, id: bookId.description)
                    
                    guard realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)?.inShelf != true else { return nil }
                    
                    guard let bookRealm = self.searchLibraryResultsRealmQueue?.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey) ?? realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
                    else { return nil }
                    
                    let book = self.convert(library: library, bookRealm: bookRealm)
                    guard bookIds.contains(book.inShelfId) == false
                    else {
                        assertionFailure("duplicate book")
                        return nil
                    }
                    bookIds.insert(book.inShelfId)
                    
                    return ShelfModel(
                        bookCoverSource: book.coverURL?.absoluteString ?? ".",
                        bookId: book.inShelfId,
                        bookTitle: book.title,
                        bookProgress: Int(
                            book.readPos.getDevices().max { lhs, rhs in
                                lhs.lastProgress < rhs.lastProgress
                            }?.lastProgress ?? 0.0),
                        bookStatus: .READY,
                        sectionId: sectionId
                    )
                }
                
                let sectionName = "\(categoryFilter.key): \(categoryFilterValue) in \(library.name)"
                
                return ShelfModelSection(sectionName: sectionName, sectionId: sectionId, sectionShelf: sectionShelf)
            }
            .receive(on: DispatchQueue.main)
            .sink { shelfModelSection in
                defer {
                    self.discoverShelfModelSubject.send(self.bookModelSection)
                }
                
                self.bookModelSection.removeAll { shelfModelSection.sectionId == $0.sectionId }
                
                guard shelfModelSection.sectionShelf.count > 1 else { return }
                
                self.bookModelSection.append(shelfModelSection)
                
                self.bookModelSection.removeAll {
                    guard let libraryId = ModelData.parseShelfSectionId(sectionId: $0.sectionId),
                          let library = self.calibreLibraries[libraryId],
                          library.hidden == false,
                          library.discoverable == true,
                          let server = self.calibreServers[library.server.id],
                          server.removed == false
                    else {
                        return true     //no corresponding library
                    }
                    return false
                }
                
                self.bookModelSection.sort { $0.sectionName < $1.sectionName }
            }
            .store(in: &calibreCancellables)
    }
}

extension ModelData {
    static func parseShelfSectionId(sectionId: String) -> String? {
        guard let sepRange = sectionId.range(of: " || ")
        else { return nil }
        let libraryId = String(sectionId[sectionId.startIndex..<sepRange.lowerBound])
        return libraryId
    }
}
