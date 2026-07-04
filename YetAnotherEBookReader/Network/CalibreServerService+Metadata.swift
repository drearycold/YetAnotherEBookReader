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
        let startDatetime = Date()
        updatingMetadata = true

        await self.logger.logStartCalibreActivity(type: "Get Book Metadata", request: request, startDatetime: startDatetime, bookId: oldbook.id, libraryId: oldbook.library.id)

        do {
            let (data, httpResponse) = try await self.validatedData(for: request, server: oldbook.library.server)
            guard httpResponse.mimeType == "application/json" else {
                throw CalibreAPIError.unsupportedPayload
            }
            let newbook = try self.handleLibraryBookOne(oldbook: oldbook, json: data)

            await self.logger.logFinishCalibreActivity(type: "Get Book Metadata", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: "Success")

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
            await self.logger.logFinishCalibreActivity(type: "Get Book Metadata", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: err.localizedDescription)
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
        let endpointURL = try makeEndpointURL(
            server: book.library.server,
            path: "/book-manifest/\(book.id)/\(format.id)",
            queryItems: [URLQueryItem(name: "library_id", value: book.library.key)]
        )

        let request = URLRequest(url: endpointURL)
        let startDatetime = Date()
        updatingMetadata = true

        await self.logger.logStartCalibreActivity(type: "Get Book Manifest", request: request, startDatetime: startDatetime, bookId: book.id, libraryId: book.library.id)

        do {
            let (data, httpResponse) = try await self.validatedData(for: request, server: book.library.server)
            guard httpResponse.mimeType == "application/json" else {
                throw CalibreAPIError.unsupportedPayload
            }
            await self.logger.logFinishCalibreActivity(type: "Get Book Manifest", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: "Success")
            await MainActor.run {
                self.updatingMetadataStatus = "Success"
                self.updatingMetadata = false
            }
            return data
        } catch {
            let err = CalibreAPIError(error: error)
            await self.logger.logFinishCalibreActivity(type: "Get Book Manifest", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: err.localizedDescription)
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
        let startDatetime = Date()

        await self.logger.logStartCalibreActivity(type: "Set Book Metadata", request: request, startDatetime: startDatetime, bookId: bookId, libraryId: library.id)

        do {
            let (_, response) = try await self.validatedData(for: request, server: library.server)
            let logErrMsg = "HTTP \(response.statusCode)"
            await self.logger.logFinishCalibreActivity(type: "Set Book Metadata", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: logErrMsg)
        } catch {
            let err = CalibreAPIError(error: error)
            await self.logger.logFinishCalibreActivity(type: "Set Book Metadata", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: err.localizedDescription)
            throw err
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
            url: endpointUrl
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
            url: endpointUrl
        )
    }

    func getMetadata(task: CalibreBookTask) async throws -> (CalibreBookTask, CalibreBookEntry) {
        let (data, _) = try await validatedData(from: task.url, server: task.server)
        return (task, try decodePayload(CalibreBookEntry.self, from: data))
    }

    func getMetadataData(task: CalibreBookTask) async throws -> (CalibreBookTask, Data, URLResponse) {
        let (data, response) = try await validatedData(from: task.url, server: task.server)
        return (task, data, response as URLResponse)
    }
}
