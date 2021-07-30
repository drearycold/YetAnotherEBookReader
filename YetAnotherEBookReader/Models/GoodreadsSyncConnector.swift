//
//  GoodreadsSyncConnector.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/5/9.
//

import Foundation

struct GoodreadsSyncConnector {
    let server: CalibreServer
    let profileName: String
    
    func endpointBaseUrlAddRemove(goodreads_id: String, shelfName: String) -> URLComponents? {
        guard var urlComponents = URLComponents(string: server.serverUrl) else { return nil }
        urlComponents.path.append("/grsync/add_remove_book_to_shelf")
        urlComponents.queryItems = [
            URLQueryItem(name: "goodreads_id", value: goodreads_id.description),
            URLQueryItem(name: "profile_name", value: profileName),
            URLQueryItem(name: "shelf_name", value: shelfName)
        ]
        
        return urlComponents
    }
    
    func endpointBaseUrlPrecent(goodreads_id: String) -> URLComponents? {
        guard var urlComponents = URLComponents(string: server.serverUrl) else { return nil }
        urlComponents.path.append("/grsync/update_reading_progress")
        urlComponents.queryItems = [
            URLQueryItem(name: "goodreads_id", value: goodreads_id.description),
            URLQueryItem(name: "profile_name", value: profileName)
        ]
        
        return urlComponents
    }
    
    
    func addToShelf(goodreads_id: String, shelfName: String) -> Bool {
        guard var endpointBaseUrl = endpointBaseUrlAddRemove(goodreads_id: goodreads_id, shelfName: shelfName) else {
            return false
        }
        endpointBaseUrl.queryItems!.append(URLQueryItem(name: "action", value: "add"))
        
        guard let url = endpointBaseUrl.url else { return false }
        
        let request = URLRequest(url: url)

        let task = URLSession.shared.dataTask(with: request) { [self] data, response, error in
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

        let task = URLSession.shared.dataTask(with: request) { [self] data, response, error in
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

        let task = URLSession.shared.dataTask(with: request) { [self] data, response, error in
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
