//
//  LibraryCategoryService.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-12.
//

import Foundation

actor LibraryCategoryService {
    private let service: CalibreServerService
    private let repository: CategoryCacheRepository
    
    init(service: CalibreServerService, repository: CategoryCacheRepository) {
        self.service = service
        self.repository = repository
    }
    
    func fetchAndCacheCategory(library: CalibreLibrary, category: CalibreLibraryCategory) async throws -> LibraryCategoryResult {
        guard let serverUrl = service.getServerUrlByReachability(server: library.server) else {
            throw URLError(.cannotFindHost)
        }
        
        let categoryName = category.name
        let libraryId = library.id
        
        // Check if we already have a fresh cache
        if let existing = try? repository.fetchLibraryCategoryResult(libraryId: libraryId, categoryName: categoryName) {
            if existing.generation >= library.lastModified {
                return existing
            }
        }
        
        var items: [LibraryCategoryItem] = []
        var offset = 0
        let limit = 10000 // page limit
        
        while true {
            guard var urlComponents = URLComponents(string: category.url) else {
                throw URLError(.badURL)
            }
            urlComponents.queryItems = [
                URLQueryItem(name: "num", value: limit.description),
                URLQueryItem(name: "offset", value: offset.description)
            ]
            
            guard let url = urlComponents.url(relativeTo: serverUrl) else {
                throw URLError(.badURL)
            }
            
            let result: LibraryCategoryListResult
            if url.isHTTP {
                result = try await service.withRequestActivity(
                    .categories, request: URLRequest(url: url), server: library.server,
                    libraryId: libraryId, qos: .background
                ) { data, response in
                    try service.requireJSON(response)
                    return try service.decodePayload(LibraryCategoryListResult.self, from: data)
                }
            } else {
                let (data, _) = try await service.withURLSession(server: library.server, qos: .background) {
                    try await $0.data(from: url)
                }
                result = try JSONDecoder().decode(LibraryCategoryListResult.self, from: data)
            }

            let fetched = result.items.map { item in
                LibraryCategoryItem(
                    name: item.name,
                    averageRating: item.average_rating,
                    count: item.count,
                    url: item.url
                )
            }
            items.append(contentsOf: fetched)
            
            if items.count >= result.total_num || fetched.isEmpty {
                let finalResult = LibraryCategoryResult(
                    libraryId: libraryId,
                    categoryName: categoryName,
                    items: items,
                    generation: library.lastModified,
                    totalNumber: result.total_num
                )
                
                try repository.saveLibraryCategoryResult(libraryId: libraryId, categoryName: categoryName, result: finalResult)
                return finalResult
            }
            
            offset = items.count
        }
    }
}
