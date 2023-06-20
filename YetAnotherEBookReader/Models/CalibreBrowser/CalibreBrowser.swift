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
    
    private let service: CalibreServerService
    
    private var cacheSearchLibraryObjects = [LibrarySearchKey: ObjectId]()
    private var cacheSearchUnifiedObjects = [SearchCriteriaMergedKey: ObjectId]()
    private var cacheSearchUnifiedRuntime = [SearchCriteriaMergedKey: CalibreUnifiedSearchRuntime]()
    
    private var cacheCategoryLibraryObjects: [CalibreLibraryCategoryKey: CalibreLibraryCategoryObject] = [:]
    private var cacheCategoryUnifiedObjects: [CalibreUnifiedCategoryKey: CalibreUnifiedCategoryObject] = [:]
    
    private var cacheRealm: Realm!
    var cacheRealmConf: Realm.Configuration!
    let cacheRealmQueue = DispatchQueue(label: "search-cache-realm-queue", qos: .userInitiated)
    private let cacheWorkerQueue = DispatchQueue(label: "search-cache-worker-queue", qos: .utility, attributes: [.concurrent])
    
    private let searchRefreshSubject = PassthroughSubject<LibrarySearchKey, Never>()
    private let searchRequestSubject = PassthroughSubject<CalibreLibrarySearchTask, Never>()
    private let metadataRequestSubject = PassthroughSubject<CalibreBooksMetadataRequest, Never>()
    
    private let searchMergerRequestSubject = PassthroughSubject<SearchCriteriaMergedKey, Never>()
    
    private let categoryRequestSubject = PassthroughSubject<LibraryCategoryList, Never>()
    
    //collect and fire to categoryMergerHandlerSubject
    private let categoryMergerRequestSubject = PassthroughSubject<CalibreUnifiedCategoryKey, Never>()

    private let categoryMergerHandlerSubject = PassthroughSubject<CalibreUnifiedCategoryKey, Never>()
    
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
            
            registerLibraryUpdateReceiver()
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
            
            
            cacheObj.sources.map({ ($0.key, $0.value) }).forEach { sourceKey, sourceObjOpt in
                guard let sourceObj = sourceObjOpt else {
                    try! cacheRealm.write {
                        cacheObj.sources.removeObject(for: sourceKey)
                    }
                    return
                }
                
                guard sourceObj.books.count <= sourceObj.bookIds.count
                else {
                    try! cacheRealm.write {
                        cacheObj.sources.removeObject(for: sourceKey)
                        cacheRealm.delete(sourceObj)
                    }
                    return
                }
                
                if sourceObj.bookIds.count > sourceObj.books.count {
                    try! cacheRealm.write {
                        sourceObj.bookIds.removeLast(sourceObj.bookIds.count - sourceObj.books.count)
                    }
                }
            }
            
            cacheSearchLibraryObjects[librarySearchKey] = cacheObj._id
            
            registerCacheSearchChangeReceiver(librarySearchKey: librarySearchKey, cacheObj: cacheObj)
        }
        
//        try! cacheRealm.write {
//            cacheRealm.delete(cacheRealm.objects(CalibreUnifiedSearchObject.self))
//            cacheRealm.delete(cacheRealm.objects(CalibreUnifiedOffsets.self))
//        }
        
        cacheRealm.objects(CalibreUnifiedSearchObject.self).changesetPublisher
            .receive(on: cacheRealmQueue)
            .sink { changes in
                switch changes {
                case .initial(let result):
                    result.forEach {
                        self.registerCacheUnifiedSearchObject($0)
                    }
                case .update(let result, deletions: _, insertions: let insertions, modifications: _):
                    insertions.forEach {
                        let object = result[$0]
                        
                        self.registerCacheUnifiedSearchObject(object, requestMerge: true)
                    }
                case .error(_):
                    break
                }
            }
            .store(in: &cancellables)
        
        
        
//        cacheRealm.objects(CalibreUnifiedSearchObject.self).forEach { cacheObj in
//            registerCacheUnifiedSearchObject(cacheObj)
//        }
        
        cacheRealm.objects(CalibreLibraryCategoryObject.self).forEach { cacheObj in
            let categoryKey = CalibreLibraryCategoryKey(libraryId: cacheObj.libraryId, categoryName: cacheObj.categoryName)
            
            cacheCategoryLibraryObjects[categoryKey] = cacheObj
            
            registerCacheCategoryLibraryChangeReceiver(cacheObj: cacheObj)
        }
        
        try! cacheRealm.write {
            cacheRealm.delete(
                cacheRealm.objects(CalibreUnifiedCategoryObject.self)
                    .where({ $0.categoryName == "" })
            )
        }
        
        cacheRealm.objects(CalibreUnifiedCategoryObject.self).changesetPublisher
            .receive(on: cacheRealmQueue)
            .sink { [self] changes in
                switch changes {
                case .initial(let result):
                    result.forEach { cacheObj in
                        cacheCategoryUnifiedObjects[cacheObj.key] = cacheObj
                        
                        registerCacheCategoryUnifiedChangeReceiver(cacheObj: cacheObj)
                        
                        if cacheObj.itemsCount == 0,
                           cacheObj.totalNumber < 999 {
                            refreshUnifiedCategoryResult(cacheObj.key)
                        }
                    }
                case .update(let result, deletions: let deletions, insertions: let insertions, modifications: let modifications):
                    insertions.forEach {
                        let cacheObj = result[$0]
                        
                        cacheCategoryUnifiedObjects[cacheObj.key] = cacheObj
                        
                        registerCacheCategoryUnifiedChangeReceiver(cacheObj: cacheObj)
                        
                        if cacheObj.itemsCount == 0,
                           cacheObj.totalNumber < 999 {
                            refreshUnifiedCategoryResult(cacheObj.key)
                        }
                    }
                case .error(_):
                    break
                }
            }
            .store(in: &cancellables)
        
