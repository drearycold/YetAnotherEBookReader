//
//  CalibreServerService+LibrarySync.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026/6/17.
//

import Foundation

extension CalibreServerService {
    /// What the app keeps about a library besides its books, read with the requests browsing makes:
    /// - `ajax/search`, newest change first, for the number of books and the most recently
    ///   changed one;
    /// - `ajax/books` for that book's `last_modified` and its `user_metadata`, which describes every
    ///   custom column of the library: calibre sets each one on every book, valued or not.
    ///
    /// Unlike calibre's `cdb` interface, both answer a user with per-library restrictions, counting
    /// only the books that user may see.
    func getLibrarySummary(library: CalibreLibrary) async throws -> CalibreLibrarySummary {
        let searchURL = try makeEndpointURL(
            server: library.server,
            path: "/ajax/search/\(library.key)",
            queryItems: [
                URLQueryItem(name: "sort", value: SortCriteria.Modified.sortQueryParam),
                URLQueryItem(name: "sort_order", value: "desc"),
                URLQueryItem(name: "num", value: "1")
            ]
        )
        let request = URLRequest(url: searchURL)
        let startDatetime = Date()
        await logger.logStartCalibreActivity(type: "Library Summary", request: request, startDatetime: startDatetime, bookId: nil, libraryId: library.id)

        do {
            let (searchData, _) = try await validatedData(for: request, server: library.server)
            let search = try decodePayload(CalibreLibraryBooksResult.SearchResult.self, from: searchData)
            var summary = CalibreLibrarySummary(bookCount: search.num_books_without_search)

            if let bookId = search.book_ids.first {
                let booksURL = try makeEndpointURL(
                    server: library.server,
                    path: "/ajax/books/\(library.key)",
                    queryItems: [
                        URLQueryItem(name: "ids", value: bookId.description),
                        URLQueryItem(name: "category_urls", value: "false")
                    ]
                )
                let (booksData, _) = try await validatedData(from: booksURL, server: library.server)
                let books = try decodePayload([String: CalibreLibrarySummaryBookEntry?].self, from: booksData)
                // The book can be deleted between the two requests.
                if let entry = books[bookId.description] ?? nil {
                    summary.lastModified = parseLastModified(entry.last_modified)
                    summary.customColumnInfos = entry.user_metadata.values.reduce(into: [:]) {
                        $0[$1.label] = CalibreCustomColumnInfo(userMetadata: $1)
                    }
                }
            }

            await logger.logFinishCalibreActivity(type: "Library Summary", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: "Success")
            return summary
        } catch {
            let apiError = CalibreAPIError(error: error)
            await logger.logFinishCalibreActivity(type: "Library Summary", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: apiError.localizedDescription)
            throw apiError
        }
    }

    func getLibraryCategories(library: CalibreLibrary) async throws -> [CalibreLibraryCategory] {
        let endpointURL = try makeEndpointURL(
            server: library.server,
            path: "/ajax/categories/\(library.key)"
        )
        let (data, _) = try await validatedData(from: endpointURL, server: library.server)
        return try decodePayload([CalibreLibraryCategory].self, from: data)
    }

    func getBooksMetadata(task: CalibreBooksTask, qos: DispatchQoS.QoSClass = .default) async -> CalibreBooksTask {
        guard let metadataUrl = task.metadataUrl,
              metadataUrl.isHTTP,
              task.books.isEmpty == false else {
            return task
        }

        do {
            let (data, response) = try await validatedData(from: metadataUrl, server: task.library.server, qos: qos)
            var resultTask = task
            resultTask.data = data
            resultTask.response = response
            return applyBooksMetadataPayload(data, to: resultTask)
        } catch {
            var resultTask = task
            resultTask.error = CalibreAPIError(error: error)
            return resultTask
        }
    }

    func buildBooksMetadataTask(library: CalibreLibrary, books: [CalibreBook], getAnnotations: Bool = false, searchTask: CalibreLibrarySearchTask? = nil) -> CalibreBooksTask? {
        let serverUrl = getServerUrlByReachability(server: library.server) ?? URL(fileURLWithPath: "/realm")

        let bookIds = books.map { $0.id.description }

        var urlComponents = URLComponents()
        urlComponents.path = "/ajax/books/\(library.key)"
        urlComponents.queryItems = [
            URLQueryItem(name: "ids", value: bookIds.joined(separator: ","))
        ]
        guard let endpointUrl = urlComponents.url(relativeTo: serverUrl) else {
            return nil
        }

        let which = books.map { [weak self] book in
            let id = book.id.description
            if book.inShelf {
                return book.formats.filter { $0.value.cached }.map { "\(id)-\($0.key)" }.joined(separator: "_")
            }
            if let format = self?.getPreferredFormat(for: book) {
                return "\(id)-\(format.rawValue)"
            }
            return ""
        }.joined(separator: "_")

        var lastReadPositionUrlComponents = URLComponents()
        lastReadPositionUrlComponents.path = "/book-get-last-read-position/\(library.key)/\(which)"
        guard let lastReadPositionEndpointUrl = lastReadPositionUrlComponents.url(relativeTo: serverUrl) else {
            return nil
        }

        var annotationsUrlComponents = URLComponents()
        annotationsUrlComponents.path = "/book-get-annotations/\(library.key)/\(which)"
        guard let annotationsEndpointUrl = annotationsUrlComponents.url(relativeTo: serverUrl) else {
            return nil
        }

        return CalibreBooksTask(
            request: .init(library: library, books: books.map { $0.id }, getAnnotations: getAnnotations),
            metadataUrl: endpointUrl,
            lastReadPositionUrl: lastReadPositionEndpointUrl,
            annotationsUrl: annotationsEndpointUrl,
            searchTask: searchTask
        )
    }

    private func applyBooksMetadataPayload(_ data: Data, to task: CalibreBooksTask) -> CalibreBooksTask {
        var task = task

        do {
            task.booksMetadataJSON = try JSONSerialization.jsonObject(with: data, options: []) as? NSDictionary
        } catch {
            task.error = CalibreAPIError(error: error)
        }

        do {
            task.booksMetadataEntry = try JSONDecoder().decode([String: CalibreBookEntry?].self, from: data)
        } catch let DecodingError.keyNotFound(_, context) {
            if let firstCodingPath = context.codingPath.first,
               let bookId = Int32(firstCodingPath.stringValue),
               bookId > 0 {
                task.booksError.insert(bookId)
            } else if task.books.count == 1 {
                task.booksError.formUnion(task.books)
            }
            if let lastCodingPath = context.codingPath.last {
                task.error = CalibreAPIError(error: DecodingError.keyNotFound(lastCodingPath, context))
            } else {
                task.error = CalibreAPIError(error: DecodingError.keyNotFound(context.codingPath.first!, context))
            }
        } catch {
            if task.books.count == 1 {
                task.booksError.formUnion(task.books)
            }
            task.error = CalibreAPIError(error: error)
        }

        if let entries = try? JSONDecoder().decode([String: CalibreBookEntry].self, from: data) {
            task.booksMetadataEntry = entries
        }

        return task
    }
}
