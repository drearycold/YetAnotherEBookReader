//
//  BookHighlight.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/14.
//

import Foundation

struct BookHighlight: Identifiable, Hashable {
    var id: String // highlightId
    var bookId: String
    var readerName: String
    var page: Int
    var startOffset: Int
    var endOffset: Int
    var date: Date
    var type: Int
    var note: String?
    var tocFamilyTitles: [String]
    var content: String
    var contentPost: String
    var contentPre: String
    
    // EPUB specific
    var cfiStart: String?
    var cfiEnd: String?
    var spineName: String?
    
    // PDF specific
    var ranges: String?
    
    var removed: Bool
    
    init(
        id: String = UUID().uuidString,
        bookId: String,
        readerName: String,
        page: Int,
        startOffset: Int,
        endOffset: Int,
        date: Date,
        type: Int,
        note: String? = nil,
        tocFamilyTitles: [String] = [],
        content: String = "",
        contentPost: String = "",
        contentPre: String = "",
        cfiStart: String? = nil,
        cfiEnd: String? = nil,
        spineName: String? = nil,
        ranges: String? = nil,
        removed: Bool = false
    ) {
        self.id = id
        self.bookId = bookId
        self.readerName = readerName
        self.page = page
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.date = date
        self.type = type
        self.note = note
        self.tocFamilyTitles = tocFamilyTitles
        self.content = content
        self.contentPost = contentPost
        self.contentPre = contentPre
        self.cfiStart = cfiStart
        self.cfiEnd = cfiEnd
        self.spineName = spineName
        self.ranges = ranges
        self.removed = removed
    }
}

extension BookHighlight {
    func toCalibreBookAnnotationHighlightEntry() -> CalibreBookAnnotationHighlightEntry? {
        guard let uuid = uuidFolioToCalibre(id),
              let readerType = ReaderType(rawValue: readerName)
        else { return nil }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
        
        switch readerType {
        case .YabrEPUB, .YabrPDF:
            return CalibreBookAnnotationHighlightEntry(
                type: "highlight",
                timestamp: dateFormatter.string(from: date),
                uuid: uuid,
                removed: removed,
                ranges: ranges,
                startCfi: cfiStart,
                endCfi: cfiEnd,
                highlightedText: content,
                style: ["kind":"color", "type":"builtin", "which": BookHighlightStyle.classForStyleCalibre(type)],
                spineName: spineName,
                spineIndex: page - 1,
                tocFamilyTitles: tocFamilyTitles,
                notes: note
            )
        default:
            return nil
        }
    }
}

extension BookHighlight {
    func toReaderEngineHighlight() -> ReaderEngineHighlight {
        return ReaderEngineHighlight(
            id: id,
            bookId: bookId,
            readerName: readerName,
            page: page,
            startOffset: startOffset,
            endOffset: endOffset,
            date: date,
            type: type,
            note: note,
            tocFamilyTitles: tocFamilyTitles,
            content: content,
            contentPost: contentPost,
            contentPre: contentPre,
            cfiStart: cfiStart,
            cfiEnd: cfiEnd,
            spineName: spineName,
            ranges: ranges,
            removed: removed
        )
    }
}

extension ReaderEngineHighlight {
    func toBookHighlight() -> BookHighlight {
        return BookHighlight(
            id: id,
            bookId: bookId,
            readerName: readerName,
            page: page,
            startOffset: startOffset,
            endOffset: endOffset,
            date: date,
            type: type,
            note: note,
            tocFamilyTitles: tocFamilyTitles,
            content: content,
            contentPost: contentPost,
            contentPre: contentPre,
            cfiStart: cfiStart,
            cfiEnd: cfiEnd,
            spineName: spineName,
            ranges: ranges,
            removed: removed
        )
    }
}
