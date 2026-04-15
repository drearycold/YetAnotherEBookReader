//
//  BookAnnotation.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/10/4.
//

import Foundation
import RealmSwift

/**
 realm backed
 */
class BookAnnotation {
    let id: Int32
    let library: CalibreLibrary
    let localFilename: String?
    
    let bookPrefId: String
    
    var isEmpty: Bool { get { get()?.isEmpty ?? true } }
    
    init(id: Int32, library: CalibreLibrary, localFilename: String? = nil) {
        self.id = id
        self.library = library
        self.localFilename = localFilename
        bookPrefId = BookAnnotation.PrefId(library: library, id: id)
    }
    
    var realm: Realm? {
        return library.server.realmPerf
    }
}

// MARK: Position
extension BookAnnotation {
    /**
     newest takePrecedence, newest first otherwise
     */
    func getPosition(_ deviceName: String?) -> BookDeviceReadingPosition? {
        guard var objects = get() else { return nil }
        
        if let deviceName = deviceName {
            objects = objects.filter(NSPredicate(format: "deviceId = %@", deviceName))
        }
        
        return objects.filter(NSPredicate(format: "takePrecedence = true"))
            .map({ BookDeviceReadingPosition(managedObject: $0) })
            .first ?? objects.map({ BookDeviceReadingPosition(managedObject: $0) }).first
    }
    
    func addInitialPosition(_ deviceName: String, _ readerName: String) {
        //TODO: try doing nothing
    }
    
    func updatePosition(_ newPosition: BookDeviceReadingPosition) {
        guard let realm = realm else { return }

        removePosition(position: newPosition)
        
        let existing = realm.objects(BookDeviceReadingPositionRealm.self)
            .filter(
                NSPredicate(
                    format: "bookId = %@ AND deviceId = %@ AND readerName = %@ AND structuralStyle = %@ AND positionTrackingStyle = %@ AND structuralRootPageNumber = %@",
                    bookPrefId,
                    newPosition.id,
                    newPosition.readerName,
                    NSNumber(value: newPosition.structuralStyle),
                    NSNumber(value: newPosition.positionTrackingStyle),
                    NSNumber(value: newPosition.structuralRootPageNumber)
                )
            )
        if existing.isEmpty {
            try? realm.write {
                realm.add(newPosition.managedObject(bookId: bookPrefId))
            }
        }
    }
    
    func removePosition(_ deviceName: String) {
        guard let realm = realm else { return }

        let objs = realm.objects(BookDeviceReadingPositionRealm.self)
            .filter(NSPredicate(format: "bookId = %@ and deviceId = %@", bookPrefId, deviceName))
        if objs.isEmpty == false {
            try? realm.write {
                realm.delete(objs)
            }
        }
    }
    
    func removePosition(position: BookDeviceReadingPosition) {
        guard let realm = realm else { return }

        try? realm.write {
            let existing = realm.objects(BookDeviceReadingPositionRealm.self)
                .filter(NSPredicate(
                    format: "bookId = %@ AND deviceId = %@ AND readerName = %@ AND structuralStyle = %@ AND positionTrackingStyle = %@ AND structuralRootPageNumber = %@ AND epoch < %@",
                    bookPrefId,
                    position.id,
                    position.readerName,
                    NSNumber(value: position.structuralStyle),
                    NSNumber(value: position.positionTrackingStyle),
                    NSNumber(value: position.structuralRootPageNumber),
                    NSNumber(value: position.epoch)
                ))
            if existing.isEmpty == false {
                realm.delete(existing)
            }
        }
    }
    
    func getCopy() -> [String: BookDeviceReadingPosition] {
        return get()?.reduce(into: [String: BookDeviceReadingPosition](), { partialResult, obj in
            if (partialResult[obj.deviceId]?.epoch ?? Date.distantPast.timeIntervalSince1970) < obj.epoch {
                partialResult[obj.deviceId] = BookDeviceReadingPosition(managedObject: obj)
            }
        }) ?? [:]
    }
    
    func getDevices() -> [BookDeviceReadingPosition] {
        return get()?.map { BookDeviceReadingPosition(managedObject: $0) } ?? []
    }
    
