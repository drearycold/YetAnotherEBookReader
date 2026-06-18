//
//  LibrarySearchService.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-11.
//

import Foundation
import RealmSwift

actor LibrarySearchService {
    private let service: CalibreServerService
    private let repository: SearchCacheRepository
    
    init(service: CalibreServerService, repository: SearchCacheRepository) {
        self.service = service
        self.repository = repository
    }
    
    private func getRealm() throws -> Realm {
        guard let conf = service.database.realmConf else {
            throw URLError(.cannotConnectToHost)
        }
        return try Realm(configuration: conf)
    }
    
    func getTargetSource(for library: CalibreLibrary) -> String {
        if library.server.isLocal {
            return URL(fileURLWithPath: "/realm").absoluteString
        } else {
            if let reachableUrl = service.getServerUrlByReachability(server: library.server) {
                return reachableUrl.absoluteString.replacingOccurrences(of: ".", with: "_")
            } else {
                return library.server.baseUrl.replacingOccurrences(of: ".", with: "_")
            }
        }
    }
    
    func searchAndFetchMetadata(
        library: CalibreLibrary,
        criteria: SearchCriteria,
        limit: Int,
        force: Bool
    ) async throws -> LibraryCachedResult {
        // Check cache first
        let cacheResult = try? repository.fetchLibraryCachedResult(
            libraryId: library.id,
            search: criteria.searchString,
            sortBy: criteria.sortCriteria.by,
            sortAsc: criteria.sortCriteria.ascending,
            filters: criteria.filterCriteriaCategory
        )
        
        let targetSource = getTargetSource(for: library)
        let sourceObj = cacheResult?.sources[targetSource]
        
        let needsFetch: Bool
        if force || sourceObj == nil || sourceObj!.generation < library.lastModified {
            needsFetch = true
        } else if sourceObj!.bookIds.count < limit && sourceObj!.bookIds.count < sourceObj!.totalNumber {
            needsFetch = true
        } else {
            needsFetch = false
        }
        
        if !needsFetch, let cached = cacheResult {
            return cached
        }
        
        // Build search parameters
        let offset = sourceObj?.bookIds.count ?? 0
        let numToFetch = limit - offset
        
        var parameters = [String: (generation: Date, num: Int, offset: Int)]()
        parameters[targetSource] = (generation: library.lastModified, num: numToFetch, offset: offset)
        
        let searchTasks = service.buildLibrarySearchTasks(library: library, searchCriteria: criteria, parameters: parameters)
        guard let task = searchTasks.first(where: {
            $0.serverUrl.absoluteString.replacingOccurrences(of: ".", with: "_") == targetSource
        }) else {
            throw SearchError.network("Could not build search task for source: \(targetSource)")
        }
        
        try Task.checkCancellation()
        
        var finalTask = task
        if task.booksListUrl.isHTTP {
            let session = service.urlSession(server: library.server)
            let (data, response) = try await session.data(from: task.booksListUrl)
            
            try Task.checkCancellation()
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw SearchError.network("Server returned invalid response code.")
            }
            
            do {
                finalTask.ajaxSearchResult = try JSONDecoder().decode(CalibreLibraryBooksResult.SearchResult.self, from: data)
            } catch {
                throw SearchError.network("Failed to decode search results: \(error.localizedDescription)")
            }
        } else if task.booksListUrl.isFileURL {
            finalTask = try performLocalSearch(task: task)
        }
        
        try Task.checkCancellation()
        
        guard let searchResult = finalTask.ajaxSearchResult else {
            throw SearchError.network("Search did not yield results.")
        }
        
        let serverUUID = library.server.uuid.uuidString
        let libraryName = library.name
        
        var toFetchIDs = [Int32]()
        
        var currentBookIds = sourceObj?.bookIds ?? []
        var currentBooks = sourceObj?.books ?? []
        
        if offset == currentBookIds.count {
            currentBookIds.append(contentsOf: searchResult.book_ids)
        } else {
            currentBookIds = searchResult.book_ids
            currentBooks = []
        }
        
        // We need to resolve what we already have in local Realm
        for bookId in currentBookIds[currentBooks.count...] {
            if let realmBook = try? getRealm().object(ofType: CalibreBookRealm.self, forPrimaryKey: CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName, id: bookId.description)) {
                let book = CalibreBook(managedObject: realmBook, library: library)
                currentBooks.append(book)
            } else {
                toFetchIDs.append(bookId)
            }
        }
        
        try Task.checkCancellation()
        
        if !toFetchIDs.isEmpty {
            let metadataTask = service.buildBooksMetadataTask(
                library: library,
                books: toFetchIDs.map { CalibreBook(id: $0, library: library) },
                getAnnotations: false
            )
            if let metadataTask = metadataTask {
                let completedTask = await service.getBooksMetadata(task: metadataTask)
                
                try Task.checkCancellation()
                
                if let entries = completedTask.booksMetadataEntry {
                    try writeMetadataToCache(library: library, entries: entries, json: completedTask.booksMetadataJSON)
                    
                    for bookId in toFetchIDs {
                        if let realmBook = try? getRealm().object(ofType: CalibreBookRealm.self, forPrimaryKey: CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName, id: bookId.description)) {
                            let book = CalibreBook(managedObject: realmBook, library: library)
                            currentBooks.append(book)
                        }
                    }
                }
            }
        }
        
        try Task.checkCancellation()
        
        let updatedSourceResult = LibrarySourceSearchResult(
            generation: library.lastModified,
            totalNumber: searchResult.total_num,
            bookIds: currentBookIds,
            books: currentBooks
        )
        
        try repository.saveLibrarySourceResult(
            libraryId: library.id,
            search: criteria.searchString,
            sortBy: criteria.sortCriteria.by,
            sortAsc: criteria.sortCriteria.ascending,
            filters: criteria.filterCriteriaCategory,
            sourceUrl: targetSource,
            result: updatedSourceResult
        )
        
        if let updatedCachedResult = try repository.fetchLibraryCachedResult(
            libraryId: library.id,
            search: criteria.searchString,
            sortBy: criteria.sortCriteria.by,
            sortAsc: criteria.sortCriteria.ascending,
            filters: criteria.filterCriteriaCategory
        ) {
            return updatedCachedResult
        }
        
        throw SearchError.database("Failed to fetch updated search result from cache.")
    }
    
    private func performLocalSearch(task: CalibreLibrarySearchTask) throws -> CalibreLibrarySearchTask {
        let realm = try getRealm()
        let libraryPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "serverUUID = %@", task.library.server.uuid.uuidString),
            NSPredicate(format: "libraryName = %@", task.library.name)
        ])
        
        var predicates = [NSPredicate]()
        let searchTerms = task.searchCriteria.searchString
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
        
        predicates = task.searchCriteria.filterCriteriaCategory.reduce(into: predicates) { partialResult, categoryFilter in
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
        
        let allbooks = realm.objects(CalibreBookRealm.self)
            .filter(libraryPredicate)
            .sorted(byKeyPath: task.searchCriteria.sortCriteria.by.sortKeyPath, ascending: task.searchCriteria.sortCriteria.ascending)
        let filteredBooks = allbooks.filter(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))
        
        let offset = task.offset
        let num = task.num
        
        var bookIds = [Int32]()
        if offset < filteredBooks.count {
            bookIds = filteredBooks[offset..<min(offset + num, filteredBooks.count)].map { $0.idInLib }
        }
        
        var completedTask = task
        completedTask.ajaxSearchResult = .init(
            total_num: filteredBooks.count,
            sort_order: task.searchCriteria.sortCriteria.ascending ? "asc" : "desc",
            num_books_without_search: allbooks.count,
            offset: task.offset,
            num: bookIds.count,
            sort: task.searchCriteria.sortCriteria.by.sortQueryParam,
            base_url: "",
            library_id: task.library.key,
            book_ids: bookIds,
            vl: ""
        )
        return completedTask
    }
    
    private func writeMetadataToCache(library: CalibreLibrary, entries: [String: CalibreBookEntry?], json: NSDictionary?) throws {
        let realm = try getRealm()
        let serverUUID = library.server.uuid.uuidString
        try realm.write {
            entries.forEach { key, entry in
                guard let entry = entry else { return }
                guard let bookId = Int32(key) else { return }
                let primaryKey = CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: library.name, id: bookId.description)
                
                let bookRealm = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey) ?? CalibreBookRealm()
                if bookRealm.realm == nil {
                    bookRealm.primaryKey = primaryKey
                    bookRealm.serverUUID = serverUUID
                    bookRealm.libraryName = library.name
                    bookRealm.idInLib = bookId
                    realm.add(bookRealm)
                }
                
                let bookRoot = json?[key] as? NSDictionary ?? NSDictionary()
                self.service.handleLibraryBookOne(library: library, bookRealm: bookRealm, entry: entry, root: bookRoot)
            }
        }
    }
}
