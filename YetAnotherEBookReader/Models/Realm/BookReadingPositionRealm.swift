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
        id = managedObject.deviceId
        readerName = managedObject.readerName
        maxPage = managedObject.maxPage
        lastReadPage = managedObject.lastReadPage
        lastReadChapter = managedObject.lastReadChapter
        lastChapterProgress = managedObject.lastChapterProgress
        lastProgress = managedObject.lastProgress
        furthestReadPage = managedObject.furthestReadPage
        furthestReadChapter = managedObject.furthestReadChapter
        lastPosition = managedObject.lastPosition.map{$0}
        cfi = managedObject.cfi
        epoch = managedObject.epoch
        
        structuralStyle = managedObject.structuralStyle
        structuralRootPageNumber = managedObject.structuralRootPageNumber
        positionTrackingStyle = managedObject.positionTrackingStyle
        lastReadBook = managedObject.lastReadBook
        lastBundleProgress = managedObject.lastBundleProgress
    }
    
    public func managedObject() -> BookDeviceReadingPositionRealm {
        let obj = BookDeviceReadingPositionRealm()
        obj.deviceId = id
        obj.readerName = readerName
        obj.maxPage = maxPage
        obj.lastReadPage = lastReadPage
        obj.lastReadChapter = lastReadChapter
        obj.lastChapterProgress = lastChapterProgress
        obj.lastProgress = lastProgress
        obj.furthestReadPage = furthestReadPage
        obj.furthestReadChapter = furthestReadChapter
        obj.lastPosition.append(objectsIn: lastPosition)
        obj.cfi = cfi
        obj.epoch = epoch
        
        obj.structuralStyle = structuralStyle
        obj.structuralRootPageNumber = structuralRootPageNumber
        obj.positionTrackingStyle = positionTrackingStyle
        obj.lastReadBook = lastReadBook
        obj.lastBundleProgress = lastBundleProgress
        
        return obj
    }
    
    public func managedObject(bookId: String) -> BookDeviceReadingPositionRealm {
        let obj = managedObject()
        obj.bookId = bookId
        return obj
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
        self.bookId = managedObject.bookId
        self.startDatetime = managedObject.startDatetime
        if let startPosition = managedObject.startPosition {
            self.startPosition = .init(managedObject: startPosition)
        }
        if let endPosition = managedObject.endPosition {
            self.endPosition = .init(managedObject: endPosition)
        }
    }
    
    public func managedObject() -> BookDeviceReadingPositionHistoryRealm {
        let object = BookDeviceReadingPositionHistoryRealm()
        object.bookId = self.bookId
        object.startDatetime = self.startDatetime
        object.startPosition = self.startPosition?.managedObject()
        object.endPosition = self.endPosition?.managedObject()
        return object
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

extension BookDeviceReadingPosition {
    public init?(entry: CalibreBookLastReadPositionEntry) {
        guard let vndFirstRange = entry.cfi.range(of: ";vndYabr_") ?? entry.cfi.range(of: ";vnd_"),
              let vndEndRange = entry.cfi.range(of: "]", range: vndFirstRange.upperBound..<entry.cfi.endIndex)
        else { return nil }
        
        let vndParameters = entry.cfi[vndFirstRange.lowerBound..<vndEndRange.lowerBound]
        
        var parameters = [String: String]()
        vndParameters.split(separator: ";").forEach { p in
            guard let equalIndex = p.firstIndex(of: "=") else { return }
            parameters[String(p[p.startIndex..<equalIndex])] = String(p[(p.index(after: equalIndex))..<p.endIndex])
        }
        
        guard let readerName = parameters["vndYabr_readerName"] ?? parameters["vnd_readerName"] else { return nil }
        
        self.id = entry.device
        self.readerName = readerName
        
        if let vndYabr_maxPage = parameters["vndYabr_maxPage"] ?? parameters["vnd_maxPage"], let maxPage = Int(vndYabr_maxPage) {
            self.maxPage = maxPage
        }
        if let vndYabr_lastReadPage = parameters["vndYabr_lastReadPage"] ?? parameters["vnd_lastReadPage"], let lastReadPage = Int(vndYabr_lastReadPage) {
            self.lastReadPage = lastReadPage
        }
        if let vndYabr_lastReadChapter = parameters["vndYabr_lastReadChapter"] ?? parameters["vnd_lastReadChapter"] {
            self.lastReadChapter = vndYabr_lastReadChapter
        }
        if let vndYabr_lastChapterProgress = parameters["vndYabr_lastChapterProgress"] ?? parameters["vnd_lastChapterProgress"], let lastChapterProgress = Double(vndYabr_lastChapterProgress) {
            self.lastChapterProgress = lastChapterProgress
        }
        if let vndYabr_lastProgress = parameters["vndYabr_lastProgress"] ?? parameters["vnd_lastProgress"], let lastProgress = Double(vndYabr_lastProgress) {
            self.lastProgress = lastProgress
        }
        if let vndYabr_furthestReadPage = parameters["vndYabr_furthestReadPage"] ?? parameters["vnd_furthestReadPage"], let furthestReadPage = Int(vndYabr_furthestReadPage) {
            self.furthestReadPage = furthestReadPage
        }
        if let vndYabr_furthestReadChapter = parameters["vndYabr_furthestReadChapter"] ?? parameters["vnd_furthestReadChapter"] {
            self.furthestReadChapter = vndYabr_furthestReadChapter
        }
        if let vndYabr_epoch = parameters["vndYabr_epoch"] ?? parameters["vnd_epoch"], let epoch = Double(vndYabr_epoch), epoch > 0.0 {
            self.epoch = epoch
        } else if entry.epoch > 0.0 {
            self.epoch = entry.epoch
        } else {
            self.epoch = Date().timeIntervalSince1970
        }
        if let vndYabr_lastPosition = parameters["vndYabr_lastPosition"] ?? parameters["vnd_lastPosition"] {
            let positions = vndYabr_lastPosition.split(separator: ".").compactMap{ Int($0) }
            if positions.count == 3 {
                self.lastPosition = positions
            }
        }
        if let vndYabr_structuralStyle = parameters["vndYabr_structuralStyle"],
           let structuralStyle = Int(vndYabr_structuralStyle) {
            self.structuralStyle = structuralStyle
        }
        if let vndYabr_structuralRootPageNumber = parameters["vndYabr_structuralRootPageNumber"],
           let structuralRootPageNumber = Int(vndYabr_structuralRootPageNumber) {
            self.structuralRootPageNumber = structuralRootPageNumber
        }
        if let vndYabr_positionTrackingStyle = parameters["vndYabr_positionTrackingStyle"],
           let positionTrackingStyle = Int(vndYabr_positionTrackingStyle) {
            self.positionTrackingStyle = positionTrackingStyle
        }
        if let vndYabr_lastReadBook = parameters["vndYabr_lastReadBook"] {
            self.lastReadBook = vndYabr_lastReadBook
        }
        if let vndYabr_lastBundleProgress = parameters["vndYabr_lastBundleProgress"],
            let lastBundleProgress = Double(vndYabr_lastBundleProgress) {
            self.lastBundleProgress = lastBundleProgress
        }
        
        self.cfi = String(entry.cfi[entry.cfi.startIndex..<vndFirstRange.lowerBound] + entry.cfi[vndEndRange.lowerBound..<entry.cfi.endIndex]).replacingOccurrences(of: "[]", with: "")
    }
    
    func encodeEPUBCFI() -> String {
        var parameters = [String: String]()
        parameters["vndYabr_readerName"] = readerName
        parameters["vndYabr_maxPage"] = maxPage.description
        parameters["vndYabr_lastReadPage"] = lastReadPage.description
        parameters["vndYabr_lastReadChapter"] = lastReadChapter
        parameters["vndYabr_lastChapterProgress"] = lastChapterProgress.description
        parameters["vndYabr_lastProgress"] = lastProgress.description
        parameters["vndYabr_furthestReadPage"] = furthestReadPage.description
        parameters["vndYabr_furthestReadChapter"] = furthestReadChapter
        parameters["vndYabr_lastPosition"] = lastPosition.map { $0.description }.joined(separator: ".")
        if epoch > 0.0 {
            parameters["vndYabr_epoch"] = epoch.description
        } else {
            parameters["vndYabr_epoch"] = Date().timeIntervalSince1970.description
        }
        parameters["vndYabr_structuralStyle"] = structuralStyle.description
        parameters["vndYabr_structuralRootPageNumber"] = structuralRootPageNumber.description
        parameters["vndYabr_positionTrackingStyle"] = positionTrackingStyle.description
        parameters["vndYabr_lastReadBook"] = lastReadBook
        parameters["vndYabr_lastBundleProgress"] = lastBundleProgress.description
        
        let vndParameters = parameters.map {
            "\($0.key)=\($0.value.replacingOccurrences(of: ",|;|=|\\[|\\]|\\s", with: ".", options: .regularExpression))"
        }.sorted().joined(separator: ";")
        
        var cfi = cfi
        if cfi.isEmpty || cfi == "/" {
            let typeKey = (ReaderType(rawValue: readerName) ?? .UNSUPPORTED).format.rawValue.lowercased()
            cfi = "\(typeKey)cfi(/\(lastReadPage*2))"
        }
        
        var insertIndex = cfi.endIndex
        var insertFragment = "[;\(vndParameters)]"
        if cfi.hasSuffix("])") {
            insertIndex = cfi.index(cfi.endIndex, offsetBy: -2, limitedBy: cfi.startIndex) ?? cfi.startIndex
            insertFragment = ";\(vndParameters)"
        } else if cfi.hasSuffix(")") {
            insertIndex = cfi.index(cfi.endIndex, offsetBy: -1, limitedBy: cfi.startIndex) ?? cfi.startIndex
        } else {
            //insert at end
        }
        cfi.insert(contentsOf: insertFragment, at: insertIndex)
        
        return cfi
    }
    
    func toEntry() -> CalibreBookLastReadPositionEntry {
        return .init(
            device: id,
            cfi: encodeEPUBCFI(),
            epoch: epoch,
            pos_frac: lastProgress / 100.0
        )
    }
}
