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


