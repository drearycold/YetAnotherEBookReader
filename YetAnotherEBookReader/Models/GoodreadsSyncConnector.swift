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
    
    func addToShelf(goodreads_id: String, shelfName: String) -> Bool {
        let request = URLRequest(url: URL(string: server.baseUrl + "/grsync/add_remove_book_to_shelf?goodreads_id=\(goodreads_id)&profile_name=\(profileName)&shelf_name=\(shelfName)&action=add")!)

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
        let request = URLRequest(url: URL(string: server.baseUrl + "/grsync/add_remove_book_to_shelf?goodreads_id=\(goodreads_id)&profile_name=\(profileName)&shelf_name=\(shelfName)&action=remove")!)

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
        let request = URLRequest(url: URL(string: server.baseUrl + "/grsync/update_reading_progress?goodreads_id=\(goodreads_id)&profile_name=\(profileName)&percent=\(progress)")!)

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
