//
//  CalibreServerService+Metadata.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026/6/17.
//

import Foundation
import Combine

extension CalibreServerService {
    func getMetadata(oldbook: CalibreBook, completion: ((_ newbook: CalibreBook) -> Void)? = nil) {
        guard oldbook.library.server.isLocal == false else {
            updatingMetadataStatus = "Local File"
            updatingMetadataSucceed = true
            return
        }

        let endpointURL: URL
        do {
            endpointURL = try makeEndpointURL(
                server: oldbook.library.server,
                path: "/get/json/\(oldbook.id)/\(oldbook.library.key)"
            )
        } catch {
            updatingMetadataStatus = CalibreAPIError(error: error).localizedDescription
            return
        }

        let request = URLRequest(url: endpointURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 600)
        let startDatetime = Date()
        updatingMetadata = true

        Task { [weak self] in
            guard let self else { return }

            await self.logger.logStartCalibreActivity(type: "Get Book Metadata", request: request, startDatetime: startDatetime, bookId: oldbook.id, libraryId: oldbook.library.id)

            var status = "Unknown Error"
            var bookResult = oldbook

            defer {
                Task { [weak self] in
                    await self?.logger.logFinishCalibreActivity(type: "Get Book Metadata", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: status)
                }

                DispatchQueue.main.async {
                    self.updatingMetadataStatus = status
                    self.updatingMetadata = false

                    if status == "Success",
                       self.getBookRealm(forPrimaryKey: bookResult.inShelfId) != nil {
                        self.updateBook(book: bookResult)
                    }

                    completion?(bookResult)
                }
            }

            do {
                let (data, httpResponse) = try await self.validatedData(for: request, server: oldbook.library.server)
                guard httpResponse.mimeType == "application/json" else {
                    status = CalibreAPIError.unsupportedPayload.localizedDescription
                    return
                }
                guard let newbook = self.handleLibraryBookOne(oldbook: oldbook, json: data) else {
                    status = CalibreAPIError.decoding(NSError(domain: "CalibreServerService", code: 0)).localizedDescription
                    return
                }

                status = "Success"
                bookResult = newbook
            } catch {
                status = CalibreAPIError(error: error).localizedDescription
            }
        }
    }

    func handleLibraryBookOne(oldbook: CalibreBook, json: Data) -> CalibreBook? {
        do {
            let entry = try decodePayload(CalibreBookEntry.self, from: json)
            guard let root = try JSONSerialization.jsonObject(with: json, options: []) as? NSDictionary else {
                return nil
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
        } catch {
            return nil
        }
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

    func getBookManifest(book: CalibreBook, format: Format, completion: ((_ manifest: Data?) -> Void)? = nil) {
        let endpointURL: URL
        do {
            endpointURL = try makeEndpointURL(
                server: book.library.server,
                path: "/book-manifest/\(book.id)/\(format.id)",
                queryItems: [URLQueryItem(name: "library_id", value: book.library.key)]
            )
        } catch {
            updatingMetadataStatus = CalibreAPIError(error: error).localizedDescription
            return
        }

        let request = URLRequest(url: endpointURL)

        let startDatetime = Date()
        updatingMetadata = true

        Task { [weak self] in
            guard let self else { return }

            await self.logger.logStartCalibreActivity(type: "Get Book Manifest", request: request, startDatetime: startDatetime, bookId: book.id, libraryId: book.library.id)

            var status = "Unknown Error"
            var manifestData: Data?

            defer {
                Task { [weak self] in
                    await self?.logger.logFinishCalibreActivity(type: "Get Book Manifest", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: status)
                }
                DispatchQueue.main.async {
                    self.updatingMetadataStatus = status
                    self.updatingMetadata = false
                    completion?(manifestData)
                }
            }

            do {
                let (data, httpResponse) = try await self.validatedData(for: request, server: book.library.server)
                guard httpResponse.mimeType == "application/json" else {
                    status = CalibreAPIError.unsupportedPayload.localizedDescription
                    return
                }
                status = "Success"
                manifestData = data
            } catch {
                status = CalibreAPIError(error: error).localizedDescription
            }
        }
    }

    func updateMetadata(library: CalibreLibrary, bookId: Int32, metadata: [Any]) -> Int {
        let endpointURL: URL
        do {
            endpointURL = try makeEndpointURL(
                server: library.server,
                path: "/cdb/cmd/set_metadata/0",
                queryItems: [URLQueryItem(name: "library_id", value: library.key)]
            )
        } catch {
            return -1
        }

        let json: [Any] = ["fields", bookId, metadata]

        guard let data = try? JSONSerialization.data(withJSONObject: json, options: []) else {
            return -1
        }

        let request = makeJSONRequest(url: endpointURL, method: "POST", body: data)
        let startDatetime = Date()

        Task { [weak self] in
            guard let self else { return }
            await self.logger.logStartCalibreActivity(type: "Set Book Metadata", request: request, startDatetime: startDatetime, bookId: bookId, libraryId: library.id)

            let logErrMsg: String
            do {
                let (_, response) = try await self.validatedData(for: request, server: library.server)
                logErrMsg = "HTTP \(response.statusCode)"
            } catch {
                logErrMsg = CalibreAPIError(error: error).localizedDescription
            }

            await self.logger.logFinishCalibreActivity(type: "Set Book Metadata", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: logErrMsg)
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

    func getMetadata(task: CalibreBookTask) -> AnyPublisher<(CalibreBookTask, CalibreBookEntry), Never> {
        validatedDataPublisher(from: task.url, server: task.server)
            .tryMap { data, _ in
                try self.decodePayload(CalibreBookEntry.self, from: data)
            }
            .mapError(CalibreAPIError.init(error:))
            .replaceError(with: CalibreBookEntry())
            .map { (task, $0) }
            .eraseToAnyPublisher()
    }

    func getMetadataNew(task: CalibreBookTask) -> AnyPublisher<(CalibreBookTask, Data, URLResponse), URLError> {
        validatedDataPublisher(from: task.url, server: task.server)
            .map { (task, $0.0, $0.1 as URLResponse) }
            .mapError(\.asURLError)
            .eraseToAnyPublisher()
    }
}
