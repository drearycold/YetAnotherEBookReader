//
//  RealmSearchCacheStore.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-10.
//

import Foundation
import RealmSwift
import Combine

final class RealmSearchCacheStore: SearchCacheRepository, CategoryCacheRepository, @unchecked Sendable {
    private let config: Realm.Configuration
    private let modelData: ModelData
    
    init(config: Realm.Configuration, modelData: ModelData) {
        self.config = config
        self.modelData = modelData
    }
    
    private func getRealm() throws -> Realm {
        return try Realm(configuration: config)
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
        return mapToLibraryCachedResult(obj)
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
            
            sObj.books.removeAll()
            let bookRealms = result.books.map { book -> CalibreBookRealm in
                let bookRealm = book.managedObject()
                return realm.create(CalibreBookRealm.self, value: bookRealm, update: .modified)
            }
            sObj.books.append(objectsIn: bookRealms)
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
                        guard let obj = matched else { return nil }
                        return self.mapToLibraryCachedResult(obj)
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
    
    private func mapToLibraryCachedResult(_ searchObj: CalibreLibrarySearchObject) -> LibraryCachedResult {
        let libraryId = searchObj.libraryId
        let library = modelData.calibreLibraries[libraryId]
        
        var sources: [String: LibrarySourceSearchResult] = [:]
        for sourceEntry in searchObj.sources {
            guard let sourceObj = sourceEntry.value else { continue }
            let url = sourceEntry.key
            
            let books = Array(sourceObj.books.compactMap { (bookRealm: CalibreBookRealm) -> CalibreBook? in
                guard let lib = library else { return nil }
                return CalibreBook(managedObject: bookRealm, library: lib)
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
