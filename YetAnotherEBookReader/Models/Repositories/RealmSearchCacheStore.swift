//
//  RealmSearchCacheStore.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-10.
//

import Foundation
import RealmSwift

final class RealmSearchCacheStore: SearchCacheRepository, CategoryCacheRepository, @unchecked Sendable {
    // Only immutable scope and the database's locked configuration cross threads.
    private let customConfig: Realm.Configuration?
    private let databaseService: DatabaseService
    private let pinnedDatabase: DatabaseService.CacheConfiguration?
    private let libraryScope: LibraryScope?

    private struct LibraryScope {
        let library: CalibreLibrary
        let rowId: UInt64
        let lifetime: CacheLibraryLifetime?
    }

    private struct CategoryItemCursor {
        let libraryId: String
        let items: Results<CalibreLibraryCategoryItemObject>
        var index = 0

        var current: CalibreLibraryCategoryItemObject? {
            guard index < items.count else { return nil }
            return items[index]
        }
    }

    init(config: Realm.Configuration? = nil, databaseService: DatabaseService) {
        self.customConfig = config
        self.databaseService = databaseService
        self.pinnedDatabase = nil
        self.libraryScope = nil
    }

    convenience init(config: Realm.Configuration? = nil, container: AppContainerProtocol) {
        self.init(config: config, databaseService: container.databaseService)
    }

    private init(
        databaseService: DatabaseService, customConfig: Realm.Configuration?,
        pinnedDatabase: DatabaseService.CacheConfiguration?, libraryScope: LibraryScope?
    ) {
        self.databaseService = databaseService
        self.customConfig = customConfig
        self.pinnedDatabase = pinnedDatabase
        self.libraryScope = libraryScope
    }

    func snapshot() throws -> RealmSearchCacheStore {
        if customConfig != nil || pinnedDatabase != nil {
            try checkDatabase()
            return self
        }
        guard let configuration = databaseService.cacheConfigurationSnapshot else {
            throw CacheContextError.databaseUnavailable
        }
        return RealmSearchCacheStore(databaseService: databaseService, customConfig: nil,
                                     pinnedDatabase: configuration, libraryScope: nil)
    }

    func scoped(to library: CalibreLibrary, lifetime: CacheLibraryLifetime?) throws -> RealmSearchCacheStore {
        if let libraryScope {
            guard libraryScope.library.hasSameCacheScope(as: library) else { throw CacheContextError.superseded }
            try checkCurrent()
            return self
        }
        let cache = try snapshot()
        let realm = try cache.openRealmForRead()
        guard let row = realm.object(ofType: CalibreLibraryRealm.self, forPrimaryKey: library.id) else {
            throw CacheContextError.superseded
        }
        let scoped = RealmSearchCacheStore(
            databaseService: databaseService, customConfig: customConfig, pinnedDatabase: cache.pinnedDatabase,
            libraryScope: LibraryScope(library: library, rowId: row.id, lifetime: lifetime)
        )
        try scoped.checkLibrary(in: realm)
        return scoped
    }

    func checkCurrent() throws {
        if libraryScope != nil { _ = try openRealmForRead() }
        else { try checkDatabase() }
    }

    private func checkDatabase() throws {
        if customConfig != nil { return }
        let current = databaseService.cacheConfigurationSnapshot
        if let pinnedDatabase {
            guard current?.id == pinnedDatabase.id else { throw CacheContextError.superseded }
        } else if current == nil {
            throw CacheContextError.databaseUnavailable
        }
    }