    func getDevices(by reader: ReaderType) -> [BookDeviceReadingPosition] {
        return get()?.filter {
            $0.readerName == reader.id
        }.map { BookDeviceReadingPosition(managedObject: $0) } ?? []
    }
    
    func createInitial(deviceName: String, reader: ReaderType) -> BookDeviceReadingPosition {
        return .init(id: deviceName, readerName: reader.rawValue)
    }
    
    /**
     sorted by epoch, newest first
     */
    private func get() -> Results<BookDeviceReadingPositionRealm>? {
        guard let realm = realm else { return nil }
        
        return realm.objects(BookDeviceReadingPositionRealm.self)
            .filter(NSPredicate(format: "bookId = %@", bookPrefId))
            .sorted(byKeyPath: "epoch", ascending: false)
    }
}

// MARK: Session
extension BookAnnotation {
    func sessions(list startDateAfter: Date? = nil) -> [BookDeviceReadingPositionHistory] {
        guard let realm = realm else { return [] }

        return realm.objects(BookDeviceReadingPositionHistoryRealm.self)
            .filter(
                startDateAfter == nil
                ? NSPredicate(format: "bookId = %@", bookPrefId)
                : NSPredicate(format: "bookId = %@ AND startDatetime >= %@", bookPrefId, startDateAfter! as NSDate)
            )
            .filter { $0.endPosition != nil }
            .map { BookDeviceReadingPositionHistory(managedObject: $0) }
    }
    
    func session(start readPosition: BookDeviceReadingPosition) -> Date? {
        guard let realm = realm else { return nil }

        let startDatetime = Date()
        
        let historyEntryFirst = realm.objects(BookDeviceReadingPositionHistoryRealm.self)
            .filter(NSPredicate(format: "bookId = %@", bookPrefId))
            .sorted(by: [SortDescriptor(keyPath: "startDatetime", ascending: false)])
            .first
        
        try? realm.write {
            if let endPosition = historyEntryFirst?.endPosition, startDatetime.timeIntervalSince1970 < endPosition.epoch + 60 {
                historyEntryFirst?.endPosition?.takePrecedence = true
            } else if let startPosition = historyEntryFirst?.startPosition, startDatetime.timeIntervalSince1970 < startPosition.epoch + 300 {
                historyEntryFirst?.endPosition?.takePrecedence = true
            } else {
                let historyEntry = BookDeviceReadingPositionHistoryRealm()
                historyEntry.bookId = bookPrefId
                historyEntry.startDatetime = startDatetime
                historyEntry.startPosition = readPosition.managedObject()
                historyEntry.startPosition?.bookId = "\(bookPrefId) - History"
                realm.add(historyEntry)
            }
        }
        
        return startDatetime
    }
    
    func session(end readPosition: BookDeviceReadingPosition) {
        guard let realm = realm else { return }

        guard let historyEntry = realm.objects(BookDeviceReadingPositionHistoryRealm.self).filter(
            NSPredicate(format: "bookId = %@", bookPrefId)
        ).sorted(by: [SortDescriptor(keyPath: "startDatetime", ascending: false)]).first else { return }
        
        guard historyEntry.endPosition == nil || historyEntry.endPosition?.takePrecedence == true else { return }
        
        try? realm.write {
            let newEndPositionObject = readPosition.managedObject()
            newEndPositionObject.bookId = "\(bookPrefId) - History"
            if let endPositionObject = historyEntry.endPosition {
                newEndPositionObject._id = endPositionObject._id
                realm.add(newEndPositionObject, update: .modified)
                
            } else {
                historyEntry.endPosition = newEndPositionObject
            }
        }
    }
    
}

//MARK: Bookmark
extension BookAnnotation {
    func bookmarks(excludeRemoved: Bool = true) -> [BookBookmarkRealm] {
        guard let realm = realm else { return [] }

        var results = realm.objects(BookBookmarkRealm.self)
            .where { $0.bookId == bookPrefId }
        if excludeRemoved {
            results = results.filter(NSPredicate(format: "removed == false"))
        }
        
        return Array(results)
    }
    
