//
//  UnifiedSearchModels.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-10.
//

import Foundation

enum SearchError: Error, Equatable, Sendable {
    case network(String)
    case database(String)
    case unknown(String)
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