    private func checkLibrary(in realm: Realm) throws {
        guard let scope = libraryScope else { return }
        try scope.lifetime?.checkCurrent()
        let library = scope.library
        guard !library.hidden, !library.server.removed else { throw CacheContextError.superseded }
        guard let row = realm.object(ofType: CalibreLibraryRealm.self, forPrimaryKey: library.id),
              row.id == scope.rowId, !row.hidden, (row.key ?? row.name) == library.key,
              row.lastModified == library.lastModified,
              let server = realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: library.server.id),
              server.baseUrl != nil,
              DSReaderHelperConnection(server.toDomain()) == DSReaderHelperConnection(library.server)
        else { throw CacheContextError.superseded }
    }

    private func checkScope(libraryId: String) throws {
        if let libraryScope, libraryScope.library.id != libraryId { throw CacheContextError.superseded }
    }

    private func scopedLibrary(_ library: CalibreLibrary) throws -> CalibreLibrary {
        try checkScope(libraryId: library.id)
        return libraryScope?.library ?? library
    }

    private func openRealm() throws -> Realm {
        try checkDatabase()
        guard var conf = customConfig ?? pinnedDatabase?.configuration ?? databaseService.cacheConfigurationSnapshot?.configuration
        else { throw CacheContextError.databaseUnavailable }
        // Strip closures to prevent EXC_BAD_ACCESS in swift_retain when copying on concurrent queues
        conf.migrationBlock = nil
        conf.shouldCompactOnLaunch = nil
        return try Realm(configuration: conf)
    }

    private func openRealmForRead() throws -> Realm {
        let realm = try openRealm()
        // Reopening can reuse a Realm with an old read version on a thread without a run loop.
        // Advance it before the synchronous query and mapping to detached values.
        if !realm.isInWriteTransaction && !realm.configuration.readOnly {
            realm.refresh()
        }
        try checkDatabase()
        try checkLibrary(in: realm)
        return realm
    }

    private func writeIfChanged(in realm: Realm, _ changes: () throws -> Bool) throws {
        realm.beginWrite()
        defer { if realm.isInWriteTransaction { realm.cancelWrite() } }
        try Task.checkCancellation()
        try checkDatabase()
        try checkLibrary(in: realm)
        if try changes() { try realm.commitWrite() }
    }

    private func mapCategorySummaries<S: Sequence>(objects: S) -> [CategoryCacheSummary] where S.Element == CalibreLibraryCategoryObject {
        var summariesByName: [String: (itemsCount: Int, totalNumber: Int)] = [:]
        for obj in objects {
            let name = obj.categoryName
            let current = summariesByName[name] ?? (0, 0)
            summariesByName[name] = (
                current.itemsCount + obj.items.count,
                current.totalNumber + obj.totalNumber
            )
        }

        return summariesByName.map { name, stats in
            CategoryCacheSummary(
                categoryName: name,
                itemsCount: stats.itemsCount,
                totalNumber: stats.totalNumber
            )
        }.sorted { $0.categoryName < $1.categoryName }
    }
    
    func fetchLibraryCachedResult(
        library: CalibreLibrary,
        search: String,
        sortBy: SortCriteria,
        sortAsc: Bool,
        filters: [String: Set<String>]
    ) throws -> LibraryCachedResult? {
        let library = try scopedLibrary(library)
        let realm = try openRealmForRead()
        let result = findSearch(in: realm, libraryId: library.id, search: search, sortBy: sortBy,
                                sortAsc: sortAsc, filters: filters)
        return result.map { mapToLibraryCachedResult($0, library: library, realm: realm) }
    }

    private func findSearch(
        in realm: Realm, libraryId: String, search: String, sortBy: SortCriteria,
        sortAsc: Bool, filters: [String: Set<String>]
    ) -> CalibreLibrarySearchObject? {
        realm.objects(CalibreLibrarySearchObject.self)
            .filter("libraryId == %@ AND search == %@ AND sortAsc == %@", libraryId, search, sortAsc)
            .first { cache in
                cache.sortBy == sortBy && cache.filters.reduce(into: [String: Set<String>]()) { values, entry in
                    if let stored = entry.value?.values { values[entry.key] = Set(stored) }
                } == filters
            }
    }

    func saveLibrarySourceResult(
        libraryId: String,
        search: String,
        sortBy: SortCriteria,
        sortAsc: Bool,
        filters: [String: Set<String>],
        sourceUrl: String,
        result: LibrarySourceSearchResult,
        expecting: CacheWriteExpectation<SearchSourceState>
    ) throws {
        try checkScope(libraryId: libraryId)
        let realm = try openRealm()
        let sourceState = result.sourceState
        // Scoped searches already persisted metadata. Their detached books can outlive a deletion.
        let seedBooks = libraryScope == nil ? result.books.map { $0.makeRealmObject() } : []
        try writeIfChanged(in: realm) {
            let existing = findSearch(in: realm, libraryId: libraryId, search: search, sortBy: sortBy,
                                      sortAsc: sortAsc, filters: filters)
            let existingSource = existing?.sources[sourceUrl] ?? nil
            let current = existingSource.map {
                SearchSourceState(generation: $0.generation, totalNumber: $0.totalNumber, bookIds: Array($0.bookIds))
            }
            let sourceChanged = current != sourceState
            if sourceChanged, case .previous(let expected) = expecting, current != expected {
                throw CacheContextError.superseded
            }

            var insertedBook = false
            for book in seedBooks {
                guard let key = book.primaryKey,
                      realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: key) == nil else { continue }
                realm.add(book)
                insertedBook = true
            }
            guard sourceChanged else { return insertedBook }

            let parent: CalibreLibrarySearchObject
            if let existing {
                parent = existing
            } else {
                parent = CalibreLibrarySearchObject()
                parent.libraryId = libraryId
                parent.search = search
                parent.sortBy = sortBy
                parent.sortAsc = sortAsc
                for (key, values) in filters {
                    let stored = CalibreLibrarySearchFilterValues()
                    stored.values.insert(objectsIn: values)
                    parent.filters[key] = stored
                }
                realm.add(parent)
            }

            let source = existingSource ?? CalibreLibrarySearchValueObject()
            if existingSource == nil { parent.sources[sourceUrl] = source }
            source.generation = result.generation
            source.totalNumber = result.totalNumber
            source.bookIds.removeAll()
            source.bookIds.append(objectsIn: result.bookIds)
            return true
        }
    }

    func fetchBooks(
        library: CalibreLibrary,
        bookIds: [Int32]
    ) throws -> [Int32: CalibreBook] {
        let library = try scopedLibrary(library)
        let realm = try openRealmForRead()
        let serverUUID = library.server.uuid.uuidString

        return bookIds.reduce(into: [Int32: CalibreBook]()) { partialResult, bookId in
            let primaryKey = CalibreBookRealm.PrimaryKey(
                serverUUID: serverUUID,
                libraryName: library.name,
                id: bookId.description
            )
            guard let bookRealm = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey) else {
                return
            }
            partialResult[bookId] = bookRealm.toDomain(library: library)
        }
    }

    func searchLocalLibrary(
        library: CalibreLibrary,
        criteria: SearchCriteria,
        offset: Int,
        limit: Int
    ) throws -> LocalLibrarySearchResult {
        let library = try scopedLibrary(library)
        let realm = try openRealmForRead()
        let libraryPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "serverUUID = %@", library.server.uuid.uuidString),
            NSPredicate(format: "libraryName = %@", library.name)
        ])
        let predicates = makeLocalSearchPredicates(criteria: criteria)

        let allBooks = realm.objects(CalibreBookRealm.self)
            .filter(libraryPredicate)
            .sorted(by: [
                SortDescriptor(keyPath: criteria.sortCriteria.by.sortKeyPath, ascending: criteria.sortCriteria.ascending),
                SortDescriptor(keyPath: "idInLib", ascending: criteria.sortCriteria.ascending),
            ])
        let filteredBooks = predicates.isEmpty
            ? allBooks
            : allBooks.filter(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))

        var bookIds = [Int32]()
        if offset < filteredBooks.count {
            bookIds = filteredBooks[offset..<min(offset + limit, filteredBooks.count)].map { $0.idInLib }
        }

        return LocalLibrarySearchResult(
            totalNumber: filteredBooks.count,
            numBooksWithoutSearch: allBooks.count,
            offset: offset,
            num: bookIds.count,
            sort: criteria.sortCriteria.by.sortQueryParam,
            bookIds: bookIds
        )
    }

    func writeMetadataEntries(
        library: CalibreLibrary,
        entries: [String: CalibreBookEntry?],
        json: NSDictionary?,
        retainingExisting: Set<Int32>,
        metadataBaseline: [Int32: Date]
    ) throws {
        let library = try scopedLibrary(library)
        let realm = try openRealm()
        let serverUUID = library.server.id
        let values = entries.compactMap { key, entry -> (Int32, CalibreBookMetadataValue)? in
            guard let entry, let id = Int32(key) else { return nil }
            return (id, CalibreBookMetadataValue(entry: entry, root: json?[key] as? NSDictionary ?? NSDictionary()))
        }

        try writeIfChanged(in: realm) {
            var changed = false
            for (id, metadata) in values {
                let key = CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: library.name, id: id.description)
                let existing = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: key)
                if existing == nil, retainingExisting.contains(id) { continue }
                if libraryScope != nil, let existing,
                   !existing.canApplyMetadata(metadata, since: metadataBaseline[id]) {
                    continue
                }
                let book = existing ?? CalibreBookRealm()
                if existing == nil {
                    book.primaryKey = key
                    book.serverUUID = serverUUID
                    book.libraryName = library.name
                    book.idInLib = id
                    realm.add(book)
                }
                book.applyMetadataValue(metadata)
                changed = true
            }
            return changed
        }
    }

    // MARK: - Mapping Helpers

    private func makeLocalSearchPredicates(criteria: SearchCriteria) -> [NSPredicate] {
        var predicates = [NSPredicate]()
        let searchTerms = criteria.searchString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split { $0.isWhitespace }
            .map { String($0) }
        if !searchTerms.isEmpty {
            predicates.append(contentsOf: searchTerms.map {
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "title CONTAINS[c] %@", $0),
                    NSPredicate(format: "authorFirst CONTAINS[c] %@", $0),
                    NSPredicate(format: "authorSecond CONTAINS[c] %@", $0)
                ])
            })
        }

        return criteria.filterCriteriaCategory.reduce(into: predicates) { partialResult, categoryFilter in
            guard !categoryFilter.value.isEmpty else { return }

            switch categoryFilter.key {
            case "Tags":
                partialResult.append(NSCompoundPredicate(orPredicateWithSubpredicates: categoryFilter.value.map {
                    NSCompoundPredicate(orPredicateWithSubpredicates: [
                        NSPredicate(format: "tagFirst = %@", $0),
                        NSPredicate(format: "tagSecond = %@", $0),
                        NSPredicate(format: "tagThird = %@", $0)
                    ])
                }))
            case "Authors":
                partialResult.append(NSCompoundPredicate(orPredicateWithSubpredicates: categoryFilter.value.map {
                    NSCompoundPredicate(orPredicateWithSubpredicates: [
                        NSPredicate(format: "authorFirst = %@", $0),
                        NSPredicate(format: "authorSecond = %@", $0),
                        NSPredicate(format: "authorThird = %@", $0)
                    ])
                }))
            case "Series":
                partialResult.append(NSCompoundPredicate(orPredicateWithSubpredicates: categoryFilter.value.map {
                    NSPredicate(format: "series = %@", $0)
                }))
            case "Publisher":
                partialResult.append(NSCompoundPredicate(orPredicateWithSubpredicates: categoryFilter.value.map {
                    NSPredicate(format: "publisher = %@", $0)
                }))
            case "Rating":
                partialResult.append(NSCompoundPredicate(orPredicateWithSubpredicates: categoryFilter.value.map {
                    NSPredicate(format: "rating = %@", NSNumber(value: $0.count * 2))
                }))
            default:
                partialResult.append(NSPredicate(value: false))
            }
        }
    }
    
    private func mapToLibraryCachedResult(
        _ searchObj: CalibreLibrarySearchObject, library: CalibreLibrary, realm: Realm
    ) -> LibraryCachedResult {
        let libraryId = searchObj.libraryId
        
        var sources: [String: LibrarySourceSearchResult] = [:]
        for sourceEntry in searchObj.sources {
            guard let sourceObj = sourceEntry.value else { continue }
            let url = sourceEntry.key
            
            let books = Array(sourceObj.bookIds.compactMap { bookId -> CalibreBook? in
                let pk = CalibreBookRealm.PrimaryKey(
                    serverUUID: library.server.uuid.uuidString,
                    libraryName: library.name,
                    id: bookId.description
                )
                guard let bookRealm = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: pk) else {
                    return nil
                }
                return bookRealm.toDomain(library: library)
            })
            
            sources[url] = LibrarySourceSearchResult(
                generation: sourceObj.generation,
                totalNumber: sourceObj.totalNumber,
                bookIds: Array(sourceObj.bookIds),
                books: books
            )
        }
        
        return LibraryCachedResult(
            libraryId: libraryId,
            search: searchObj.search,
            sortBy: searchObj.sortBy,
            sortAsc: searchObj.sortAsc,
            filters: searchObj.filters.reduce(into: [:]) { partialResult, filter in
                if let values = filter.value?.values {
                    partialResult[filter.key] = Set(values)
                }
            },
            sources: sources
        )
    }
    
    func fetchLibraryCategoryResult(
        libraryId: String,
        categoryName: String
    ) throws -> LibraryCategoryResult? {
        try checkScope(libraryId: libraryId)
        let realm = try openRealmForRead()
        
        guard let obj = realm.objects(CalibreLibraryCategoryObject.self)
            .filter("libraryId == %@ AND categoryName == %@", libraryId, categoryName)
            .first
        else { return nil }
        
        return mapCategoryResult(obj)
    }

    private func mapCategoryResult(_ obj: CalibreLibraryCategoryObject) -> LibraryCategoryResult {
        let items = obj.items.map { itemObj in
            LibraryCategoryItem(
                name: itemObj.name,
                averageRating: itemObj.averageRating,
                count: itemObj.count,
                url: itemObj.url
            )
        }
        
        return LibraryCategoryResult(
            libraryId: obj.libraryId,
            categoryName: obj.categoryName,
            items: Array(items),
            generation: obj.generation,
            totalNumber: obj.totalNumber
        )
    }
    
    func saveLibraryCategoryResult(
        libraryId: String,
        categoryName: String,
        result: LibraryCategoryResult,
        expecting: CacheWriteExpectation<LibraryCategoryResult>
    ) throws {
        try checkScope(libraryId: libraryId)
        let realm = try openRealm()
        
        try writeIfChanged(in: realm) {
            var cacheObj = realm.objects(CalibreLibraryCategoryObject.self)
                .filter("libraryId == %@ AND categoryName == %@", libraryId, categoryName)
                .first

            if case .previous(let expected) = expecting {
                let current = cacheObj.map(mapCategoryResult)
                if current == result { return false }
                guard current == expected else { throw CacheContextError.superseded }
            }
                
            if cacheObj == nil {
                let newObj = CalibreLibraryCategoryObject()
                newObj.libraryId = libraryId
                newObj.categoryName = categoryName
                realm.add(newObj)
                cacheObj = newObj
            }
            
            guard let obj = cacheObj else { return false }
            obj.generation = result.generation
            obj.totalNumber = result.totalNumber
            
            obj.items.removeAll()
            
            for item in result.items {
                let itemObj = realm.objects(CalibreLibraryCategoryItemObject.self)
                    .filter("url == %@", item.url)
                    .first ?? CalibreLibraryCategoryItemObject()
                
                if itemObj.realm == nil {
                    itemObj.name = item.name
                    itemObj.averageRating = item.averageRating
                    itemObj.count = item.count
                    itemObj.url = item.url
                    realm.add(itemObj)
                } else {
                    if itemObj.name != item.name { itemObj.name = item.name }
                    if itemObj.averageRating != item.averageRating { itemObj.averageRating = item.averageRating }
                    if itemObj.count != item.count { itemObj.count = item.count }
                }
                obj.items.append(itemObj)
            }
            return true
        }
    }
    
    func fetchCategorySummaries() throws -> [CategoryCacheSummary] {
        let realm = try openRealmForRead()
        let objects = realm.objects(CalibreLibraryCategoryObject.self)
        return mapCategorySummaries(objects: objects)
    }

    func fetchCategorySummaries(libraryIds: Set<String>) throws -> [CategoryCacheSummary] {
        guard !libraryIds.isEmpty else {
            return try fetchCategorySummaries()
        }

        let realm = try openRealmForRead()
        let objects = realm.objects(CalibreLibraryCategoryObject.self)
            .filter("libraryId IN %@", Array(libraryIds))
        return mapCategorySummaries(objects: objects)
    }

    func fetchUnifiedCategoryItemsPage(
        categoryName: String,
        searchString: String,
        libraryIds: Set<String>,
        offset: Int,
        limit: Int
    ) throws -> UnifiedCategoryPageResult {
        let realm = try openRealmForRead()
        let trimmedSearch = searchString.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeOffset = max(0, offset)
        let safeLimit = max(1, limit)

        var categoryObjects = realm.objects(CalibreLibraryCategoryObject.self)
            .filter("categoryName == %@", categoryName)
        if !libraryIds.isEmpty {
            categoryObjects = categoryObjects.filter("libraryId IN %@", Array(libraryIds))
        }

        var sourceTotalNumber = 0
        var cursors: [CategoryItemCursor] = []
        for categoryObject in categoryObjects {
            sourceTotalNumber += categoryObject.totalNumber
            let itemResults: Results<CalibreLibraryCategoryItemObject>
            if trimmedSearch.isEmpty {
                itemResults = categoryObject.items.sorted(byKeyPath: "name", ascending: true)
            } else {
                itemResults = categoryObject.items
                    .filter("name CONTAINS[c] %@", trimmedSearch)
                    .sorted(byKeyPath: "name", ascending: true)
            }

            if !itemResults.isEmpty {
                cursors.append(CategoryItemCursor(libraryId: categoryObject.libraryId, items: itemResults))
            }
        }

        var processedUniqueCount = 0
        var pageItems: [UnifiedCategoryItem] = []
        let collectionLimit = safeLimit + 1

        while pageItems.count < collectionLimit {
            guard let nextName = cursors.compactMap({ $0.current?.name }).min(by: { lhs, rhs in
                lhs.localizedCompare(rhs) == .orderedAscending
            }) else {
                break
            }

            var libraryItems: [String: LibraryCategoryItem] = [:]
            for cursorIndex in cursors.indices {
                while let current = cursors[cursorIndex].current,
                      current.name == nextName {
                    libraryItems[cursors[cursorIndex].libraryId] = LibraryCategoryItem(
                        name: current.name,
                        averageRating: current.averageRating,
                        count: current.count,
                        url: current.url
                    )
                    cursors[cursorIndex].index += 1
                }
            }

            if processedUniqueCount >= safeOffset {
                let stats = libraryItems.values.reduce((0, 0.0)) { partialResult, item in
                    (partialResult.0 + item.count, partialResult.1 + item.averageRating * Double(item.count))
                }
                let totalCount = stats.0
                let averageRating = totalCount > 0 ? stats.1 / Double(totalCount) : 0.0

                pageItems.append(
                    UnifiedCategoryItem(
                        categoryName: categoryName,
                        name: nextName,
                        averageRating: averageRating,
                        count: totalCount,
                        libraryItems: libraryItems
                    )
                )
            }

            processedUniqueCount += 1
        }

        let hasMore = pageItems.count > safeLimit
        let visibleItems = hasMore ? Array(pageItems.prefix(safeLimit)) : pageItems

        return UnifiedCategoryPageResult(
            categoryName: categoryName,
            search: trimmedSearch,
            totalNumber: sourceTotalNumber,
            itemsCount: processedUniqueCount,
            items: visibleItems,
            hasMore: hasMore,
            nextOffset: safeOffset + visibleItems.count
        )
    }

    func observeBookChanges(in libraries: [CalibreLibrary]) -> AsyncStream<Void> {
        guard !libraries.isEmpty, let cache = try? snapshot(), let realm = try? cache.openRealmForRead(),
              !realm.configuration.readOnly, !realm.isInWriteTransaction else {
            return AsyncStream { $0.finish() }
        }
        let byServer = Dictionary(grouping: libraries, by: { $0.server.id })
        let scope = NSCompoundPredicate(orPredicateWithSubpredicates: byServer.map { server, libraries in
            NSPredicate(format: "serverUUID == %@ AND libraryName IN %@", server, libraries.map(\.name))
        })
        let books = realm.objects(CalibreBookRealm.self).filter(scope)
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let token = books.observe(on: DispatchQueue.main) { changes in
                guard (try? cache.checkDatabase()) != nil else { continuation.finish(); return }
                if case .update = changes { continuation.yield(()) }
            }
            continuation.onTermination = { _ in token.invalidate() }
        }
    }

    func observeCategorySummaries() -> AsyncStream<[CategoryCacheSummary]> {
        guard let cache = try? snapshot(), let realm = try? cache.openRealmForRead() else {
            return AsyncStream { continuation in
                continuation.yield([])
                continuation.finish()
            }
        }
        guard !realm.configuration.readOnly, !realm.isInWriteTransaction else {
            return AsyncStream { $0.finish() }
        }

        let objects = realm.objects(CalibreLibraryCategoryObject.self)
        return AsyncStream { continuation in
            var lastSummaries: [CategoryCacheSummary]?
            let token = objects.observe(on: DispatchQueue.main) { changes in
                do { try cache.checkDatabase() }
                catch { continuation.finish(); return }
                switch changes {
                case .initial(let objects), .update(let objects, _, _, _):
                    let summaries = cache.mapCategorySummaries(objects: objects)
                    guard summaries != lastSummaries else { return }
                    lastSummaries = summaries
                    continuation.yield(summaries)
                case .error:
                    continuation.yield([])
                }
            }
            continuation.onTermination = { _ in
                token.invalidate()
            }
        }
    }

    func observeCategoryCacheUpdates(categoryName: String, libraryIds: Set<String>?) -> AsyncStream<Void> {
        guard let cache = try? snapshot(), let realm = try? cache.openRealmForRead(),
              !realm.configuration.readOnly, !realm.isInWriteTransaction else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        var objects = realm.objects(CalibreLibraryCategoryObject.self)
            .filter("categoryName == %@", categoryName)
        if let libraryIds {
            objects = objects.filter("libraryId IN %@", Array(libraryIds))
        }

        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let token = objects.observe(
                keyPaths: ["generation", "totalNumber", "items", "items.name", "items.count", "items.averageRating", "items.url"],
                on: DispatchQueue.main
            ) { changes in
                do { try cache.checkDatabase() }
                catch { continuation.finish(); return }
                switch changes {
                case .initial:
                    break
                case .update:
                    continuation.yield(())
                case .error:
                    break
                }
            }
            continuation.onTermination = { _ in
                token.invalidate()
            }
        }
    }
    
    func invalidateCategoryCache(libraryId: String, categoryName: String) throws {
        try checkScope(libraryId: libraryId)
        let realm = try openRealm()
        try writeIfChanged(in: realm) {
            if let cacheObj = realm.objects(CalibreLibraryCategoryObject.self)
                .filter("libraryId == %@ AND categoryName == %@", libraryId, categoryName)
                .first {
                guard cacheObj.generation != .distantPast else { return false }
                cacheObj.generation = .distantPast
                return true
            }
            return false
        }
    }

    func removeLibraryCategoryResultsNotIn(
        libraryId: String,
        activeCategoryNames: Set<String>
    ) throws {
        try checkScope(libraryId: libraryId)
        let realm = try openRealm()
        try writeIfChanged(in: realm) {
            let libraryCategories = realm.objects(CalibreLibraryCategoryObject.self)
                .filter("libraryId == %@", libraryId)
            let staleCategories: [CalibreLibraryCategoryObject]
            if activeCategoryNames.isEmpty {
                staleCategories = Array(libraryCategories)
            } else {
                staleCategories = Array(
                    libraryCategories.filter("NOT categoryName IN %@", Array(activeCategoryNames))
                )
            }

            guard !staleCategories.isEmpty else { return false }
            realm.delete(staleCategories)

            let orphanedItems = realm.objects(CalibreLibraryCategoryItemObject.self)
                .filter("assignee.@count == 0")
            realm.delete(orphanedItems)
            return true
        }
    }
}