    func bookmarks(andPage page: NSNumber?) -> [BookBookmarkRealm] {
        guard let realm = realm else { return [] }
        
        let objects = realm.objects(BookBookmarkRealm.self)
            .filter(NSPredicate(format: "bookId = %@ AND removed != true", bookPrefId))
            .filter{ page == nil || $0.page == page?.intValue }
        
        return Array(objects)
    }
    
    func bookmarks(getBy bookmarkPos: String) -> BookBookmarkRealm? {
        guard let realm = realm else { return nil }
        
        return realm.objects(BookBookmarkRealm.self)
            .filter(NSPredicate(format: "bookId = %@ AND pos = %@ AND removed != true", bookPrefId, bookmarkPos))
            .first
    }
    
    func bookmarks(updated bookmarkPos: String, title: String) {
        guard let realm = realm else { return }
        
        try? realm.write {
            realm.objects(BookBookmarkRealm.self).filter(NSPredicate(format: "bookId = %@ AND pos = %@ AND removed != true", bookPrefId, bookmarkPos)).forEach {
                $0.date = .init()
                $0.title = title
            }
        }
    }
    
    func bookmarks(removed bookmarkPos: String) {
        guard let realm = realm else { return }
        
        try? realm.write {
            realm.objects(BookBookmarkRealm.self).filter(NSPredicate(format: "bookId = %@ AND pos = %@ AND removed != true", bookPrefId, bookmarkPos)).forEach {
                $0.date = .init()
                $0.removed = true
            }
        }
    }
    
    func bookmarks(added bookmark: BookBookmarkRealm) -> (Int, String?) {
        guard let realm = self.realm else { return (-1, nil) }
        
        if let existing = bookmarks(getBy: bookmark.pos) { return (-2, existing.title) }
        
        do {
            try realm.write {
                realm.add(bookmark)
            }
        } catch let e as NSError {
            return (-3, e.localizedDescription)
        }
        
        return (0, nil)
    }
}

// MARK: Highlight
extension BookAnnotation {
    func highlights(saveNoteFor highlightId: String, with note: String?) {
        guard let realm = self.realm,
              let object = realm.object(ofType: BookHighlightRealm.self, forPrimaryKey: highlightId)
        else { return }
        
        try? realm.write {
            object.note = note
            object.date = Date()
        }
    }
    func highlights(excludeRemoved: Bool = true) -> [BookHighlightRealm] {
        guard let realm = self.realm else { return .init() }
        
        var results = realm.objects(BookHighlightRealm.self)
            .where { $0.bookId == bookPrefId }
        if excludeRemoved {
            results = results.filter(NSPredicate(format: "removed == false"))
        }
        
        return Array(results)
    }
    
    func highlights(allByBookId bookId: String, andPage page: NSNumber?) -> [BookHighlightRealm] {
        guard let realm = self.realm else { return .init() }
        
        let predicate = { () -> NSPredicate in
            if let page = page {
                return NSPredicate(format: "removed == false && bookId = %@ && page = %@", bookId, page)
            } else {
                return NSPredicate(format: "removed == false && bookId = %@", bookId)
            }
        }()
        
        return Array(realm.objects(BookHighlightRealm.self)
            .filter(predicate))
    }
    
    func highlight(getById highlightId: String) -> BookHighlightRealm? {
        guard let realm = self.realm else { return nil}
        
        return realm.object(ofType: BookHighlightRealm.self, forPrimaryKey: highlightId)
    }
    
    func highlight(updateById highlightId: String, type: Int) {
        guard let realm = self.realm,
              let object = realm.object(ofType: BookHighlightRealm.self, forPrimaryKey: highlightId)
        else { return }
        
        try? realm.write {
            object.type = type
            object.date = Date()
        }
    }
    
    func highlight(removedId highlightId: String) {
        guard let realm = self.realm,
              let object = realm.object(ofType: BookHighlightRealm.self, forPrimaryKey: highlightId)
        else { return }
        
        try? realm.write {
            object.removed = true
            object.date = Date()
        }
    }
    
    /**
     will replace existing entry
     */
    func highlight(added highlight: BookHighlightRealm) {
        guard let realm = self.realm else { return }
        
        try? realm.write {
            realm.add(highlight, update: .modified)
        }
    }
}