//        cacheRealm.objects(CalibreUnifiedCategoryObject.self).forEach { cacheObj in
//            cacheCategoryUnifiedObjects[cacheObj.categoryName] = cacheObj
//
//            registerCacheCategoryUnifiedChangeReceiver(cacheObj: cacheObj)
//        }
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
        
        try! cacheRealm.write {
            cacheRealm.add(cacheObj)
        }
        
        cacheSearchLibraryObjects[searchKey] = cacheObj._id
        
        registerCacheSearchChangeReceiver(librarySearchKey: searchKey, cacheObj: cacheObj)
        
        return cacheObj
    }
    
    func initCacheSearchValueObject(librarySearchKey: LibrarySearchKey, cacheObj: CalibreLibrarySearchObject, serverUrl: String) -> CalibreLibrarySearchValueObject {
        let sourceObj = CalibreLibrarySearchValueObject()
        
        try! cacheRealm.write {
            cacheRealm.add(sourceObj)
            cacheObj.sources[serverUrl] = sourceObj
        }
        
        registerCacheSearchValueChangeReceiver(librarySearchKey: librarySearchKey, cacheObj: cacheObj, sourceObj: sourceObj)
        
        return sourceObj
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
        
        cacheSearchUnifiedObjects[key] = cacheObj._id
        cacheSearchUnifiedRuntime[key] = .init()
        
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
        cacheObj.generation = .distantPast
        
        try! cacheRealm.write {
            cacheRealm.add(cacheObj)
        }
        
        cacheCategoryLibraryObjects[categoryKey] = cacheObj
        
        registerCacheCategoryLibraryChangeReceiver(cacheObj: cacheObj)
        
        return cacheObj
    }
    
    func registerCacheSearchValueChangeReceiver(librarySearchKey: LibrarySearchKey, cacheObj: CalibreLibrarySearchObject, sourceObj: CalibreLibrarySearchValueObject) {
        sourceObj.bookIds.changesetPublisher
            .subscribe(on: cacheRealmQueue)
            .map { changes -> (library: CalibreLibrary?, insertedBookIds: [Int32]) in
                var insertedBookIds = [Int32]()
                
                switch changes {
                case .initial(_):
                    guard sourceObj.bookIds.count > sourceObj.books.count
                    else {
                        return (nil, [])
                    }
                    insertedBookIds.append(contentsOf: sourceObj.bookIds[ sourceObj.books.count...])
                case .update(_, deletions: let deletions, insertions: let insertions, modifications: let modifications):
                    self.logger.info("cacheRealm \(sourceObj._id) \(librarySearchKey) bookIds changeset deletion \(deletions.map { $0.description }.joined(separator: ","))")
                    self.logger.info("cacheRealm \(sourceObj._id) \(librarySearchKey) bookIds changeset insertions \(insertions.map { $0.description }.joined(separator: ","))")
                    self.logger.info("cacheRealm \(sourceObj._id) \(librarySearchKey) bookIds changeset modifications \(modifications.map { $0.description }.joined(separator: ","))")
                    
                    insertedBookIds.append(contentsOf: insertions.map {
                        sourceObj.bookIds[$0]
                    })
                case .error(_):
                    return (nil, [])
                }
                
                //trigger book metadata fetcher
                guard let library = self.service.modelData.calibreLibraries[librarySearchKey.libraryId]
                else {
                    return (nil, [])
                }
                
                return (library, insertedBookIds)
            }
            .receive(on: self.cacheRealmQueue)
            .sink { library, insertedBookIds in
                guard let library = library
                else {
                    return
                }
                
                let serverUUID = library.server.uuid.uuidString
                
                var books = [CalibreBookRealm]()
                var toFetchIDs = [Int32]()
                
//                insertedBookIds.forEach { bookId in
                guard sourceObj.books.count < sourceObj.bookIds.count
                else {
                    return
                }
                
                sourceObj.bookIds[sourceObj.books.count...].forEach { bookId in
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
                    try! self.cacheRealm.write {
                        sourceObj.books.append(objectsIn: books)
                        assert(sourceObj.books.count <= sourceObj.bookIds.count)
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
            .store(in: &cancellables)
        
        sourceObj.books.changesetPublisher
            .subscribe(on: cacheRealmQueue)
            .sink { changes in
                var insertedBooks: [CalibreBookRealm] = []
                switch changes {
                case .error(_):
                    break
                case .initial(_):
//                    insertedBooks.append(contentsOf: sourceObj.books)
                    break
                case .update(_, deletions: let deletions, insertions: let insertions, modifications: let modifications):
                    self.logger.info("cacheRealm \(sourceObj._id) \(librarySearchKey) books changeset insertions \(insertions.map { $0.description }.joined(separator: ","))")
                    self.logger.info("cacheRealm \(sourceObj._id) \(librarySearchKey) books changeset deletions \(deletions.map { $0.description }.joined(separator: ","))")
                    self.logger.info("cacheRealm \(sourceObj._id) \(librarySearchKey) books changeset modifications \(modifications.map { $0.description }.joined(separator: ","))")
                    
                    insertedBooks.append(contentsOf: insertions.map({
                        sourceObj.books[$0]
                    }))
                    break
                }
                
                guard self.service.modelData.calibreLibraries[librarySearchKey.libraryId] != nil
                else {
                    return
                }
                
                if insertedBooks.isEmpty == false {
                    //trigger unified result merger
                    self.cacheSearchUnifiedObjects.forEach { mergedKey, mergedObjId in
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
                }
            }
            .store(in: &cancellables)
    }
    
    func registerCacheSearchChangeReceiver(librarySearchKey: LibrarySearchKey, cacheObj: CalibreLibrarySearchObject) {
        cacheObj.sources.forEach {
            guard let sourceObj = $0.value
            else {
                return
            }
            
            registerCacheSearchValueChangeReceiver(librarySearchKey: librarySearchKey, cacheObj: cacheObj, sourceObj: sourceObj)
        }
    }
    
    fileprivate func registerCacheUnifiedSearchObject(_ cacheObj: CalibreUnifiedSearchObject, requestMerge: Bool = false) {
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
        
        assert(cacheSearchUnifiedObjects[mergedKey] == nil)
        
        cacheSearchUnifiedObjects[mergedKey] = cacheObj._id
        
        var idMap: [String: Int] = [:]
        for index in cacheObj.books.startIndex..<cacheObj.books.endIndex {
            let book = cacheObj.books[index]
            
            idMap[book.primaryKey!] = index
            //                print("\(#function) mergedKey=\(mergedKey) primaryKey=\(book.primaryKey!) title=\(book.title) index=\(index)")
        }
        
        if cacheSearchUnifiedRuntime[mergedKey] == nil {
            cacheSearchUnifiedRuntime[mergedKey] = .init()
        }
        
        if idMap.count != cacheObj.books.count {
            try! cacheRealm.write {
                cacheObj.resetList()
            }
            cacheSearchUnifiedRuntime[mergedKey]?.indexMap = [:]
        } else {
            cacheSearchUnifiedRuntime[mergedKey]?.indexMap = idMap
        }
        
        registerCacheUnifiedChangeReceiver(unifiedKey: mergedKey, cacheObj: cacheObj)
        
        guard requestMerge else { return }
        
        cacheRealmQueue.asyncAfter(deadline: .now() + 5.0) { [self] in
            if cacheObj.limitNumber == 0 {
                try! cacheRealm.write {
                    cacheObj.limitNumber = 100
                }
            }
            
            if cacheObj.unifiedOffsets.keys.isEmpty {
                searchMergerRequestSubject.send(mergedKey)
                return
            }
            
            if cacheObj.totalNumber > 0,
               cacheObj.books.isEmpty {
                searchMergerRequestSubject.send(mergedKey)
                return
            }
            
            var merged = true
            cacheObj.unifiedOffsets.forEach {
                //                print("\(#function) \($0.key) \($0.value?.description ?? "nil")")
                guard merged,
                      let library = self.service.modelData.calibreLibraries[$0.key],
                      library.hidden == false,
                      library.server.removed == false,
                      let unifiedOffset = $0.value,
                      unifiedOffset.searchObjectSource.isEmpty == false,
                      let sourceObjOpt = unifiedOffset.searchObject?.sources[unifiedOffset.searchObjectSource],
                      let sourceObj = sourceObjOpt
                else {
                    merged = false
                    return
                }
            }
            
            guard merged
            else {
                searchMergerRequestSubject.send(mergedKey)
                return
            }
        }
    }
    
    func registerCacheUnifiedChangeReceiver(unifiedKey: SearchCriteriaMergedKey, cacheObj: CalibreUnifiedSearchObject) {
        cacheSearchUnifiedRuntime[unifiedKey]!.objectNotificationToken = cacheObj.observe(keyPaths: ["limitNumber"], { change in
            switch change {
            case .change(let object, let properties):
                for property in properties {
//                    print("Property '\(property.name)' of object \(object) changed to '\(property.newValue!)' from '\(property.oldValue ?? -1)'")
                    if property.name == "limitNumber",
                       let newValue = property.newValue as? Int,
                       let oldValue = property.oldValue as? Int {
                        print("Property '\(property.name)' changed to '\(newValue)' from '\(oldValue)'")
                        if newValue < oldValue {
                            self.cacheRealm.writeAsync {
                                cacheObj.resetList()
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
                var initialCount = 0
                var updateCount = 0
                changesList.forEach { changes in
                    switch changes {
                    case .error(_):
                        break
                    case .initial(_):
                        initialCount += cacheObj.items.count
                        break
                    case .update(_, deletions: let deletions, insertions: let insertions, modifications: let modifications):
                        print("\(#function) \(cacheObj.libraryId) \(cacheObj.categoryName) deletion count=\(deletions.count)")
                        print("\(#function) \(cacheObj.libraryId) \(cacheObj.categoryName) insertions count=\(insertions.count)")
                        
                        updateCount += deletions.count + insertions.count + modifications.count
                    }
                }
                
                if updateCount > 0 {
                    self.categoryMergerHandlerSubject.send(.init(categoryName: cacheObj.categoryName, search: ""))
                }
                else if initialCount > 0 {
                    self.categoryMergerRequestSubject.send(.init(categoryName: cacheObj.categoryName, search: ""))
                }
            }
            .store(in: &cancellables)
    }
    
    func registerCacheCategoryUnifiedChangeReceiver(cacheObj: CalibreUnifiedCategoryObject) {
        cacheObj.items.changesetPublisher
            .subscribe(on: cacheRealmQueue)
            .sink { changes in
                switch changes {
                case .error(_):
                    break
                case .initial(_):
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
                if let cacheObjId = cacheSearchLibraryObjects[searchKey],
                   let cacheObj = cacheRealm.object(ofType: CalibreLibrarySearchObject.self, forPrimaryKey: cacheObjId){
                    return (searchKey, cacheObj)
                } else {
                    return (searchKey, initCacheSearchObject(searchKey: searchKey))
                }
            }
            .sink { [self] searchKey, cacheObj in
                /*
                guard let library = service.modelData.calibreLibraries[cacheObj.libraryId],
                      let searchTask = service.buildLibrarySearchTask(
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
                */
                
                guard let library = service.modelData.calibreLibraries[cacheObj.libraryId]
                else {
                    return
                }
                
                 try! cacheRealm.write {
                    cacheObj.sources.forEach {
                        guard let sourceObj = $0.value
                        else {
                            return
                        }
                        
                        sourceObj.books.removeAll()
                        sourceObj.bookIds.removeAll()
                        sourceObj.generation = Date.distantPast
                    }
                }
                
                let searchTasks = service.buildLibrarySearchTasks(library: library, searchCriteria: searchKey.criteria, parameters: [:])
                searchTasks.forEach { task in
                    searchRequestSubject.send(task)
                }
            }
            .store(in: &cancellables)
    }
    
    func registerSearchRequestReceiver() {
        searchRequestSubject.receive(on: cacheRealmQueue)
            .map { task -> CalibreLibrarySearchTask in
//                self.cacheSearchLibraryObjects[.init(libraryId: task.library.id, criteria: task.searchCriteria)]?.loading = true
                
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
                guard let cacheObjId = self.cacheSearchLibraryObjects[.init(libraryId: task.library.id, criteria: task.searchCriteria)],
                      let cacheObj = self.cacheRealm.object(ofType: CalibreLibrarySearchObject.self, forPrimaryKey: cacheObjId)
                else { return }
                
                try! self.cacheRealm.write {
                    let sourceObj = self.getOrCreateLibrarySearchValueObject(
                        librarySearchKey: .init(libraryId: task.library.id, criteria: task.searchCriteria),
                        cacheObj: cacheObj,
                        serverUrl: task.serverUrl.absoluteString.replacingOccurrences(of: ".", with: "_")
                    )
                    
                    guard task.num > 0
                    else {
                        //let's trigger metadata request
                        if sourceObj.books.count < sourceObj.bookIds.count {
                            self.metadataRequestSubject.send(
                                .init(
                                    library: task.library,
                                    books: sourceObj.bookIds[sourceObj.books.count ..< sourceObj.bookIds.count].map { $0 },
                                    getAnnotations: false
                                )
                            )
                        }
                        return
                    }
                    
                    guard let ajaxSearchResult = task.ajaxSearchResult
                    else {
                        cacheObj.error = true
                        return
                    }
                    
                    if task.generation == sourceObj.generation {
                        sourceObj.totalNumber = ajaxSearchResult.total_num
                        if sourceObj.bookIds.count == task.offset {
                            guard sourceObj.books.count <= sourceObj.bookIds.count
                            else {
                                fatalError("\(task.booksListUrl.absoluteString) \(sourceObj.description) books.count beyond bookIds.count")
                            }
                            sourceObj.bookIds.append(objectsIn: ajaxSearchResult.book_ids)
                        } else {
                            //redundant request, discard
                        }
                    } else if task.generation > sourceObj.generation {
                        if task.offset == 0 {
                            sourceObj.totalNumber = ajaxSearchResult.total_num
                            sourceObj.generation = task.generation
                            sourceObj.books.removeAll()
                            sourceObj.bookIds.removeAll()
                            sourceObj.bookIds.append(objectsIn: ajaxSearchResult.book_ids)
                        } else {
//                            fatalError("shouldn't reach here")
                            //sourceObj was cleared by refresh request
                            //dicard result
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
                    if task.books.count > 20000 {
                        print("")
                    }
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
                
                self.cacheSearchLibraryObjects.forEach { searchKey, cacheObjId in
                    guard searchKey.libraryId == task.library.id,
                          let cacheObj = self.cacheRealm.object(ofType: CalibreLibrarySearchObject.self, forPrimaryKey: cacheObjId)
                          
                    else {
                        return
                    }
                    
                    cacheObj.sources.forEach { sourceEntry in
                        
                        guard let sourceObj = sourceEntry.value,
                              sourceObj.bookIds.count > sourceObj.books.count
                        else {
                            return
                        }
                        
                        try? self.cacheRealm.write({
                            var idx = sourceObj.books.endIndex
                            while idx < sourceObj.bookIds.count,
                                  let bookObj = self.cacheRealm.object(
                                    ofType: CalibreBookRealm.self,
                                    forPrimaryKey: CalibreBookRealm.PrimaryKey(
                                        serverUUID: serverUUID,
                                        libraryName: task.library.name,
                                        id: sourceObj.bookIds[idx].description
                                    )
                                  ) {
                                sourceObj.books.append(bookObj)
                                idx += 1
                            }
                            assert(sourceObj.books.count <= sourceObj.bookIds.count)
                        })
                    }
                    
                }
            }
            .store(in: &cancellables)
    }
    
    func regsiterUnifiedMergerRequestReceiver() {
        self.searchMergerRequestSubject.receive(on: cacheRealmQueue)
//            .map { mergedKey -> SearchCriteriaMergedKey in
//                self.cacheSearchUnifiedObjects[mergedKey]?.loading = true
//                return mergedKey
//            }
            .sink { mergedKey in
                guard let mergedObjId = self.cacheSearchUnifiedObjects[mergedKey],
                      let mergedObj = self.cacheRealm.object(ofType: CalibreUnifiedSearchObject.self, forPrimaryKey: mergedObjId)
                else {
                    return
                }
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "y-MM-dd H:mm:ss.SSSS"
                
                try? self.cacheRealm.write {
                    print("\(#function) start=\(dateFormatter.string(from: .now))")
                    let searchResults: [String: CalibreLibrarySearchObject] = self.service.modelData.calibreLibraries.reduce(into: [:]) { partialResult, libraryEntry in
                        guard libraryEntry.value.hidden == false,
                              libraryEntry.value.server.removed == false,
                              mergedKey.libraryIds.isEmpty || mergedKey.libraryIds.contains(libraryEntry.key)
                        else {
                            return
                        }
                        
                        let searchKey = LibrarySearchKey(libraryId: libraryEntry.key, criteria: mergedKey.criteria)
                        
                        guard let searchObjId = self.cacheSearchLibraryObjects[searchKey],
                           let searchObj = self.cacheRealm.object(ofType: CalibreLibrarySearchObject.self, forPrimaryKey: searchObjId)
                        else {
                            self.searchRefreshSubject.send(searchKey)
                            return
                        }
                        
                        partialResult[libraryEntry.key] = searchObj
                        
                        self.getOrCreateUnifiedOffsetObject(libraryId: libraryEntry.key, mergedObj: mergedObj).searchObject = searchObj
                    }
                    
                    mergedObj.unifiedOffsets.map({ $0 }).forEach { unifiedOffsetEntry in
                        guard searchResults[unifiedOffsetEntry.key] == nil
                        else {
                            return
                        }
                        
                        if let unifiedOffsetObj = unifiedOffsetEntry.value {
                            self.cacheRealm.delete(unifiedOffsetObj)
                        }
                        mergedObj.unifiedOffsets.removeObject(for: unifiedOffsetEntry.key)
                    }
                    
                        //FIXME: reset merged list
                        mergedObj.unifiedOffsets.compactMap({ $0.value }).forEach { unifiedOffsetObj in
                            unifiedOffsetObj.offset = 0
                            unifiedOffsetObj.cutOffOffset = 0
                            unifiedOffsetObj.beenConsumed = false
                            unifiedOffsetObj.beenCutOff = false
                            unifiedOffsetObj.searchObjectSource = ""
                        }
                        mergedObj.books.removeAll()
                    
                    self.mergeBookListsNew(mergedKey: mergedKey, mergedObj: mergedObj)
                    
//                    mergedObj.totalNumber = searchResults.map { $0.value.totalNumber }.reduce(0, +)
                    
                    var booksDup = Set<String>()
                    mergedObj.books.forEach {
                        guard let primaryKey = $0.primaryKey else {
                            return
                        }
                        assert(booksDup.contains(primaryKey) == false)
                        booksDup.insert(primaryKey)
                    }
                }
                
                mergedObj.unifiedOffsets.forEach { unifiedOffsetEntry in
                    guard let unifiedOffsetObject = unifiedOffsetEntry.value,
                          unifiedOffsetObject.beenCutOff == true,
                          let library = self.service.modelData.calibreLibraries[unifiedOffsetEntry.key]
                    else { return }
                    
                    let searchKey = LibrarySearchKey(libraryId: unifiedOffsetEntry.key, criteria: mergedKey.criteria)
                    guard let searchObjId = self.cacheSearchLibraryObjects[searchKey],
                          let searchObj = self.cacheRealm.object(ofType: CalibreLibrarySearchObject.self, forPrimaryKey: searchObjId)
                    else {
                        return
                    }
                    
                    let searchTasks = self.service.buildLibrarySearchTasks(
                        library: library,
                        searchCriteria: mergedKey.criteria,
                        parameters: searchObj.sources.reduce(into: [String: (generation: Date, num: Int, offset: Int)](), { partialResult, sourceEntry in
                            guard let sourceObj = sourceEntry.value
                            else { return }

                            var num = 100
                            if unifiedOffsetObject.offset + num < sourceObj.bookIds.count {
                                num = 0
                            } else if sourceObj.totalNumber - sourceObj.bookIds.count < num {
                                num = max(0, sourceObj.totalNumber - sourceObj.bookIds.count)
                            }
                            
                            partialResult[sourceEntry.key] = (sourceObj.generation, num, sourceObj.bookIds.count)
                        })
                    )
                    
                    searchTasks.forEach { task in
                        self.searchRequestSubject.send(task)
                    }
                }
                
                print("\(#function) end=\(dateFormatter.string(from: .now)) mergedObj.books.count=\(mergedObj.books.count)")
            }
            .store(in: &cancellables)
    }
    
    func registerCategoryRefreshReceiver() {
        categoryRequestSubject
            .receive(on: cacheRealmQueue)
            .flatMap { request -> AnyPublisher<LibraryCategoryList, Never> in
                var justRequest = request
                justRequest.retries = 0
                
                let just = Just(justRequest).setFailureType(to: Never.self).eraseToAnyPublisher()
                
                guard let serverUrl = self.service.getServerUrlByReachability(server: request.library.server)
                else { return just }
                
                if let object = self.cacheCategoryLibraryObjects[.init(libraryId: request.library.id, categoryName: request.category.name)] {
                    guard object.generation < request.library.lastModified
                    else {
                        return just
                    }
                }
                
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
                
                try! cacheRealm.write({
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
    
    fileprivate func registerCategoryMergeReceiver() {
        self.categoryMergerRequestSubject
            .collect(.byTime(RunLoop.main, .seconds(1)))
            .sink { categoryKeys in
                Set(categoryKeys).forEach {
                    self.categoryMergerHandlerSubject.send($0)
                }
            }
            .store(in: &cancellables)
        
        self.categoryMergerHandlerSubject.receive(on: cacheRealmQueue)
            .map { categoryKey -> (CalibreUnifiedCategoryKey, [String: [CalibreLibraryCategoryItemObject]]) in
                let nameItems = self.cacheCategoryLibraryObjects.filter {
                    $0.key.categoryName == categoryKey.categoryName
                }.filter {
                    guard let library = self.service.modelData.calibreLibraries[$0.key.libraryId],
                          library.hidden == false,
                          library.server.removed == false
                    else {
                        return false
                    }
                    
                    return true
                }.reduce(into: [String: [CalibreLibraryCategoryItemObject]]()) { partialResult, libraryCategoryEntry in
                    
                    libraryCategoryEntry.value.items
                        .filter({
                            categoryKey.search.isEmpty
                            ||
                            $0.name.localizedCaseInsensitiveContains(categoryKey.search)
                        })
                        .forEach { categoryItem in
                        
                        if partialResult[categoryItem.name] == nil {
                            partialResult[categoryItem.name] = [categoryItem]
                        } else {
                            partialResult[categoryItem.name]?.append(categoryItem)
                        }
                    }
                }
                
                return (categoryKey, nameItems)
            }
            .sink { categoryKey, nameItems in
                let cacheObj = self.retrieveUnifiedCategoryObject(categoryKey.categoryName, categoryKey.search, self.cacheRealm.objects(CalibreUnifiedCategoryObject.self))
                
                try! self.cacheRealm.write {
                    if cacheObj.realm == nil {
                        self.cacheRealm.add(cacheObj)
                    } else {
                        cacheObj.items.removeAll()
                        cacheObj.itemsCount = 0
                        cacheObj.totalNumber = 0
                    }
                    
                    guard nameItems.count < 1000
                    else {
                        nameItems.forEach {
                            cacheObj.totalNumber += $0.value.reduce(0, { partialResult, itemObj in
                                partialResult + itemObj.count
                            })
                        }
                        cacheObj.itemsCount = nameItems.count
                        
                        return
                    }
                    
                    nameItems
                        .sorted { $0.key < $1.key }
                        .forEach { nameItemEntry in
                            let unifiedItemObj = self.getOrCreateUnifiedCategoryItem(categoryName: categoryKey.categoryName, name: nameItemEntry.key)
                            
                            unifiedItemObj.items.removeAll()
                            unifiedItemObj.items.insert(objectsIn: nameItemEntry.value)
                            
                            let stats = unifiedItemObj.items.reduce((0, 0.0)) { partialResult, itemObj in
                                (partialResult.0 + itemObj.count, partialResult.1 + itemObj.averageRating * Double(itemObj.count))
                            }
                            unifiedItemObj.count = stats.0
                            unifiedItemObj.averageRating = stats.1 / Double(stats.0)
                            
                            cacheObj.items.append(unifiedItemObj)
                            cacheObj.itemsCount += 1
                            cacheObj.totalNumber += stats.0
                        }
                }
            }
            .store(in: &cancellables)
    }
    
    func registerLibraryUpdateReceiver() {
        return;
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.formUnion(.withColonSeparatorInTimeZone)
        formatter.timeZone = .current
        
        let dateFormatter = ISO8601DateFormatter()
        let dateFormatter2 = ISO8601DateFormatter()
        dateFormatter2.formatOptions.formUnion(.withFractionalSeconds)
        
        self.service.modelData.calibreUpdatedSubject.receive(on: cacheRealmQueue)
            .compactMap({ calibreUpdatedSignal -> (library: CalibreLibrary, lastModified: Date)? in
                switch calibreUpdatedSignal {
                case .library(let library):
                    let result = self.cacheRealm.objects(CalibreBookRealm.self)
                        .where({
                            $0.libraryName == library.name
                            &&
                            $0.serverUUID == library.server.uuid.uuidString
                        })
                        .sorted(byKeyPath: "lastModified", ascending: false)
                    
                    let resultSync = result
                        .where { $0.lastSynced < $0.lastModified }
                    
                    print("\(#function) library name=\(library.name) result=\(result.count) sync=\(resultSync.count)")
                    
                    if resultSync.count > 0 {
                        let ids: [Int32] = resultSync.map { $0.idInLib }
                        ids.chunks(size: 256).forEach {
                            self.metadataRequestSubject.send(.init(library: library, books: $0, getAnnotations: false))
                        }
                    }
                    
                    guard let bookMostRecentObj = result.first,
                          bookMostRecentObj.lastModified < library.lastModified
                          
                    else {
                       return nil
                    }
                    
                    return (library, bookMostRecentObj.lastModified)
                    
                default:
                    return nil
                }
            })
            .receive(on: cacheWorkerQueue)
            .flatMap { library, lastModified -> AnyPublisher<CalibreSyncLibraryResult, Never> in

                let lastModifiedStr = formatter.string(from: lastModified)
                let filter = "last_modified:\">\(lastModifiedStr)\""

                return self.service.syncLibraryPublisher(
                    resultPrev: .init(
                        request: .init(
                            library: library,
                            autoUpdateOnly: false,
                            incremental: false
                        ),
                        result: [:]
                    ),
                    filter: filter
                )
            }
            .receive(on: cacheRealmQueue)
            .sink(receiveValue: { result in
                guard result.list.book_ids.isEmpty == false
                else {
                    return
                }

                let library = result.request.library
                let serverUUID = library.server.uuid.uuidString

                result.list.book_ids.chunks(size: 1024).forEach { ids in
                    try! self.cacheRealm.write {
                        ids.forEach { id in
                            let idStr = id.description
                            guard let lastModifiedStr = result.list.data.last_modified[idStr]?.v,
                                  let lastModified = dateFormatter.date(from: lastModifiedStr) ?? dateFormatter2.date(from: lastModifiedStr)
                            else {
                                return
                            }

                            let primaryKey = CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: library.name, id: idStr)

                            self.cacheRealm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)?.lastModified = lastModified
                        }
                    }
                }

                self.service.modelData.calibreUpdatedSubject.send(.library(library))
            })
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
    
    func getOrCreateLibrarySearchValueObject(librarySearchKey: LibrarySearchKey, cacheObj: CalibreLibrarySearchObject, serverUrl: String) -> CalibreLibrarySearchValueObject {
        if let sourceObjOpt = cacheObj.sources[serverUrl],
           let sourceObj = sourceObjOpt {
            return sourceObj
        } else {
            let sourceObj = CalibreLibrarySearchValueObject()
            sourceObj.generation = .distantPast
            
            cacheRealm.add(sourceObj)
            cacheObj.sources[serverUrl] = sourceObj
            
            registerCacheSearchValueChangeReceiver(librarySearchKey: librarySearchKey, cacheObj: cacheObj, sourceObj: sourceObj)
            
            return sourceObj
        }
    }
    
    func getOrCreateUnifiedOffsetObject(libraryId: String, mergedObj: CalibreUnifiedSearchObject) -> CalibreUnifiedOffsets {
        if let unifiedOffsetOpt = mergedObj.unifiedOffsets[libraryId],
           let unifiedOffset = unifiedOffsetOpt {
            return unifiedOffset
        } else {
            let unifiedOffsetObj = CalibreUnifiedOffsets()
            
            cacheRealm.add(unifiedOffsetObj)
            mergedObj.unifiedOffsets[libraryId] = unifiedOffsetObj
            
            return unifiedOffsetObj
        }
    }
    
    func getMergedBookIndex(mergedKey: SearchCriteriaMergedKey, primaryKey: String) -> Int? {
        var index: Int?
        self.cacheRealmQueue.sync {
            index = self.cacheSearchUnifiedRuntime[mergedKey]?.indexMap[primaryKey]
        }
        return index
    }
    
    func refreshSearchResults() {
        cacheSearchLibraryObjects.keys.forEach {
            self.searchRefreshSubject.send($0)
        }
    }
    
    func refreshSearchResults(libraryIds: Set<String>, searchCriteria: SearchCriteria) {
        cacheRealmQueue.async { [self] in
            cacheSearchLibraryObjects
                .filter({ key, value in
                    key.criteria == searchCriteria
                })
                .filter({ key, value in
                    libraryIds.isEmpty || libraryIds.contains(key.libraryId)
                })
                .filter({ key, value in
                    guard let library = self.service.modelData.calibreLibraries[key.libraryId],
                          let object = self.cacheRealm.object(ofType: CalibreLibrarySearchObject.self, forPrimaryKey: value)
                    else {
                        return false
                    }
                    return !object.sources.allSatisfy { entry in
                        guard let sourceObj = entry.value,
                              sourceObj.generation >= library.lastModified
                        else {
                            return false
                        }
                        return true
                    }
                })
                .forEach({ key, value in
                    self.searchRefreshSubject.send(key)
                })
        }
    }
    
    func refreshUnifiedSearchResult(mergedObj: CalibreUnifiedSearchObject) {
        self.searchMergerRequestSubject.send(
            .init(
                libraryIds: .init(mergedObj.libraryIds),
                criteria: .init(
                    searchString: mergedObj.search,
                    sortCriteria: .init(by: mergedObj.sortBy, ascending: mergedObj.sortAsc),
                    filterCriteriaCategory: mergedObj.filters.reduce(into: [:], { partialResult, filter in
                        if let values = filter.value?.values {
                            partialResult[filter.key] = Set(values)
                        }
                    })
                )
            )
        )
    }
    
    func refreshUnifiedCategoryResult(_ categoryKey: CalibreUnifiedCategoryKey) {
        self.categoryMergerHandlerSubject.send(categoryKey)
    }
    /**
     merged search results
     */
    
    func retrieveUnifiedSearchObject(_ criteriaLibraries: Set<String>, _ searchCriteria: SearchCriteria, _ unifiedSearches: Results<CalibreUnifiedSearchObject>) -> CalibreUnifiedSearchObject {
        if let objectId = cacheSearchUnifiedObjects[.init(libraryIds: criteriaLibraries, criteria: searchCriteria)] {
            return unifiedSearches.where({ $0._id == objectId }).first!
        }
        
        let existingObjs = unifiedSearches.where {
            $0.search == searchCriteria.searchString
            &&
            $0.sortBy == searchCriteria.sortCriteria.by
            &&
            $0.sortAsc == searchCriteria.sortCriteria.ascending
        }.filter({ object in
            guard criteriaLibraries.count == object.libraryIds.count,
                  criteriaLibraries == Set(object.libraryIds)
            else {
                return false
            }
            
            guard object.filters.count == searchCriteria.filterCriteriaCategory.count,
                  object.filters.allSatisfy({ filterEntry in
                      guard let filterValues = filterEntry.value,
                            let searchFilterValues = searchCriteria.filterCriteriaCategory[filterEntry.key],
                            filterValues.values.count == searchFilterValues.count
                      else {
                          return false
                      }
                      
                      return searchFilterValues == Set(filterValues.values)
                  })
            else {
                return false
            }
            
            return true
        })
        
        if let cacheObj = existingObjs.first {
            return cacheObj
        }
        
        let cacheObj = CalibreUnifiedSearchObject()
        cacheObj.search = searchCriteria.searchString
        cacheObj.sortBy = searchCriteria.sortCriteria.by
        cacheObj.sortAsc = searchCriteria.sortCriteria.ascending
        cacheObj.filters = searchCriteria.filterCriteriaCategory.reduce(into: Map<String, CalibreLibrarySearchFilterValues?>()) { partialResult, entry in
            let values = CalibreLibrarySearchFilterValues()
            values.values.insert(objectsIn: entry.value)
            partialResult[entry.key] = values
        }
        cacheObj.libraryIds.insert(objectsIn: criteriaLibraries)
        
        return cacheObj
    }
    
    func retrieveUnifiedCategoryObject(_ categoryName: String, _ filter: String, _ unifiedCategories: Results<CalibreUnifiedCategoryObject>) -> CalibreUnifiedCategoryObject {
        if let object = unifiedCategories.where({
            $0.categoryName == categoryName
            &&
            $0.search == filter
        }).first {
            return object
        }
        
        let object = CalibreUnifiedCategoryObject()
        object.categoryName = categoryName
        object.search = filter
        object.totalNumber = 0
        
        return object
    }
    
    private func mergeBookListsNew(mergedKey: SearchCriteriaMergedKey, mergedObj: CalibreUnifiedSearchObject) {
        
        // sort in reverse so we can use popLast() (O(1)) to merge
        let sortComparator = MergeSortComparatorNew(criteria: mergedObj.sortBy, order: mergedObj.sortAsc ? .reverse : .forward)
        
        mergedObj.totalNumber = 0
        
        var heads = mergedObj.unifiedOffsets.compactMap { unifiedOffsetEntry -> (CalibreUnifiedOffsets, CalibreLibrarySearchValueObject)? in
            
            guard let library = service.modelData.calibreLibraries[unifiedOffsetEntry.key],
                  let unifiedOffset = unifiedOffsetEntry.value
            else {
                fatalError("Shouldn't missing unifiedOffset")
            }
            
            guard let searchObj = unifiedOffset.searchObject
            else {
                return nil
            }
            
            guard let sourceEntry = searchObj.sources.filter({
                if $0.key == library.server.publicUrl.replacingOccurrences(of: ".", with: "_"),
                    service.modelData.isServerReachable(server: library.server, isPublic: true) == true {
                    return true
                }
                if $0.key == library.server.baseUrl.replacingOccurrences(of: ".", with: "_"),
                    service.modelData.isServerReachable(server: library.server, isPublic: false) == true {
                    return true
                }
                if $0.key == URL(fileURLWithPath: "/realm").absoluteString,
                   service.modelData.isServerReachable(server: library.server) == false {
                    return true
                }
                return false
            }).sorted(by: { lhs, rhs in
                (lhs.value?.books.count ?? 0) > (rhs.value?.books.count ?? 0)
            }).first,
                  let sourceObj = sourceEntry.value
            else {
                return nil
            }
            
            unifiedOffset.searchObjectSource = sourceEntry.key
            mergedObj.totalNumber += sourceObj.totalNumber
            
            unifiedOffset.beenConsumed = unifiedOffset.offset >= sourceObj.totalNumber
            if unifiedOffset.beenConsumed {
                return nil
            }
            
            unifiedOffset.beenCutOff = unifiedOffset.offset >= sourceObj.books.endIndex
            if unifiedOffset.beenCutOff {
                return nil
            }
            
            return (unifiedOffset, sourceObj)
        }.sorted(using: sortComparator)
        
        guard mergedObj.unifiedOffsets.allSatisfy({
            $0.value?.beenConsumed == true || $0.value?.beenCutOff == false
        }) else {
            //should trigger library search
            return
        }
        
        print("LIBRARYINFOVIEW heads=\(heads.count)")
        
        guard mergedObj.limitNumber > mergedObj.books.count
        else {
            return
        }
        
        while mergedObj.books.count < mergedObj.limitNumber,
              let headEntry = heads.popLast() {
            let unifiedOffset = headEntry.offset
            let sourceObj = headEntry.value
            
            let head = sourceObj.books[unifiedOffset.offset]
            self.cacheSearchUnifiedRuntime[mergedKey]?.indexMap[head.primaryKey!] = mergedObj.books.endIndex
            mergedObj.books.append(head)
            
            unifiedOffset.offset += 1
            
            guard unifiedOffset.offset < sourceObj.books.count else {
                if sourceObj.books.count < sourceObj.totalNumber {
                    unifiedOffset.beenCutOff = true
                    break
                } else {
                    unifiedOffset.beenConsumed = true
                    continue
                }
            }
            
            let next = (unifiedOffset, sourceObj)
            heads.append(next)
            heads.sort(using: sortComparator)
        }
        
        print("\(#function) merged from \(mergedObj.unifiedOffsets.count) libraries")
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

struct MergeSortComparatorNew: SortComparator {
    let criteria: SortCriteria
    var order: SortOrder
    
    func compare(
        _ lh: (offset: CalibreUnifiedOffsets, value: CalibreLibrarySearchValueObject),
        _ rh: (offset: CalibreUnifiedOffsets, value: CalibreLibrarySearchValueObject)
    ) -> ComparisonResult {
        let lhs = lh.value.books[lh.offset.offset]
        let rhs = rh.value.books[rh.offset.offset]
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
    func buildLibrarySearchTasks(library: CalibreLibrary, searchCriteria: SearchCriteria, parameters: [String: (generation: Date, num: Int, offset: Int)]) -> [CalibreLibrarySearchTask] {
        var serverUrls = [URL]()
        if let baseUrl = URL(string: library.server.baseUrl) {
            serverUrls.append(baseUrl)
        }
        if library.server.hasPublicUrl,
           let publicUrl = URL(string: library.server.publicUrl) {
            serverUrls.append(publicUrl)
        }
        if library.autoUpdate || library.server.isLocal {
            serverUrls.append(URL(fileURLWithPath: "/realm"))
        }
        
        guard serverUrls.isEmpty == false
        else {
            return []
        }
        
        let sortQueryItems = [
            URLQueryItem(name: "sort", value: searchCriteria.sortCriteria.by.sortQueryParam),
            URLQueryItem(name: "sort_order", value: searchCriteria.sortCriteria.ascending ? "asc" : "desc")
        ]
        
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
        
        
        return serverUrls.map { serverUrl -> (serverUrl: URL, booksListUrl: URL?, parameter: (generation: Date, num: Int, offset: Int)) in
            var booksListUrlComponents = URLComponents()
            booksListUrlComponents.path = "ajax/search/\(library.key)"
            
            var booksListUrlQueryItems = [URLQueryItem]()
            booksListUrlQueryItems.append(contentsOf: sortQueryItems)
            
            let parameter = parameters[serverUrl.absoluteString.replacingOccurrences(of: ".", with: "_")] ?? (generation: library.lastModified, num: 100, offset: 0)
            
            
            booksListUrlQueryItems.append(.init(name: "offset", value: parameter.offset.description))
            booksListUrlQueryItems.append(.init(name: "num", value: parameter.num.description))
            
            booksListUrlQueryItems.append(.init(name: "query", value: queryStrings.joined(separator: " AND ")))
            
            booksListUrlComponents.queryItems = booksListUrlQueryItems
            
            return (
                serverUrl,
                booksListUrlComponents.url(relativeTo: serverUrl)?.absoluteURL,
                parameter
            )
        }.compactMap {
            $0.booksListUrl == nil ? nil : CalibreLibrarySearchTask(
                serverUrl: $0.serverUrl,
                generation: $0.parameter.generation,
                library: library,
                searchCriteria: searchCriteria,
                booksListUrl: $0.booksListUrl!,
                offset: $0.parameter.offset,
                num: $0.parameter.num
            )
        }
        
//        guard let booksListUrl = booksListUrlComponents.url(relativeTo: serverUrl)?.absoluteURL else {
//            return nil
//        }
//
//        return CalibreLibrarySearchTask(
//            generation: generation,
//            library: library,
//            searchCriteria: searchCriteria,
//            booksListUrl: booksListUrl,
//            offset: offset,
//            num: num
//        )
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
    
}
