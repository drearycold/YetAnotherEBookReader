//
//  CalibreBrowser.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/11/5.
//

import Foundation
import RealmSwift
import Combine
import OSLog

struct LibrarySearchSort: Hashable, CustomStringConvertible {
    var by = SortCriteria.Modified
    var ascending = false
    
    var description: String {
        "\(ascending ? "First" : "Last") \(by)"
    }
}

enum SortCriteria: String, CaseIterable, Identifiable, CustomStringConvertible, PersistableEnum {
    var id: String { self.rawValue }
    
    case Title
    case Added
    case Publication
    case Modified
    case SeriesIndex
    
    var sortKeyPath: String {
        switch(self) {
        case .Title:
            return "title"
        case .Added:
            return "timestamp"
        case .Publication:
            return "pubDate"
        case .Modified:
            return "lastModified"
        case .SeriesIndex:
            return "seriesIndex"
        }
    }
    
    var sortQueryParam: String {
        switch(self) {
        case .Title:
            return "sort"
        case .Added:
            return "timestamp"
        case .Publication:
            return "pubdate"
        case .Modified:
            return "last_modified"
        case .SeriesIndex:
            return "series_index"
        }
    }
    
    var description: String {
        switch (self) {
        case .SeriesIndex:
            return "Series Index"
        default:
            return self.rawValue
        }
    }
}

struct SearchCriteria: Hashable, CustomStringConvertible {
    let searchString: String
    let sortCriteria: LibrarySearchSort
    let filterCriteriaCategory: [String: Set<String>]
    let pageSize: Int = 100
    
    var hasEmptyFilter: Bool {
        filterCriteriaCategory.isEmpty
    }
    
    var description: String {
        "\(searchString)^\(sortCriteria)^\(filterCriteriaCategory)"
    }
}

struct SearchCriteriaMergedKey: Hashable {
    let libraryIds: Set<String>
    let criteria: SearchCriteria
}

struct LibrarySearchCriteriaResultMerged {
    struct MergedPageOffset {
        var offsets: [Int]
        var beenCutOff: Bool
        var cutOffOffset : Int
        
        mutating func setOffset(index: Int, offset: Int) {
            if index < offsets.endIndex {
                offsets[index] = offset
            } else {
                offsets.append(offset)
            }
        }
    }
    /***
     key: libraryId
     value:
        index: pageNo - 0-based
        element: offset in bookIds
     */
    var mergedPageOffsets: [String: MergedPageOffset]
    
//    @available(*, deprecated, message: "replaced by mergedBooks")
//    var books = [CalibreBook]()
    
    var mergedBooks = [CalibreBook]()
    
    var totalNumber = 0
    var merging = false
    
    init(libraryIds: Set<String>) {
        mergedPageOffsets = libraryIds.reduce(into: [:], { partialResult, libraryId in
            partialResult[libraryId] = .init(offsets: [0], beenCutOff: false, cutOffOffset: 0)
        })
    }
    
    func booksForPage(page: Int, pageSize: Int) -> ArraySlice<CalibreBook> {
        if mergedBooks.count >= (page+1)*pageSize {
            return mergedBooks[page*pageSize..<(page+1)*pageSize]
        } else if mergedBooks.count > (page)*pageSize {
            return mergedBooks.suffix(mergedBooks.count - page * pageSize)
        } else {
            return mergedBooks.suffix(0)
        }
    }
}

struct LibrarySearchKey: Hashable, CustomStringConvertible {
    let libraryId: String
    let criteria: SearchCriteria
    
    var description: String {
        "\(libraryId) || \(criteria)"
    }
}

struct LibrarySearchResult: CustomStringConvertible {
    let library: CalibreLibrary
    var loading = false
    var offlineResult = false
    var error = false
    var totalNumber = 0

    var bookIds = [Int32]()
    
    var description: String {
        "\(bookIds.count)/\(totalNumber)"
    }
}

class CalibreLibrarySearchManager: ObservableObject {
    enum CacheType: Comparable, CaseIterable {
        case online
        case onlineCache
        case offline
    }
    struct CacheKey: Hashable {
        let searchKey: LibrarySearchKey
        let type: CacheType
    }
    
    private let service: CalibreServerService
    
    private var cache = [CacheKey: LibrarySearchResult]()
    
    private var cacheSearchLibraryObjects = [LibrarySearchKey: CalibreLibrarySearchObject]()
    private var cacheSearchUnifiedObjects = [SearchCriteriaMergedKey: CalibreUnifiedSearchObject]()
    
    private var cacheCategoryLibraryObjects: [CalibreLibraryCategoryKey: CalibreLibraryCategoryObject] = [:]
    private var cacheCategoryUnifiedObjects: [String: CalibreUnifiedCategoryObject] = [:]
    
    private var cacheRealm: Realm!
    var cacheRealmConf: Realm.Configuration!
    let cacheRealmQueue = DispatchQueue(label: "search-cache-realm-queue", qos: .userInitiated)
    private let cacheWorkerQueue = DispatchQueue(label: "search-cache-worker-queue", qos: .utility, attributes: [.concurrent])
    
    private let searchRefreshSubject = PassthroughSubject<LibrarySearchKey, Never>()
    private let searchRequestSubject = PassthroughSubject<CalibreLibrarySearchTask, Never>()
    private let metadataRequestSubject = PassthroughSubject<CalibreBooksMetadataRequest, Never>()
    
    private let searchMergerRequestSubject = PassthroughSubject<SearchCriteriaMergedKey, Never>()
    
    private let categoryRequestSubject = PassthroughSubject<LibraryCategoryList, Never>()
    private let categoryMergerRequestSubject = PassthroughSubject<String, Never>()  //category name
    
    private var cancellables = Set<AnyCancellable>()
    
    private let logger = Logger()
    
    init(service: CalibreServerService) {
        self.service = service
        self.cacheRealmConf = service.modelData.realmConf
        
        /*
        var cacheRealmConf = Realm.Configuration()
        cacheRealmConf.schemaVersion = UInt64(service.modelData.yabrBuild) ?? 1
        cacheRealmConf.fileURL = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("cache.realm")
        
        
        let fileURL = cacheRealmConf.fileURL?.path ?? "!!!"
        logger.info("cache realm: \(fileURL)")
        
        cacheRealmConf.objectTypes = [
            CalibreBookRealm.self,
            CalibreLibrarySearchFilterValues.self,
            CalibreLibrarySearchObject.self,
            CalibreUnifiedOffsets.self,
            CalibreUnifiedSearchObject.self
        ]
        
        self.cacheRealmConf = cacheRealmConf
        */
        
        cacheRealmQueue.sync {
            initCacheStore()
            
            registerSearchRefreshReceiver()
            registerSearchRequestReceiver()
            registerMetadataRequestReceiver()
            
            regsiterUnifiedMergerRequestReceiver()
            
            registerCategoryRefreshReceiver()
            registerCategoryMergeReceiver()
        }
    }
    
    func initCacheStore() {
        print("\(#function) file=\(cacheRealmConf.fileURL?.absoluteString ?? "x")")
        
        cacheRealm = try! Realm(configuration: cacheRealmConf, queue: cacheRealmQueue)
        
        cacheRealm.objects(CalibreLibrarySearchObject.self).forEach { cacheObj in
            let librarySearchKey = LibrarySearchKey(
                libraryId: cacheObj.libraryId,
                criteria: .init(
                    searchString: cacheObj.search,
                    sortCriteria: .init(by: cacheObj.sortBy, ascending: cacheObj.sortAsc),
                    filterCriteriaCategory: cacheObj.filters.reduce(into: [:], { partialResult, filter in
                        if let values = filter.value?.values {
                            partialResult[filter.key] = Set(values)
                        }
                    })
                )
            )
            guard cacheObj.books.count <= cacheObj.bookIds.count,
                  cacheSearchLibraryObjects[librarySearchKey] == nil
            else {
                try! cacheRealm.write {
                    cacheRealm.delete(cacheObj)
                }
                return
            }
            
            if cacheObj.bookIds.count > cacheObj.books.count {
                try! cacheRealm.write {
                    cacheObj.bookIds.removeLast(cacheObj.bookIds.count - cacheObj.books.count)
                }
            }
            
            cacheSearchLibraryObjects[librarySearchKey] = cacheObj
            
            registerCacheSearchChangeReceiver(librarySearchKey: librarySearchKey, cacheObj: cacheObj)
        }
        
        cacheRealm.objects(CalibreUnifiedSearchObject.self).forEach { cacheObj in
            let mergedKey = SearchCriteriaMergedKey(
                libraryIds: Set(cacheObj.libraryIds),
                criteria: .init(
                    searchString: cacheObj.search,
                    sortCriteria: .init(by: cacheObj.sortBy, ascending: cacheObj.sortAsc),
                    filterCriteriaCategory: cacheObj.filters.reduce(into: [:], { partialResult, filter in
                        if let values = filter.value?.values {
                            partialResult[filter.key] = Set(values)
                        }
                    })
                )
            )
            
            for index in cacheObj.books.startIndex..<cacheObj.books.endIndex {
                let book = cacheObj.books[index]
                cacheObj.idMap[book.primaryKey!] = index
                print("\(#function) mergedKey=\(mergedKey) primaryKey=\(book.primaryKey!) title=\(book.title) index=\(index)")
            }
            
            if cacheObj.idMap.count != cacheObj.books.count {
                try! cacheRealm.write {
                    cacheObj.resetList()
                }
            }
            
            assert(cacheSearchUnifiedObjects[mergedKey] == nil)
            
            cacheSearchUnifiedObjects[mergedKey] = cacheObj
            
            registerCacheUnifiedChangeReceiver(unifiedKey: mergedKey, cacheObj: cacheObj)
        }
        
        cacheRealm.objects(CalibreLibraryCategoryObject.self).forEach { cacheObj in
            let categoryKey = CalibreLibraryCategoryKey(libraryId: cacheObj.libraryId, categoryName: cacheObj.categoryName)
            
            cacheCategoryLibraryObjects[categoryKey] = cacheObj
            
            registerCacheCategoryLibraryChangeReceiver(cacheObj: cacheObj)
        }
        
        cacheRealm.objects(CalibreUnifiedCategoryObject.self).forEach { cacheObj in
            cacheCategoryUnifiedObjects[cacheObj.categoryName] = cacheObj
            
            registerCacheCategoryUnifiedChangeReceiver(cacheObj: cacheObj)
        }
    }
    
