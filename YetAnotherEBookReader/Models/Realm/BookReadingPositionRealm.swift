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
    
    var epochByLocale: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: Date(timeIntervalSince1970: epoch))
    }
    
    var epochLocaleLong: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .long
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: Date(timeIntervalSince1970: epoch))
    }
}

extension BookDeviceReadingPosition: Persistable {
    public init(managedObject: BookDeviceReadingPositionRealm) {
        self = managedObject.toDomain()
    }
    
    public func managedObject() -> BookDeviceReadingPositionRealm {
        return self.makeRealmObject(bookId: "")
    }
    
    public func managedObject(bookId: String) -> BookDeviceReadingPositionRealm {
        return self.makeRealmObject(bookId: bookId)
    }
}

class BookDeviceReadingPositionHistoryRealm: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId
    
    @Persisted var bookId: String = ""
    
    @Persisted var startDatetime = Date()
    @Persisted var startPosition: BookDeviceReadingPositionRealm?
    @Persisted var endPosition: BookDeviceReadingPositionRealm?
    
    var startDateByLocale: String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: startDatetime)
    }
    var startDateByLocaleLong: String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .long
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: startDatetime)
    }
    
    override static func primaryKey()-> String? {
        return "_id"
    }
}

extension BookDeviceReadingPositionHistory: Persistable {
    public init(managedObject: BookDeviceReadingPositionHistoryRealm) {
        self = managedObject.toDomain()
    }
    
    public func managedObject() -> BookDeviceReadingPositionHistoryRealm {
        return self.makeRealmObject()
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
