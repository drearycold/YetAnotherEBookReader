//
//  CalibreServerService+Metadata.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026/6/17.
//

import Foundation
import Combine

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

    @available(*, deprecated, message: "Use async throwing getMetadata(oldbook:) instead")
    func getMetadata(oldbook: CalibreBook, completion: ((_ newbook: CalibreBook) -> Void)? = nil) {
        guard oldbook.library.server.isLocal == false else {
            updatingMetadataStatus = "Local File"
            updatingMetadataSucceed = true
            completion?(oldbook)
            return
        }

        Task {
            do {
                let newbook = try await getMetadata(oldbook: oldbook)
                await MainActor.run {
                    self.updatingMetadataStatus = "Success"
                    self.updatingMetadataSucceed = true
                    completion?(newbook)
                }
            } catch {
                await MainActor.run {
                    self.updatingMetadataStatus = error.localizedDescription
                    self.updatingMetadataSucceed = false
                    completion?(oldbook)
                }
            }
        }
    }

    func handleLibraryBookOne(oldbook: CalibreBook, json: Data) throws -> CalibreBook {
        let entry = try decodePayload(CalibreBookEntry.self, from: json)
        guard let root = try JSONSerialization.jsonObject(with: json, options: []) as? NSDictionary else {
            throw CalibreAPIError.unsupportedPayload
        }

        var book = oldbook
        book.title = entry.title
        book.publisher = entry.publisher ?? ""
        book.series = entry.series ?? ""
        book.seriesIndex = entry.series_index ?? 0.0

        let parserOne = ISO8601DateFormatter()
        parserOne.formatOptions = .withInternetDateTime
        let parserTwo = ISO8601DateFormatter()
        parserTwo.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        book.pubDate = parserTwo.date(from: entry.pubdate) ?? parserOne.date(from: entry.pubdate) ?? .distantPast
        book.timestamp = parserTwo.date(from: entry.timestamp) ?? parserOne.date(from: entry.timestamp) ?? .init()
        book.lastModified = parserTwo.date(from: entry.last_modified) ?? parserOne.date(from: entry.last_modified) ?? .init()
        book.lastSynced = book.lastModified

        book.tags = entry.tags

        book.formats = entry.format_metadata.reduce(into: book.formats) {
            var formatInfo = $0[$1.key.uppercased()] ?? FormatInfo(serverSize: 0, serverMTime: .distantPast, cached: false, cacheSize: 0, cacheMTime: .distantPast)

            formatInfo.serverSize = $1.value.size

            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
            formatInfo.serverMTime = dateFormatter.date(from: $1.value.mtime) ?? .distantPast

            $0[$1.key.uppercased()] = formatInfo
        }

        book.size = 0
        book.rating = Int(entry.rating * 2)
        book.authors = entry.authors
        book.identifiers = entry.identifiers
        book.comments = entry.comments ?? ""

        if let userMetadata = root["user_metadata"] as? NSDictionary {
            book.userMetadatas = userMetadata.reduce(into: book.userMetadatas) {
                guard let dict = $1.value as? NSDictionary,
                      let label = dict["label"] as? String,
                      let value = dict["#value#"] else {
                    return
                }
                $0[label] = value
            }
        }

        return book
    }

    func handleLibraryBookOne(library: CalibreLibrary, bookRealm: CalibreBookRealm, entry: CalibreBookEntry, root: NSDictionary) {
        let decoder = JSONDecoder()

        bookRealm.title = entry.title
        bookRealm.publisher = entry.publisher ?? ""
        bookRealm.series = entry.series ?? ""
        bookRealm.seriesIndex = entry.series_index ?? 0.0

        let parserOne = ISO8601DateFormatter()
        parserOne.formatOptions = .withInternetDateTime
        let parserTwo = ISO8601DateFormatter()
        parserTwo.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        bookRealm.pubDate = parserTwo.date(from: entry.pubdate) ?? parserOne.date(from: entry.pubdate) ?? .distantPast
        bookRealm.timestamp = parserTwo.date(from: entry.timestamp) ?? parserOne.date(from: entry.timestamp) ?? .distantPast
        bookRealm.lastModified = parserTwo.date(from: entry.last_modified) ?? parserOne.date(from: entry.last_modified) ?? .distantPast
        bookRealm.lastSynced = bookRealm.lastModified

        var authors = entry.authors
        bookRealm.authorFirst = authors.popFirst() ?? "Unknown"
        bookRealm.authorSecond = authors.popFirst()
        bookRealm.authorThird = authors.popFirst()
        bookRealm.authorsMore.replaceSubrange(bookRealm.authorsMore.indices, with: authors)

        var tags = entry.tags
        bookRealm.tagFirst = tags.popFirst()
        bookRealm.tagSecond = tags.popFirst()
        bookRealm.tagThird = tags.popFirst()
        bookRealm.tagsMore.replaceSubrange(bookRealm.tagsMore.indices, with: tags)

        var formats: [String: FormatInfo] = (try? decoder.decode([String: FormatInfo].self, from: bookRealm.formatsData as Data? ?? .init())) ?? [:]

        formats = entry.format_metadata.reduce(into: formats) {
            var formatInfo = $0[$1.key.uppercased()] ?? FormatInfo(serverSize: 0, serverMTime: .distantPast, cached: false, cacheSize: 0, cacheMTime: .distantPast)

            formatInfo.serverSize = $1.value.size

            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
            formatInfo.serverMTime = dateFormatter.date(from: $1.value.mtime) ?? .distantPast

            $0[$1.key.uppercased()] = formatInfo
        }
        bookRealm.formatsData = try? JSONEncoder().encode(formats)

        bookRealm.size = 0
        bookRealm.rating = Int(entry.rating * 2)
        bookRealm.identifiersData = try? JSONEncoder().encode(entry.identifiers)
        bookRealm.comments = entry.comments ?? ""

        var userMetadatas = bookRealm.userMetadatas()
        if let userMetadata = root["user_metadata"] as? NSDictionary {
            userMetadatas = userMetadata.reduce(into: userMetadatas) {
                guard let dict = $1.value as? NSDictionary,
                      let label = dict["label"] as? String,
                      let value = dict["#value#"] else {
                    return
                }
                $0[label] = value
            }
        }
        bookRealm.userMetaData = try? JSONSerialization.data(withJSONObject: userMetadatas, options: [])
        bookRealm.lastUpdated = Date()
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

    @available(*, deprecated, message: "Use async throwing getBookManifest(book:format:) instead")
    func getBookManifest(book: CalibreBook, format: Format, completion: ((_ manifest: Data?) -> Void)? = nil) {
        Task {
            do {
                let data = try await getBookManifest(book: book, format: format)
                completion?(data)
            } catch {
                completion?(nil)
            }
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

    @available(*, deprecated, message: "Use async throwing updateMetadata instead")
    func updateMetadata(library: CalibreLibrary, bookId: Int32, metadata: [Any]) -> Int {
        Task {
            do {
                try await updateMetadata(library: library, bookId: bookId, metadata: metadata)
            } catch {
                // No-op
            }
        }
        return 0
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

    func getMetadata(task: CalibreBookTask) -> AnyPublisher<(CalibreBookTask, CalibreBookEntry), CalibreAPIError> {
        Deferred {
            Future { promise in
                Task {
                    do {
                        promise(.success(try await self.getMetadata(task: task)))
                    } catch {
                        promise(.failure(CalibreAPIError(error: error)))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func getMetadata(task: CalibreBookTask) async throws -> (CalibreBookTask, CalibreBookEntry) {
        let (data, _) = try await validatedData(from: task.url, server: task.server)
        return (task, try decodePayload(CalibreBookEntry.self, from: data))
    }

    func getMetadataNew(task: CalibreBookTask) -> AnyPublisher<(CalibreBookTask, Data, URLResponse), CalibreAPIError> {
        Deferred {
            Future { promise in
                Task {
                    do {
                        promise(.success(try await self.getMetadataNew(task: task)))
                    } catch {
                        promise(.failure(CalibreAPIError(error: error)))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func getMetadataNew(task: CalibreBookTask) async throws -> (CalibreBookTask, Data, URLResponse) {
        let (data, response) = try await validatedData(from: task.url, server: task.server)
        return (task, data, response as URLResponse)
    }

    @available(*, deprecated, message: "Use CalibreAPIError publisher version instead")
    func getMetadataNew(task: CalibreBookTask) -> AnyPublisher<(CalibreBookTask, Data, URLResponse), URLError> {
        getMetadataNew(task: task)
            .mapError(\.asURLError)
            .eraseToAnyPublisher()
    }
}
