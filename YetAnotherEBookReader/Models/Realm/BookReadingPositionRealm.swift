//
//  BookReadingPositionRealm.swift
//  YetAnotherEBookReader
//

import Foundation
import RealmSwift

class BookDeviceReadingPositionRealm: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId
    
    @Persisted var bookId: String = .init()
//    @Persisted var id = ""
    @Persisted var deviceId: String
    
    @Persisted var readerName: String
    @Persisted var maxPage = 0
    @Persisted var lastReadPage = 0
    @Persisted var lastReadChapter = ""
    /// range 0 - 100
    @Persisted var lastChapterProgress = 0.0
    /// range 0 - 100
    @Persisted var lastProgress = 0.0
    @Persisted var furthestReadPage = 0
    @Persisted var furthestReadChapter = ""
    @Persisted var lastPosition: List<Int>
    @Persisted var cfi = "/"
    @Persisted var epoch = 0.0
    
    /// Legacy/inert field from old synchronization/FolioReader logic.
    /// Do not use for new features; session lifecycle and position selection are now policy-based.
    @Persisted var takePrecedence: Bool = false
    
    //for non-linear book structure
    @Persisted var structuralStyle: Int = .zero
    @Persisted var structuralRootPageNumber: Int = 1
    @Persisted var positionTrackingStyle: Int = .zero
    @Persisted var lastReadBook = ""
    @Persisted var lastBundleProgress: Double = .zero
    
}

class BookDeviceReadingPositionHistoryRealm: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId
    
    @Persisted var bookId: String = ""
    
    @Persisted var startDatetime = Date()
    @Persisted var startPosition: BookDeviceReadingPositionRealm?
    @Persisted var endPosition: BookDeviceReadingPositionRealm?
    
    override static func primaryKey()-> String? {
        return "_id"
    }
}

@available(*, deprecated, message: "Remove CalibreBookLastReadPositionRealm")
class CalibreBookLastReadPositionRealm: Object {
    @objc dynamic var device = ""
    @objc dynamic var cfi = ""
    @objc dynamic var epoch = 0.0
    @objc dynamic var pos_frac = 0.0
    
    override static func primaryKey() -> String? {
        return "device"
    }
}
