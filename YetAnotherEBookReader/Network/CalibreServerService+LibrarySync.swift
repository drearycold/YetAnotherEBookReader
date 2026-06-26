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
            var resultTask = task
            resultTask.error = CalibreAPIError(error: error)
            return resultTask
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

    func syncLibraryPublisher(resultPrev: CalibreSyncLibraryResult, order: String = "ascending", filter: String = "", limit: Int = -1) -> AnyPublisher<CalibreSyncLibraryResult, CalibreAPIError> {
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
                .handleEvents(receiveOutput: { [weak self] listResult in
                    let errMsg = (listResult["result"]?.book_ids.first == -1) ? "Failure" : "Success"
                    Task { [weak self] in
                        await self?.logger.logFinishCalibreActivity(type: "Sync Library Books", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: errMsg)
                    }
                }, receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        Task { [weak self] in
                            await self?.logger.logFinishCalibreActivity(type: "Sync Library Books", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: error.localizedDescription)
                        }
                    }
                })
                .map { listResult -> CalibreSyncLibraryResult in
                    var result = resultPrev
                    if let list = listResult["result"] {
                        result.list = list
                    }
                    return result
                }
                .eraseToAnyPublisher()
        } catch {
            return Fail(error: CalibreAPIError(error: error)).eraseToAnyPublisher()
        }
    }

    @available(*, deprecated, message: "Use CalibreAPIError version instead")
    func syncLibraryPublisher(resultPrev: CalibreSyncLibraryResult, order: String = "ascending", filter: String = "", limit: Int = -1) -> AnyPublisher<CalibreSyncLibraryResult, Never> {
        let typedPublisher: AnyPublisher<CalibreSyncLibraryResult, CalibreAPIError> = syncLibraryPublisher(resultPrev: resultPrev, order: order, filter: filter, limit: limit)
        return typedPublisher
            .catch { [weak self] error -> Just<CalibreSyncLibraryResult> in
                var result = resultPrev
                result.errmsg = error.localizedDescription
                return Just(result)
            }
            .eraseToAnyPublisher()
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

    func getBooksMetadata(task: CalibreBooksTask, qos: DispatchQoS.QoSClass = .default) -> AnyPublisher<CalibreBooksTask, CalibreAPIError> {
        guard let metadataUrl = task.metadataUrl,
              metadataUrl.isHTTP,
              task.books.isEmpty == false else {
            return Just(task).setFailureType(to: CalibreAPIError.self).eraseToAnyPublisher()
        }

        return validatedDataPublisher(from: metadataUrl, server: task.library.server, qos: qos)
            .map { data, response -> CalibreBooksTask in
                var resultTask = task
                resultTask.data = data
                resultTask.response = response
                return self.applyBooksMetadataPayload(data, to: resultTask)
            }
            .eraseToAnyPublisher()
    }

    @available(*, deprecated, message: "Use CalibreAPIError publisher version instead")
    func getBooksMetadata(task: CalibreBooksTask, qos: DispatchQoS.QoSClass = .default) -> AnyPublisher<CalibreBooksTask, URLError> {
        getBooksMetadata(task: task, qos: qos)
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

    func getLibraryCategoriesPublisher(resultPrev: CalibreSyncLibraryResult) -> AnyPublisher<CalibreSyncLibraryResult, CalibreAPIError> {
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
                .eraseToAnyPublisher()
        } catch {
            return Fail(error: CalibreAPIError(error: error)).eraseToAnyPublisher()
        }
    }

    @available(*, deprecated, message: "Use CalibreAPIError version instead")
    func getLibraryCategoriesPublisher(resultPrev: CalibreSyncLibraryResult) -> AnyPublisher<CalibreSyncLibraryResult, Never> {
        let typedPublisher: AnyPublisher<CalibreSyncLibraryResult, CalibreAPIError> = getLibraryCategoriesPublisher(resultPrev: resultPrev)
        return typedPublisher
            .catch { error -> Just<CalibreSyncLibraryResult> in
                var result = resultPrev
                result.errmsg = error.localizedDescription
                return Just(result)
            }
            .eraseToAnyPublisher()
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
