//
//  GoodreadsSyncConnector.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/5/9.
//

import Foundation
import Combine

struct DSReaderHelperConnector {
    let calibreServerService: CalibreServerService
    let server: CalibreServer
    let dsreaderHelperServer: CalibreServerDSReaderHelper
    let goodreadsSync: CalibreLibraryGoodreadsSync?
    
    let metadataQueue: OperationQueue = {
        var queue = OperationQueue()
        queue.name = "Book Metadata queue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    
    var urlSession: URLSession {
        if let space = calibreServerService.getProtectionSpace(server: server, port: dsreaderHelperServer.port) {
            let userCredential = URLCredential(user: server.username,
                                               password: server.password,
                                               persistence: .forSession)
            if Thread.isMainThread == false {
                DispatchQueue.main.sync {
                    URLCredentialStorage.shared.set(userCredential, for: space)
                }
            } else {
                URLCredentialStorage.shared.set(userCredential, for: space)
            }
        }
        
        return calibreServerService.urlSession(server: server)
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
    
    func refreshConfiguration() -> AnyPublisher<(id: String, port: Int, data: Data), URLError>? {
        guard let url = endpointConfiguration()?.url else { return nil }
        let publisher = urlSession.dataTaskPublisher(for: url)
            .map{ (id: dsreaderHelperServer.id, port: dsreaderHelperServer.port, data: $0.data) }
            .eraseToAnyPublisher()
        
        return publisher
    }
    
    func refreshConfiguration(_ libraryKey: String) async throws -> (CalibreDSReaderHelperConfiguration, Data) {
        guard let url = endpointConfigurationV1(libraryKey: libraryKey)?.url else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await urlSession.data(from: url)
        let config = try JSONDecoder().decode(CalibreDSReaderHelperConfiguration.self, from: data)
        
        return (config, data)
    }
    
    func addToShelf(goodreads_id: String, shelfName: String) -> Bool {
        guard var endpointBaseUrl = endpointBaseUrlAddRemove(goodreads_id: goodreads_id, shelfName: shelfName) else {
            return false
        }
        endpointBaseUrl.queryItems!.append(URLQueryItem(name: "action", value: "add"))
        
        guard let url = endpointBaseUrl.url else { return false }
        
        let request = URLRequest(url: url)
        
        let task = urlSession.dataTask(with: request) { [self] data, response, error in
            if let error = error {
                
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                
                return
            }
            if !(200...299).contains(httpResponse.statusCode) {
                
                return
            }
            
            if let mimeType = httpResponse.mimeType, mimeType == "application/json",
               let data = data,
               let string = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    
                }
            }
        }
        
        task.resume()
        return true
    }
    
    func removeFromShelf(goodreads_id: String, shelfName: String) -> Bool {
        guard var endpointBaseUrl = endpointBaseUrlAddRemove(goodreads_id: goodreads_id, shelfName: shelfName) else {
            return false
        }
        endpointBaseUrl.queryItems!.append(URLQueryItem(name: "action", value: "remove"))
        
        guard let url = endpointBaseUrl.url else { return false }
        let request = URLRequest(url: url)

        let task = urlSession.dataTask(with: request) { [self] data, response, error in
            if let error = error {
                
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                
                return
            }
            if !(200...299).contains(httpResponse.statusCode) {
                
                return
            }
            
            if let mimeType = httpResponse.mimeType, mimeType == "application/json",
               let data = data,
               let string = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    
                }
            }
        }
        
        task.resume()
        return true
    }
    
    func updateReadingProgress(goodreads_id: String, progress: Double) -> Bool {
        guard var endpointBaseUrl = endpointBaseUrlPrecent(goodreads_id: goodreads_id) else {
            return false
        }
        endpointBaseUrl.queryItems!.append(URLQueryItem(name: "percent", value: progress.description))
        
        guard let url = endpointBaseUrl.url else { return false }
        let request = URLRequest(url: url)

        let task = urlSession.dataTask(with: request) { [self] data, response, error in
            if let error = error {
                
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                
                return
            }
            if !(200...299).contains(httpResponse.statusCode) {
                
                return
            }
            
            if let data = data, let string = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    print(string)
                }
            }
        }
        
        task.resume()
        return true
    }
}
