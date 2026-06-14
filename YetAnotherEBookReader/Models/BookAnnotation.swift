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
    private var annotationRepository: AnnotationRepositoryProtocol {
        RealmAnnotationRepository()
    }
    
    func bookmarks(excludeRemoved: Bool = true) -> [BookBookmark] {
        return annotationRepository.getBookmarks(forBookId: bookPrefId, excludeRemoved: excludeRemoved)
    }
    
    func bookmarks(andPage page: NSNumber?) -> [BookBookmark] {
        let all = annotationRepository.getBookmarks(forBookId: bookPrefId, excludeRemoved: true)
        return all.filter { page == nil || $0.page == page?.intValue }
    }
    
    func bookmarks(getBy bookmarkPos: String) -> BookBookmark? {
        return annotationRepository.getBookmark(byPos: bookmarkPos, bookId: bookPrefId)
    }
    
    func bookmarks(updated bookmarkPos: String, title: String) {
        if let existing = annotationRepository.getBookmark(byPos: bookmarkPos, bookId: bookPrefId) {
            var updated = existing
            updated.title = title
            updated.date = Date()
            _ = annotationRepository.saveBookmark(updated)
        }
    }
    
    func bookmarks(removed bookmarkPos: String) {
        annotationRepository.removeBookmark(pos: bookmarkPos, bookId: bookPrefId)
    }
    
    func bookmarks(added bookmark: BookBookmark) -> (Int, String?) {
        return annotationRepository.saveBookmark(bookmark)
    }
    
    func bookmarks(added entries: [CalibreBookAnnotationBookmarkEntry]) -> Int {
        return annotationRepository.syncBookmarks(entries: entries, forBookId: bookPrefId)
    }
}

// MARK: Highlight
extension BookAnnotation {
    func highlights(saveNoteFor highlightId: String, with note: String?) {
        annotationRepository.updateHighlightNote(id: highlightId, note: note)
    }
    
    func highlights(excludeRemoved: Bool = true) -> [BookHighlight] {
        return annotationRepository.getHighlights(forBookId: bookPrefId, excludeRemoved: excludeRemoved)
    }
    
    func highlights(allByBookId bookId: String, andPage page: NSNumber?) -> [BookHighlight] {
        let all = annotationRepository.getHighlights(forBookId: bookId, excludeRemoved: true)
        return all.filter { page == nil || $0.page == page?.intValue }
    }
    
    func highlight(getById highlightId: String) -> BookHighlight? {
        return annotationRepository.getHighlight(byId: highlightId)
    }
    
    func highlight(updateById highlightId: String, type: Int) {
        if let existing = annotationRepository.getHighlight(byId: highlightId) {
            var updated = existing
            updated.type = type
            updated.date = Date()
            annotationRepository.saveHighlight(updated)
        }
    }
    
    func highlight(removedId highlightId: String) {
        annotationRepository.removeHighlight(id: highlightId)
    }
    
    func highlight(added highlight: BookHighlight) {
        annotationRepository.saveHighlight(highlight)
    }
    
    func highlights(added entries: [CalibreBookAnnotationHighlightEntry]) -> Int {
        return annotationRepository.syncHighlights(entries: entries, forBookId: bookPrefId)
    }
}
