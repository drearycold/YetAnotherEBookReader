//
//  MergeHead.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-10.
//

import Foundation

struct MergeHead: Comparable {
    let libraryId: String
    let books: [CalibreBook]
    var offset: Int
    let sortBy: SortCriteria
    
    var currentBook: CalibreBook {
        books[offset]
    }
    
    var hasNext: Bool {
        offset + 1 < books.count
    }
    
    mutating func advance() -> Bool {
        guard hasNext else { return false }
        offset += 1
        return true
    }
    
    static func < (lhs: MergeHead, rhs: MergeHead) -> Bool {
        let lhsBook = lhs.currentBook
        let rhsBook = rhs.currentBook
        
        switch lhs.sortBy {
        case .Title:
            let result = lhsBook.title.compare(rhsBook.title)
            if result == .orderedSame {
                return lhs.libraryId < rhs.libraryId || (lhs.libraryId == rhs.libraryId && lhsBook.id < rhsBook.id)
            }
            return result == .orderedAscending
        case .Added:
            let result = lhsBook.timestamp.compare(rhsBook.timestamp)
            if result == .orderedSame {
                return lhs.libraryId < rhs.libraryId || (lhs.libraryId == rhs.libraryId && lhsBook.id < rhsBook.id)
            }
            return result == .orderedAscending
        case .Publication:
            let result = lhsBook.pubDate.compare(rhsBook.pubDate)
            if result == .orderedSame {
                return lhs.libraryId < rhs.libraryId || (lhs.libraryId == rhs.libraryId && lhsBook.id < rhsBook.id)
            }
            return result == .orderedAscending
        case .Modified:
            let result = lhsBook.lastModified.compare(rhsBook.lastModified)
            if result == .orderedSame {
                return lhs.libraryId < rhs.libraryId || (lhs.libraryId == rhs.libraryId && lhsBook.id < rhsBook.id)
            }
            return result == .orderedAscending
        case .SeriesIndex:
            if lhsBook.seriesIndex == rhsBook.seriesIndex {
                return lhs.libraryId < rhs.libraryId || (lhs.libraryId == rhs.libraryId && lhsBook.id < rhsBook.id)
            }
            return lhsBook.seriesIndex < rhsBook.seriesIndex
        }
    }
    
    static func == (lhs: MergeHead, rhs: MergeHead) -> Bool {
        let lhsBook = lhs.currentBook
        let rhsBook = rhs.currentBook
        
        return lhs.libraryId == rhs.libraryId && lhsBook.id == rhsBook.id
    }
}
