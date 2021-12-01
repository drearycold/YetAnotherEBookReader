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
    let goodreadsSync: CalibreLibraryGoodreadsSync
    
    var urlSession: URLSession {
        if let space = calibreServerService.getProtectionSpace(server: server, port: dsreaderHelperServer.port) {
            let userCredential = URLCredential(user: server.username,
                                               password: server.password,
                                               persistence: .forSession)
            URLCredentialStorage.shared.set(userCredential, for: space)
        }
        
        let urlSessionConfiguration = URLSessionConfiguration.default
        urlSessionConfiguration.timeoutIntervalForRequest = 10
        let urlSessionDelegate = CalibreServerTaskDelegate(server.username)
        
        return URLSession(configuration: urlSessionConfiguration, delegate: urlSessionDelegate, delegateQueue: nil)
    }
    
    func endpointConfiguration() -> URLComponents? {
        guard let serverUrl = calibreServerService.getServerUrlByReachability(server: server),
              var urlComponents = URLComponents(url: serverUrl, resolvingAgainstBaseURL: false) else { return nil }
        urlComponents.port = dsreaderHelperServer.port
        urlComponents.path.append("/dshelper/configuration")
        
        return urlComponents
    }
    
    func endpointBaseUrlAddRemove(goodreads_id: String, shelfName: String) -> URLComponents? {
        guard var urlComponents = URLComponents(string: server.serverUrl) else { return nil }
        urlComponents.port = dsreaderHelperServer.port
        urlComponents.path.append("/dshelper/grsync/add_remove_book_to_shelf")
        urlComponents.queryItems = [
            URLQueryItem(name: "goodreads_id", value: goodreads_id.description),
            URLQueryItem(name: "profile_name", value: goodreadsSync.profileName),
            URLQueryItem(name: "shelf_name", value: shelfName)
        ]
        
        return urlComponents
    }
    
    func endpointBaseUrlPrecent(goodreads_id: String) -> URLComponents? {
        guard var urlComponents = URLComponents(string: server.serverUrl) else { return nil }
        urlComponents.port = dsreaderHelperServer.port
        urlComponents.path.append("/dshelper/grsync/update_reading_progress")
        urlComponents.queryItems = [
            URLQueryItem(name: "goodreads_id", value: goodreads_id.description),
            URLQueryItem(name: "profile_name", value: goodreadsSync.profileName)
        ]
        
        return urlComponents
    }
    
    func refreshConfiguration() -> AnyPublisher<Data, URLError>? {
        guard let url = endpointConfiguration()?.url else { return nil }
        let publisher = urlSession.dataTaskPublisher(for: url)
            .map{ $0.data }
            .eraseToAnyPublisher()
        
        return publisher
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
