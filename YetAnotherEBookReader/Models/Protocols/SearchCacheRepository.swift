//
//  SearchCacheRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-10.
//

import Foundation

struct LibrarySourceSearchResult: Equatable, Sendable {
    var generation: Date
    var totalNumber: Int
    var bookIds: [Int32]
    var books: [CalibreBook]
    
    init(
        generation: Date = Date(timeIntervalSince1970: 0),
        totalNumber: Int = 0,
        bookIds: [Int32] = [],
        books: [CalibreBook] = []
    ) {
        self.generation = generation
        self.totalNumber = totalNumber
        self.bookIds = bookIds
        self.books = books
    }
}

struct LibraryCachedResult: Equatable, Sendable {
    var libraryId: String
    var search: String
    var sortBy: SortCriteria
    var sortAsc: Bool
    var filters: [String: Set<String>]
    var sources: [String: LibrarySourceSearchResult]
    
    init(
        libraryId: String = "",
        search: String = "",
        sortBy: SortCriteria = .Modified,
        sortAsc: Bool = false,
        filters: [String: Set<String>] = [:],
        sources: [String: LibrarySourceSearchResult] = [:]
    ) {
        self.libraryId = libraryId
        self.search = search
        self.sortBy = sortBy
        self.sortAsc = sortAsc
        self.filters = filters
        self.sources = sources
    }
}

struct LocalLibrarySearchResult: Equatable, Sendable {
    var totalNumber: Int
    var numBooksWithoutSearch: Int
    var offset: Int
    var num: Int
    var sort: String
    var bookIds: [Int32]

    init(
        totalNumber: Int = 0,
        numBooksWithoutSearch: Int = 0,
        offset: Int = 0,
        num: Int = 0,
        sort: String = "",
        bookIds: [Int32] = []
    ) {
        self.totalNumber = totalNumber
        self.numBooksWithoutSearch = numBooksWithoutSearch
        self.offset = offset
        self.num = num
        self.sort = sort
        self.bookIds = bookIds
    }
}

protocol SearchCacheRepository: Sendable {
    func fetchLibraryCachedResult(
        libraryId: String,
        search: String,
        sortBy: SortCriteria,
        sortAsc: Bool,
        filters: [String: Set<String>]
    ) throws -> LibraryCachedResult?
    
    func saveLibrarySourceResult(
        libraryId: String,
        search: String,
        sortBy: SortCriteria,
        sortAsc: Bool,
        filters: [String: Set<String>],
        sourceUrl: String,
        result: LibrarySourceSearchResult
    ) throws

    func fetchBooks(
        library: CalibreLibrary,
        bookIds: [Int32]
    ) throws -> [Int32: CalibreBook]

    func searchLocalLibrary(
        library: CalibreLibrary,
        criteria: SearchCriteria,
        offset: Int,
        limit: Int
    ) throws -> LocalLibrarySearchResult

    func writeMetadataEntries(
        library: CalibreLibrary,
        entries: [String: CalibreBookEntry?],
        json: NSDictionary?
    ) throws
}
