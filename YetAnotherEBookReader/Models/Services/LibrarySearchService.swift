//
//  LibrarySearchService.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-11.
//

import Foundation

actor LibrarySearchService {
    /// Called with the books an `ajax/books` answer had null (`missing`) or an entry for (`present`).
    typealias MetadataAnswersHandler = @Sendable (
        _ library: CalibreLibrary, _ missing: Set<Int32>, _ present: Set<Int32>, _ cache: SearchCacheRepository
    ) async -> Void

    struct Request: Sendable {
        let library: CalibreLibrary
        let cache: SearchCacheRepository
        let url: URL?
        let source: String
    }

    private let service: CalibreServerService
    private let repository: SearchCacheRepository
    private let onMetadataAnswers: MetadataAnswersHandler?

    init(service: CalibreServerService, repository: SearchCacheRepository, onMetadataAnswers: MetadataAnswersHandler? = nil) {
        self.service = service
        self.repository = repository
        self.onMetadataAnswers = onMetadataAnswers
    }

    private func targetURL(for library: CalibreLibrary) -> URL? {
        if library.server.isLocal { return URL(fileURLWithPath: "/realm") }
        return service.getServerUrlByReachability(server: library.server) ?? URL(string: library.server.baseUrl)
    }

    func getTargetSource(for library: CalibreLibrary) -> String {
        (targetURL(for: library)?.absoluteString ?? library.server.baseUrl).replacingOccurrences(of: ".", with: "_")
    }

    func prepareRequest(library: CalibreLibrary, cache: SearchCacheRepository? = nil) throws -> Request {
        try Task.checkCancellation()
        let database = try (cache ?? repository.snapshot())
        let lifetime = try service.cacheLifetime(for: library)
        let scope = try database.scoped(to: library, lifetime: lifetime)
        let url = targetURL(for: library)
        let source = (url?.absoluteString ?? library.server.baseUrl).replacingOccurrences(of: ".", with: "_")
        return Request(library: library, cache: scope, url: url, source: source)
    }

    func searchAndFetchMetadata(
        library: CalibreLibrary,
        criteria: SearchCriteria,
        limit: Int,
        force: Bool,
        forceMetadataRefresh: Bool = false
    ) async throws -> LibraryCachedResult {
        let request = try prepareRequest(library: library)
        return try await searchAndFetchMetadata(request: request, criteria: criteria, limit: limit,
                                                force: force, forceMetadataRefresh: forceMetadataRefresh)
    }

    func searchAndFetchMetadata(
        request: Request, criteria: SearchCriteria, limit: Int, force: Bool, forceMetadataRefresh: Bool
    ) async throws -> LibraryCachedResult {
        let library = request.library
        let cache = request.cache
        let targetSource = request.source
        let cacheResult = try cache.fetchLibraryCachedResult(
            library: library,
            search: criteria.searchString,
            sortBy: criteria.sortCriteria.by,
            sortAsc: criteria.sortCriteria.ascending,
            filters: criteria.filterCriteriaCategory
        )
        let sourceObj = cacheResult?.sources[targetSource]

        let isStaleGeneration = sourceObj.map { $0.generation < library.lastModified } ?? false
        // Local imports/deletions change the database without a server generation change.
        // Read the current local ids, including after a previously empty search.
        let shouldRebuildCache = force || library.server.isLocal || sourceObj == nil || isStaleGeneration
        let needsFetch: Bool
        if shouldRebuildCache {
            needsFetch = true
        } else if sourceObj!.bookIds.count < limit && sourceObj!.bookIds.count < sourceObj!.totalNumber {
            needsFetch = true
        } else {
            needsFetch = false
        }

        if !needsFetch, let cached = cacheResult, let sourceObj {
            let booksById = sourceObj.books.reduce(into: [Int32: CalibreBook]()) { partialResult, book in
                partialResult[book.id] = book
            }
            let loadedBookIds = Array(sourceObj.bookIds.prefix(limit))
            let refreshIDs = forceMetadataRefresh
                ? loadedBookIds
                : metadataRefreshIDs(bookIds: sourceObj.bookIds, booksById: booksById)
            guard !refreshIDs.isEmpty else {
                return cached
            }

            _ = try await refreshMetadata(request: request, bookIds: refreshIDs,
                                          retainingExisting: Set(booksById.keys))

            if let updatedCachedResult = try cache.fetchLibraryCachedResult(
                library: library,
                search: criteria.searchString,
                sortBy: criteria.sortCriteria.by,
                sortAsc: criteria.sortCriteria.ascending,
                filters: criteria.filterCriteriaCategory
            ) {
                return updatedCachedResult
            }

            return cached
        }

        var offset = shouldRebuildCache ? 0 : (sourceObj?.bookIds.count ?? 0)
        var searchResult = try await fetchSearchResult(
            request: request,
            criteria: criteria,
            num: max(limit - offset, 0),
            offset: offset
        )

        if !shouldRebuildCache,
           offset > 0,
           let sourceObj,
           shouldRebuildAfterIncrementalFetch(source: sourceObj, searchResult: searchResult) {
            offset = 0
            searchResult = try await fetchSearchResult(
                request: request,
                criteria: criteria,
                num: limit,
                offset: offset
            )
        }

        var toFetchIDs = [Int32]()

        var currentBookIds = offset == 0 ? [] : (sourceObj?.bookIds ?? [])
        let cachedBooksById = (offset == 0 ? [] : (sourceObj?.books ?? [])).reduce(into: [Int32: CalibreBook]()) { partialResult, book in
            if partialResult[book.id] == nil {
                partialResult[book.id] = book
            }
        }

        if offset == currentBookIds.count {
            currentBookIds.append(contentsOf: searchResult.book_ids)
        } else {
            currentBookIds = searchResult.book_ids
        }

        currentBookIds = currentBookIds.uniquedPreservingOrder()
        let newlyFetchedBookIds = searchResult.book_ids.uniquedPreservingOrder()

        var booksById = cachedBooksById
        let existingBooks = try cache.fetchBooks(library: library, bookIds: currentBookIds)
        booksById.merge(existingBooks) { _, new in new }

        if forceMetadataRefresh {
            toFetchIDs = offset == 0 ? currentBookIds : newlyFetchedBookIds
        } else if isStaleGeneration {
            toFetchIDs = currentBookIds
        } else {
            toFetchIDs = metadataRefreshIDs(bookIds: currentBookIds, booksById: booksById)
        }

        try Task.checkCancellation()

        var metadataComplete = true
        if !toFetchIDs.isEmpty {
            let refreshed = try await refreshMetadata(request: request, bookIds: toFetchIDs,
                                                       retainingExisting: Set(existingBooks.keys))
            for (bookId, book) in refreshed.books {
                booksById[bookId] = book
            }
            metadataComplete = refreshed.complete
        }

        try Task.checkCancellation()

        let currentBooks = currentBookIds.compactMap { booksById[$0] }

        let updatedSourceResult = LibrarySourceSearchResult(
            // Until the books' metadata is all read, the cache keeps the generation it had, so the
            // next search reads it again.
            generation: metadataComplete ? library.lastModified : (sourceObj?.generation ?? Date(timeIntervalSince1970: 0)),
            totalNumber: searchResult.total_num,
            bookIds: currentBookIds,
            books: currentBooks
        )

        try cache.saveLibrarySourceResult(
            libraryId: library.id,
            search: criteria.searchString,
            sortBy: criteria.sortCriteria.by,
            sortAsc: criteria.sortCriteria.ascending,
            filters: criteria.filterCriteriaCategory,
            sourceUrl: targetSource,
            result: updatedSourceResult,
            expecting: .previous(sourceObj?.sourceState)
        )

        if let updatedCachedResult = try cache.fetchLibraryCachedResult(
            library: library,
            search: criteria.searchString,
            sortBy: criteria.sortCriteria.by,
            sortAsc: criteria.sortCriteria.ascending,
            filters: criteria.filterCriteriaCategory
        ) {
            return updatedCachedResult
        }

        throw SearchError.database("Failed to fetch updated search result from cache.")
    }

    private func fetchSearchResult(
        request: Request,
        criteria: SearchCriteria,
        num: Int,
        offset: Int
    ) async throws -> CalibreLibraryBooksResult.SearchResult {
        try request.cache.checkCurrent()
        let library = request.library
        let targetSource = request.source
        var parameters = [String: (generation: Date, num: Int, offset: Int)]()
        parameters[targetSource] = (generation: library.lastModified, num: num, offset: offset)

        let searchTasks = service.buildLibrarySearchTasks(library: library, searchCriteria: criteria, parameters: parameters)
        guard let task = searchTasks.first(where: {
            $0.serverUrl.absoluteString.replacingOccurrences(of: ".", with: "_") == targetSource
        }) else {
            throw SearchError.invalidState("Could not build search task for source: \(targetSource)")
        }

        try Task.checkCancellation()

        var finalTask = task
        if task.booksListUrl.isHTTP {
            do {
                finalTask.ajaxSearchResult = try await service.withRequestActivity(
                    .search, request: URLRequest(url: task.booksListUrl), server: library.server, libraryId: library.id
                ) { data, response in
                    try Task.checkCancellation()
                    try service.requireJSON(response)
                    return try service.decodePayload(CalibreLibraryBooksResult.SearchResult.self, from: data)
                }
            } catch is CancellationError {
                throw SearchError.cancelled
            } catch {
                try Task.checkCancellation()
                let calibreError = CalibreAPIError(error: error)
                throw SearchError.network(calibreError)
            }
        } else if task.booksListUrl.isFileURL {
            finalTask = try performLocalSearch(task: task, cache: request.cache)
        }

        try Task.checkCancellation()

        guard let searchResult = finalTask.ajaxSearchResult else {
            throw SearchError.invalidState("Search did not yield results.")
        }
        return searchResult
    }

    private func shouldRebuildAfterIncrementalFetch(
        source: LibrarySourceSearchResult,
        searchResult: CalibreLibraryBooksResult.SearchResult
    ) -> Bool {
        if source.totalNumber != searchResult.total_num {
            return true
        }

        let existingIds = Set(source.bookIds)
        return searchResult.book_ids.contains { existingIds.contains($0) }
    }

    private func metadataRefreshIDs(bookIds: [Int32], booksById: [Int32: CalibreBook]) -> [Int32] {
        bookIds.filter { bookId in
            guard let book = booksById[bookId] else { return true }
            return book.needsMetadataRefresh
        }
    }

    /// Reads the books' metadata from calibre, in batches (`booksMetadataBatchSize`). `complete` is
    /// false when a request failed, so the caller doesn't take the books for up to date.
    private func refreshMetadata(
        request: Request,
        bookIds: [Int32],
        retainingExisting: Set<Int32>
    ) async throws -> (books: [Int32: CalibreBook], complete: Bool) {
        guard !bookIds.isEmpty else { return ([:], true) }
        let library = request.library
        let cache = request.cache

        var complete = true
        for batch in bookIds.chunks(size: CalibreServerService.booksMetadataBatchSize) {
            try Task.checkCancellation()
            try cache.checkCurrent()
            let before = try cache.fetchBooks(library: library, bookIds: batch)
            guard let metadataTask = service.buildBooksMetadataTask(
                library: library,
                books: batch.map { CalibreBook(id: $0, library: library) },
                getAnnotations: false,
                serverURL: request.url
            ) else {
                complete = false
                continue
            }

            let completedTask = await service.getBooksMetadata(task: metadataTask)

            try Task.checkCancellation()

            guard let entries = completedTask.booksMetadataEntry else {
                // An answer that couldn't be read won't read better next time; one that didn't
                // arrive might.
                if completedTask.data == nil {
                    complete = false
                }
                continue
            }
            if !completedTask.invalidMetadataIDs.isEmpty {
                complete = false
            }
            try cache.writeMetadataEntries(
                library: library,
                entries: entries,
                json: completedTask.booksMetadataJSON,
                retainingExisting: retainingExisting.union(before.keys),
                metadataBaseline: before.mapValues(\.lastUpdated)
            )

            if let onMetadataAnswers {
                var missing = Set<Int32>()
                var present = Set<Int32>()
                let nullIDs = entries.compactMap { key, entry in entry == nil ? Int32(key) : nil }
                let after = try cache.fetchBooks(library: library, bookIds: nullIDs)
                for (key, entry) in entries {
                    guard let bookId = Int32(key) else { continue }
                    if entry == nil {
                        if before[bookId]?.lastUpdated == after[bookId]?.lastUpdated,
                           before[bookId]?.lastModified == after[bookId]?.lastModified {
                            missing.insert(bookId)
                        }
                    } else {
                        present.insert(bookId)
                    }
                }
                await onMetadataAnswers(library, missing, present, cache)
            }
        }

        return (try cache.fetchBooks(library: library, bookIds: bookIds), complete)
    }

    private func performLocalSearch(task: CalibreLibrarySearchTask, cache: SearchCacheRepository) throws -> CalibreLibrarySearchTask {
        let result = try cache.searchLocalLibrary(
            library: task.library,
            criteria: task.searchCriteria,
            offset: task.offset,
            limit: task.num
        )

        var completedTask = task
        completedTask.ajaxSearchResult = .init(
            total_num: result.totalNumber,
            sort_order: task.searchCriteria.sortCriteria.ascending ? "asc" : "desc",
            num_books_without_search: result.numBooksWithoutSearch,
            offset: result.offset,
            num: result.num,
            sort: result.sort,
            base_url: "",
            library_id: task.library.key,
            book_ids: result.bookIds,
            vl: ""
        )
        return completedTask
    }
}

private extension Array where Element: Hashable {
    func uniquedPreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
