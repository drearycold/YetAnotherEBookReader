//
//  GoodreadsSyncConnector.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/5/9.
//

import Foundation

struct DSReaderHelperConnector {
    let calibreServerService: CalibreServerService
    let server: CalibreServer
    let dsreaderHelperServer: CalibreServerDSReaderHelper
    let goodreadsSync: CalibreGoodreadsSyncPrefs.PluginPrefs?

    let metadataQueue: OperationQueue = {
        var queue = OperationQueue()
        queue.name = "Book Metadata queue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    var urlSession: URLSession {
        calibreServerService.urlSession(server: server)
    }

    func endpointBaseUrlAddRemove(goodreads_id: String, shelfName: String) -> URLComponents? {
        guard var urlComponents = URLComponents(string: server.serverUrl) else { return nil }
        guard let profileName = goodreadsSync?.profileName else { return nil }
        urlComponents.port = dsreaderHelperServer.port
        urlComponents.path.append("/dshelper/grsync/add_remove_book_to_shelf")
        urlComponents.queryItems = [
            URLQueryItem(name: "goodreads_id", value: goodreads_id.description),
            URLQueryItem(name: "profile_name", value: profileName),
            URLQueryItem(name: "shelf_name", value: shelfName)
        ]

        return urlComponents
    }

    func endpointDictLookup() -> URLComponents? {
        guard let serverUrl = calibreServerService.getServerUrlByReachability(server: server),
              var urlComponents = URLComponents(url: serverUrl, resolvingAgainstBaseURL: false) else { return nil }
        urlComponents.port = dsreaderHelperServer.port
        urlComponents.path.append("/dshelper/dict_viewer/lookup")

        return urlComponents
    }

    func endpointBaseUrlPrecent(goodreads_id: String) -> URLComponents? {
        guard var urlComponents = URLComponents(string: server.serverUrl) else { return nil }
        guard let profileName = goodreadsSync?.profileName else { return nil }
        urlComponents.port = dsreaderHelperServer.port
        urlComponents.path.append("/dshelper/grsync/update_reading_progress")
        urlComponents.queryItems = [
            URLQueryItem(name: "goodreads_id", value: goodreads_id.description),
            URLQueryItem(name: "profile_name", value: profileName)
        ]

        return urlComponents
    }

    func fetchConfiguration(baseURL: URL, legacy: Bool = false) async throws -> DSReaderHelperConfigurationPayload {
        let path = legacy ? "/dshelper/configuration" : "/dshelper/1/configuration/_"
        return try await fetchConfiguration(baseURL: baseURL, path: path) { payload in
            guard payload.configuration.dsreader_helper_prefs != nil else { throw CalibreAPIError.unsupportedPayload }
            return payload
        }
    }

    func fetchLibraryConfiguration(
        baseURL: URL, library: DSReaderHelperConfigurationRequest.Library
    ) async throws -> CalibreCountPagesPrefs.LibraryConfig {
        let segment = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/%"))
        guard !library.key.isEmpty, library.key != "_",
              let key = library.key.addingPercentEncoding(withAllowedCharacters: segment) else { throw URLError(.badURL) }
        return try await fetchConfiguration(baseURL: baseURL, path: "/dshelper/1/configuration/\(key)", libraryID: library.id) { payload in
            // Helper can catch a library read error and return HTTP 200 with an empty object.
            guard let columns = payload.configuration.count_pages_prefs?.library_config?[library.key] else {
                throw CalibreAPIError.unsupportedPayload
            }
            return columns
        }
    }

    private func fetchConfiguration<Result>(
        baseURL: URL, path: String, libraryID: String? = nil,
        parse: (DSReaderHelperConfigurationPayload) throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              components.host?.isEmpty == false else { throw URLError(.badURL) }
        components.port = dsreaderHelperServer.port
        if components.percentEncodedPath.hasSuffix("/") { components.percentEncodedPath.removeLast() }
        components.percentEncodedPath += path
        guard let url = components.url else { throw URLError(.badURL) }

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        return try await calibreServerService.withActivity(.helper, request: request, libraryId: libraryID) { activity in
            do {
                try Task.checkCancellation()
                let (data, response) = try await calibreServerService.validatedData(for: request, server: server, activity: activity)
                try Task.checkCancellation()
                try calibreServerService.requireJSON(response)
                let result = try parse(DSReaderHelperConfigurationPayload(data: data, service: calibreServerService))
                try Task.checkCancellation()
                return result
            } catch {
                try Task.checkCancellation()
                if let code = activity.httpStatusCode, code == 401 || code == 403 {
                    throw CalibreAPIError.authFailed
                }
                throw error
            }
        }
    }

    func addToShelf(goodreads_id: String, shelfName: String, book: CalibreBook? = nil) async throws {
        guard var endpointBaseUrl = endpointBaseUrlAddRemove(goodreads_id: goodreads_id, shelfName: shelfName) else {
            throw CalibreAPIError.invalidURL("addToShelf")
        }
        endpointBaseUrl.queryItems!.append(URLQueryItem(name: "action", value: "add"))

        guard let url = endpointBaseUrl.url else {
            throw CalibreAPIError.invalidURL("addToShelf")
        }

        try await submitGoodreadsJob(url: url, book: book)
    }

    func removeFromShelf(goodreads_id: String, shelfName: String, book: CalibreBook? = nil) async throws {
        guard var endpointBaseUrl = endpointBaseUrlAddRemove(goodreads_id: goodreads_id, shelfName: shelfName) else {
            throw CalibreAPIError.invalidURL("removeFromShelf")
        }
        endpointBaseUrl.queryItems!.append(URLQueryItem(name: "action", value: "remove"))

        guard let url = endpointBaseUrl.url else {
            throw CalibreAPIError.invalidURL("removeFromShelf")
        }

        try await submitGoodreadsJob(url: url, book: book)
    }

    func updateReadingProgress(goodreads_id: String, progress: Double, book: CalibreBook? = nil) async throws {
        guard var endpointBaseUrl = endpointBaseUrlPrecent(goodreads_id: goodreads_id) else {
            throw CalibreAPIError.invalidURL("updateReadingProgress")
        }
        endpointBaseUrl.queryItems!.append(URLQueryItem(name: "percent", value: progress.description))

        guard let url = endpointBaseUrl.url else {
            throw CalibreAPIError.invalidURL("updateReadingProgress")
        }

        try await submitGoodreadsJob(url: url, book: book)
    }
    private func submitGoodreadsJob(url: URL, book: CalibreBook?) async throws {
        try await calibreServerService.withRequestActivity(
            .helper, request: URLRequest(url: url), server: server,
            libraryId: book?.library.id, bookIds: book.map { Set([$0.id]) } ?? []
        ) { data, _ in
            // The Helper responds with a plain-text job ID or an error such as "-1".
            let reply = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if reply == "-1" || reply.hasPrefix("missing ") {
                throw CalibreAPIError.serverRejected(nil)
            }
            guard let jobId = Int(reply), jobId >= 0 else {
                throw CalibreAPIError.unsupportedPayload
            }
        }
    }

}
