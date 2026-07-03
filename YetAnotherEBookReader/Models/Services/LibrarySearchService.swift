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

        var toFetchIDs = [Int32]()

        var currentBookIds = sourceObj?.bookIds ?? []
        var currentBooks = sourceObj?.books ?? []

        if offset == currentBookIds.count {
            currentBookIds.append(contentsOf: searchResult.book_ids)
        } else {
            currentBookIds = searchResult.book_ids
            currentBooks = []
        }

        let unresolvedBookIds = Array(currentBookIds[currentBooks.count...])
        let existingBooks = try repository.fetchBooks(library: library, bookIds: unresolvedBookIds)
        for bookId in unresolvedBookIds {
            if let book = existingBooks[bookId] {
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
                    try repository.writeMetadataEntries(
                        library: library,
                        entries: entries,
                        json: completedTask.booksMetadataJSON
                    )

                    let fetchedBooks = try repository.fetchBooks(library: library, bookIds: toFetchIDs)
                    for bookId in toFetchIDs {
                        if let book = fetchedBooks[bookId] {
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