    func initCacheSearchObject(searchKey: LibrarySearchKey) -> CalibreLibrarySearchObject {
        let cacheObj = CalibreLibrarySearchObject()
        cacheObj.libraryId = searchKey.libraryId
        cacheObj.search = searchKey.criteria.searchString
        cacheObj.sortBy = searchKey.criteria.sortCriteria.by
        cacheObj.sortAsc = searchKey.criteria.sortCriteria.ascending
        searchKey.criteria.filterCriteriaCategory
            .sorted(by: { $0.key < $1.key })
            .forEach { category, items in
                guard items.isEmpty == false else { return }
                
                let filterValues = CalibreLibrarySearchFilterValues()
                filterValues.values.insert(objectsIn: items)
                
                cacheObj.filters[category] = filterValues
            }
        
        try? cacheRealm?.write {
            cacheRealm?.add(cacheObj)
        }
        
        cacheSearchLibraryObjects[searchKey] = cacheObj
        
        registerCacheSearchChangeReceiver(librarySearchKey: searchKey, cacheObj: cacheObj)
        
        return cacheObj
    }
    
    private func initCacheUnifiedObject(key: SearchCriteriaMergedKey, requestMerge: Bool = false) -> CalibreUnifiedSearchObject {
        let cacheObj = CalibreUnifiedSearchObject()
        cacheObj.search = key.criteria.searchString
        cacheObj.sortBy = key.criteria.sortCriteria.by
        cacheObj.sortAsc = key.criteria.sortCriteria.ascending
        cacheObj.filters = key.criteria.filterCriteriaCategory.reduce(into: Map<String, CalibreLibrarySearchFilterValues?>()) { partialResult, entry in
            let values = CalibreLibrarySearchFilterValues()
            values.values.insert(objectsIn: entry.value)
            partialResult[entry.key] = values
        }
        cacheObj.libraryIds.insert(objectsIn: key.libraryIds)
        
        try? cacheRealm.write {
            cacheRealm.add(cacheObj)
        }
        
        cacheSearchUnifiedObjects[key] = cacheObj
        
        registerCacheUnifiedChangeReceiver(unifiedKey: key, cacheObj: cacheObj)
        
        if requestMerge {
            searchMergerRequestSubject.send(key)
        }
        
        return cacheObj
    }
    
    private func initCacheLibraryCategoryObject(categoryKey: CalibreLibraryCategoryKey) -> CalibreLibraryCategoryObject {
        let cacheObj = CalibreLibraryCategoryObject()
        cacheObj.libraryId = categoryKey.libraryId
        cacheObj.categoryName = categoryKey.categoryName
        
        try! cacheRealm.write {
            cacheRealm.add(cacheObj)
        }
        
        cacheCategoryLibraryObjects[categoryKey] = cacheObj
        
        registerCacheCategoryLibraryChangeReceiver(cacheObj: cacheObj)
        
        return cacheObj
    }
    
    private func initCacheUnifiedCategoryObject(categoryName: String) -> CalibreUnifiedCategoryObject {
        let cacheObj = CalibreUnifiedCategoryObject()
        cacheObj.categoryName = categoryName
        
        try! cacheRealm.write {
            cacheRealm.add(cacheObj)
        }
        
        cacheCategoryUnifiedObjects[categoryName] = cacheObj
        
        registerCacheCategoryUnifiedChangeReceiver(cacheObj: cacheObj)
        
        return cacheObj
    }
    
    func registerCacheSearchChangeReceiver(librarySearchKey: LibrarySearchKey, cacheObj: CalibreLibrarySearchObject) {
        cacheObj.bookIds.changesetPublisher
            .subscribe(on: cacheRealmQueue)
            .sink { changes in
                switch changes {
                case .initial(_):
                    break
                case .update(_, deletions: let deletions, insertions: let insertions, modifications: let modifications):
                    self.logger.info("cacheRealm \(cacheObj._id) \(librarySearchKey) bookIds changeset deletion \(deletions.map { $0.description }.joined(separator: ","))")
                    self.logger.info("cacheRealm \(cacheObj._id) \(librarySearchKey) bookIds changeset insertions \(insertions.map { $0.description }.joined(separator: ","))")
                    self.logger.info("cacheRealm \(cacheObj._id) \(librarySearchKey) bookIds changeset modifications \(modifications.map { $0.description }.joined(separator: ","))")
                    
                    //trigger book metadata fetcher
                    guard let library = self.service.modelData.calibreLibraries[librarySearchKey.libraryId]
                    else {
                        return
                    }
                    
                    let serverUUID = library.server.uuid.uuidString
                    
                    var books = [CalibreBookRealm]()
                    var toFetchIDs = [Int32]()
                    
                    if insertions.isEmpty == false {
                        insertions.forEach { idx in
                            let bookId = cacheObj.bookIds[idx]
                            if let obj = self.cacheRealm.object(
                                ofType: CalibreBookRealm.self,
                                forPrimaryKey: CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: library.name, id: bookId.description)
                            ) {
                                books.append(obj)
                            } else {
                                toFetchIDs.append(bookId)
                            }
                        }
                        
                        if toFetchIDs.isEmpty {
                            self.cacheRealm.writeAsync {
                                cacheObj.books.append(objectsIn: books)
                                assert(cacheObj.books.count <= cacheObj.bookIds.count)
                            }
                        } else {
                            self.metadataRequestSubject.send(
                                .init(
                                    library: library,
                                    books: toFetchIDs,
                                    getAnnotations: false
                                )
                            )
                        }
                    }
                    break
                case .error(_):
                    break
                }
            }
            .store(in: &cancellables)
        
