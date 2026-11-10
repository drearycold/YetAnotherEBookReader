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

    func endpointConfiguration() -> URLComponents? {
        guard let serverUrl = calibreServerService.getServerUrlByReachability(server: server),
              var urlComponents = URLComponents(url: serverUrl, resolvingAgainstBaseURL: false) else { return nil }
        urlComponents.port = dsreaderHelperServer.port
        urlComponents.path.append("/dshelper/configuration")

        return urlComponents
    }

    func endpointConfigurationV1(libraryKey: String) -> URLComponents? {
        guard let serverUrl = calibreServerService.getServerUrlByReachability(server: server),
              var urlComponents = URLComponents(url: serverUrl, resolvingAgainstBaseURL: false) else { return nil }
        urlComponents.port = dsreaderHelperServer.port
        urlComponents.path.append("/dshelper/1/configuration/\(libraryKey)")

        return urlComponents
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

    func refreshConfiguration() async throws -> (id: String, port: Int, data: Data) {
        guard let url = endpointConfiguration()?.url else {
            throw URLError(.badURL)
        }

        let result: (Data, Error?) = try await calibreServerService.withRequestActivity(
            .helper, request: URLRequest(url: url), server: server, resultError: { $0.1 }
        ) { data, response in
            do {
                try calibreServerService.requireJSON(response)
                _ = try decodeConfiguration(data, requiresPluginPreferences: true)
                return (data, nil)
            } catch {
                // The legacy settings UI separately reports an unreadable configuration.
                return (data, error)
            }
        }
        return (id: server.uuid.uuidString, port: dsreaderHelperServer.port, data: result.0)
    }

    func refreshConfiguration(_ libraryKey: String, libraryId: String? = nil) async throws -> (CalibreDSReaderHelperConfiguration, Data) {
        guard let url = endpointConfigurationV1(libraryKey: libraryKey)?.url else {
            throw URLError(.badURL)
        }

        return try await calibreServerService.withRequestActivity(
            .helper, request: URLRequest(url: url), server: server, libraryId: libraryId
        ) { data, response in
            try calibreServerService.requireJSON(response)
            return (try decodeConfiguration(data, requiresPluginPreferences: libraryKey == "_"), data)
        }
    }

    private func decodeConfiguration(_ data: Data, requiresPluginPreferences: Bool) throws -> CalibreDSReaderHelperConfiguration {
        let config = try calibreServerService.decodePayload(CalibreDSReaderHelperConfiguration.self, from: data)
        if requiresPluginPreferences && config.dsreader_helper_prefs == nil {
            throw CalibreAPIError.serverRejected(nil)
        }
        return config
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
