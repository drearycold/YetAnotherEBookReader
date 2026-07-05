//
//  RealmSearchCacheStore.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-10.
//

import Foundation
import RealmSwift
import OSLog

final class RealmSearchCacheStore: SearchCacheRepository, CategoryCacheRepository, @unchecked Sendable {
    private let customConfig: Realm.Configuration?
    private let databaseService: DatabaseService
    private weak var librarySnapshotProvider: CalibreLibrarySnapshotProviding?

    var defaultLog = Logger()

    private struct CategoryItemCursor {
        let libraryId: String
        let items: Results<CalibreLibraryCategoryItemObject>
        var index = 0

        var current: CalibreLibraryCategoryItemObject? {
            guard index < items.count else { return nil }
            return items[index]
        }
    }

    init(
        config: Realm.Configuration? = nil,
        databaseService: DatabaseService,
        librarySnapshotProvider: CalibreLibrarySnapshotProviding
    ) {
        self.customConfig = config
        self.databaseService = databaseService
        self.librarySnapshotProvider = librarySnapshotProvider
    }

    convenience init(config: Realm.Configuration? = nil, container: AppContainerProtocol) {
        self.init(
            config: config,
            databaseService: container.databaseService,
            librarySnapshotProvider: container
        )
    }
    
    private func getRealm() throws -> Realm {
        var conf = customConfig ?? databaseService.realmConf ?? Realm.Configuration()
        // Strip closures to prevent EXC_BAD_ACCESS in swift_retain when copying on concurrent queues
        conf.migrationBlock = nil
        conf.shouldCompactOnLaunch = nil
        return try Realm(configuration: conf)
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
        libraryId: String,
        search: String,
        sortBy: SortCriteria,
        sortAsc: Bool,
        filters: [String: Set<String>]
    ) throws -> LibraryCachedResult? {
        let realm = try getRealm()
        
        let matchingObj = realm.objects(CalibreLibrarySearchObject.self)
            .filter("libraryId == %@ AND search == %@ AND sortAsc == %@", libraryId, search, sortAsc)
            .filter { $0.sortBy == sortBy }
            .first { cacheObj in
                let objFilters = cacheObj.filters.reduce(into: [String: Set<String>]()) { partial, filter in
                    if let values = filter.value?.values {
                        partial[filter.key] = Set(values)
                    }
                }
                return objFilters == filters
            }
            
        guard let obj = matchingObj else { return nil }
        return mapToLibraryCachedResult(obj, realm: realm)
    }
    
    func saveLibrarySourceResult(
        libraryId: String,
        search: String,
        sortBy: SortCriteria,
        sortAsc: Bool,
        filters: [String: Set<String>],
        sourceUrl: String,
        result: LibrarySourceSearchResult
    ) throws {
        let realm = try getRealm()

        let existingSearchObject = realm.objects(CalibreLibrarySearchObject.self)
            .filter("libraryId == %@ AND search == %@ AND sortAsc == %@", libraryId, search, sortAsc)
            .filter { $0.sortBy == sortBy }
            .first { cacheObj in
                let objFilters = cacheObj.filters.reduce(into: [String: Set<String>]()) { partial, filter in
                    if let values = filter.value?.values {
                        partial[filter.key] = Set(values)
                    }
                }
                return objFilters == filters
            }

        let missingBooks = result.books.filter { book in
            let primaryKey = CalibreBookRealm.PrimaryKey(
                serverUUID: book.library.server.uuid.uuidString,
                libraryName: book.library.name,
                id: book.id.description
            )
            return realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey) == nil
        }
        let sourceUnchanged: Bool
        if let existingSource = existingSearchObject?.sources[sourceUrl] ?? nil {
            sourceUnchanged = existingSource.generation == result.generation
                && existingSource.totalNumber == result.totalNumber
                && Array(existingSource.bookIds) == result.bookIds
        } else {
            sourceUnchanged = false
        }

        if sourceUnchanged && missingBooks.isEmpty {
            return
        }

        try realm.write {
            for book in missingBooks {
                let primaryKey = CalibreBookRealm.PrimaryKey(
                    serverUUID: book.library.server.uuid.uuidString,
                    libraryName: book.library.name,
                    id: book.id.description
                )
                if realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey) == nil {
                    realm.add(book.makeRealmObject())
                }
            }

            guard !sourceUnchanged else { return }

            // Find or create CalibreLibrarySearchObject
            var searchObj = existingSearchObject
                
            if searchObj == nil {
                let newObj = CalibreLibrarySearchObject()
                newObj.libraryId = libraryId
                newObj.search = search
                newObj.sortBy = sortBy
                newObj.sortAsc = sortAsc
                filters.forEach { key, values in
                    let filterValues = CalibreLibrarySearchFilterValues()
                    filterValues.values.insert(objectsIn: values)
                    newObj.filters[key] = filterValues
                }
                realm.add(newObj)
                searchObj = newObj
            }
            
            guard let parentObj = searchObj else { return }
            
            // Find or create CalibreLibrarySearchValueObject for the sourceUrl
            var sourceObjOpt = parentObj.sources[sourceUrl]
            if sourceObjOpt == nil {
                let newSource = CalibreLibrarySearchValueObject()
                realm.add(newSource)
                parentObj.sources[sourceUrl] = newSource
                sourceObjOpt = newSource
            }
            
            guard let sObjOpt = sourceObjOpt, let sObj = sObjOpt else { return }
            sObj.generation = result.generation
            sObj.totalNumber = result.totalNumber
            
