//
//  SearchCacheRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-10.
//

import Foundation

enum CacheContextError: Error, Equatable {
    case databaseUnavailable
    case superseded
}

/// Invalidated when a published library changes identity, connection, generation or visibility.
final class CacheLibraryLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true

    func invalidate() { lock.withLock { valid = false } }

    func checkCurrent() throws {
        try withCurrent {}
    }

    func withCurrent<T>(_ body: () throws -> T) throws -> T {
        try lock.withLock {
            guard valid else { throw CacheContextError.superseded }
            return try body()
        }
    }
}

extension CalibreLibrary {
    func hasSameCacheScope(as other: CalibreLibrary) -> Bool {
        id == other.id && key == other.key && hidden == other.hidden && lastModified == other.lastModified
            && categoryFields == other.categoryFields && customColumnInfos == other.customColumnInfos
            && DSReaderHelperConnection(server) == DSReaderHelperConnection(other.server)
    }
}

enum CacheWriteExpectation<Value: Sendable>: Sendable {
    case unconditional
    case previous(Value?)
}

struct SearchSourceState: Equatable, Sendable {
    let generation: Date
    let totalNumber: Int
    let bookIds: [Int32]
}

protocol CacheRepository: Sendable {
    func snapshot() throws -> Self
    func scoped(to library: CalibreLibrary, lifetime: CacheLibraryLifetime?) throws -> Self
    func checkCurrent() throws
}

extension CacheRepository {
    func snapshot() throws -> Self { self }
    func scoped(to library: CalibreLibrary, lifetime: CacheLibraryLifetime?) throws -> Self { self }
    func checkCurrent() throws {}
}

struct LibrarySourceSearchResult: Equatable, Sendable {
    var generation: Date
    var totalNumber: Int
    var bookIds: [Int32]
    var books: [CalibreBook]

    var sourceState: SearchSourceState {
        SearchSourceState(generation: generation, totalNumber: totalNumber, bookIds: bookIds)
    }
    
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

protocol SearchCacheRepository: CacheRepository {
    func observeBookChanges(in libraries: [CalibreLibrary]) -> AsyncStream<Void>
    func fetchLibraryCachedResult(
        library: CalibreLibrary,
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
        result: LibrarySourceSearchResult,
        expecting: CacheWriteExpectation<SearchSourceState>
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
        json: NSDictionary?,
        retainingExisting: Set<Int32>,
        metadataBaseline: [Int32: Date]
    ) throws
}

extension SearchCacheRepository {
    func observeBookChanges(in libraries: [CalibreLibrary]) -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    func writeMetadataEntries(library: CalibreLibrary, entries: [String: CalibreBookEntry?], json: NSDictionary?,
                              retainingExisting: Set<Int32> = []) throws {
        try writeMetadataEntries(library: library, entries: entries, json: json, retainingExisting: retainingExisting,
                                 metadataBaseline: [:])
    }

    func saveLibrarySourceResult(
        libraryId: String, search: String, sortBy: SortCriteria, sortAsc: Bool, filters: [String: Set<String>],
        sourceUrl: String, result: LibrarySourceSearchResult
    ) throws {
        try saveLibrarySourceResult(libraryId: libraryId, search: search, sortBy: sortBy, sortAsc: sortAsc,
                                    filters: filters, sourceUrl: sourceUrl, result: result, expecting: .unconditional)
    }
}
