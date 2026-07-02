//
//  CalibreServerService+ReadingPosition.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026/6/17.
//

import Foundation
import Combine

extension CalibreServerService {
    func getLastReadPosition(task: CalibreBooksTask) -> AnyPublisher<CalibreBooksTask, CalibreAPIError> {
        Deferred {
            Future { promise in
                Task {
                    do {
                        promise(.success(try await self.getLastReadPosition(task: task)))
                    } catch {
                        promise(.failure(CalibreAPIError(error: error)))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func getLastReadPosition(task: CalibreBooksTask) async throws -> CalibreBooksTask {
        guard let lastReadPositionUrl = task.lastReadPositionUrl,
              lastReadPositionUrl.isHTTP else {
            return task
        }

        let (data, _) = try await validatedData(from: lastReadPositionUrl, server: task.library.server)
        var task = task
        task.lastReadPositionsData = data
        return task
    }

    @available(*, deprecated, message: "Use CalibreAPIError publisher version instead")
    func getLastReadPosition(task: CalibreBooksTask) -> AnyPublisher<CalibreBooksTask, URLError> {
        getLastReadPosition(task: task)
            .mapError(\.asURLError)
            .eraseToAnyPublisher()
    }

    func buildSetLastReadPositionTask(library: CalibreLibrary, bookId: Int32, format: Format, entry: CalibreBookLastReadPositionEntry) throws -> CalibreBookSetLastReadPositionTask {
        let lastReadPositionEndpointUrl = try makeEndpointURL(
            server: library.server,
            path: "/book-set-last-read-position/\(library.key)/\(bookId)/\(format.rawValue)"
        )

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

    func setLastReadPositionByTask(task: CalibreBookSetLastReadPositionTask) async -> CalibreBookSetLastReadPositionTask {
        await logger.logStartCalibreActivity(type: "Set Last Read Position", request: task.urlRequest, startDatetime: task.startDatetime, bookId: task.bookId, libraryId: task.library.id)

        var resultTask = task
        do {
            let (data, response) = try await validatedData(for: task.urlRequest, server: task.library.server)
            resultTask.urlResponse = response
            resultTask.data = data
        } catch {
            resultTask.error = CalibreAPIError(error: error)
        }

        let logErrMsg: String
        if let calibreError = resultTask.error {
            logErrMsg = calibreError.localizedDescription
        } else if let httpUrlResponse = resultTask.urlResponse as? HTTPURLResponse {
            logErrMsg = "HTTP \(httpUrlResponse.statusCode)"
        } else {
            logErrMsg = "Unknown"
        }
        await logger.logFinishCalibreActivity(type: "Set Last Read Position", request: task.urlRequest, startDatetime: task.startDatetime, finishDatetime: Date(), errMsg: logErrMsg)

        return resultTask
    }

    func setLastReadPositionByTask(task: CalibreBookSetLastReadPositionTask) -> AnyPublisher<CalibreBookSetLastReadPositionTask, CalibreAPIError> {
        Deferred {
            Future { promise in
                Task {
                    let resultTask = await self.setLastReadPositionByTask(task: task)
                    if let error = resultTask.error {
                        promise(.failure(error))
                    } else {
                        promise(.success(resultTask))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    @available(*, deprecated, message: "Use CalibreAPIError publisher version instead")
    func setLastReadPositionByTask(task: CalibreBookSetLastReadPositionTask) -> AnyPublisher<CalibreBookSetLastReadPositionTask, Never> {
        let publisher: AnyPublisher<CalibreBookSetLastReadPositionTask, CalibreAPIError> = setLastReadPositionByTask(task: task)
        return publisher
            .replaceError(with: task)
            .eraseToAnyPublisher()
    }
}
