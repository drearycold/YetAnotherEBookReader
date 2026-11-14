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
    var libraryId: String? = nil
}

struct CalibreBooksMetadataRequest {
    let library: CalibreLibrary
    let books: [Int32]
    let getAnnotations: Bool
}

/// The answer for one book in this request; independent of the service's legacy global status.
enum BookMetadataRefreshResult: Equatable {
    case updated
    case unchanged
    case unavailable
    case localBookMissing
    case failed(String)
    case superseded
    case cancelled
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
    
    var invalidMetadataIDs = Set<Int32>()

    var error: CalibreAPIError? = nil
    var annotationsError: CalibreAPIError? = nil

    var metadataAnswers: [Int32: BookMetadataAnswer] {
        var answers: [Int32: BookMetadataAnswer] = [:]
        for id in books {
            if invalidMetadataIDs.contains(id) {
                answers[id] = .invalid
            } else if let answer = booksMetadataEntry?[id.description] {
                switch answer {
                case .none:
                    answers[id] = .unavailable
                case .some(let entry):
                    let root = booksMetadataJSON?[id.description] as? NSDictionary ?? [:]
                    answers[id] = .metadata(.init(entry: entry, root: root))
                }
            }
        }
        return answers
    }
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
    var error: CalibreAPIError?
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
    var error: CalibreAPIError?
}