        cacheObj.books.changesetPublisher
            .subscribe(on: cacheRealmQueue)
            .sink { changes in
                switch changes {
                case .initial(_), .error(_):
                    break
                case .update(_, deletions: let deletions, insertions: let insertions, modifications: let modifications):
                    self.logger.info("cacheRealm \(cacheObj._id) \(librarySearchKey) books changeset insertions \(insertions.map { $0.description }.joined(separator: ","))")
                    self.logger.info("cacheRealm \(cacheObj._id) \(librarySearchKey) books changeset deletions \(deletions.map { $0.description }.joined(separator: ","))")
                    self.logger.info("cacheRealm \(cacheObj._id) \(librarySearchKey) books changeset modifications \(modifications.map { $0.description }.joined(separator: ","))")
                    
                    //trigger unified result merger
                    self.cacheSearchUnifiedObjects.forEach { mergedKey, mergedObj in
                        guard mergedKey.libraryIds.isEmpty || mergedKey.libraryIds.contains(cacheObj.libraryId)
                        else {
                            return
                        }
                        
                        guard mergedKey.criteria.searchString == cacheObj.search,
                              mergedKey.criteria.sortCriteria.by == cacheObj.sortBy,
                              mergedKey.criteria.sortCriteria.ascending == cacheObj.sortAsc
                        else {
                            return
                        }
                        
                        guard mergedKey.criteria.filterCriteriaCategory == cacheObj.filters.reduce(into: [:], { partialResult, filter in
                            guard let filterValue = filter.value?.values,
                                  filterValue.isEmpty == false
                            else {
                                return
                            }
                            
                            partialResult[filter.key] = Set(filterValue)
                        })
                        else {
                            return
                        }

                        self.searchMergerRequestSubject.send(mergedKey)
                    }
                    
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    func registerCacheUnifiedChangeReceiver(unifiedKey: SearchCriteriaMergedKey, cacheObj: CalibreUnifiedSearchObject) {
        cacheObj.objectNotificationToken = cacheObj.observe(keyPaths: ["limitNumber"], { change in
            switch change {
            case .change(let object, let properties):
                for property in properties {
//                    print("Property '\(property.name)' of object \(object) changed to '\(property.newValue!)' from '\(property.oldValue ?? -1)'")
                    if property.name == "limitNumber",
                       let newValue = property.newValue as? Int,
                       let oldValue = property.oldValue as? Int {
                        print("Property '\(property.name)' changed to '\(newValue)' from '\(oldValue)'")
                        if newValue < oldValue {
                            try! self.cacheRealm.writeAsync {
                                cacheObj.books.removeAll()
                                cacheObj.unifiedOffsets.forEach {
                                    $0.value?.beenCutOff = false
                                    $0.value?.beenConsumed = false
                                    $0.value?.offset = 0
//                                    $0.value?.cutOffOffset = 0
//                                    $0.value?.offsets.removeAll()
                                }
                            }
                        }
                        
                        self.searchMergerRequestSubject.send(unifiedKey)
                    }
                }
            case .deleted, .error(_):
                break
            }
        })
    }
    
    func registerCacheCategoryLibraryChangeReceiver(cacheObj: CalibreLibraryCategoryObject) {
        cacheObj.items.changesetPublisher
            .subscribe(on: cacheRealmQueue)
            .collect(.byTime(cacheRealmQueue, .seconds(2)))
            .sink { changesList in
                var count = 0
                changesList.forEach { changes in
                    switch changes {
                    case .initial(_), .error(_):
                        break
                    case .update(_, deletions: let deletions, insertions: let insertions, modifications: let modifications):
                        print("\(#function) \(cacheObj.libraryId) \(cacheObj.categoryName) deletion count=\(deletions.count)")
                        print("\(#function) \(cacheObj.libraryId) \(cacheObj.categoryName) insertions count=\(insertions.count)")
                        
                        count += deletions.count + insertions.count
                        break
                    }
                }
                
                if count > 0 {
                    self.categoryMergerRequestSubject.send(cacheObj.categoryName)
                }
            }
            .store(in: &cancellables)
    }
    
    func registerCacheCategoryUnifiedChangeReceiver(cacheObj: CalibreUnifiedCategoryObject) {
        cacheObj.items.changesetPublisher
            .subscribe(on: cacheRealmQueue)
            .sink { changes in
                switch changes {
                case .initial(_), .error(_):
                    break
                case .update(_, deletions: let deletions, insertions: let insertions, modifications: let modifications):
                    print("\(#function) \(cacheObj.categoryName) deletion count=\(deletions.count)")
                    print("\(#function) \(cacheObj.categoryName) insertions count=\(insertions.count)")
                    break
                }
                            }
            .store(in: &cancellables)
    }
    
    func registerSearchRefreshReceiver() {
        searchRefreshSubject.receive(on: cacheRealmQueue)
            .map { [self] searchKey -> (LibrarySearchKey, CalibreLibrarySearchObject) in
                if let cacheObj = cacheSearchLibraryObjects[searchKey] {
                    return (searchKey, cacheObj)
                } else {
                    return (searchKey, initCacheSearchObject(searchKey: searchKey))
                }
            }
            .sink { [self] searchKey, cacheObj in
                guard let library = service.modelData.calibreLibraries[cacheObj.libraryId],
                      let searchTask = service.buildLibrarySearchTaskNew(
                        library: library,
                        searchCriteria: searchKey.criteria,
                        generation: library.lastModified,
                        num: 100,
                        offset: 0
                      ),
                      searchTask.booksListUrl.isHTTP
                else {
                    return
                }
                
                try! cacheRealm.write {
                    cacheObj.bookIds.removeAll()
                    cacheObj.books.removeAll()
                    cacheObj.loading = false
                    cacheObj.generation = searchTask.generation
                }
                
                searchRequestSubject.send(searchTask)
            }
            .store(in: &cancellables)
    }
    
    func registerSearchRequestReceiver() {
        searchRequestSubject.receive(on: cacheRealmQueue)
            .map { task -> CalibreLibrarySearchTask in
                self.cacheSearchLibraryObjects[.init(libraryId: task.library.id, criteria: task.searchCriteria)]?.loading = true
                
                self.service.modelData.filteredBookListRefreshingSubject.send("")
                
                return task
            }
            .receive(on: cacheWorkerQueue)
            .flatMap { task -> AnyPublisher<CalibreLibrarySearchTask, Never> in
                var errorTask = task
                errorTask.ajaxSearchError = true
                
                if task.num > 0 {
                    return self.service.searchLibraryBooks(task: task)
                        .replaceError(with: errorTask)
                        .eraseToAnyPublisher()
                } else {
                    return Just(errorTask).setFailureType(to: Never.self).eraseToAnyPublisher()
                }
            }
            .receive(on: cacheRealmQueue)
            .sink { task in
                guard let cacheObj = self.cacheSearchLibraryObjects[.init(libraryId: task.library.id, criteria: task.searchCriteria)]
                else { return }
                
                guard let ajaxSearchResult = task.ajaxSearchResult
                else {
                    cacheObj.error = true
                    return
                }
                
                try? self.cacheRealm?.write {
                    cacheObj.error = false
                    
                    if task.generation == cacheObj.generation {
                        cacheObj.totalNumber = ajaxSearchResult.total_num
                        
                        if cacheObj.bookIds.count == task.offset {
                            cacheObj.bookIds.append(objectsIn: ajaxSearchResult.book_ids)
                        } else {
//                            fatalError("shouldn't reach here")
//                            ignore
                        }
                    } else if task.generation > cacheObj.generation {
                        if task.offset == 0 {
                            cacheObj.totalNumber = ajaxSearchResult.total_num
                            cacheObj.bookIds.append(objectsIn: ajaxSearchResult.book_ids)
                        } else {
                            fatalError("shouldn't reach here")
                        }
                    } else {
                        //task.generation < cacheObj.generation
                        //discard result
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func registerMetadataRequestReceiver() {
        metadataRequestSubject.receive(on: cacheWorkerQueue)
            .flatMap { request -> AnyPublisher<CalibreBooksTask, Never> in
                if let task = self.service.buildBooksMetadataTask(library: request.library, books: request.books.map({ bookId in
                    CalibreBook(id: bookId, library: request.library)
                }), getAnnotations: request.getAnnotations) {
                    return self.service
                        .getBooksMetadata(task: task)
                        .replaceError(with: task)
                        .eraseToAnyPublisher()
                } else {
                    return Just(CalibreBooksTask(request: request))
                        .setFailureType(to: Never.self)
                        .eraseToAnyPublisher()
                }
            }
            .receive(on: cacheRealmQueue)
            .map { task -> CalibreBooksTask in
                guard let cacheRealm = self.cacheRealm,
                      let entries = task.booksMetadataEntry,
                      let json = task.booksMetadataJSON else {
                    return task
                }
                
                let serverUUID = task.library.server.uuid.uuidString
                let libraryName = task.library.name
                
                try? cacheRealm.write {
                    task.books.forEach {
                        let bookIdStr = $0.description
                        
                        let obj = self.getOrCreateBookMetadat(serverUUID: serverUUID, libraryName: libraryName, id: $0, idStr: bookIdStr)
                        
                        if let entryOptional = entries[bookIdStr],
                           let entry = entryOptional,
                           let root = json[bookIdStr] as? NSDictionary {
                            self.service.handleLibraryBookOne(library: task.library, bookRealm: obj, entry: entry, root: root)
                        } else {
                            obj.title = ""
                            obj.lastSynced = obj.lastModified
                        }
                    }
                    
                }
                
                return task
            }
            .receive(on: cacheWorkerQueue)
            .flatMap { task -> AnyPublisher<CalibreBooksTask, Never> in
                if task.request.getAnnotations {
                    return self.service
                        .getAnnotations(task: task)
                        .replaceError(with: task)
                        .eraseToAnyPublisher()
                } else {
                    return Just(task).setFailureType(to: Never.self).eraseToAnyPublisher()
                }
            }
            .receive(on: cacheRealmQueue)
            .sink { task in
                let serverUUID = task.library.server.uuid.uuidString
                
                self.cacheSearchLibraryObjects.forEach { searchKey, cacheObj in
                    guard searchKey.libraryId == task.library.id,
                          cacheObj.bookIds.count > cacheObj.books.count
                    else {
                        return
                    }
                    
                    try? self.cacheRealm.write({
                        var idx = cacheObj.books.endIndex
                        while idx < cacheObj.bookIds.count,
                              let bookObj = self.cacheRealm.object(
                                ofType: CalibreBookRealm.self,
                                forPrimaryKey: CalibreBookRealm.PrimaryKey(
                                    serverUUID: serverUUID,
                                    libraryName: task.library.name,
                                    id: cacheObj.bookIds[idx].description
                                )
                              ) {
                            cacheObj.books.append(bookObj)
                            idx += 1
                        }
                        assert(cacheObj.books.count <= cacheObj.bookIds.count)
                    })
                }
            }
            .store(in: &cancellables)
    }
    
    func regsiterUnifiedMergerRequestReceiver() {
        self.searchMergerRequestSubject.receive(on: cacheRealmQueue)
            .map { mergedKey -> SearchCriteriaMergedKey in
                self.cacheSearchUnifiedObjects[mergedKey]?.loading = true
                
                return mergedKey
            }
            .sink { mergedKey in
                guard let mergedObj = self.cacheSearchUnifiedObjects[mergedKey]
                else {
                    return
                }
                
                try? self.cacheRealm.write({
                    let searchResults: [String: CalibreLibrarySearchObject] = self.service.modelData.calibreLibraries.reduce(into: [:]) { partialResult, libraryEntry in
                        guard libraryEntry.value.hidden == false,
                              mergedKey.libraryIds.isEmpty || mergedKey.libraryIds.contains(libraryEntry.key)
                        else {
                            if let unifiedOffsetObjOpt = mergedObj.unifiedOffsets[libraryEntry.key] {
                                mergedObj.unifiedOffsets.removeObject(for: libraryEntry.key)
                                if let unifiedOffsetObj = unifiedOffsetObjOpt {
                                    self.cacheRealm.delete(unifiedOffsetObj)
                                }
                            }
                               
                            return
                        }
                        
                        let searchKey = LibrarySearchKey(libraryId: libraryEntry.key, criteria: mergedKey.criteria)
                        
                        if let searchObj = self.cacheSearchLibraryObjects[searchKey] {
                            partialResult[libraryEntry.key] = searchObj
                            
                            if mergedObj.unifiedOffsets[libraryEntry.key] == nil {
                                let unifiedOffsetObj = CalibreUnifiedOffsets()
                                
//                                unifiedOffsetObj.beenCutOff = true
//                                unifiedOffsetObj.cutOffOffset = 0
//                                unifiedOffsetObj.offsets.append(0)
                                
                                mergedObj.unifiedOffsets[libraryEntry.key] = unifiedOffsetObj
                            }
                        } else {
                            self.searchRefreshSubject.send(searchKey)
                        }
                    }
                    
//                    let searchResults: [String: CalibreLibrarySearchObject] = self.cacheSearchObjects.reduce(into: [:]) { partialResult, searchEntry in
//                        guard mergedKey.libraryIds.isEmpty || mergedKey.libraryIds.contains(searchEntry.key.libraryId)
//                        else {
//                            return
//                        }
//                        guard mergedKey.criteria == searchEntry.key.criteria
//                        else {
//                            return
//                        }
//                        partialResult[searchEntry.key.libraryId] = searchEntry.value
//
//                        if mergedObj.unifiedOffsets[searchEntry.key.libraryId] == nil {
//                            let unifiedOffsetObj = CalibreUnifiedOffsets()
//
//                            unifiedOffsetObj.beenCutOff = true
//                            unifiedOffsetObj.cutOffOffset = 0
//                            unifiedOffsetObj.offsets.append(0)
//
//                            mergedObj.unifiedOffsets[searchEntry.key.libraryId] = unifiedOffsetObj
//                        }
//                    }
                    
                    self.mergeBookLists(mergedObj: mergedObj, searchResults: searchResults)
                    
                    mergedObj.totalNumber = searchResults.map { $0.value.totalNumber }.reduce(0, +)
                    
                    var booksDup = Set<String>()
                    mergedObj.books.forEach {
                        guard let primaryKey = $0.primaryKey else {
                            return
                        }
                        assert(booksDup.contains(primaryKey) == false)
                        booksDup.insert(primaryKey)
                    }
                    
                    if mergedObj.books.count < mergedObj.totalNumber {
                        mergedObj.unifiedOffsets.filter {
                            $0.value?.beenCutOff == true
                        }.compactMap {
                            self.service.modelData.calibreLibraries[$0.key]
                        }.map {
                            ($0, self.cacheSearchLibraryObjects[.init(libraryId: $0.id, criteria: mergedKey.criteria)])
                        }.compactMap {
                            self.service.buildLibrarySearchTaskNew(
                                library: $0.0,
                                searchCriteria: mergedKey.criteria,
                                generation: $0.1?.generation ?? $0.0.lastModified,
                                num: 100,
                                offset: $0.1?.bookIds.count ?? 0
                            )
                        }.forEach {
                            self.searchRequestSubject.send($0)
                        }
                    }
                })
                
                print("\(#function) mergedObj.books.count=\(mergedObj.books.count)")
            }
            .store(in: &cancellables)
    }
    
    func registerCategoryRefreshReceiver() {
        categoryRequestSubject.receive(on: cacheWorkerQueue)
            .flatMap { request -> AnyPublisher<LibraryCategoryList, Never> in
                let just = Just(request).setFailureType(to: Never.self).eraseToAnyPublisher()
                guard let serverUrl = self.service.getServerUrlByReachability(server: request.library.server)
                else { return just }
                
                var urlComponents = URLComponents(string: request.category.url)
                urlComponents?.queryItems = [
                    URLQueryItem(name: "num", value: request.num.description),
                    URLQueryItem(name: "offset", value: request.items.count.description)
                ]
                guard let url = urlComponents?.url(relativeTo: serverUrl)
                else { return just }
                
                return self.service.urlSession(server: request.library.server, qos: .background).dataTaskPublisher(for: url)
                    .map {
                        $0.data
                    }
                    .decode(type: LibraryCategoryListResult.self, decoder: JSONDecoder())
                    .map { result -> LibraryCategoryList in
                        var request = request
                        request.result = result
                        return request
                    }
                    .replaceError(with: request)
                    .eraseToAnyPublisher()
            }
            .receive(on: cacheRealmQueue)
            .sink { [self] categoryList in
                let categoryKey = CalibreLibraryCategoryKey(libraryId: categoryList.library.id, categoryName: categoryList.category.name)
                
                
                // retry request
                guard let result = categoryList.result else {
                    if categoryList.retries > 0 {
                        var categoryList = categoryList
                        categoryList.retries -= 1
                        cacheWorkerQueue.asyncAfter(deadline: .now() + 60.0) {
                            self.categoryRequestSubject.send(categoryList)
                        }
                    }
                    
                    return
                }
                
                if let cacheObj = cacheCategoryLibraryObjects[categoryKey] {
                    guard result.total_num != cacheObj.items.count ||
                        categoryList.library.lastModified > cacheObj.generation
                    else {
                        print("\(#function) skipping update for \(categoryKey)")
                        return
                    }
                }
                
                
                var categoryList = categoryList
                
                try? cacheRealm.write({
                    result.items.forEach { item in
                        let itemObj = cacheRealm
                            .objects(CalibreLibraryCategoryItemObject.self)
                            .where({ $0.url == item.url })
                            .first ?? CalibreLibraryCategoryItemObject()
                        
                        if itemObj.realm == nil {
                            itemObj.name = item.name
                            itemObj.averageRating = item.average_rating
                            itemObj.count = item.count
                            itemObj.url = item.url
                            cacheRealm.add(itemObj)
                        } else {
                            if itemObj.name != item.name {
                                itemObj.name = item.name
                            }
                            if itemObj.averageRating != item.average_rating {
                                itemObj.averageRating = item.average_rating
                            }
                            if itemObj.count != item.count {
                                itemObj.count = item.count
                            }
                        }
                        
                        categoryList.items.append(itemObj)
                    }
                })
                
                if categoryList.items.count < result.total_num {
                    // request more items if total_num is not reached
                    categoryList.retries = 9
                    categoryList.num = min(result.total_num - categoryList.items.count, 10000)
                    categoryRequestSubject.send(categoryList)
                } else {
                    let cacheObj = cacheCategoryLibraryObjects[categoryKey] ?? initCacheLibraryCategoryObject(categoryKey: categoryKey)
                    
                    try? cacheRealm.write {
                        cacheObj.items.removeAll()
                        cacheObj.items.append(objectsIn: categoryList.items)
                        cacheObj.generation = categoryList.library.lastModified
                        cacheObj.totalNumber = result.total_num
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func registerCategoryMergeReceiver() {
        self.categoryMergerRequestSubject.receive(on: cacheRealmQueue)
            .sink { categoryName in
                let cacheObj = self.cacheCategoryUnifiedObjects[categoryName] ?? self.initCacheUnifiedCategoryObject(categoryName: categoryName)
                
                let nameItems = self.cacheCategoryLibraryObjects.filter {
                    $0.key.categoryName == categoryName
                }.reduce(into: [String: [CalibreLibraryCategoryItemObject]]()) { partialResult, libraryCategoryEntry in
                    
                    libraryCategoryEntry.value.items.forEach { categoryItem in
                        if partialResult[categoryItem.name] == nil {
                            partialResult[categoryItem.name] = [categoryItem]
                        } else {
                            partialResult[categoryItem.name]?.append(categoryItem)
                        }
                    }
                }
                
                var totalNumber = 0
                try? self.cacheRealm.write {
                    let items = nameItems
                        .sorted(by: { $0.key < $1.key})
                        .reduce(into: [CalibreUnifiedCategoryItemObject]()) { partialResult, nameItemEntry in
                            let unifiedItemObj = self.getOrCreateUnifiedCategoryItem(categoryName: categoryName, name: nameItemEntry.key)
                            
                            unifiedItemObj.items.removeAll()
                            unifiedItemObj.items.insert(objectsIn: nameItemEntry.value)
                            
                            let stats = unifiedItemObj.items.reduce((0, 0.0)) { partialResult, itemObj in
                                (partialResult.0 + itemObj.count, partialResult.1 + itemObj.averageRating * Double(itemObj.count))
                            }
                            unifiedItemObj.count = stats.0
                            unifiedItemObj.averageRating = stats.1 / Double(stats.0)
                            
                            partialResult.append(unifiedItemObj)
                            
                            totalNumber += stats.0
                        }
                    
                    cacheObj.items.removeAll()
                    cacheObj.items.append(objectsIn: items)
                    
                    cacheObj.totalNumber = totalNumber
                }
            }
            .store(in: &cancellables)
    }
    
    func getOrCreateBookMetadat(serverUUID: String, libraryName: String, id: Int32, idStr: String) -> CalibreBookRealm {
        if let existing = cacheRealm?.object(
            ofType: CalibreBookRealm.self,
            forPrimaryKey: CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName, id: idStr)
        ) {
            return existing
        } else {
            let obj = CalibreBookRealm()
            
            obj.serverUUID = serverUUID
            obj.libraryName = libraryName
            obj.idInLib = id
            
            cacheRealm?.add(obj)
            
            return obj
        }
    }
    
    func getOrCreateUnifiedCategoryItem(categoryName: String, name: String) -> CalibreUnifiedCategoryItemObject {
        if let obj = cacheRealm.objects(CalibreUnifiedCategoryItemObject.self).where({
            $0.categoryName == categoryName && $0.name == name
        }).first {
            return obj
        } else {
            let obj = CalibreUnifiedCategoryItemObject()
            
            obj.categoryName = categoryName
            obj.name = name
            
            cacheRealm.add(obj)
            
            return obj
        }
    }
    
    func getMergedBookIndex(mergedKey: SearchCriteriaMergedKey, primaryKey: String) -> Int? {
        self.cacheSearchUnifiedObjects[mergedKey]?.getIndex(primaryKey: primaryKey)
    }
    
    func expandSearchUnifiedBookLimit(mergedKey: SearchCriteriaMergedKey) {
        guard let cacheObj = self.cacheSearchUnifiedObjects[mergedKey]
        else {
            return
        }
        self.cacheRealmQueue.async {
            try! self.cacheRealm.write {
                
            }
        }
    }
    
    /**
     nil value for type means any available
     */
    func getCache(for library: CalibreLibrary, of criteria: SearchCriteria, by type: CacheType? = nil) -> LibrarySearchResult {
        let searchKey = LibrarySearchKey(libraryId: library.id, criteria: criteria)
        
        if cacheSearchLibraryObjects[searchKey] == nil,
           type == .online {
            self.searchRefreshSubject.send(searchKey)
        }
        
        if let type = type {
            let cacheKey = CacheKey(searchKey: searchKey, type: type)
	            if let result = cache[cacheKey] {
                return result
            } else {
                return .init(library: library, offlineResult: type == .offline, error: true)
            }
        } else {
            for type in CacheType.allCases {
                if let result = cache[.init(searchKey: searchKey, type: type)] {
                    return result
                }
            }
            return .init(library: library, offlineResult: type == .offline, error: true)
        }
    }
    
    /**
     first non-empty result for each library by preference ( online > onlineCache > offline )
     */
    func getCaches(for libraryIds: Set<String>, of criteria: SearchCriteria, by type: CacheType? = nil) -> [LibrarySearchKey: LibrarySearchResult] {
        self.cache.filter {
            (
                libraryIds.isEmpty
                ||
                libraryIds.contains($0.key.searchKey.libraryId)
            )
            &&
            $0.key.searchKey.criteria == criteria
            &&
            (
                (type == nil && $0.value.bookIds.count > 0)
                ||
                (type == $0.key.type)
            )
        }.sorted { lhs, rhs in
            lhs.key.type < rhs.key.type
        }.reduce(into: [:]) { partialResult, cacheEntry in
            if partialResult[cacheEntry.key.searchKey] == nil {
                partialResult[cacheEntry.key.searchKey] = cacheEntry.value
            }
        }
    }
    
    func resetCache(for library: CalibreLibrary, of criteria: SearchCriteria, by type: CacheType) {
        let cacheKey = CacheKey(searchKey: .init(libraryId: library.id, criteria: criteria), type: type)
        if var cacheVal = cache[cacheKey] {
            cacheVal.loading = false
            cacheVal.error = true
            cacheVal.bookIds.removeAll(keepingCapacity: true)
            cache[cacheKey] = cacheVal
        } else {
            cache[cacheKey] = .init(library: library, offlineResult: type == .offline, error: true)
        }
    }
    
    func startLoading(for library: CalibreLibrary, of criteria: SearchCriteria, by type: CacheType) {
        let cacheKey = CacheKey(searchKey: .init(libraryId: library.id, criteria: criteria), type: type)
        if cache[cacheKey] == nil {
            cache[cacheKey] = .init(library: library, offlineResult: type == .offline, error: true)
        }
        cache[cacheKey]?.loading = true
    }
    
    func finishLoading(for library: CalibreLibrary, of criteria: SearchCriteria, by type: CacheType) {
        let cacheKey = CacheKey(searchKey: .init(libraryId: library.id, criteria: criteria), type: type)
        cache[cacheKey]?.loading = false
    }
    
    func setIsError(for library: CalibreLibrary, of criteria: SearchCriteria, by type: CacheType, to error: Bool) {
        let cacheKey = CacheKey(searchKey: .init(libraryId: library.id, criteria: criteria), type: type)
        if cache[cacheKey] == nil {
            cache[cacheKey] = .init(library: library, offlineResult: type == .offline, error: error)
        } else {
            cache[cacheKey]?.error = error
        }
    }
    
    func setTotalNumber(for library: CalibreLibrary, of criteria: SearchCriteria, by type: CacheType, to totalNumber: Int) {
        let cacheKey = CacheKey(searchKey: .init(libraryId: library.id, criteria: criteria), type: type)
        cache[cacheKey]?.totalNumber = totalNumber
    }
    
    func appendResult(for library: CalibreLibrary, of criteria: SearchCriteria, by type: CacheType, contentsOf bookIds: [Int32]) {
        let cacheKey = CacheKey(searchKey: .init(libraryId: library.id, criteria: criteria), type: type)
        cache[cacheKey]?.bookIds.append(contentsOf: bookIds)
        cache[cacheKey]?.error = false
    }
    
    func refreshSearchResults() {
        cacheSearchLibraryObjects.keys.forEach {
            self.searchRefreshSubject.send($0)
        }
    }
    
    func refreshSearchResult(libraryIds: Set<String>, searchCriteria: SearchCriteria) {
        cacheSearchLibraryObjects.keys
            .filter({ key in
                key.criteria == searchCriteria
            })
            .filter({ key in
                libraryIds.isEmpty || libraryIds.contains(key.libraryId)
            })
            .forEach({ key in
                self.searchRefreshSubject.send(key)
            })
    }
    
    /**
     merged search results
     */
    
    func getUnifiedResult(libraryIds: Set<String>, searchCriteria: SearchCriteria) -> CalibreUnifiedSearchObject {
        let key = SearchCriteriaMergedKey(libraryIds: libraryIds, criteria: searchCriteria)
        let cacheObj = cacheSearchUnifiedObjects[key] ?? initCacheUnifiedObject(key: key, requestMerge: false)
        
        searchMergerRequestSubject.send(key)
        
        return cacheObj
    }
    
    func getLibraryResultObjectIdForSwiftUI(libraryId: String, searchCriteria: SearchCriteria) -> ObjectId? {
        let key = LibrarySearchKey(libraryId: libraryId, criteria: searchCriteria)
        
        var objectId: ObjectId?
        cacheRealmQueue.sync {
//            let cacheObj =
            
            objectId = (cacheSearchLibraryObjects[key] ?? initCacheSearchObject(searchKey: key))._id
        }
        
        return objectId
    }
    
    func getUnifiedResultObjectIdForSwiftUI(libraryIds: Set<String>, searchCriteria: SearchCriteria) -> ObjectId? {
        let key = SearchCriteriaMergedKey(libraryIds: libraryIds, criteria: searchCriteria)
        
        var objectId: ObjectId?
        cacheRealmQueue.sync {
//            let cacheObj =
            
            objectId = (cacheSearchUnifiedObjects[key] ?? initCacheUnifiedObject(key: key, requestMerge: true))._id
        }
        
        return objectId
    }
    
    private func mergeBookLists(mergedObj: CalibreUnifiedSearchObject, searchResults: [String: CalibreLibrarySearchObject]) {
        
        guard mergedObj.limitNumber > mergedObj.books.count
        else {
            return
        }
        
        // sort in reverse so we can use popLast() (O(1)) to merge
        let sortComparator = MergeSortComparator(criteria: mergedObj.sortBy, order: mergedObj.sortAsc ? .reverse : .forward)
        
        var heads = searchResults.compactMap { libraryId, searchObj -> CalibreBookRealm? in
            guard let unifiedOffsetOpt = mergedObj.unifiedOffsets[libraryId],
                  let unifiedOffset = unifiedOffsetOpt
            else {
                fatalError("Shouldn't missing unifiedOffset")
            }
            
            unifiedOffset.beenConsumed = unifiedOffset.offset >= searchObj.totalNumber
            if unifiedOffset.beenConsumed {
                return nil
            }
            
            unifiedOffset.beenCutOff = unifiedOffset.offset >= searchObj.books.endIndex
            if unifiedOffset.beenCutOff {
                return nil
            }
            
            return searchObj.books[unifiedOffset.offset]
        }.sorted(using: sortComparator)
        
        guard mergedObj.unifiedOffsets.allSatisfy({
            $0.value?.beenConsumed == true || $0.value?.beenCutOff == false
        }) else {
            //should trigger library search
            return
        }
        
        print("LIBRARYINFOVIEW heads=\(heads.count)")
        
        while mergedObj.books.count < mergedObj.limitNumber,
              let head = heads.popLast() {
            mergedObj.idMap[head.primaryKey!] = mergedObj.books.endIndex
            mergedObj.books.append(head)
            
            let headLibraryId = CalibreLibraryRealm.PrimaryKey(serverUUID: head.serverUUID!, libraryName: head.libraryName!)
            guard let searchResult = searchResults[headLibraryId],
                  let unifiedOffsetOpt = mergedObj.unifiedOffsets[headLibraryId],
                  let unifiedOffset = unifiedOffsetOpt
            else {
                fatalError("Shouldn't reach here")
            }
            
            unifiedOffset.offset += 1
            
            guard unifiedOffset.offset < searchResult.books.count else {
                if searchResult.books.count < searchResult.totalNumber {
                    unifiedOffset.beenCutOff = true
                    break
                } else {
                    unifiedOffset.beenConsumed = true
                    continue
                }
            }
            
            let next = searchResult.books[unifiedOffset.offset]
            heads.append(next)
            heads.sort(using: sortComparator)
        }
        
        print("\(#function) merged from \(searchResults.count) libraries")
    }
    
    @available(*, deprecated, message: "drop paging")
    private func mergeBookListsOld(mergedObj: CalibreUnifiedSearchObject, searchResults: [String: CalibreLibrarySearchObject], page: Int = 0, limit: Int = 100) {
        
        var startPage = page
        while startPage > 0, searchResults.allSatisfy({ libraryId, searchObj in
            guard let unifiedOffsetOptional = mergedObj.unifiedOffsets[libraryId],
                  let unifiedOffset = unifiedOffsetOptional
            else { return false }
            
            return unifiedOffset.offsets.endIndex > startPage
            &&
            (unifiedOffset.offsets.last ?? 0) > searchObj.totalNumber
        }) == false {
            startPage -= 1
        }
        
        var headIndex = [String: Int]()
        searchResults.forEach { libraryId, searchObj in
            guard let unifiedOffsetOptional = mergedObj.unifiedOffsets[libraryId],
                  let unifiedOffset = unifiedOffsetOptional
            else { return }
            
            if unifiedOffset.offsets.isEmpty {
                unifiedOffset.offsets.append(0)
            }
            
            guard startPage < unifiedOffset.offsets.endIndex,
                  (unifiedOffset.offsets.last ?? 0) < searchObj.totalNumber
            else {  //beyond search's totalNumber
                return
            }
            
            let startPageOffset = unifiedOffset.offsets[startPage]
            headIndex[libraryId] = startPageOffset
            
            unifiedOffset.beenCutOff = startPageOffset >= searchObj.books.endIndex && startPageOffset < searchObj.totalNumber + 1
            unifiedOffset.cutOffOffset = searchObj.books.endIndex
        }
        
        headIndex.forEach {
            print("LIBRARYINFOVIEW headIndex \($0)")
        }
        
        var heads = searchResults.compactMap { libraryId, searchObj -> CalibreBookRealm? in
            guard let headOffset = headIndex[libraryId],
                  headOffset < searchObj.books.count
            else { return nil}
            
            return searchObj.books[headOffset]
        }
        
        print("LIBRARYINFOVIEW heads=\(heads.count) headIndex=\(headIndex.count)")
        
        // sort in reverse so we can use popLast() (O(1)) to merge
        let sortComparator = MergeSortComparator(criteria: mergedObj.sortBy, order: mergedObj.sortAsc ? .reverse : .forward)
        heads.sort(using: sortComparator)
        
        let mergeLength = (page + 1) * limit
        if mergedObj.books.count > startPage * limit {
            mergedObj.books.removeLast(mergedObj.books.count - startPage * limit)
        }
        while mergedObj.books.count < mergeLength,
              heads.count == headIndex.count,
              let head = heads.popLast() {
            mergedObj.books.append(head)
            
            let headLibraryId = CalibreLibraryRealm.PrimaryKey(serverUUID: head.serverUUID!, libraryName: head.libraryName!)
            guard let searchResult = searchResults[headLibraryId] else { continue }
            
            headIndex[headLibraryId]? += 1
            
            if mergedObj.books.count % limit == 0 {
                let currentPage = mergedObj.books.count / limit
                headIndex.forEach {
                    mergedObj.unifiedOffsets[$0.key]??.setOffset(index: currentPage, offset: $0.value)
                }
            }
            
            guard let headOffset = headIndex[headLibraryId],
                  headOffset < searchResult.books.count else {
                if searchResult.books.count < searchResult.totalNumber {
                    mergedObj.unifiedOffsets[headLibraryId]??.beenCutOff = true
                    mergedObj.unifiedOffsets[headLibraryId]??.cutOffOffset = searchResult.books.count
                }
                continue
            }
            
            let next = searchResult.books[headOffset]
            heads.append(next)
            heads.sort(using: sortComparator)
        }
        
        print("\(#function) merged from \(searchResults.count) libraries")
    }
    
    func refreshLibraryCategory(library: CalibreLibrary, category: CalibreLibraryCategory) {
        self.categoryRequestSubject.send(.init(library: library, category: category, reqId: 0, offset: 0, num: 0))
    }
}

struct LibraryCategoryList {
    let library: CalibreLibrary
    let category: CalibreLibraryCategory
    let reqId: Int
    var offset: Int
    var num: Int
    var retries: Int = 9
    var items: [CalibreLibraryCategoryItemObject] = []
    
    var result: LibraryCategoryListResult?
}

struct LibraryCategoryListResult: Codable {
    struct Item: Codable {
        let name: String
        let average_rating: Double
        let count: Int
        let url: String
        let has_children: Bool
    }
    let category_name: String
    let base_url: String
    let total_num: Int
    let offset: Int
    let num: Int
    let sort: String
    let sort_order: String
    //"subcategories": [],  unknown
    let items: [Item]
}

extension ModelData {
    func getBook(for primaryKey: String) -> CalibreBook? {
        var bookLocal: CalibreBook? = nil
        var bookSearch: CalibreBook? = nil
        if let obj = getBookRealm(forPrimaryKey: primaryKey) {
            bookLocal = convert(bookRealm: obj)
        }
        
        if let obj = searchLibraryResultsRealmMainThread?.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey) {
            bookSearch = convert(bookRealm: obj)
        }
        
        if bookSearch == nil {
            return bookLocal
        }
        if bookLocal == nil {
            return bookSearch
        }
        
        if bookLocal?.lastModified == bookSearch?.lastModified,
           bookLocal?.lastModified == bookLocal?.lastSynced {
            return bookLocal
        }
        
        return bookSearch
    }
    
    var currentLibrarySearchCriteria: SearchCriteria {
        SearchCriteria(
            searchString: self.searchString,
            sortCriteria: self.sortCriteria,
            filterCriteriaCategory: self.filterCriteriaCategory
        )
    }
    
    var currentLibrarySearchResultKey: SearchCriteriaMergedKey {
        .init(
            libraryIds: filterCriteriaLibraries.isEmpty ? self.calibreLibraries.reduce(into: Set<String>(), { partialResult, entry in
                if entry.value.hidden == false,
                   entry.value.server.removed == false {
                    partialResult.insert(entry.key)
                }
            }) : filterCriteriaLibraries,
            criteria: .init(
                searchString: self.searchString,
                sortCriteria: self.sortCriteria,
                filterCriteriaCategory: self.filterCriteriaCategory
            )
        )
    }
    
    var currentLibrarySearchResultMerged: LibrarySearchCriteriaResultMerged? {
        self.searchCriteriaMergedResults[self.currentLibrarySearchResultKey]
    }
    
    var currentSearchLibraryResults: [LibrarySearchKey: LibrarySearchResult] {
        librarySearchManager.getCaches(
            for: self.filterCriteriaLibraries,
            of: self.currentLibrarySearchCriteria
        )
    }
    
    var currentSearchLibraryResultsCannotFurther: Bool {
        guard let currentLibrarySearchResultMerged = currentLibrarySearchResultMerged
        else { return true }
        
        guard let maxPage = self.currentSearchLibraryResults
            .compactMap({ result -> Int? in
                let resultIsError = result.value.error || result.value.loading
                if let libraryMergedPageOffset = currentLibrarySearchResultMerged.mergedPageOffsets[result.key.libraryId] {
                    if resultIsError {
                        return libraryMergedPageOffset.offsets.lastIndex { $0 < result.value.bookIds.count }
                    } else {
                        return libraryMergedPageOffset.offsets.endIndex
                    }
                } else {
                    return 1
                }
            }).max()
        else { return true }
        
        return self.filteredBookListPageNumber + 1 == maxPage
    }
    
    func mergeBookLists(mergeKey: SearchCriteriaMergedKey, mergedResult: LibrarySearchCriteriaResultMerged, page: Int = 0, limit: Int = 100) -> LibrarySearchCriteriaResultMerged {
        guard let realm = try? Realm(configuration: realmConf),
              let realmSearch = searchLibraryResultsRealmQueue
        else { return mergedResult }
        
        let searchResults: [String: LibrarySearchResult] = self.librarySearchManager.getCaches(
            for: mergeKey.libraryIds,
            of: mergeKey.criteria
        ).reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key.libraryId] = entry.value
        }
        
        var startPage = page
        while startPage > 0, mergeKey.libraryIds.allSatisfy({ libraryId in
            guard let mergedPageOffset = mergedResult.mergedPageOffsets[libraryId]
            else { return false }
            
            return mergedPageOffset.offsets.endIndex > startPage
            &&
            (mergedPageOffset.offsets.last ?? 0) > (searchResults[libraryId]?.totalNumber ?? -1)
        }) == false {
            startPage -= 1
        }
        
        var mergedResult = mergedResult
        
        var headIndex = [String: Int]()
        mergeKey.libraryIds.forEach { libraryId in
            guard let mergedPageOffset = mergedResult.mergedPageOffsets[libraryId]
            else { return }
            
            let startPageOffset = mergedPageOffset.offsets[startPage]
            headIndex[libraryId] = startPageOffset
            
            if let searchResult = searchResults[libraryId] {
                mergedResult.mergedPageOffsets[libraryId]?.beenCutOff = startPageOffset >= searchResult.bookIds.endIndex
                mergedResult.mergedPageOffsets[libraryId]?.cutOffOffset = searchResult.bookIds.endIndex
            } else {
                mergedResult.mergedPageOffsets[libraryId]?.beenCutOff = true
                mergedResult.mergedPageOffsets[libraryId]?.cutOffOffset = 0
            }
        }
        
        headIndex.forEach {
            print("LIBRARYINFOVIEW headIndex \($0)")
        }
        
        var heads = mergeKey.libraryIds.compactMap { libraryId -> CalibreBookRealm? in
            guard let headOffset = headIndex[libraryId],
                  let searchResult = searchResults[libraryId],
                  headOffset < searchResult.bookIds.count
            else { return nil}
            
            let primaryKey = CalibreBookRealm.PrimaryKey(
                serverUUID: searchResult.library.server.uuid.uuidString,
                libraryName: searchResult.library.name,
                id: searchResult.bookIds[headOffset].description
            )
            
            let obj = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
            ?? realmSearch.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
            
            print("LIBRARYINFOVIEW headObj=\(String(describing: obj)) primaryKey=\(primaryKey)")
            
            return obj
        }
        
        print("LIBRARYINFOVIEW heads=\(heads.count)")
        
        // sort in reverse so we can use popLast() (O(1)) to merge
        let sortComparator = MergeSortComparator(criteria: mergeKey.criteria.sortCriteria.by, order: mergeKey.criteria.sortCriteria.ascending ? .reverse : .forward)
        heads.sort(using: sortComparator)
        
        let mergeLength = (page + 1) * limit
        if mergedResult.mergedBooks.count > startPage * limit {
            mergedResult.mergedBooks.removeLast(mergedResult.mergedBooks.count - startPage * limit)
        }
        while mergedResult.mergedBooks.count < mergeLength, let head = heads.popLast() {
            if let book = self.convert(bookRealm: head) {
                mergedResult.mergedBooks.append(book)
            }
            
            let headLibraryId = CalibreLibraryRealm.PrimaryKey(serverUUID: head.serverUUID!, libraryName: head.libraryName!)
            guard let searchResult = searchResults[headLibraryId] else { continue }
            
            headIndex[headLibraryId]? += 1
            
            if mergedResult.mergedBooks.count % limit == 0 {
                let currentPage = mergedResult.mergedBooks.count / limit
                headIndex.forEach {
                    mergedResult.mergedPageOffsets[$0.key]?.setOffset(index: currentPage, offset: $0.value)
                }
            }
            
            guard let headOffset = headIndex[headLibraryId],
                  headOffset < searchResult.bookIds.count else {
                if searchResult.bookIds.count < searchResult.totalNumber {
                    mergedResult.mergedPageOffsets[headLibraryId]?.beenCutOff = true
                    mergedResult.mergedPageOffsets[headLibraryId]?.cutOffOffset = searchResult.bookIds.count
                }
                continue
            }
            
            let primaryKey = CalibreBookRealm.PrimaryKey(
                serverUUID: searchResult.library.server.uuid.uuidString,
                libraryName: searchResult.library.name,
                id: searchResult.bookIds[headOffset].description
            )
            
            guard let next = realmSearch.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey) ?? realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
            else {
                continue
            }
            
            heads.append(next)
            heads.sort(using: sortComparator)
        }
        
        print("\(#function) merged from \(searchResults.count) libraries")
        
        return mergedResult
    }
}

struct MergeSortComparator: SortComparator {
    let criteria: SortCriteria
    var order: SortOrder
    
    func compare(
        _ lhs: CalibreBookRealm,
        _ rhs: CalibreBookRealm
    ) -> ComparisonResult {
        switch order {
        case .forward:
            switch criteria {
            case .Title:
                return lhs.title.compare(rhs.title)
            case .Added:
                return lhs.timestamp.compare(rhs.timestamp)
            case .Publication:
                return lhs.pubDate.compare(rhs.pubDate)
            case .Modified:
                return lhs.lastModified.compare(rhs.lastModified)
            case .SeriesIndex:
                if lhs.seriesIndex < rhs.seriesIndex {
                    return .orderedAscending
                } else if lhs.seriesIndex > rhs.seriesIndex {
                    return .orderedDescending
                } else {
                    return .orderedSame
                }
            }
        case .reverse:
            switch criteria {
            case .Title:
                return rhs.title.compare(lhs.title)
            case .Added:
                return rhs.timestamp.compare(lhs.timestamp)
            case .Publication:
                return rhs.pubDate.compare(lhs.pubDate)
            case .Modified:
                return rhs.lastModified.compare(lhs.lastModified)
            case .SeriesIndex:
                if rhs.seriesIndex < lhs.seriesIndex {
                    return .orderedAscending
                } else if rhs.seriesIndex > lhs.seriesIndex {
                    return .orderedDescending
                } else {
                    return .orderedSame
                }
            }
        }
    }
}


extension CalibreServerService {
    func buildLibrarySearchTask(library: CalibreLibrary, searchCriteria: SearchCriteria, generation: Date = .now, skipPrev: Bool = false) -> CalibreLibrarySearchTask? {
        guard let serverUrl =
                modelData.librarySyncStatus[library.id]?.isError == true
                ?
                URL(fileURLWithPath: "/realm")
                :
                (
                    getServerUrlByReachability(server: library.server)
                    ??
                    (
                        (library.autoUpdate || library.server.isLocal)
                        ?
                        URL(fileURLWithPath: "/realm")
                        :
                        nil
                    )
                )
        else { return nil }
        
        let searchPrevResult = skipPrev ? .init(library: library) : modelData.librarySearchManager.getCache(
            for: library,
            of: searchCriteria,
            by: serverUrl.isFileURL ? .offline : .online
        )
        
        guard searchPrevResult.loading == false
        else { return nil }
        
        var booksListUrlComponents = URLComponents()
        booksListUrlComponents.path = "ajax/search/\(library.key)"
        
        var booksListUrlQueryItems = [URLQueryItem]()
        
        booksListUrlQueryItems.append(URLQueryItem(name: "sort", value: searchCriteria.sortCriteria.by.sortQueryParam))
        booksListUrlQueryItems.append(URLQueryItem(name: "sort_order", value: searchCriteria.sortCriteria.ascending ? "asc" : "desc"))
        
        let maxMergedOffset = modelData.searchCriteriaMergedResults.compactMap {
            $0.value.mergedPageOffsets[library.id]?.offsets.last
        }.max() ?? 0
        
        let searchedOffset = searchPrevResult.bookIds.count
        let searchNum = maxMergedOffset + searchCriteria.pageSize - searchedOffset
        guard searchNum >= 0 else {
            return nil
        }
        
        booksListUrlQueryItems.append(.init(name: "offset", value: searchedOffset.description))
        booksListUrlQueryItems.append(.init(name: "num", value: searchNum.description))
        
        var queryStrings = [String]()
        if searchCriteria.searchString.isEmpty == false {
            queryStrings.append(searchCriteria.searchString)
        }
        searchCriteria.filterCriteriaCategory.forEach { entry in
            var queryKey = entry.key.lowercased()
            var queryIsRating = entry.key == "Rating"
            
            if let customColumnInfo = library.customColumnInfos.filter({ $0.value.name == entry.key }).first {
                queryKey = "#\(customColumnInfo.key)"
                queryIsRating = customColumnInfo.value.datatype == "rating"
            }
            
            let q = entry.value.map {
                "\(queryKey):" + (queryIsRating ? "\($0.count)" : "\"=\($0)\"")
            }.joined(separator: " OR ")
            if q.isEmpty == false {
                queryStrings.append("( " + q + " )")
            }
        }
        
        booksListUrlQueryItems.append(.init(name: "query", value: queryStrings.joined(separator: " AND ")))
        
        booksListUrlComponents.queryItems = booksListUrlQueryItems
        
        guard let booksListUrl = booksListUrlComponents.url(relativeTo: serverUrl)?.absoluteURL else {
            return nil
        }
        
        return CalibreLibrarySearchTask(
            generation: generation,
            library: library,
            searchCriteria: searchCriteria,
            booksListUrl: booksListUrl,
            offset: searchedOffset,
            num: searchNum
        )
    }
    
    func buildLibrarySearchTaskNew(library: CalibreLibrary, searchCriteria: SearchCriteria, generation: Date, num: Int, offset: Int) -> CalibreLibrarySearchTask? {
        guard let serverUrl =
                modelData.librarySyncStatus[library.id]?.isError == true
                ?
                URL(fileURLWithPath: "/realm")
                :
                (
                    getServerUrlByReachability(server: library.server)
                    ??
                    (
                        (library.autoUpdate || library.server.isLocal)
                        ?
                        URL(fileURLWithPath: "/realm")
                        :
                        nil
                    )
                )
        else { return nil }
        
        var booksListUrlComponents = URLComponents()
        booksListUrlComponents.path = "ajax/search/\(library.key)"
        
        var booksListUrlQueryItems = [URLQueryItem]()
        
        booksListUrlQueryItems.append(URLQueryItem(name: "sort", value: searchCriteria.sortCriteria.by.sortQueryParam))
        booksListUrlQueryItems.append(URLQueryItem(name: "sort_order", value: searchCriteria.sortCriteria.ascending ? "asc" : "desc"))
        
        booksListUrlQueryItems.append(.init(name: "offset", value: offset.description))
        booksListUrlQueryItems.append(.init(name: "num", value: num.description))
        
        var queryStrings = [String]()
        if searchCriteria.searchString.isEmpty == false {
            queryStrings.append(searchCriteria.searchString)
        }
        searchCriteria.filterCriteriaCategory.forEach { entry in
            var queryKey = entry.key.lowercased()
            var queryIsRating = entry.key == "Rating"
            
            if let customColumnInfo = library.customColumnInfos.filter({ $0.value.name == entry.key }).first {
                queryKey = "#\(customColumnInfo.key)"
                queryIsRating = customColumnInfo.value.datatype == "rating"
            }
            
            let q = entry.value.map {
                "\(queryKey):" + (queryIsRating ? "\($0.count)" : "\"=\($0)\"")
            }.joined(separator: " OR ")
            if q.isEmpty == false {
                queryStrings.append("( " + q + " )")
            }
        }
        
        booksListUrlQueryItems.append(.init(name: "query", value: queryStrings.joined(separator: " AND ")))
        
        booksListUrlComponents.queryItems = booksListUrlQueryItems
        
        guard let booksListUrl = booksListUrlComponents.url(relativeTo: serverUrl)?.absoluteURL else {
            return nil
        }
        
        return CalibreLibrarySearchTask(
            generation: generation,
            library: library,
            searchCriteria: searchCriteria,
            booksListUrl: booksListUrl,
            offset: offset,
            num: num
        )
    }
    
    func searchLibraryBooks(task: CalibreLibrarySearchTask) -> AnyPublisher<CalibreLibrarySearchTask, URLError> {
        if task.booksListUrl.isHTTP {
            return urlSession(server: task.library.server).dataTaskPublisher(for: task.booksListUrl)
                .map { result -> CalibreLibrarySearchTask in
                    var task = task
                    do {
                        task.ajaxSearchResult = try JSONDecoder().decode(CalibreLibraryBooksResult.SearchResult.self, from: result.data)
                    } catch {
                        task.ajaxSearchError = true
                    }
                    return task
                }
                .eraseToAnyPublisher()
        }
        if task.booksListUrl.isFileURL,
           let urlComponents = URLComponents(url: task.booksListUrl, resolvingAgainstBaseURL: false) {    //search offline realm
            var task = task
            
            let libraryPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "serverUUID = %@", task.library.server.uuid.uuidString),
                    NSPredicate(format: "libraryName = %@", task.library.name)
                ])
            
            var predicates = [NSPredicate]()
            let searchTerms = task.searchCriteria.searchString
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

            predicates = task.searchCriteria.filterCriteriaCategory.reduce(into: predicates) { partialResult, categoryFilter in
                guard categoryFilter.value.isEmpty == false else { return }
                
                switch categoryFilter.key {
                case "Tags":
                    partialResult.append(
                        NSCompoundPredicate(
                            orPredicateWithSubpredicates:
                                categoryFilter.value.map ({
                                    NSCompoundPredicate(orPredicateWithSubpredicates: [
                                        NSPredicate(format: "tagFirst = %@", $0),
                                        NSPredicate(format: "tagSecond = %@", $0),
                                        NSPredicate(format: "tagThird = %@", $0)
                                    ])
                                    
                                })
                        )
                    )
                case "Authors":
                    partialResult.append(
                        NSCompoundPredicate(
                            orPredicateWithSubpredicates:
                                categoryFilter.value.map ({
                                    NSCompoundPredicate(orPredicateWithSubpredicates: [
                                        NSPredicate(format: "authorFirst = %@", $0),
                                        NSPredicate(format: "authorSecond = %@", $0),
                                        NSPredicate(format: "authorThird = %@", $0)
                                    ])
                                    
                                })
                        )
                    )
                case "Series":
                    partialResult.append(
                        NSCompoundPredicate(
                            orPredicateWithSubpredicates:
                                categoryFilter.value.map ({
                                    NSPredicate(format: "series = %@", $0)
                                })
                        )
                    )
                case "Publisher":
                    partialResult.append(
                        NSCompoundPredicate(
                            orPredicateWithSubpredicates:
                                categoryFilter.value.map ({
                                    NSPredicate(format: "publisher = %@", $0)
                                })
                        )
                    )
                case "Rating":
                    partialResult.append(
                        NSCompoundPredicate(
                            orPredicateWithSubpredicates:
                                categoryFilter.value.map ({
                                    NSPredicate(format: "rating = %@", NSNumber(value: $0.count * 2))
                                })
                        )
                    )
                case "Languages":   //not recorded in realm
                    partialResult.append(NSPredicate(value: false))
                default:    //unrecognized
                    partialResult.append(NSPredicate(value: false))
                }
            }
            
            if let realm = try? Realm(configuration: modelData.realmConf) {
                let allbooks = realm.objects(CalibreBookRealm.self)
                    .filter(libraryPredicate)
                    .sorted(byKeyPath: task.searchCriteria.sortCriteria.by.sortKeyPath, ascending: task.searchCriteria.sortCriteria.ascending)
                let filteredBooks = allbooks.filter(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))
                
                let offset = Int(urlComponents.queryItems?.first(where: { $0.name == "offset" })?.value ?? "0") ?? 0
                let num = Int(urlComponents.queryItems?.first(where: { $0.name == "num" })?.value ?? "100") ?? 100
                
                if offset <= filteredBooks.count {
                    let bookIds : [Int32] = filteredBooks[offset..<min(offset+num, filteredBooks.endIndex)]
                        .map {
                            $0.idInLib
                        }
                    
                    task.ajaxSearchResult = .init(total_num: filteredBooks.count, sort_order: task.searchCriteria.sortCriteria.ascending ? "asc" : "desc", num_books_without_search: allbooks.count, offset: offset, num: bookIds.count, sort: task.searchCriteria.sortCriteria.by.sortQueryParam, base_url: "", library_id: task.library.key, book_ids: bookIds, vl: "")
                    
                    return Just(task).setFailureType(to: URLError.self).eraseToAnyPublisher()
                }
            }
        }
        
        return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
    }
    
    func registerLibrarySearchHandler() {
        let queue = DispatchQueue(label: "library-search", qos: .userInitiated)
        modelData.librarySearchRequestSubject.receive(on: DispatchQueue.main)
            .map({ task -> CalibreLibrarySearchTask in
                let librarySearchKey = LibrarySearchKey(libraryId: task.library.id, criteria: task.searchCriteria)
                
                let prevResult = modelData.librarySearchManager.getCache(
                    for: task.library,
                    of: task.searchCriteria,
                    by: task.booksListUrl.isFileURL ? .offline : .online
                )
                
                print("\(#function) id=\(task.id) librarySearchKey=\(librarySearchKey) fire num=\(task.num) offset=\(task.offset) prevCount=\(prevResult.bookIds.count) prevOffline=\(prevResult.offlineResult) offline=\(task.booksListUrl.isFileURL && !task.library.server.isLocal) prevLoading=\(prevResult.loading)")
                
                if librarySearchKey.libraryId == "Calibre-Default@0FB2EFE0-6C43-4E05-A86E-815E5B21D989", librarySearchKey.criteria == .init(searchString: "", sortCriteria: .init(), filterCriteriaCategory: [:]) {
                    print()
                }
                
                modelData.librarySearchManager.startLoading(
                    for: task.library,
                    of: task.searchCriteria,
                    by: task.booksListUrl.isFileURL ? .offline : .online
                )
                
                modelData.filteredBookListRefreshingSubject.send("")
                
                print("\(#function) id=\(task.id) searchUrl=\(task.booksListUrl.absoluteString)")
                
                return task
            })
            .receive(on: queue)
            .flatMap({ task -> AnyPublisher<CalibreLibrarySearchTask, Never> in
                var errorTask = task
                errorTask.ajaxSearchError = true
                
                if task.num > 0 {
                    return modelData.calibreServerService.searchLibraryBooks(task: task)
                        .replaceError(with: errorTask)
                        .eraseToAnyPublisher()
                } else {
                    return Just(errorTask).setFailureType(to: Never.self).eraseToAnyPublisher()
                }
            })
            .receive(on: ModelData.SearchLibraryResultsRealmQueue)
            .flatMap { searchTask -> AnyPublisher<CalibreBooksTask, Never> in
                let serverUUID = searchTask.library.server.uuid.uuidString
                
                if let realm = modelData.searchLibraryResultsRealmQueue,
                      let books = searchTask.ajaxSearchResult?.book_ids
                    .filter({ realm.object(
                        ofType: CalibreBookRealm.self,
                        forPrimaryKey:
                            CalibreBookRealm.PrimaryKey(
                                serverUUID: serverUUID,
                                libraryName: searchTask.library.name,
                                id: $0.description
                            )) == nil })
                    .map({ CalibreBook(id: $0, library: searchTask.library) }),
                   books.isEmpty == false,
                   let metaTask = buildBooksMetadataTask(library: searchTask.library, books: books, searchTask: searchTask) {
                    return modelData.calibreServerService.getBooksMetadata(task: metaTask, qos: .userInitiated)
                        .replaceError(with: metaTask)
                        .eraseToAnyPublisher()
                } else {
                    let dummyURL = URL(fileURLWithPath: "/realm")
                    let metaTask = buildBooksMetadataTask(library: searchTask.library, books: [], searchTask: searchTask) ??
                    CalibreBooksTask(request: .init(library: searchTask.library, books: [], getAnnotations: false), metadataUrl: dummyURL, lastReadPositionUrl: dummyURL, annotationsUrl: dummyURL, searchTask: searchTask)
                    return Just(metaTask)
                        .setFailureType(to: Never.self)
                        .eraseToAnyPublisher()
                }
            }
            .receive(on: ModelData.SearchLibraryResultsRealmQueue)
            .map { task -> CalibreBooksTask in
                let serverUUID = task.library.server.uuid.uuidString
                
                if let booksMetadataEntry = task.booksMetadataEntry,
                   let booksMetadataJSON = task.booksMetadataJSON,
                   let searchLibraryResultsRealm = modelData.searchLibraryResultsRealmQueue {
                    let realmBooks = booksMetadataEntry.compactMap { metadataEntry -> CalibreBookRealm? in
                        guard let entry = metadataEntry.value,
                              let bookId = Int32(metadataEntry.key)
                        else { return nil }
                        
                        let obj = CalibreBookRealm()
                        obj.serverUUID = serverUUID
                        obj.libraryName = task.library.name
                        obj.idInLib = bookId
                        
                        modelData.calibreServerService.handleLibraryBookOne(library: task.library, bookRealm: obj, entry: entry, root: booksMetadataJSON)
                        
                        return obj
                    }
                    
                    try? searchLibraryResultsRealm.write{
                        searchLibraryResultsRealm.add(realmBooks, update: .modified)
                    }
                }
                
                return task
            }
            .receive(on: DispatchQueue.main)
            .sink { task in
                guard let searchTask = task.searchTask else { return }
                
                let librarySearchKey = LibrarySearchKey(libraryId: task.library.id, criteria: searchTask.searchCriteria)
                let prevResult = modelData.librarySearchManager.getCache(for: searchTask.library, of: searchTask.searchCriteria, by: searchTask.booksListUrl.isFileURL ? .offline : .online)
                
                if let searchResult = searchTask.ajaxSearchResult {
                    if searchResult.total_num > 0,
                        prevResult.totalNumber == 0 {
                        //trigger list remerge
                        modelData.librarySearchManager.setIsError(
                            for: searchTask.library,
                            of: searchTask.searchCriteria,
                            by: searchTask.booksListUrl.isFileURL ? .offline : .online,
                            to: true
                        )
                    }
                    modelData.librarySearchManager.setTotalNumber(
                        for: searchTask.library,
                        of: searchTask.searchCriteria,
                        by: searchTask.booksListUrl.isFileURL ? .offline : .online,
                        to: searchResult.total_num
                    )
                    
                    print("\(#function) id=\(searchTask.id) librarySearchKey=\(librarySearchKey) result num=\(searchResult.num) tn=\(searchResult.total_num) offset=\(searchResult.offset) prevCount=\(prevResult.bookIds.count) offline=\(searchTask.booksListUrl.isFileURL && !searchTask.library.server.isLocal)")
                    
                    guard prevResult.bookIds.count == searchResult.offset,
                          Set(prevResult.bookIds).union(Set(searchResult.book_ids)).count == prevResult.bookIds.count + searchResult.book_ids.count
                    else {
                        //duplication, reset search result
                        print("\(#function) duplicate id=\(searchTask.id) librarySearchKey=\(librarySearchKey) mismatch_or_duplicate num=\(searchResult.num) tn=\(searchResult.total_num) offset=\(searchResult.offset) prevCount=\(prevResult.bookIds.count)")
                        
                        modelData.librarySearchManager.resetCache(
                            for: searchTask.library,
                            of: searchTask.searchCriteria,
                            by: searchTask.booksListUrl.isFileURL ? .offline : .online
                        )
                        
                        if let newTask = modelData.calibreServerService.buildLibrarySearchTask(library: searchTask.library, searchCriteria: searchTask.searchCriteria) {
                            modelData.librarySearchRequestSubject.send(newTask)
                        }
                        
                        return
                    }
                        
                    modelData.librarySearchManager.appendResult(
                        for: searchTask.library,
                        of: searchTask.searchCriteria,
                        by: searchTask.booksListUrl.isFileURL ? .offline : .online,
                        contentsOf: searchResult.book_ids
                    )
                    
                    print("\(#function) finishLoading id=\(searchTask.id) library=\(task.library.key) \(searchResult.num) \(searchResult.total_num)")
                    
                    modelData.librarySearchResultSubject.send(searchTask)
                } else if searchTask.ajaxSearchError {
                    print("\(#function) ajaxSearchError id=\(searchTask.id) library=\(task.library.key)")
                    
                    modelData.librarySearchManager.setIsError(
                        for: searchTask.library,
                        of: searchTask.searchCriteria,
                        by: searchTask.booksListUrl.isFileURL ? .offline : .online,
                        to: searchTask.num > 0
                    )
                    
                    modelData.librarySearchManager.finishLoading(
                        for: searchTask.library,
                        of: searchTask.searchCriteria,
                        by: searchTask.booksListUrl.isFileURL ? .offline : .online
                    )
                }
            }.store(in: &modelData.calibreCancellables)
        
        modelData.librarySearchResultSubject.collect(.byTime(RunLoop.main, .seconds(2)))
            .sink { tasks in
                tasks.reduce(into: Set<SearchCriteriaMergedKey>()) { partialResult, task in
                    let librarySearchKey = LibrarySearchKey(libraryId: task.library.id, criteria: task.searchCriteria)
                    let searchResult = modelData.librarySearchManager.getCache(
                        for: task.library,
                        of: task.searchCriteria,
                        by: task.booksListUrl.isFileURL ? .offline : .online
                    )
                    partialResult.formUnion(
                        self.modelData.searchCriteriaMergedResults.filter {
                            guard let mergedPageOffset = $0.value.mergedPageOffsets[librarySearchKey.libraryId]
                            else { return false }
                            
                            return mergedPageOffset.beenCutOff == true
                            &&
                            mergedPageOffset.cutOffOffset < searchResult.bookIds.count
                        }.keys
                    )
                    
                    modelData.librarySearchManager.finishLoading(
                        for: task.library,
                        of: task.searchCriteria,
                        by: task.booksListUrl.isFileURL ? .offline : .online
                    )
                }.forEach {
                    //prevent animation gap in LibraryInfoView
                    modelData.searchCriteriaMergedResults[$0]?.merging = true
                    
                    modelData.filteredBookListMergeSubject.send($0)
                }
                
                modelData.filteredBookListRefreshingSubject.send("")
            }.store(in: &modelData.calibreCancellables)
    }
    
    func registerFilteredBookListMergeHandler() {
        modelData.filteredBookListMergeSubject.receive(on: DispatchQueue.main)
            .map { searchCriteriaResultKey -> SearchCriteriaMergedKey in
                if modelData.searchCriteriaMergedResults[searchCriteriaResultKey] == nil {
                    modelData.searchCriteriaMergedResults[searchCriteriaResultKey] = .init(libraryIds: searchCriteriaResultKey.libraryIds)
                    
                }
                modelData.searchCriteriaMergedResults[searchCriteriaResultKey]?.merging = true
                
                modelData.filteredBookListRefreshingSubject.send("")
                
                return searchCriteriaResultKey
            }
            .receive(on: ModelData.SearchLibraryResultsRealmQueue)
            .map { searchCriteriaMergedKey -> (SearchCriteriaMergedKey, LibrarySearchCriteriaResultMerged) in
                print("\(#function) librarySearchKey=\(searchCriteriaMergedKey)")
                
                var mergedResult = modelData.searchCriteriaMergedResults[searchCriteriaMergedKey]!
                
                let searchResults = modelData.librarySearchManager.getCaches(
                    for: searchCriteriaMergedKey.libraryIds,
                    of: searchCriteriaMergedKey.criteria
                )
                
                mergedResult.totalNumber = searchResults.values.map { $0.totalNumber }
                    .reduce(0, +)

                mergedResult = modelData.mergeBookLists(
                    mergeKey: searchCriteriaMergedKey,
                    mergedResult: mergedResult,
                    page: modelData.filteredBookListPageNumber,
                    limit: modelData.filteredBookListPageSize
                )
                
                return (searchCriteriaMergedKey, mergedResult)
            }
            .receive(on: DispatchQueue.main)
            .map { searchCriteriaMergedKey, mergedResult -> LibrarySearchCriteriaResultMerged in
                
                modelData.searchCriteriaMergedResults[searchCriteriaMergedKey] = mergedResult
                print("\(#function) library=\(searchCriteriaMergedKey) merged=\(mergedResult.mergedBooks.count)")
                
                modelData.searchCriteriaMergedResults[searchCriteriaMergedKey]?.merging = false
                
                mergedResult.mergedPageOffsets.forEach { mergedPageOffset in
                    guard let library = modelData.calibreLibraries[mergedPageOffset.key]
                    else { return }
                    
                    let searchResult = modelData.librarySearchManager.getCache(
                        for: library,
                        of: searchCriteriaMergedKey.criteria
                    )
                    
                    guard searchCriteriaMergedKey.libraryIds.isEmpty || searchCriteriaMergedKey.libraryIds.contains(mergedPageOffset.key)
                    else { return }
                        
                    if searchResult.error == false,
                       searchResult.totalNumber == searchResult.bookIds.count {
                        //reached full list
                        return
                    }
                    
                    if mergedPageOffset.value.beenCutOff
                        ||
                        (
                            (
                                (mergedPageOffset.value.offsets.last ?? 0)
                                +
                                modelData.filteredBookListPageSize
                            )
                            >=
                            searchResult.bookIds.count
                        ) {
                        if let library = modelData.calibreLibraries[mergedPageOffset.key],
                           let task = modelData.calibreServerService.buildLibrarySearchTask(library: library, searchCriteria: searchCriteriaMergedKey.criteria) {
                            modelData.librarySearchRequestSubject.send(task)
                        }
                    }
                }
                
                if searchCriteriaMergedKey == modelData.currentLibrarySearchResultKey {
                    modelData.filteredBookListPageCount = Int((Double(mergedResult.totalNumber) / Double(modelData.filteredBookListPageSize)).rounded(.up))
                }
                
                return mergedResult
            }
            .sink(receiveValue: { librarySearchMergeResult in
                modelData.filteredBookListRefreshingSubject.send("")
            })
            .store(in: &modelData.calibreCancellables)
    }
    
    
    func registerLibrarySearchResetHandler() {
        modelData.librarySearchResetSubject.subscribe(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                
            }, receiveValue: { librarySearchKey in
                if librarySearchKey.libraryId.isEmpty {
                    let keysToRemove = modelData.searchCriteriaMergedResults.filter {
                        $0.key.criteria == librarySearchKey.criteria
                    }.map { $0.key }
                    keysToRemove.forEach {
                        modelData.searchCriteriaMergedResults.removeValue(forKey: $0)
                    }
                } else {
                    if let library = modelData.calibreLibraries[librarySearchKey.libraryId] {
                        modelData.librarySearchManager.resetCache(for: library, of: librarySearchKey.criteria, by: .online)
                    }
                }
            })
            .store(in: &modelData.calibreCancellables)
    }
}
