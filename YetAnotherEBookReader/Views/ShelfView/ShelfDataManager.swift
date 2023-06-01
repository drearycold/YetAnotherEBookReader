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
        
        var cancellables: Set<AnyCancellable> = []
        
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
    
    let discoverShelfSubject = PassthroughSubject<[String: ShelfModelSection], Never>()
    
    var cancellables: Set<AnyCancellable> = []
    
    let dispatchQueue = DispatchQueue(label: "shelf-queue")
    
    var realmOnQueue: Realm!
    
    init(service: CalibreServerService, searchManager: CalibreLibrarySearchManager) {
        self.service = service
        self.searchManager = searchManager
        
        dispatchQueue.sync {
            realmOnQueue = try! Realm(configuration: self.service.modelData.realm.configuration, queue: dispatchQueue)
            
            realmOnQueue.objects(CalibreBookRealm.self)
                .changesetPublisher(keyPaths: ["inShelf"])
                .subscribe(on: dispatchQueue)
                .sink { changes in
                    switch changes {
                    case .initial(let results):
                        results.where({
                            $0.inShelf == true
                        })
                        .forEach(self.addToShelf(book:))
                        break
                    case .update(let results, deletions: _, insertions: _, modifications: let modifications):
                        modifications
                            .map { results[$0] }
                            .forEach {
                                if $0.inShelf {
                                    self.addToShelf(book: $0)
                                } else {
                                    self.removeFromShelf(book: $0)
                                }
                            }
                        break
                    case .error(_):
                        break
                    }
                }
                .store(in: &cancellables)
        }
        
//        service.modelData.$booksInShelf
//            .receive(on: DispatchQueue.main)
//            .sink { books in
//                books.forEach {
//                    self.addToShelf(book: $0.value)
//                }
//            }
//            .store(in: &cancellables)
        
//        service.modelData.booksInShelf.forEach {
//            self.addToShelf(book: $0.value)
//        }
        
        /*
        Timer.publish(every: 600, on: .main, in: .default)
            .autoconnect()
            .receive(on: self.searchManager.cacheRealmQueue)
            .sink { timer in
                self.searchManager.refreshSearchResults()
            }
            .store(in: &cancellables)
         */
    }
    
    /**
     run on dispatchQueue
     */
    func addToShelf(book: CalibreBookRealm) {
        guard let inShelfId = book.primaryKey
        else {
            return
        }
        
        for categoryName in [book.authorFirst, book.authorSecond, book.authorThird] {
            guard let categoryName = categoryName
            else {
                return
            }
            
            let category = CategoryObject(type: .Author, category: categoryName)
            if let index = categories.firstIndex(of: category) {
                categories[index].inShelfBookIds.insert(inShelfId)
                return
            }
            
            category.inShelfBookIds.insert(inShelfId)
            
            guard let unifiedSearchObjectId = searchManager.getUnifiedResultObjectIdForSwiftUI(
                libraryIds: [],
                searchCriteria: .init(
                    searchString: "",
                    sortCriteria: .init(),
                    filterCriteriaCategory: ["Authors" : Set([categoryName])]
                )
            )
            else {
                return
            }
            
            guard let unifiedSearchObject = self.realmOnQueue.object(ofType: CalibreUnifiedSearchObject.self, forPrimaryKey: unifiedSearchObjectId)
            else {
                return
            }
            
            category.unifiedSearchObject = unifiedSearchObject
            
            unifiedSearchObject.books.changesetPublisher
                .subscribe(on: self.dispatchQueue)
                .map { changeset -> ShelfModelSection in
                    switch changeset {
                    case .initial(_), .error(_):
                        print("unifiedSearchObject changeset \(category.type.rawValue) \(category.category) initial \(unifiedSearchObject.books.count)")
                        break
                    case .update(_, deletions: let deletions, insertions: let insertions, modifications: let modifications):
                        print("unifiedSearchObject changeset \(category.type.rawValue) \(category.category) update \(unifiedSearchObject.books.count)")
                        break
                    }
                    
                    return self.buildShelfModelSection(category: category)
                }
                .receive(on: DispatchQueue.main)
                .sink { discoverShelfSection in
                    if discoverShelfSection.sectionShelf.count > 1 {
                        self.discoverShelf[discoverShelfSection.sectionId] = discoverShelfSection
                        self.discoverShelfSubject.send(self.discoverShelf)
                    }
                }
                .store(in: &category.cancellables)
                
            categories.insert(category)
            
            let discoverShelfSection = self.buildShelfModelSection(category: category)
            DispatchQueue.main.async {
                if discoverShelfSection.sectionShelf.count > 1 {
                    self.discoverShelf[discoverShelfSection.sectionId] = discoverShelfSection
                    self.discoverShelfSubject.send(self.discoverShelf)
                }
            }
        }
    }
    
    func removeFromShelf(book: CalibreBookRealm) {
        guard let inShelfId = book.primaryKey
        else {
            return
        }
        
        for categoryName in [book.authorFirst, book.authorSecond, book.authorThird] {
            guard let categoryName = categoryName
            else {
                return
            }
            
            guard let index = categories.firstIndex(of: CategoryObject(type: .Author, category: categoryName))
            else {
                return
            }
            
            let category = categories[index]
            category.inShelfBookIds.remove(inShelfId)
            
            guard category.inShelfBookIds.isEmpty
            else {
                return
            }
            
            category.cancellables.removeAll()
            category.unifiedSearchObject = nil
            
            let discoverShelfSection = self.buildShelfModelSection(category: category)
            DispatchQueue.main.async {
                self.discoverShelf.removeValue(forKey: discoverShelfSection.sectionId)
                self.discoverShelfSubject.send(self.discoverShelf)
            }
            
            categories.remove(at: index)
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
    
    func refresh() {
        dispatchQueue.async {
            self.categories.compactMap {
                $0.unifiedSearchObject
            }.forEach(
                self.searchManager.refreshUnifiedSearchResult(mergedObj:)
            )
        }
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
}

extension ModelData {
    static func parseShelfSectionId(sectionId: String) -> String? {
        guard let sepRange = sectionId.range(of: " || ")
        else { return nil }
        let libraryId = String(sectionId[sectionId.startIndex..<sepRange.lowerBound])
        return libraryId
    }
}
