//
//  BookBookmark.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/14.
//

import Foundation

struct BookBookmark: Identifiable, Hashable {
    var id: String
    var bookId: String
    var page: Int
    var pos_type: String
    var pos: String
    var title: String
    var date: Date
    var removed: Bool
    
    init(
        id: String = UUID().uuidString,
        bookId: String,
        page: Int,
        pos_type: String,
        pos: String,
        title: String,
        date: Date,
        removed: Bool = false
    ) {
        self.id = id
        self.bookId = bookId
        self.page = page
        self.pos_type = pos_type
        self.pos = pos
        self.title = title
        self.date = date
        self.removed = removed
    }
}

extension BookBookmark {
    static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
        return formatter
    }()
    
    func toCalibreBookAnnotationBookmarkEntry() -> CalibreBookAnnotationBookmarkEntry {
        return CalibreBookAnnotationBookmarkEntry(
            type: "bookmark",
            timestamp: BookBookmark.dateFormatter.string(from: date),
            pos_type: pos_type,
            pos: pos,
            title: title,
            removed: removed
        )
    }
}
