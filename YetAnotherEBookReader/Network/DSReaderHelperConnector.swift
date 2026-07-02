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

        return try await refreshConfiguration(from: url)
    }

    private func refreshConfiguration(from url: URL) async throws -> (id: String, port: Int, data: Data) {
        let request = URLRequest(url: url)
        let (data, _) = try await calibreServerService.validatedData(for: request, server: server)
        return (id: server.uuid.uuidString, port: dsreaderHelperServer.port, data: data)
    }

    func refreshConfiguration(_ libraryKey: String) async throws -> (CalibreDSReaderHelperConfiguration, Data) {
        guard let url = endpointConfigurationV1(libraryKey: libraryKey)?.url else {
            throw URLError(.badURL)
        }

        let request = URLRequest(url: url)
        let (data, _) = try await calibreServerService.validatedData(for: request, server: server)
        let config = try JSONDecoder().decode(CalibreDSReaderHelperConfiguration.self, from: data)

        return (config, data)
    }

    func addToShelf(goodreads_id: String, shelfName: String) async throws {
        guard var endpointBaseUrl = endpointBaseUrlAddRemove(goodreads_id: goodreads_id, shelfName: shelfName) else {
            throw CalibreAPIError.invalidURL("addToShelf")
        }
        endpointBaseUrl.queryItems!.append(URLQueryItem(name: "action", value: "add"))

        guard let url = endpointBaseUrl.url else {
            throw CalibreAPIError.invalidURL("addToShelf")
        }

        let request = URLRequest(url: url)
        _ = try await calibreServerService.validatedData(for: request, server: server)
    }

    func removeFromShelf(goodreads_id: String, shelfName: String) async throws {
        guard var endpointBaseUrl = endpointBaseUrlAddRemove(goodreads_id: goodreads_id, shelfName: shelfName) else {
            throw CalibreAPIError.invalidURL("removeFromShelf")
        }
        endpointBaseUrl.queryItems!.append(URLQueryItem(name: "action", value: "remove"))

        guard let url = endpointBaseUrl.url else {
            throw CalibreAPIError.invalidURL("removeFromShelf")
        }

        let request = URLRequest(url: url)
        _ = try await calibreServerService.validatedData(for: request, server: server)
    }

    func updateReadingProgress(goodreads_id: String, progress: Double) async throws {
        guard var endpointBaseUrl = endpointBaseUrlPrecent(goodreads_id: goodreads_id) else {
            throw CalibreAPIError.invalidURL("updateReadingProgress")
        }
        endpointBaseUrl.queryItems!.append(URLQueryItem(name: "percent", value: progress.description))

        guard let url = endpointBaseUrl.url else {
            throw CalibreAPIError.invalidURL("updateReadingProgress")
        }

        let request = URLRequest(url: url)
        _ = try await calibreServerService.validatedData(for: request, server: server)
    }

}
