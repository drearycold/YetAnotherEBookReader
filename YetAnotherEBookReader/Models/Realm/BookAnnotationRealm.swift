//
//  BookAnnotationRealm.swift
//  YetAnotherEBookReader
//

import Foundation
import RealmSwift

class BookHighlightRealm: Object {
    @objc open dynamic var removed: Bool = false
    
    @objc open dynamic var bookId: String = ""
    @objc open dynamic var highlightId: String = ""
    @objc open dynamic var readerName: String = ""
    
    @objc open dynamic var page: Int = 0
    @objc open dynamic var startOffset: Int = -1
    @objc open dynamic var endOffset: Int = -1
    
    @objc open dynamic var date: Date = .init()
    @objc open dynamic var type: Int = 0
    @objc open dynamic var note: String?
    
    open dynamic var tocFamilyTitles = List<String>()
    @objc open dynamic var content: String = ""
    @objc open dynamic var contentPost: String = ""
    @objc open dynamic var contentPre: String = ""
    
    // MARK: EPUB Specific
    @objc open dynamic var cfiStart: String?
    @objc open dynamic var cfiEnd: String?
    @objc open dynamic var spineName: String?
    
    // MARK: PDF Specific
    @objc open dynamic var ranges: String?
    
    var contentEncoded: String? {
        content.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }
    var contentPreEncoded: String? {
        contentPre.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }
    var contentPostEncoded: String? {
        contentPost.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }
    
    override static func primaryKey()-> String? {
        return "highlightId"
    }
}

class BookBookmarkRealm: Object, ObjectKeyIdentifiable {
    static let PDFBookmarkPosType = "yabrpdf"
    
    @objc dynamic var _id: ObjectId = .generate()
    @objc dynamic var bookId: String = .init()
    @objc dynamic var page: Int = .zero
    
    @objc dynamic var pos_type: String = .init()
    @objc dynamic var pos: String = .init()
    
    @objc dynamic var title: String = .init()
    @objc dynamic var date: Date = .init()
    
    @objc dynamic var removed: Bool = false
    
    override static func primaryKey() -> String? {
        return "_id"
    }
}

extension BookHighlightRealm {
    func toCalibreBookAnnotationHighlightEntry() -> CalibreBookAnnotationHighlightEntry? {
        guard let uuid = uuidFolioToCalibre(highlightId),
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
                tocFamilyTitles: tocFamilyTitles.map { $0 },
                notes: note
            )
        default:
            return nil
        }
    }
}

extension BookBookmarkRealm {
    static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
        return formatter
    }()
    
    func toCalibreBookAnnotationBookmarkEntry() -> CalibreBookAnnotationBookmarkEntry {
        return CalibreBookAnnotationBookmarkEntry(
            type: "bookmark",
            timestamp: BookBookmarkRealm.dateFormatter.string(from: date),
            pos_type: pos_type,
            pos: pos,
            title: title,
            removed: removed
        )
    }
}
