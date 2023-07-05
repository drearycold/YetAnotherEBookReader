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
        migrateIndividualRealm()
        return library.server.realmPerf
    }
    
    func migrateIndividualRealm() {
        guard let bookBaseUrl = getBookBaseUrl(id: id, library: library, localFilename: localFilename),
           let bookPrefConf = BookAnnotation.getBookPreferenceIndividualConfig(bookFileURL: bookBaseUrl) as Realm.Configuration?,
           let basePrefUrl = bookPrefConf.fileURL,
           FileManager.default.fileExists(atPath: basePrefUrl.path)
        else {
            return
        }
        
        autoreleasepool {
            let individualRealm = try! Realm(configuration: bookPrefConf)
            let serverRealm = library.server.realmPerf
            individualRealm.configuration.objectTypes?.forEach { objectType in
                guard let objectType = objectType as? Object.Type
                else {
                    assert(false, "Not an Object")
                    return
                }
                try! serverRealm.write {
                    switch objectType.className() {
                    case BookDeviceReadingPositionRealm.className():
                        let objects = individualRealm.objects(BookDeviceReadingPositionRealm.self)
                            .where { !$0.bookId.ends(with: " - History") }
                        objects.forEach { object in
                            guard serverRealm.object(ofType: BookDeviceReadingPositionRealm.self, forPrimaryKey: object._id) == nil
                            else {
                                return
                            }
                            serverRealm.create(objectType.self, value: object)
                        }
                    case BookDeviceReadingPositionHistoryRealm.className(),
                        FolioReaderPreferenceRealm.className(),
                        BookHighlightRealm.className(),
                        BookBookmarkRealm.className():
                        guard let primaryKey = objectType.primaryKey()
                        else {
                            assert(false, "Need Primary Key")
                            return
                        }
                        individualRealm.objects(objectType.self)
                            .forEach { object in
                                guard serverRealm.object(ofType: objectType.self, forPrimaryKey: object[primaryKey]) == nil
                                else {
                                    return
                                }
                                serverRealm.create(objectType.self, value: object)
                            }
                    case FolioReaderReadPositionRealm.className():
                        individualRealm.objects(FolioReaderReadPositionRealm.self)
                            .filter(NSPredicate(format: "maxPage > %@", NSNumber(1)))
                            .compactMap { $0.toReadPosition()?.toBookDeviceReadingPosition()
                            }
                            .forEach { newPosition in
                                let existing = serverRealm.objects(BookDeviceReadingPositionRealm.self)
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
                                    serverRealm.add(newPosition.managedObject(bookId: bookPrefId))
                                }
                            }
                    case FolioReaderHighlightRealm.className():
                        individualRealm.objects(FolioReaderHighlightRealm.self)
                            .forEach { oldObj in
                                guard serverRealm.object(ofType: BookHighlightRealm.self, forPrimaryKey: oldObj.highlightId) == nil
                                else {
                                    // realm.delete(oldObj)
                                    return
                                }
                                
                                guard let newObj = oldObj.toBookHighlightRealm(readerName: ReaderType.YabrEPUB.rawValue)
                                else { return }
                                
                                serverRealm.add(newObj)
                                // realm.delete(oldObj)
                            }
                    case PDFOptionsRealm.className():
                        individualRealm.objects(PDFOptionsRealm.self)
                            .forEach { oldObj in
                                guard serverRealm.objects(YabrPDFOptionsRealm.self)
                                    .where({ $0.bookId == id && $0.libraryName == library.name })
                                    .isEmpty
                                else {
                                    return
                                }
                                
                                let newObj = YabrPDFOptionsRealm()
                                newObj.bookId = oldObj.id
                                newObj.libraryName = oldObj.libraryName
                                
                                newObj.themeMode = PDFThemeMode(rawValue: oldObj.themeMode) ?? .serpia
                                newObj.selectedAutoScaler = PDFAutoScaler(rawValue: oldObj.selectedAutoScaler) ?? .Width
                                newObj.pageMode = PDFLayoutMode(rawValue: oldObj.pageMode) ?? .Page
                                newObj.readingDirection = PDFReadDirection(rawValue: oldObj.readingDirection) ?? .LtR_TtB
                                newObj.scrollDirection = PDFScrollDirection(rawValue: oldObj.scrollDirection) ?? .Vertical
                                
                                newObj.hMarginAutoScaler = oldObj.hMarginAutoScaler
                                newObj.vMarginAutoScaler = oldObj.vMarginAutoScaler
                                newObj.hMarginDetectStrength = oldObj.hMarginDetectStrength
                                newObj.vMarginDetectStrength = oldObj.vMarginDetectStrength
                                newObj.lastScale = oldObj.lastScale
                                newObj.rememberInPagePosition = oldObj.rememberInPagePosition
                                
                                serverRealm.add(newObj)
                            }
                    case CalibreBookLastReadPositionRealm.className():
                        break   //ignore deprecated types
                    default:
                        assert(individualRealm.objects(objectType.self).isEmpty, "Unrecognized ObjectType \(objectType.className())")
                    }
                }
            }
        }
        
        if try! Realm.deleteFiles(for: bookPrefConf) {
            let basePrefPath = basePrefUrl.deletingLastPathComponent()
            let enumerator = FileManager.default.enumerator(atPath: basePrefPath.path)
            
            var toRemoveURL = [URL]()
            while let file = enumerator?.nextObject() as? String {
                let fileURL = basePrefPath.appendingPathComponent(file)
                if fileURL.lastPathComponent.starts(with: basePrefUrl.lastPathComponent) {
                    toRemoveURL.append(fileURL)
                }
            }
            
            toRemoveURL.forEach {
                print("\(#function) removeItem=\($0.path)")
                try? FileManager.default.removeItem(at: $0)
            }
        }
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
    func bookmarks(excludeRemoved: Bool = true) -> [BookBookmark] {
        guard let realm = realm else { return [] }

        var results = realm.objects(BookBookmarkRealm.self)
            .where { $0.bookId == bookPrefId }
        if excludeRemoved {
            results = results.filter(NSPredicate(format: "removed == false"))
        }
        
        return results.map { BookBookmark(managedObject: $0) }
    }
    
    func bookmarks(andPage page: NSNumber?) -> [BookBookmark] {
        guard let realm = realm else { return [] }
        
        let objects = realm.objects(BookBookmarkRealm.self)
            .filter(NSPredicate(format: "bookId = %@ AND removed != true", bookPrefId))
            .filter{ page == nil || $0.page == page?.intValue }
        
        return objects.map { BookBookmark(managedObject: $0) }
    }
    
    func bookmarks(getBy bookmarkPos: String) -> BookBookmark? {
        guard let realm = realm else { return nil }
        
        guard let obj = realm.objects(BookBookmarkRealm.self)
            .filter(NSPredicate(format: "bookId = %@ AND pos = %@ AND removed != true", bookPrefId, bookmarkPos))
            .first
        else { return nil }
        
        return BookBookmark(managedObject: obj)
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
    
    func bookmarks(added bookmark: BookBookmark) -> (Int, String?) {
        guard let realm = self.realm else { return (-1, nil) }
        
        if let existing = bookmarks(getBy: bookmark.pos) { return (-2, existing.title) }
        
        do {
            try realm.write {
                realm.add(bookmark.managedObject())
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
    func highlights(excludeRemoved: Bool = true) -> [BookHighlight] {
        guard let realm = self.realm else { return .init() }
        
        var results = realm.objects(BookHighlightRealm.self)
            .where { $0.bookId == bookPrefId }
        if excludeRemoved {
            results = results.filter(NSPredicate(format: "removed == false"))
        }
        
        return results.map { .init(managedObject: $0) }
    }
    
    func highlights(allByBookId bookId: String, andPage page: NSNumber?) -> [BookHighlight] {
        guard let realm = self.realm else { return .init() }
        
        let predicate = { () -> NSPredicate in
            if let page = page {
                return NSPredicate(format: "removed == false && bookId = %@ && page = %@", bookId, page)
            } else {
                return NSPredicate(format: "removed == false && bookId = %@", bookId)
            }
        }()
        
        return realm.objects(BookHighlightRealm.self)
            .filter(predicate)
            .map { .init(managedObject: $0) }
    }
    
    func highlight(getById highlightId: String) -> BookHighlight? {
        guard let realm = self.realm else { return nil}
        
        guard let object = realm.object(ofType: BookHighlightRealm.self, forPrimaryKey: highlightId) else { return nil }
        
        return .init(managedObject: object)
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
    func highlight(added highlight: BookHighlight) {
        guard let realm = self.realm else { return }
        
        try? realm.write {
            realm.add(highlight.managedObject(), update: .modified)
        }
    }
}
