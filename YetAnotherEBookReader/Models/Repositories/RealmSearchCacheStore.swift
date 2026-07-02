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
    private let container: AppContainerProtocol

    var defaultLog = Logger()

    init(config: Realm.Configuration? = nil, container: AppContainerProtocol) {
        self.customConfig = config
        self.container = container
    }
    
    private func getRealm() throws -> Realm {
        var conf = customConfig ?? container.realmConf ?? Realm.Configuration()
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
    
    // MARK: - Mapping Helpers
    
    private func mapToLibraryCachedResult(_ searchObj: CalibreLibrarySearchObject, realm: Realm) -> LibraryCachedResult {
        let libraryId = searchObj.libraryId
        let library = container.calibreLibraries[libraryId]
        
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

    func observeCategorySummaries() -> AsyncStream<[CategoryCacheSummary]> {
        guard let realm = try? getRealm() else {
            return AsyncStream { continuation in
                continuation.yield([])
                continuation.finish()
            }
        }

        let objects = realm.objects(CalibreLibraryCategoryObject.self)
        return AsyncStream { [weak self] continuation in
            if let self {
                continuation.yield(self.mapCategorySummaries(objects: objects))
            } else {
                continuation.yield([])
            }
            let token = objects.observe(keyPaths: ["items", "totalNumber"], on: DispatchQueue.main) { [weak self] changes in
                guard let self else {
                    continuation.yield([])
                    return
                }
                switch changes {
                case .initial:
                    break
                case .update(let objects, _, _, _):
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
