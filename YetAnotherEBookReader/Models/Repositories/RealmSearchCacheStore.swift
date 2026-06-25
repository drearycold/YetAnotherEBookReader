//
//  RealmSearchCacheStore.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-10.
//

import Foundation
import RealmSwift
import Combine
import OSLog

final class RealmSearchCacheStore: SearchCacheRepository, CategoryCacheRepository, @unchecked Sendable {
    private let customConfig: Realm.Configuration?
    private let modelData: AppContainerProtocol

    var defaultLog = Logger()

    init(config: Realm.Configuration? = nil, modelData: AppContainerProtocol) {
        self.customConfig = config
        self.modelData = modelData
    }
    
    private func getRealm() throws -> Realm {
        var conf = customConfig ?? modelData.realmConf ?? Realm.Configuration()
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
        
        try realm.write {
            // Find or create CalibreLibrarySearchObject
            var searchObj = realm.objects(CalibreLibrarySearchObject.self)
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
            
            for book in result.books {
                let bookRealm = book.makeRealmObject()
                _ = realm.create(CalibreBookRealm.self, value: bookRealm, update: .modified)
            }
        }
    }
    

    func libraryCachedResultPublisher(
        libraryId: String,
        search: String,
        sortBy: SortCriteria,
        sortAsc: Bool,
        filters: [String: Set<String>]
    ) -> AnyPublisher<LibraryCachedResult, Error> {
        let publisher = Deferred { () -> AnyPublisher<LibraryCachedResult, Error> in
            do {
                let realm = try self.getRealm()
                let results = realm.objects(CalibreLibrarySearchObject.self)
                    .filter("libraryId == %@ AND search == %@ AND sortAsc == %@", libraryId, search, sortAsc)
                
                let mapped = results.changesetPublisher
                    .tryMap { [weak self] changeset -> LibraryCachedResult? in
                        guard let self = self else { return nil }
                        
                        self.defaultLog.log("libraryCachedResultPublisher \(libraryId) \(search) \(sortAsc)")
                        
                        let collection: Results<CalibreLibrarySearchObject>
                        switch changeset {
                        case .initial(let col):
                            collection = col
                        case .update(let col, _, _, _):
                            collection = col
                        case .error(let err):
                            throw err
                        }
                        
                        let matched = collection
                            .filter { $0.sortBy == sortBy }
                            .first { cacheObj in
                                let objFilters = cacheObj.filters.reduce(into: [String: Set<String>]()) { partial, filter in
                                    if let values = filter.value?.values {
                                        partial[filter.key] = Set(values)
                                    }
                                }
                                return objFilters == filters
                            }
                        let realm = try self.getRealm()
                        guard let obj = matched else { return nil }
                        return self.mapToLibraryCachedResult(obj, realm: realm)
                    }
                    .compactMap { $0 }
                    .eraseToAnyPublisher()
                
                return mapped
            } catch {
                return Fail(error: error).eraseToAnyPublisher()
            }
        }
        
        return publisher
            .subscribe(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    

    
    // MARK: - Mapping Helpers
    
    private func mapToLibraryCachedResult(_ searchObj: CalibreLibrarySearchObject, realm: Realm) -> LibraryCachedResult {
        let libraryId = searchObj.libraryId
        let library = modelData.calibreLibraries[libraryId]
        
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

    func observeCategorySummaries() -> AnyPublisher<[CategoryCacheSummary], Never> {
        guard let realm = try? getRealm() else {
            return Just([]).eraseToAnyPublisher()
        }

        return realm.objects(CalibreLibraryCategoryObject.self)
            .changesetPublisher(keyPaths: ["items", "totalNumber"])
            .map { [weak self] changes -> [CategoryCacheSummary] in
                guard let self = self else { return [] }
                switch changes {
                case .initial(let objects), .update(let objects, _, _, _):
                    return self.mapCategorySummaries(objects: objects)
                case .error:
                    return []
                }
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func observeCategoryCacheUpdates(categoryName: String) -> AnyPublisher<Void, Never> {
        guard let realm = try? getRealm() else {
            return Empty().eraseToAnyPublisher()
        }

        return realm.objects(CalibreLibraryCategoryObject.self)
            .filter("categoryName == %@", categoryName)
            .changesetPublisher(keyPaths: ["items", "totalNumber"])
            .compactMap { changes -> Void? in
                switch changes {
                case .initial:
                    return nil
                case .update:
                    return ()
                case .error:
                    return nil
                }
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
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
