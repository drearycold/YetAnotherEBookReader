//
//  CalibreServerService+LibrarySync.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026/6/17.
//

import Foundation
import Combine

extension CalibreServerService {
    func syncLibrary(resultPrev: CalibreSyncLibraryResult, order: String = "ascending", filter: String = "", limit: Int = -1) async -> CalibreSyncLibraryResult {
        do {
            let endpointURL = try makeEndpointURL(
                server: resultPrev.request.library.server,
                path: "/cdb/cmd/list/\(resultPrev.request.library.key)"
            )

            let payload: [String: Any] = [
                "args": [
                    "[\"last_modified\"]",
                    filter,
                    order
                ],
                "kwargs": [:]
            ]

            let body = try JSONSerialization.data(withJSONObject: payload, options: [])
            let request = makeJSONRequest(url: endpointURL, method: "POST", body: body)

            let startDatetime = Date()
            await logger.logStartCalibreActivity(type: "Sync Library Books", request: request, startDatetime: startDatetime, bookId: nil, libraryId: resultPrev.request.library.id)

            var result = resultPrev
            defer {
                Task {
                    await self.logger.logFinishCalibreActivity(type: "Sync Library Books", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: result.list.book_ids.first == -1 ? result.errmsg : "Success")
                }
            }

            let (data, _) = try await validatedData(for: request, server: resultPrev.request.library.server)
            result.list = try decodePayload(CalibreCdbCmdListResult.self, from: data)
            result.errmsg = ""
            return result
        } catch {
            var result = resultPrev
            result.errmsg = CalibreAPIError(error: error).localizedDescription
            return result
        }
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
            return task
        }
    }

    func getCustomColumns(request: CalibreSyncLibraryRequest) async -> CalibreSyncLibraryResult {
        let errorResult: [String: [String: CalibreCustomColumnInfo]] = ["error": [:]]

        do {
            let url = try makeEndpointURL(
                server: request.library.server,
                path: "/cdb/cmd/custom_columns/\(request.library.key)"
            )
            let (data, _) = try await validatedData(from: url, server: request.library.server)
            let result = try decodePayload([String: [String: CalibreCustomColumnInfo]].self, from: data)
            return CalibreSyncLibraryResult(request: request, result: result)
        } catch {
            return CalibreSyncLibraryResult(request: request, result: errorResult)
        }
    }

    func getLibraryCategories(resultPrev: CalibreSyncLibraryResult) async -> CalibreSyncLibraryResult {
        do {
            let endpointURL = try makeEndpointURL(
                server: resultPrev.request.library.server,
                path: "ajax/categories/\(resultPrev.request.library.key)"
            )
            let (data, _) = try await validatedData(from: endpointURL, server: resultPrev.request.library.server)
            var result = resultPrev
            result.categories = try decodePayload([CalibreLibraryCategory].self, from: data)
            result.errmsg = ""
            return result
        } catch {
            var result = resultPrev
            result.errmsg = CalibreAPIError(error: error).localizedDescription
            return result
        }
    }

    func syncLibraryPublisher(resultPrev: CalibreSyncLibraryResult, order: String = "ascending", filter: String = "", limit: Int = -1) -> AnyPublisher<CalibreSyncLibraryResult, Never> {
        do {
            let endpointURL = try makeEndpointURL(
                server: resultPrev.request.library.server,
                path: "/cdb/cmd/list/0",
                queryItems: [URLQueryItem(name: "library_id", value: resultPrev.request.library.key)]
            )

            let payload: [Any] = [["last_modified"], "last_modified", order, filter, limit]
            let body = try JSONSerialization.data(withJSONObject: payload, options: [])
            let request = makeJSONRequest(
                url: endpointURL,
                method: "POST",
                body: body,
                acceptEncoding: "gzip"
            )

            let startDatetime = Date()
            Task { [weak self] in
                await self?.logger.logStartCalibreActivity(type: "Sync Library Books", request: request, startDatetime: startDatetime, bookId: nil, libraryId: resultPrev.request.library.id)
            }

            return validatedDataPublisher(for: request, server: resultPrev.request.library.server)
                .tryMap { data, _ in
                    try self.decodePayload([String: CalibreCdbCmdListResult].self, from: data)
                }
                .mapError(CalibreAPIError.init(error:))
                .map { [weak self] listResult -> CalibreSyncLibraryResult in
                    var result = resultPrev
                    if let list = listResult["result"] {
                        result.list = list
                    }
                    Task { [weak self] in
                        await self?.logger.logFinishCalibreActivity(type: "Sync Library Books", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: result.list.book_ids.first == -1 ? "Failure" : "Success")
                    }
                    return result
                }
                .catch { [weak self] error -> Just<CalibreSyncLibraryResult> in
                    var result = resultPrev
                    result.errmsg = error.localizedDescription
                    Task { [weak self] in
                        await self?.logger.logFinishCalibreActivity(type: "Sync Library Books", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: result.errmsg)
                    }
                    return Just(result)
                }
                .eraseToAnyPublisher()
        } catch {
            var result = resultPrev
            result.errmsg = CalibreAPIError(error: error).localizedDescription
            return Just(result).eraseToAnyPublisher()
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

    func getBooksMetadata(task: CalibreBooksTask, qos: DispatchQoS.QoSClass = .default) -> AnyPublisher<CalibreBooksTask, URLError> {
        guard let metadataUrl = task.metadataUrl,
              metadataUrl.isHTTP,
              task.books.isEmpty == false else {
            return Just(task).setFailureType(to: URLError.self).eraseToAnyPublisher()
        }

        return validatedDataPublisher(from: metadataUrl, server: task.library.server, qos: qos)
            .map { data, response -> CalibreBooksTask in
                var resultTask = task
                resultTask.data = data
                resultTask.response = response
                return self.applyBooksMetadataPayload(data, to: resultTask)
            }
            .mapError(\.asURLError)
            .eraseToAnyPublisher()
    }

    func getCustomColumnsPublisher(request: CalibreSyncLibraryRequest) -> AnyPublisher<CalibreSyncLibraryResult, Never> {
        let errorResult: [String: [String: CalibreCustomColumnInfo]] = ["error": [:]]

        do {
            let endpointURL = try makeEndpointURL(
                server: request.library.server,
                path: "/cdb/cmd/custom_columns/0",
                queryItems: [URLQueryItem(name: "library_id", value: request.library.key)]
            )
            let urlRequest = makeJSONRequest(
                url: endpointURL,
                method: "POST",
                body: Data("[]".utf8)
            )

            return validatedDataPublisher(for: urlRequest, server: request.library.server)
                .tryMap { data, _ in
                    try self.decodePayload([String: [String: CalibreCustomColumnInfo]].self, from: data)
                }
                .mapError(CalibreAPIError.init(error:))
                .map {
                    CalibreSyncLibraryResult(request: request, result: $0)
                }
                .catch { error in
                    var result = CalibreSyncLibraryResult(request: request, result: errorResult)
                    result.errmsg = error.localizedDescription
                    return Just(result)
                }
                .eraseToAnyPublisher()
        } catch {
            var result = CalibreSyncLibraryResult(request: request, result: errorResult)
            result.errmsg = CalibreAPIError(error: error).localizedDescription
            return Just(result).eraseToAnyPublisher()
        }
    }

    func getLibraryCategoriesPublisher(resultPrev: CalibreSyncLibraryResult) -> AnyPublisher<CalibreSyncLibraryResult, Never> {
        do {
            let endpointURL = try makeEndpointURL(
                server: resultPrev.request.library.server,
                path: "ajax/categories/\(resultPrev.request.library.key)"
            )

            return validatedDataPublisher(from: endpointURL, server: resultPrev.request.library.server)
                .tryMap { data, _ in
                    try self.decodePayload([CalibreLibraryCategory].self, from: data)
                }
                .mapError(CalibreAPIError.init(error:))
                .map { categories -> CalibreSyncLibraryResult in
                    var result = resultPrev
                    result.categories = categories
                    return result
                }
                .catch { _ in
                    Just(resultPrev)
                }
                .eraseToAnyPublisher()
        } catch {
            return Just(resultPrev).eraseToAnyPublisher()
        }
    }

    private func applyBooksMetadataPayload(_ data: Data, to task: CalibreBooksTask) -> CalibreBooksTask {
        var task = task

        task.booksMetadataJSON = try? JSONSerialization.jsonObject(with: data, options: []) as? NSDictionary

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
        } catch {
            if task.books.count == 1 {
                task.booksError.formUnion(task.books)
            }
        }

        if let entries = try? JSONDecoder().decode([String: CalibreBookEntry].self, from: data) {
            task.booksMetadataEntry = entries
        }

        return task
    }
}
