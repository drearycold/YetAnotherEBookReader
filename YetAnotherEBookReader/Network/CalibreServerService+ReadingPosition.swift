//
//  CalibreServerService+ReadingPosition.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026/6/17.
//

import Foundation
import Combine

extension CalibreServerService {
    func getLastReadPosition(task: CalibreBooksTask) -> AnyPublisher<CalibreBooksTask, URLError> {
        guard let lastReadPositionUrl = task.lastReadPositionUrl,
              lastReadPositionUrl.isHTTP else {
            return Just(task).setFailureType(to: URLError.self).eraseToAnyPublisher()
        }

        return validatedDataPublisher(from: lastReadPositionUrl, server: task.library.server)
            .map { data, _ -> CalibreBooksTask in
                var task = task
                task.lastReadPositionsData = data
                return task
            }
            .mapError(\.asURLError)
            .eraseToAnyPublisher()
    }

    func buildSetLastReadPositionTask(library: CalibreLibrary, bookId: Int32, format: Format, entry: CalibreBookLastReadPositionEntry) -> CalibreBookSetLastReadPositionTask? {
        guard let lastReadPositionEndpointUrl = try? makeEndpointURL(
            server: library.server,
            path: "/book-set-last-read-position/\(library.key)/\(bookId)/\(format.rawValue)"
        ) else {
            return nil
        }

        guard let postData = try? JSONEncoder().encode(entry) else {
            return nil
        }

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

    func setLastReadPositionByTask(task: CalibreBookSetLastReadPositionTask) async -> CalibreBookSetLastReadPositionTask {
        await logger.logStartCalibreActivity(type: "Set Last Read Position", request: task.urlRequest, startDatetime: task.startDatetime, bookId: task.bookId, libraryId: task.library.id)

        var resultTask = task
        do {
            let (data, response) = try await validatedData(for: task.urlRequest, server: task.library.server)
            resultTask.urlResponse = response
            resultTask.data = data
        } catch {
        }

        let logErrMsg: String
        if let httpUrlResponse = resultTask.urlResponse as? HTTPURLResponse {
            logErrMsg = "HTTP \(httpUrlResponse.statusCode)"
        } else {
            logErrMsg = "Unknown"
        }
        await logger.logFinishCalibreActivity(type: "Set Last Read Position", request: task.urlRequest, startDatetime: task.startDatetime, finishDatetime: Date(), errMsg: logErrMsg)

        return resultTask
    }

    func setLastReadPositionByTask(task: CalibreBookSetLastReadPositionTask) -> AnyPublisher<CalibreBookSetLastReadPositionTask, Never> {
        validatedDataPublisher(for: task.urlRequest, server: task.library.server)
            .map { data, response -> CalibreBookSetLastReadPositionTask in
                var task = task
                task.urlResponse = response
                task.data = data
                return task
            }
            .replaceError(with: task)
            .eraseToAnyPublisher()
    }
}
