//
//  CalibreServerService+Metadata.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026/6/17.
//

import Foundation

extension CalibreServerService {
    func getMetadata(oldbook: CalibreBook) async throws -> CalibreBook {
        guard oldbook.library.server.isLocal == false else {
            updatingMetadataStatus = "Local File"
            updatingMetadataSucceed = true
            return oldbook
        }

        let endpointURL = try makeEndpointURL(
            server: oldbook.library.server,
            path: "/get/json/\(oldbook.id)/\(oldbook.library.key)"
        )

        let request = URLRequest(url: endpointURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 600)
        updatingMetadata = true

        do {
            let newbook = try await withRequestActivity(
                .bookMetadata, request: request, server: oldbook.library.server,
                libraryId: oldbook.library.id, bookIds: [oldbook.id]
            ) { data, response in
                guard response.mimeType == "application/json" else { throw CalibreAPIError.unsupportedPayload }
                return try handleLibraryBookOne(oldbook: oldbook, json: data)
            }

            await MainActor.run {
                self.updatingMetadataStatus = "Success"
                self.updatingMetadata = false

                if self.config?.calibreLibraries.isEmpty == false {
                    self.updateBook(book: newbook)
                }
            }

            return newbook
        } catch {
            let err = CalibreAPIError(error: error)
            await MainActor.run {
                self.updatingMetadataStatus = err.localizedDescription
                self.updatingMetadata = false
            }
            throw err
        }
    }

    func handleLibraryBookOne(oldbook: CalibreBook, json: Data) throws -> CalibreBook {
        let entry = try decodePayload(CalibreBookEntry.self, from: json)
        guard let root = try JSONSerialization.jsonObject(with: json, options: []) as? NSDictionary else {
            throw CalibreAPIError.unsupportedPayload
        }

        var book = oldbook
        book.applyMetadataValue(CalibreBookMetadataValue(entry: entry, root: root))
        return book
    }

    func getBookManifest(book: CalibreBook, format: Format) async throws -> Data {
        try await fetchBookManifest(book: book, format: format).data
    }

    func getBookManifestContents(book: CalibreBook, format: Format) async throws -> CalibreBookManifestContents {
        try await fetchBookManifest(book: book, format: format).contents
    }

    private func fetchBookManifest(book: CalibreBook, format: Format) async throws -> (data: Data, contents: CalibreBookManifestContents) {
        let endpointURL = try makeEndpointURL(
            server: book.library.server,
            path: "/book-manifest/\(book.id)/\(format.id)",
            queryItems: [URLQueryItem(name: "library_id", value: book.library.key)]
        )

        let request = URLRequest(url: endpointURL)
        updatingMetadata = true
        do {
            let result: (data: Data, contents: CalibreBookManifestContents) = try await withRequestActivity(
                .bookManifest, request: request, server: book.library.server, libraryId: book.library.id,
                bookIds: [book.id], timeout: 10, resultError: { $0.contents.error }
            ) { data, response in
                guard response.mimeType == "application/json" else { throw CalibreAPIError.unsupportedPayload }
                return (data, CalibreBookManifestContents(data: data))
            }
            let status = result.contents.error?.localizedDescription ?? "Success"
            await MainActor.run {
                self.updatingMetadataStatus = status
                self.updatingMetadata = false
            }
            return result
        } catch {
            let err = CalibreAPIError(error: error)
            await MainActor.run {
                self.updatingMetadataStatus = err.localizedDescription
                self.updatingMetadata = false
            }
            throw err
        }
    }

    func updateMetadata(library: CalibreLibrary, bookId: Int32, metadata: [Any]) async throws {
        let endpointURL = try makeEndpointURL(
            server: library.server,
            path: "/cdb/cmd/set_metadata/0",
            queryItems: [URLQueryItem(name: "library_id", value: library.key)]
        )

        let json: [Any] = ["fields", bookId, metadata]
        let data = try JSONSerialization.data(withJSONObject: json, options: [])
        let request = makeJSONRequest(url: endpointURL, method: "POST", body: data)
        try await withRequestActivity(
            .updateMetadata, request: request, server: library.server, libraryId: library.id, bookIds: [bookId]
        ) { data, response in
            try requireJSON(response)
            // The cdb command API can return HTTP 200 with an "err" envelope.
            let payload = try jsonObject(data)
            if payload["err"] != nil { throw CalibreAPIError.serverRejected(nil) }
            guard payload["result"] != nil else { throw CalibreAPIError.unsupportedPayload }
        }
    }

    func buildMetadataTask(library: CalibreLibrary, bookId: Int32) -> CalibreBookTask? {
        guard let endpointUrl = try? makeEndpointURL(
            server: library.server,
            path: "/get/json/\(bookId)/\(library.key)"
        ) else {
            return nil
        }

        return CalibreBookTask(
            server: library.server,
            bookId: bookId,
            inShelfId: "",
            url: endpointUrl,
            libraryId: library.id
        )
    }

    func buildMetadataTask(book: CalibreBook) -> CalibreBookTask? {
        guard let endpointUrl = try? makeEndpointURL(
            server: book.library.server,
            path: "/get/json/\(book.id)/\(book.library.key)"
        ) else {
            return nil
        }

        return CalibreBookTask(
            server: book.library.server,
            bookId: book.id,
            inShelfId: book.inShelfId,
            url: endpointUrl,
            libraryId: book.library.id
        )
    }

    func getMetadata(task: CalibreBookTask) async throws -> (CalibreBookTask, CalibreBookEntry) {
        try await withRequestActivity(.bookMetadata, request: URLRequest(url: task.url), server: task.server,
                                      libraryId: task.libraryId, bookIds: [task.bookId]) { data, response in
            try requireJSON(response)
            return (task, try decodePayload(CalibreBookEntry.self, from: data))
        }
    }

    func getMetadataData(task: CalibreBookTask) async throws -> (CalibreBookTask, Data, URLResponse) {
        let result: (Data, HTTPURLResponse, Error?) = try await withRequestActivity(
            .bookMetadata, request: URLRequest(url: task.url), server: task.server,
            libraryId: task.libraryId, bookIds: [task.bookId], resultError: { $0.2 }
        ) { data, response in
            do {
                try requireJSON(response)
                _ = try decodePayload(CalibreBookEntry.self, from: data)
                return (data, response, nil)
            } catch {
                return (data, response, error)
            }
        }
        return (task, result.0, result.1)
    }
}
