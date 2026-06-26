//
//  CalibreServerService+Annotations.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026/6/17.
//

import Foundation
import Combine

extension CalibreServerService {
    func getAnnotations(task: CalibreBooksTask) async -> CalibreBooksTask {
        guard let annotationsUrl = task.annotationsUrl,
              annotationsUrl.isHTTP else {
            return task
        }

        do {
            let (data, _) = try await validatedData(from: annotationsUrl, server: task.library.server)
            var resultTask = task
            resultTask.annotationsData = data
            resultTask.booksAnnotationsEntry = try? JSONDecoder().decode([String: CalibreBookAnnotationsResult].self, from: data)
            return resultTask
        } catch {
            return task
        }
    }

    func getAnnotations(task: CalibreBooksTask) -> AnyPublisher<CalibreBooksTask, URLError> {
        guard let annotationsUrl = task.annotationsUrl,
              annotationsUrl.isHTTP else {
            return Just(task).setFailureType(to: URLError.self).eraseToAnyPublisher()
        }

        return validatedDataPublisher(from: annotationsUrl, server: task.library.server)
            .map { data, _ -> CalibreBooksTask in
                var task = task
                task.annotationsData = data
                task.booksAnnotationsEntry = try? JSONDecoder().decode([String: CalibreBookAnnotationsResult].self, from: data)
                return task
            }
            .mapError(\.asURLError)
            .eraseToAnyPublisher()
    }

    func buildUpdateAnnotationsTask(library: CalibreLibrary, bookId: Int32, format: Format, highlights: [CalibreBookAnnotationHighlightEntry], bookmarks: [CalibreBookAnnotationBookmarkEntry]) -> CalibreBookUpdateAnnotationsTask? {
        guard let endpointUrl = try? makeEndpointURL(
            server: library.server,
            path: "/book-update-annotations/\(library.key)/\(bookId)/\(format.rawValue)"
        ) else {
            return nil
        }

        let encoder = JSONEncoder()
        var annotations = [Any]()
        annotations.append(contentsOf: highlights.compactMap {
            guard let data = try? encoder.encode($0) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        })
        annotations.append(contentsOf: bookmarks.compactMap {
            guard let data = try? encoder.encode($0) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        })

        let entry = ["\(bookId):\(format.rawValue)": annotations]
        guard let postData = try? JSONSerialization.data(withJSONObject: entry) else {
            return nil
        }

        let urlRequest = makeJSONRequest(url: endpointUrl, method: "POST", body: postData)

        return CalibreBookUpdateAnnotationsTask(
            library: library,
            bookId: bookId,
            format: format,
            entry: entry,
            urlRequest: urlRequest
        )
    }

    func updateAnnotationByTask(task: CalibreBookUpdateAnnotationsTask) async -> CalibreBookUpdateAnnotationsTask {
        await logger.logStartCalibreActivity(type: "Update Annotations", request: task.urlRequest, startDatetime: task.startDatetime, bookId: task.bookId, libraryId: task.library.id)

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
        await logger.logFinishCalibreActivity(type: "Update Annotations", request: task.urlRequest, startDatetime: task.startDatetime, finishDatetime: Date(), errMsg: logErrMsg)

        return resultTask
    }

    func updateAnnotationByTask(task: CalibreBookUpdateAnnotationsTask) -> AnyPublisher<CalibreBookUpdateAnnotationsTask, Never> {
        validatedDataPublisher(for: task.urlRequest, server: task.library.server)
            .map { data, response -> CalibreBookUpdateAnnotationsTask in
                var task = task
                task.urlResponse = response
                task.data = data
                return task
            }
            .replaceError(with: task)
            .eraseToAnyPublisher()
    }
}
