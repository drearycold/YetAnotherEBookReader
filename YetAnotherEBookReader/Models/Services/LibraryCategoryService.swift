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
    
    func fetchAndCacheCategory(
        library: CalibreLibrary, category: CalibreLibraryCategory, cache: CategoryCacheRepository? = nil
    ) async throws -> LibraryCategoryResult {
        try Task.checkCancellation()
        let database = try (cache ?? repository.snapshot())
        let cache = try database.scoped(to: library, lifetime: service.cacheLifetime(for: library))
        guard let serverUrl = service.getServerUrlByReachability(server: library.server) else {
            throw URLError(.cannotFindHost)
        }
        
        let categoryName = category.name
        let libraryId = library.id
        
        // Check if we already have a fresh cache
        let existing = try cache.fetchLibraryCategoryResult(libraryId: libraryId, categoryName: categoryName)
        if let existing, existing.generation >= library.lastModified {
            return existing
        }
        
        var items: [LibraryCategoryItem] = []
        var offset = 0
        let limit = 10000 // page limit
        
        while true {
            try Task.checkCancellation()
            try cache.checkCurrent()
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
                
                try Task.checkCancellation()
                try cache.saveLibraryCategoryResult(libraryId: libraryId, categoryName: categoryName,
                                                    result: finalResult, expecting: .previous(existing))
                try cache.checkCurrent()
                return finalResult
            }
            
            offset = items.count
        }
    }
}
