//
//  CalibreServerService+Annotations.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026/6/17.
//

import Foundation

extension CalibreServerService {
    func getAnnotations(task: CalibreBooksTask, checkCurrent: () throws -> Void = {}) async -> CalibreBooksTask {
        guard let annotationsUrl = task.annotationsUrl,
              annotationsUrl.isHTTP else {
            return task
        }

        do {
            let (result, _): (CalibreBooksTask, CalibreAPIError?) = try await withRequestActivity(
                .annotations, request: URLRequest(url: annotationsUrl), server: task.library.server,
                libraryId: task.library.id, bookIds: Set(task.books), resultError: { $0.1 },
                checkCurrent: checkCurrent
            ) { data, response in
                var result = task
                result.annotationsData = data
                do {
                    try requireJSON(response)
                    result.booksAnnotationsEntry = try decodePayload([String: CalibreBookAnnotationsResult].self, from: data)
                    // The task can already carry a metadata error. This activity covers annotations only.
                    return (result, nil)
                } catch {
                    let annotationError = CalibreAPIError(error: error)
                    result.annotationsError = annotationError
                    return (result, annotationError)
                }
            }
            return result
        } catch {
            var resultTask = task
            resultTask.annotationsError = CalibreAPIError(error: error)
            return resultTask
        }
    }

    func buildUpdateAnnotationsTask(library: CalibreLibrary, bookId: Int32, format: Format, highlights: [CalibreBookAnnotationHighlightEntry], bookmarks: [CalibreBookAnnotationBookmarkEntry], serverURL: URL? = nil) throws -> CalibreBookUpdateAnnotationsTask {
        let path = "/book-update-annotations/\(library.key)/\(bookId)/\(format.rawValue)"
        let endpointUrl = try serverURL.map { try makeEndpointURL(serverURL: $0, path: path) }
            ?? makeEndpointURL(server: library.server, path: path)

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

    func updateAnnotationByTask(task: CalibreBookUpdateAnnotationsTask,
                                checkCurrent: () throws -> Void = {}) async -> CalibreBookUpdateAnnotationsTask {
        var result = task
        do {
            (result.data, result.urlResponse) = try await withRequestActivity(
                .annotations, request: task.urlRequest, server: task.library.server,
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