            sObj.bookIds.removeAll()
            sObj.bookIds.append(objectsIn: result.bookIds)
        }
    }

    func fetchBooks(
        library: CalibreLibrary,
        bookIds: [Int32]
    ) throws -> [Int32: CalibreBook] {
        let realm = try getRealm()
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
        let realm = try getRealm()
        let libraryPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "serverUUID = %@", library.server.uuid.uuidString),
            NSPredicate(format: "libraryName = %@", library.name)
        ])
        let predicates = makeLocalSearchPredicates(criteria: criteria)

        let allBooks = realm.objects(CalibreBookRealm.self)
            .filter(libraryPredicate)
            .sorted(byKeyPath: criteria.sortCriteria.by.sortKeyPath, ascending: criteria.sortCriteria.ascending)
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
        json: NSDictionary?
    ) throws {
        let realm = try getRealm()
        let serverUUID = library.server.uuid.uuidString

        try realm.write {
            entries.forEach { key, entry in
                guard let entry = entry else { return }
                guard let bookId = Int32(key) else { return }
                let primaryKey = CalibreBookRealm.PrimaryKey(
                    serverUUID: serverUUID,
                    libraryName: library.name,
                    id: bookId.description
                )

                let bookRealm = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey) ?? CalibreBookRealm()
                if bookRealm.realm == nil {
                    bookRealm.primaryKey = primaryKey
                    bookRealm.serverUUID = serverUUID
                    bookRealm.libraryName = library.name
                    bookRealm.idInLib = bookId
                    realm.add(bookRealm)
                }

                let bookRoot = json?[key] as? NSDictionary ?? NSDictionary()
                bookRealm.applyMetadataEntry(entry, root: bookRoot)
            }
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
    
    private func mapToLibraryCachedResult(_ searchObj: CalibreLibrarySearchObject, realm: Realm) -> LibraryCachedResult {
        let libraryId = searchObj.libraryId
        let library = librarySnapshotProvider?.calibreLibraries[libraryId]
        
        var sources: [String: LibrarySourceSearchResult] = [:]
        for sourceEntry in searchObj.sources {
            guard let sourceObj = sourceEntry.value else { continue }
            let url = sourceEntry.key
            
            let books = Array(sourceObj.bookIds.compactMap { bookId -> CalibreBook? in
                guard let lib = library else { return nil }
                let pk = CalibreBookRealm.PrimaryKey(
                    serverUUID: lib.server.uuid.uuidString,
                    libraryName: lib.name,
                    id: bookId.description
                )
                guard let bookRealm = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: pk) else {
                    return nil
                }
                return bookRealm.toDomain(library: lib)
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
        let realm = try getRealm()
        
        guard let obj = realm.objects(CalibreLibraryCategoryObject.self)
            .filter("libraryId == %@ AND categoryName == %@", libraryId, categoryName)
            .first
        else { return nil }
        
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
        result: LibraryCategoryResult
    ) throws {
        let realm = try getRealm()
        
        try realm.write {
            var cacheObj = realm.objects(CalibreLibraryCategoryObject.self)
                .filter("libraryId == %@ AND categoryName == %@", libraryId, categoryName)
                .first
                
            if cacheObj == nil {
                let newObj = CalibreLibraryCategoryObject()
                newObj.libraryId = libraryId
                newObj.categoryName = categoryName
                realm.add(newObj)
                cacheObj = newObj
            }
            
            guard let obj = cacheObj else { return }
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
        }
    }
    
    func fetchCategorySummaries() throws -> [CategoryCacheSummary] {
        let realm = try getRealm()
        let objects = realm.objects(CalibreLibraryCategoryObject.self)
        return mapCategorySummaries(objects: objects)
    }

    func fetchCategorySummaries(libraryIds: Set<String>) throws -> [CategoryCacheSummary] {
        guard !libraryIds.isEmpty else {
            return try fetchCategorySummaries()
        }

        let realm = try getRealm()
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
        let realm = try getRealm()
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

    func observeCategorySummaries() -> AsyncStream<[CategoryCacheSummary]> {
        guard let realm = try? getRealm() else {
            return AsyncStream { continuation in
                continuation.yield([])
                continuation.finish()
            }
        }

        _ = realm.refresh()

        let objects = realm.objects(CalibreLibraryCategoryObject.self)
        return AsyncStream { [weak self] continuation in
            let token = objects.observe(keyPaths: ["items", "totalNumber"], on: DispatchQueue.main) { [weak self] changes in
                guard let self else {
                    continuation.yield([])
                    return
                }
                switch changes {
                case .initial(let objects), .update(let objects, _, _, _):
                    continuation.yield(self.mapCategorySummaries(objects: objects))
                case .error:
                    continuation.yield([])
                }
            }
            continuation.onTermination = { _ in
                token.invalidate()
            }
        }
    }

    func observeCategoryCacheUpdates(categoryName: String) -> AsyncStream<Void> {
        guard let realm = try? getRealm() else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        _ = realm.refresh()

        let objects = realm.objects(CalibreLibraryCategoryObject.self)
            .filter("categoryName == %@", categoryName)

        return AsyncStream { continuation in
            let token = objects.observe(keyPaths: ["items", "totalNumber"], on: DispatchQueue.main) { changes in
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
        let realm = try getRealm()
        try realm.write {
            if let cacheObj = realm.objects(CalibreLibraryCategoryObject.self)
                .filter("libraryId == %@ AND categoryName == %@", libraryId, categoryName)
                .first {
                cacheObj.generation = .distantPast
            }
        }
    }
}
