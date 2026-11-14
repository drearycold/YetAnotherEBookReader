//
//  CalibreServerService+ReadingPosition.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026/6/17.
//

import Foundation

extension CalibreServerService {
    func getLastReadPosition(task: CalibreBooksTask) async throws -> CalibreBooksTask {
        guard let lastReadPositionUrl = task.lastReadPositionUrl,
              lastReadPositionUrl.isHTTP else {
            return task
        }

        return try await withRequestActivity(
            .readingPosition, request: URLRequest(url: lastReadPositionUrl), server: task.library.server,
            libraryId: task.library.id, bookIds: Set(task.books)
        ) { data, response in
            try requireJSON(response)
            _ = try decodePayload([String: [CalibreBookLastReadPositionEntry]].self, from: data)
            var result = task
            result.lastReadPositionsData = data
            return result
        }
    }

    func buildSetLastReadPositionTask(library: CalibreLibrary, bookId: Int32, format: Format, entry: CalibreBookLastReadPositionEntry, serverURL: URL? = nil) throws -> CalibreBookSetLastReadPositionTask {
        let path = "/book-set-last-read-position/\(library.key)/\(bookId)/\(format.rawValue)"
        let lastReadPositionEndpointUrl = try serverURL.map { try makeEndpointURL(serverURL: $0, path: path) }
            ?? makeEndpointURL(server: library.server, path: path)

        let postData = try JSONEncoder().encode(entry)

        let urlRequest = makeJSONRequest(url: lastReadPositionEndpointUrl, method: "POST", body: postData)

        return CalibreBookSetLastReadPositionTask(
            library: library,
            bookId: bookId,
            format: format,
            entry: entry,
            urlRequest: urlRequest,
            startDatetime: Date()
        )
    }

    func setLastReadPositionByTask(task: CalibreBookSetLastReadPositionTask,
                                   checkCurrent: () throws -> Void = {}) async -> CalibreBookSetLastReadPositionTask {
        var result = task
        do {
            (result.data, result.urlResponse) = try await withRequestActivity(
                .readingPosition, request: task.urlRequest, server: task.library.server,
                libraryId: task.library.id, bookIds: [task.bookId], checkCurrent: checkCurrent
            ) { data, response in
                try validateMutationResponse(data, response: response)
                return (data, response)
            }
        } catch {
            result.error = CalibreAPIError(error: error)
        }
        return result
    }
}
