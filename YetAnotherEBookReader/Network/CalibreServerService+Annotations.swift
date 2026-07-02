//
//  CalibreServerService+Annotations.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026/6/17.
//

import Foundation

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
            do {
                resultTask.booksAnnotationsEntry = try JSONDecoder().decode([String: CalibreBookAnnotationsResult].self, from: data)
            } catch {
                resultTask.booksError.formUnion(task.books)
                resultTask.error = CalibreAPIError(error: error)
            }
            return resultTask
        } catch {
            var resultTask = task
            resultTask.error = CalibreAPIError(error: error)
            return resultTask
        }
    }

    func buildUpdateAnnotationsTask(library: CalibreLibrary, bookId: Int32, format: Format, highlights: [CalibreBookAnnotationHighlightEntry], bookmarks: [CalibreBookAnnotationBookmarkEntry]) throws -> CalibreBookUpdateAnnotationsTask {
        let endpointUrl = try makeEndpointURL(
            server: library.server,
            path: "/book-update-annotations/\(library.key)/\(bookId)/\(format.rawValue)"
        )

        let encoder = JSONEncoder()
        var annotations = [Any]()
        annotations.append(contentsOf: try highlights.map {
            let data = try encoder.encode($0)
            return try JSONSerialization.jsonObject(with: data)
        })
        annotations.append(contentsOf: try bookmarks.map {
            let data = try encoder.encode($0)
            return try JSONSerialization.jsonObject(with: data)
        })

        let entry = ["\(bookId):\(format.rawValue)": annotations]
        let postData = try JSONSerialization.data(withJSONObject: entry)

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
        await logger.logFinishCalibreActivity(type: "Update Annotations", request: task.urlRequest, startDatetime: task.startDatetime, finishDatetime: Date(), errMsg: logErrMsg)

        return resultTask
    }

}
