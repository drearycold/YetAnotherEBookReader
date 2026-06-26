//
//  CalibreServerService+Search.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026-06-17.
//

import Foundation

extension CalibreServerService {
    func buildLibrarySearchTasks(
        library: CalibreLibrary,
        searchCriteria: SearchCriteria,
        parameters: [String: (generation: Date, num: Int, offset: Int)]
    ) -> [CalibreLibrarySearchTask] {
        var serverUrls = [URL]()
        if let baseUrl = URL(string: library.server.baseUrl) {
            serverUrls.append(baseUrl)
        }
        if library.server.hasPublicUrl,
           let publicUrl = URL(string: library.server.publicUrl) {
            serverUrls.append(publicUrl)
        }
        if library.autoUpdate || library.server.isLocal {
            serverUrls.append(URL(fileURLWithPath: "/realm"))
        }
        
        guard !serverUrls.isEmpty else {
            return []
        }
        
        let sortQueryItems = [
            URLQueryItem(name: "sort", value: searchCriteria.sortCriteria.by.sortQueryParam),
            URLQueryItem(name: "sort_order", value: searchCriteria.sortCriteria.ascending ? "asc" : "desc")
        ]
        
        var queryStrings = [String]()
        if !searchCriteria.searchString.isEmpty {
            queryStrings.append(searchCriteria.searchString)
        }
        
        searchCriteria.filterCriteriaCategory.forEach { entry in
            var queryKey = entry.key.lowercased()
            var queryIsRating = entry.key == "Rating"
            
            if let customColumnInfo = library.customColumnInfos.first(where: { $0.value.name == entry.key }) {
                queryKey = "#\(customColumnInfo.key)"
                queryIsRating = customColumnInfo.value.datatype == "rating"
            }
            
            let query = entry.value.map {
                "\(queryKey):" + (queryIsRating ? "\($0.count)" : "\"=\($0)\"")
            }.joined(separator: " OR ")
            
            if !query.isEmpty {
                queryStrings.append("( " + query + " )")
            }
        }
        
        return serverUrls.compactMap { serverUrl in
            var booksListUrlComponents = URLComponents()
            booksListUrlComponents.path = "ajax/search/\(library.key)"
            
            let parameter = parameters[
                serverUrl.absoluteString.replacingOccurrences(of: ".", with: "_")
            ] ?? (generation: library.lastModified, num: 100, offset: 0)
            
            booksListUrlComponents.queryItems = sortQueryItems + [
                .init(name: "offset", value: parameter.offset.description),
                .init(name: "num", value: parameter.num.description),
                .init(name: "query", value: queryStrings.joined(separator: " AND "))
            ]
            
            guard let booksListUrl = booksListUrlComponents.url(relativeTo: serverUrl) else {
                return nil
            }
            
            return CalibreLibrarySearchTask(
                serverUrl: serverUrl,
                generation: parameter.generation,
                library: library,
                searchCriteria: searchCriteria,
                booksListUrl: booksListUrl,
                offset: parameter.offset,
                num: parameter.num
            )
        }
    }
}
