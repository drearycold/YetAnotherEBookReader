//
//  LibrarySearchService.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-11.
//

import Foundation

actor LibrarySearchService {
    private let service: CalibreServerService
    private let repository: SearchCacheRepository

    init(service: CalibreServerService, repository: SearchCacheRepository) {
        self.service = service
        self.repository = repository
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
        force: Bool,
        forceMetadataRefresh: Bool = false
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

        let isStaleGeneration = sourceObj.map { $0.generation < library.lastModified } ?? false
        let shouldRebuildCache = force || sourceObj == nil || isStaleGeneration
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

            _ = try await refreshMetadata(library: library, bookIds: refreshIDs)

            if let updatedCachedResult = try repository.fetchLibraryCachedResult(
                libraryId: library.id,
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
            library: library,
            criteria: criteria,
            targetSource: targetSource,
            num: max(limit - offset, 0),
            offset: offset
        )

        if !shouldRebuildCache,
           offset > 0,
           let sourceObj,
           shouldRebuildAfterIncrementalFetch(source: sourceObj, searchResult: searchResult) {
            offset = 0
            searchResult = try await fetchSearchResult(
                library: library,
                criteria: criteria,
                targetSource: targetSource,
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
        let existingBooks = try repository.fetchBooks(library: library, bookIds: currentBookIds)
        booksById.merge(existingBooks) { _, new in new }

        if forceMetadataRefresh {
            toFetchIDs = offset == 0 ? currentBookIds : newlyFetchedBookIds
        } else if isStaleGeneration {
            toFetchIDs = currentBookIds
        } else {
            toFetchIDs = metadataRefreshIDs(bookIds: currentBookIds, booksById: booksById)
        }

        try Task.checkCancellation()

        if !toFetchIDs.isEmpty {
            let fetchedBooks = try await refreshMetadata(library: library, bookIds: toFetchIDs)
            for (bookId, book) in fetchedBooks {
                booksById[bookId] = book
            }
        }

        try Task.checkCancellation()

        let currentBooks = currentBookIds.compactMap { booksById[$0] }

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

    private func fetchSearchResult(
        library: CalibreLibrary,
        criteria: SearchCriteria,
        targetSource: String,
        num: Int,
        offset: Int
    ) async throws -> CalibreLibraryBooksResult.SearchResult {
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
                let (data, _) = try await service.validatedData(from: task.booksListUrl, server: library.server)
                try Task.checkCancellation()

                finalTask.ajaxSearchResult = try service.decodePayload(CalibreLibraryBooksResult.SearchResult.self, from: data)
            } catch is CancellationError {
                throw SearchError.cancelled
            } catch {
                try Task.checkCancellation()
                let calibreError = CalibreAPIError(error: error)
                throw SearchError.network(calibreError)
            }
        } else if task.booksListUrl.isFileURL {
            finalTask = try performLocalSearch(task: task)
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

    private func refreshMetadata(
        library: CalibreLibrary,
        bookIds: [Int32]
    ) async throws -> [Int32: CalibreBook] {
        guard !bookIds.isEmpty else { return [:] }

        let metadataTask = service.buildBooksMetadataTask(
            library: library,
            books: bookIds.map { CalibreBook(id: $0, library: library) },
            getAnnotations: false
        )
        guard let metadataTask else { return [:] }

        let completedTask = await service.getBooksMetadata(task: metadataTask)

        try Task.checkCancellation()

        guard let entries = completedTask.booksMetadataEntry else { return [:] }
        try repository.writeMetadataEntries(
            library: library,
            entries: entries,
            json: completedTask.booksMetadataJSON
        )

        return try repository.fetchBooks(library: library, bookIds: bookIds)
    }

    private func performLocalSearch(task: CalibreLibrarySearchTask) throws -> CalibreLibrarySearchTask {
        let result = try repository.searchLocalLibrary(
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
