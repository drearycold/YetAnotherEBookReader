//
//  CalibreTasks.swift
//  YetAnotherEBookReader
//
//  Split from CalibreData.swift on 2026/6/18.
//  Zero-behavior-change move: network/metadata task structs consumed by
//  managers and services.
//

import Foundation

struct CalibreBookTask {
    var server: CalibreServer
    var bookId: Int32
    var inShelfId: String
    var url: URL
}

struct CalibreBooksMetadataRequest {
    let library: CalibreLibrary
    let books: [Int32]
    let getAnnotations: Bool
}

struct CalibreBooksTask {
    let request: CalibreBooksMetadataRequest
    var library: CalibreLibrary {
        request.library
    }
    var books: [Int32] {
        request.books
    }
    var metadataUrl: URL?
    var lastReadPositionUrl: URL?
    var annotationsUrl: URL?
    var data: Data?
    var response: URLResponse?
    var lastReadPositionsData: Data?
    var annotationsData: Data?
    
    var booksMetadataEntry: [String: CalibreBookEntry?]?
    var booksMetadataJSON: NSDictionary?
    
    var booksAnnotationsEntry: [String:CalibreBookAnnotationsResult]?
    
    var searchCriteria: SearchCriteria?
    var searchTask: CalibreLibrarySearchTask?
    
    var booksUpdated = Set<Int32>()
    var booksError = Set<Int32>()
    var booksDeleted = Set<Int32>()
    var booksInShelf = [CalibreBook]()
    var booksAnnotation = [CalibreBook]()
}

struct CalibreLibraryProbeTask {
    let library: CalibreLibrary
    let probeUrl: URL
    
    var probeResult: CalibreLibraryBooksResult.SearchResult?
}

struct CalibreLibrarySearchTask: Identifiable {
    let id = UUID()
    let serverUrl: URL
    
    let generation: Date
    
    let library: CalibreLibrary
    let searchCriteria: SearchCriteria
    let booksListUrl: URL
    let offset: Int
    let num: Int
    
    //results
    var data: Data? = nil
    var booksMetadataEntry: [String: CalibreBookEntry?]? = nil
    var booksMetadataJSON: NSDictionary? = nil
    var ajaxSearchResult: CalibreLibraryBooksResult.SearchResult? = nil
    var ajaxSearchError = false
}

struct CalibreBookSetLastReadPositionTask {
    let library: CalibreLibrary
    let bookId: Int32
    let format: Format
    let entry: CalibreBookLastReadPositionEntry
    var urlRequest: URLRequest
    var urlResponse: URLResponse?
    var data: Data?
    let startDatetime: Date
}

struct CalibreBookUpdateAnnotationsTask {
    let library: CalibreLibrary
    let bookId: Int32
    let format: Format
    let entry: [String : [Any]]
    let startDatetime = Date()
    var urlRequest: URLRequest
    var urlResponse: URLResponse?
    var data: Data?
}
