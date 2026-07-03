//
//  UnifiedSearchModels.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-10.
//

import Foundation

struct LibrarySearchSort: Hashable, CustomStringConvertible {
    var by = SortCriteria.Modified
    var ascending = false
    
    var description: String {
        "\(ascending ? "First" : "Last") \(by)"
    }
}

enum SortCriteria: String, CaseIterable, Identifiable, CustomStringConvertible {
    var id: String { self.rawValue }
    
    case Title
    case Added
    case Publication
    case Modified
    case SeriesIndex
    
    var sortKeyPath: String {
        switch self {
        case .Title:
            return "title"
        case .Added:
            return "timestamp"
        case .Publication:
            return "pubDate"
        case .Modified:
            return "lastModified"
        case .SeriesIndex:
            return "seriesIndex"
        }
    }
    
    var sortQueryParam: String {
        switch self {
        case .Title:
            return "sort"
        case .Added:
            return "timestamp"
        case .Publication:
            return "pubdate"
        case .Modified:
            return "last_modified"
        case .SeriesIndex:
            return "series_index"
        }
    }
    
    var description: String {
        switch self {
        case .SeriesIndex:
            return "Series Index"
        default:
            return rawValue
        }
    }
}

struct SearchCriteria: Hashable, CustomStringConvertible {
    let searchString: String
    let sortCriteria: LibrarySearchSort
    let filterCriteriaCategory: [String: Set<String>]
    let pageSize: Int = 100
    
    var hasEmptyFilter: Bool {
        filterCriteriaCategory.isEmpty
    }
    
    var description: String {
        "\(searchString)^\(sortCriteria)^\(filterCriteriaCategory)"
    }
}

struct SearchCriteriaMergedKey: Hashable {
    let libraryIds: Set<String>
    let criteria: SearchCriteria
}

enum SearchError: Error, Equatable, Sendable {
    case network(CalibreAPIError)
    case database(String)
    case invalidState(String)
    case cancelled
}

struct LibrarySearchStatus: Equatable, Sendable {
    var loading: Bool
    var error: SearchError?
    
    init(loading: Bool = false, error: SearchError? = nil) {
        self.loading = loading
        self.error = error
    }
}

struct MergeOffset: Codable, Equatable, Sendable {
    var beenCutOff: Bool
    var beenConsumed: Bool
    var cutOffOffset: Int
    var offset: Int
    var generation: Date
    var searchObjectSource: String

    init(
        beenCutOff: Bool = false,
        beenConsumed: Bool = false,
        cutOffOffset: Int = 0,
        offset: Int = 0,
        generation: Date = Date(timeIntervalSince1970: 0),
        searchObjectSource: String = ""
    ) {
        self.beenCutOff = beenCutOff
        self.beenConsumed = beenConsumed
        self.cutOffOffset = cutOffOffset
        self.offset = offset
        self.generation = generation
        self.searchObjectSource = searchObjectSource
    }
}

struct UnifiedSearchResult: Equatable, Sendable {
    var search: String
    var sortBy: SortCriteria
    var sortAsc: Bool
    var filters: [String: Set<String>]
    var libraryIds: Set<String>
    var unifiedOffsets: [String: MergeOffset]
    var totalNumber: Int
    var limitNumber: Int
    var books: [CalibreBook]
    
    init(
        search: String = "",
        sortBy: SortCriteria = .Modified,
        sortAsc: Bool = false,
        filters: [String: Set<String>] = [:],
        libraryIds: Set<String> = [],
        unifiedOffsets: [String: MergeOffset] = [:],
        totalNumber: Int = 0,
        limitNumber: Int = 100,
        books: [CalibreBook] = []
    ) {
        self.search = search
        self.sortBy = sortBy
        self.sortAsc = sortAsc
        self.filters = filters
        self.libraryIds = libraryIds
        self.unifiedOffsets = unifiedOffsets
        self.totalNumber = totalNumber
        self.limitNumber = limitNumber
        self.books = books
    }
}

struct SearchUpdate: Equatable, Sendable {
    let result: UnifiedSearchResult
    let statuses: [String: LibrarySearchStatus]
}

protocol LibraryProvider {
    @MainActor func getLibraries() -> [String: CalibreLibrary]
    @MainActor func isServerReachable(server: CalibreServer, isPublic: Bool) -> Bool?
    @MainActor func isServerReachable(server: CalibreServer) -> Bool
}
