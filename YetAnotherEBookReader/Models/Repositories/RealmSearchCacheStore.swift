//
//  RealmSearchCacheStore.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-10.
//

import Foundation
import RealmSwift
import Combine

class RealmSearchCacheStore: SearchCacheRepository {
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
            let bookRealms = result.books.map { $0.managedObject() }
            sObj.books.append(objectsIn: bookRealms)
        }
    }
    
    func fetchUnifiedSearchResult(
        libraryIds: Set<String>,
        search: String,
        sortBy: SortCriteria,
        sortAsc: Bool,
        filters: [String: Set<String>]
    ) throws -> UnifiedSearchResult? {
        let realm = try getRealm()
        
        let matchingObj = realm.objects(CalibreUnifiedSearchObject.self)
            .filter("search == %@ AND sortAsc == %@", search, sortAsc)
            .filter { $0.sortBy == sortBy }
            .filter { Set($0.libraryIds) == libraryIds }
            .first { cacheObj in
                let objFilters = cacheObj.filters.reduce(into: [String: Set<String>]()) { partial, filter in
                    if let values = filter.value?.values {
                        partial[filter.key] = Set(values)
                    }
                }
                return objFilters == filters
            }
            
        guard let obj = matchingObj else { return nil }
        return mapToUnifiedSearchResult(obj)
    }
    
    func saveUnifiedSearchResult(_ result: UnifiedSearchResult) throws {
        let realm = try getRealm()
        
        try realm.write {
            var unifiedObj = realm.objects(CalibreUnifiedSearchObject.self)
                .filter("search == %@ AND sortAsc == %@", result.search, result.sortAsc)
                .filter { $0.sortBy == result.sortBy }
                .filter { Set($0.libraryIds) == result.libraryIds }
                .first { cacheObj in
                    let objFilters = cacheObj.filters.reduce(into: [String: Set<String>]()) { partial, filter in
                        if let values = filter.value?.values {
                            partial[filter.key] = Set(values)
                        }
                    }
                    return objFilters == result.filters
                }
                
            if unifiedObj == nil {
                let newObj = CalibreUnifiedSearchObject()
                newObj.search = result.search
                newObj.sortBy = result.sortBy
                newObj.sortAsc = block_sortAsc(result.sortAsc)
                newObj.libraryIds.insert(objectsIn: result.libraryIds)
                result.filters.forEach { key, values in
                    let filterValues = CalibreLibrarySearchFilterValues()
                    filterValues.values.insert(objectsIn: values)
                    newObj.filters[key] = filterValues
                }
                realm.add(newObj)
                unifiedObj = newObj
            }
            
            guard let uObj = unifiedObj else { return }
            uObj.totalNumber = result.totalNumber
            uObj.limitNumber = result.limitNumber
            
            // Map unifiedOffsets
            // First, remove removed ones
            for key in Array(uObj.unifiedOffsets.keys) {
                if result.unifiedOffsets[key] == nil {
                    if let oldOffsetOpt = uObj.unifiedOffsets[key], let oldOffset = oldOffsetOpt {
                        realm.delete(oldOffset)
                    }
                    uObj.unifiedOffsets.removeObject(for: key)
                }
            }
            
            // Update or create offsets
            for (libraryId, offsetVal) in result.unifiedOffsets {
                var offsetObjOpt = uObj.unifiedOffsets[libraryId]
                if offsetObjOpt == nil {
                    let newOffset = CalibreUnifiedOffsets()
                    realm.add(newOffset)
                    uObj.unifiedOffsets[libraryId] = newOffset
                    offsetObjOpt = newOffset
                }
                
                guard let oObjOpt = offsetObjOpt, let oObj = oObjOpt else { continue }
                oObj.beenCutOff = offsetVal.beenCutOff
                oObj.beenConsumed = offsetVal.beenConsumed
                oObj.cutOffOffset = offsetVal.cutOffOffset
                oObj.offset = offsetVal.offset
                oObj.generation = offsetVal.generation
                oObj.searchObjectSource = offsetVal.searchObjectSource
                
                // Link to searchObject if library exists
                if let library = modelData.calibreLibraries[libraryId] {
                    // Try to find the matching library search object to link
                    let searchObj = realm.objects(CalibreLibrarySearchObject.self)
                        .filter("libraryId == %@ AND search == %@ AND sortAsc == %@", libraryId, result.search, result.sortAsc)
                        .filter { $0.sortBy == result.sortBy }
                        .first { cacheObj in
                            let objFilters = cacheObj.filters.reduce(into: [String: Set<String>]()) { partial, filter in
                                if let values = filter.value?.values {
                                    partial[filter.key] = Set(values)
                                }
                            }
                            return objFilters == result.filters
                        }
                    oObj.searchObject = searchObj
                }
            }
            
            // Update books list
            uObj.books.removeAll()
            for book in result.books {
                let unmanaged = book.managedObject()
                unmanaged.updatePrimaryKey()
                let managedBook = realm.create(CalibreBookRealm.self, value: unmanaged, update: .modified)
                uObj.books.append(managedBook)
            }
        }
    }
    
    private func block_sortAsc(_ val: Bool) -> Bool {
        return val
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
    
    func unifiedSearchResultPublisher(
        libraryIds: Set<String>,
        search: String,
        sortBy: SortCriteria,
        sortAsc: Bool,
        filters: [String: Set<String>]
    ) -> AnyPublisher<UnifiedSearchResult, Error> {
        let publisher = Deferred { () -> AnyPublisher<UnifiedSearchResult, Error> in
            do {
                let realm = try self.getRealm()
                let results = realm.objects(CalibreUnifiedSearchObject.self)
                    .filter("search == %@ AND sortAsc == %@", search, sortAsc)
                
                let mapped = results.changesetPublisher
                    .tryMap { [weak self] changeset -> UnifiedSearchResult? in
                        guard let self = self else { return nil }
                        
                        let collection: Results<CalibreUnifiedSearchObject>
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
                            .filter { Set($0.libraryIds) == libraryIds }
                            .first { cacheObj in
                                let objFilters = cacheObj.filters.reduce(into: [String: Set<String>]()) { partial, filter in
                                    if let values = filter.value?.values {
                                        partial[filter.key] = Set(values)
                                    }
                                }
                                return objFilters == filters
                            }
                        guard let obj = matched else { return nil }
                        return self.mapToUnifiedSearchResult(obj)
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
    
    private func mapToUnifiedSearchResult(_ unifiedObj: CalibreUnifiedSearchObject) -> UnifiedSearchResult {
        var unifiedOffsets: [String: MergeOffset] = [:]
        for offsetEntry in unifiedObj.unifiedOffsets {
            guard let offsetObj = offsetEntry.value else { continue }
            let libraryId = offsetEntry.key
            
            unifiedOffsets[libraryId] = MergeOffset(
                beenCutOff: offsetObj.beenCutOff,
                beenConsumed: offsetObj.beenConsumed,
                cutOffOffset: offsetObj.cutOffOffset,
                offset: offsetObj.offset,
                generation: offsetObj.generation,
                searchObjectSource: offsetObj.searchObjectSource
            )
        }
        
        let books = Array(unifiedObj.books.compactMap { (bookRealm: CalibreBookRealm) -> CalibreBook? in
            guard let serverUUID = bookRealm.serverUUID,
                  let libraryName = bookRealm.libraryName,
                  let library = self.modelData.calibreLibraries[CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName)]
            else {
                return nil
            }
            return CalibreBook(managedObject: bookRealm, library: library)
        })
        
        return UnifiedSearchResult(
            search: unifiedObj.search,
            sortBy: unifiedObj.sortBy,
            sortAsc: unifiedObj.sortAsc,
            filters: unifiedObj.filters.reduce(into: [:]) { partial, filter in
                if let values = filter.value?.values {
                    partial[filter.key] = Set(values)
                }
            },
            libraryIds: Set(unifiedObj.libraryIds),
            unifiedOffsets: unifiedOffsets,
            totalNumber: unifiedObj.totalNumber,
            limitNumber: unifiedObj.limitNumber,
            books: books
        )
    }
}
