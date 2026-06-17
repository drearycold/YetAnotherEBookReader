//
//  AnnotationRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/14.
//

import Foundation
import RealmSwift

protocol AnnotationRepositoryProtocol {
    // Bookmarks CRUD
    func getBookmarks(forBookId bookId: String, excludeRemoved: Bool) -> [BookBookmark]
    func getBookmark(byPos pos: String, bookId: String) -> BookBookmark?
    func saveBookmark(_ bookmark: BookBookmark) -> (Int, String?)
    func removeBookmark(pos: String, bookId: String)
    
    // Highlights CRUD
    func getHighlights(forBookId bookId: String, excludeRemoved: Bool) -> [BookHighlight]
    func getHighlight(byId id: String) -> BookHighlight?
    func saveHighlight(_ highlight: BookHighlight)
    func removeHighlight(id: String)
    func updateHighlightNote(id: String, note: String?)
    
    // Remote Sync (Calibre Server Merges)
    func syncBookmarks(entries: [CalibreBookAnnotationBookmarkEntry], forBookId bookId: String) -> Int
    func syncHighlights(entries: [CalibreBookAnnotationHighlightEntry], forBookId bookId: String) -> Int
}

class RealmAnnotationRepository: AnnotationRepositoryProtocol {
    private let databaseService: DatabaseService
    
    init(databaseService: DatabaseService = .shared) {
        self.databaseService = databaseService
    }
    
    private func getRealm() -> Realm? {
        if Thread.isMainThread {
            return databaseService.realm
        }
        let key = "AnnotationRepositoryRealm"
        if let cachedRealm = Thread.current.threadDictionary[key] as? Realm {
            return cachedRealm
        }
        if let conf = databaseService.realmConf, let realm = try? Realm(configuration: conf) {
            Thread.current.threadDictionary[key] = realm
            return realm
        }
        return nil
    }
    
    // MARK: - Bookmarks CRUD
    func getBookmarks(forBookId bookId: String, excludeRemoved: Bool) -> [BookBookmark] {
        guard let realm = getRealm() else { return [] }
        var results = realm.objects(BookBookmarkRealm.self).filter("bookId == %@", bookId)
        if excludeRemoved {
            results = results.filter("removed != true")
        }
        return results.map { $0.toValue() }
    }
    
    func getBookmark(byPos pos: String, bookId: String) -> BookBookmark? {
        guard let realm = getRealm() else { return nil }
        let objects = realm.objects(BookBookmarkRealm.self).filter("bookId == %@ AND pos == %@", bookId, pos)
        return objects.first?.toValue()
    }
    
    func saveBookmark(_ bookmark: BookBookmark) -> (Int, String?) {
        guard let realm = getRealm() else { return (0, nil) }
        
        let bookmarkRealm = BookBookmarkRealm(value: bookmark)
        var returnStatus = 0
        var oldTitle: String? = nil
        
        try? realm.write {
            // Check if pos exists
            let existing = realm.objects(BookBookmarkRealm.self).filter("bookId == %@ AND pos == %@ AND removed != true", bookmark.bookId, bookmark.pos)
            if let first = existing.first {
                oldTitle = first.title
                if first.title != bookmark.title {
                    first.title = bookmark.title
                    first.date = bookmark.date
                    returnStatus = 2 // updated title
                } else {
                    returnStatus = 0 // same
                }
            } else {
                realm.add(bookmarkRealm, update: .modified)
                returnStatus = 1 // added new
            }
        }
        return (returnStatus, oldTitle)
    }
    
    func removeBookmark(pos: String, bookId: String) {
        guard let realm = getRealm() else { return }
        try? realm.write {
            let existing = realm.objects(BookBookmarkRealm.self).filter("bookId == %@ AND pos == %@ AND removed != true", bookId, pos)
            existing.forEach {
                $0.removed = true
                $0.date = Date()
            }
        }
    }
    
    // MARK: - Highlights CRUD
    func getHighlights(forBookId bookId: String, excludeRemoved: Bool) -> [BookHighlight] {
        guard let realm = getRealm() else { return [] }
        var results = realm.objects(BookHighlightRealm.self).filter("bookId == %@", bookId)
        if excludeRemoved {
            results = results.filter("removed != true")
        }
        return results.map { $0.toValue() }
    }
    
    func getHighlight(byId id: String) -> BookHighlight? {
        guard let realm = getRealm() else { return nil }
        let object = realm.object(ofType: BookHighlightRealm.self, forPrimaryKey: id)
        return object?.toValue()
    }
    
    func saveHighlight(_ highlight: BookHighlight) {
        guard let realm = getRealm() else { return }
        let highlightRealm = BookHighlightRealm(value: highlight)
        try? realm.write {
            realm.add(highlightRealm, update: .all)
        }
    }
    
    func removeHighlight(id: String) {
        guard let realm = getRealm() else { return }
        try? realm.write {
            if let object = realm.object(ofType: BookHighlightRealm.self, forPrimaryKey: id) {
                object.removed = true
                object.date = Date()
            }
        }
    }
    
    func updateHighlightNote(id: String, note: String?) {
        guard let realm = getRealm() else { return }
        try? realm.write {
            if let object = realm.object(ofType: BookHighlightRealm.self, forPrimaryKey: id) {
                object.note = note
                object.date = Date()
            }
        }
    }
    
    // MARK: - Remote Sync (Calibre Server Merges)
    func syncBookmarks(entries: [CalibreBookAnnotationBookmarkEntry], forBookId bookId: String) -> Int {
        guard let realm = getRealm() else { return 0 }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
        
        let bookObjects = realm.objects(BookBookmarkRealm.self).filter("bookId == %@", bookId)
        
        var pending = bookObjects.reduce(into: Set<String>()) { partialResult, object in
            partialResult.insert(object.pos)
        }
        
        let bookmarksByPos = entries.reduce(into: [String: [CalibreBookAnnotationBookmarkEntry]]()) { partialResult, entry in
            guard entry.type == "bookmark",
                  dateFormatter.date(from: entry.timestamp) != nil
            else { return }
            
            if partialResult[entry.pos] != nil {
                partialResult[entry.pos]?.append(entry)
            } else {
                partialResult[entry.pos] = [entry]
            }
        }.map { posEntry in
            (key: posEntry.key, value: posEntry.value.sorted(by: { lhs, rhs in
                (dateFormatter.date(from: lhs.timestamp) ?? .distantPast) > (dateFormatter.date(from: rhs.timestamp) ?? .distantPast)
            }))
        }
        
        try? realm.write {
            bookmarksByPos.forEach { pos, entries in
                guard let entryNewest = entries.first,
                      let entryNewestDate = dateFormatter.date(from: entryNewest.timestamp) else { return }
                
                let objects = bookObjects
                    .filter(NSPredicate(format: "pos = %@", pos))
                    .sorted(byKeyPath: "date", ascending: false)
                
                let objectsVisible = objects.filter(NSPredicate(format: "removed != true"))
                
                if let objectNewest = objects.first {
                    if objectNewest.date == entryNewestDate
                        || (
                            (objectNewest.date < entryNewestDate + 0.1)
                            &&
                            (entryNewestDate < objectNewest.date + 0.1)
                        ) {
                        //same date, ignore server one
                        pending.remove(pos)
                    } else if objectNewest.date < entryNewestDate + 0.1 {
                        //server has newer entry, remove all local entries
                        while( objectsVisible.isEmpty == false ) {
                            objectsVisible.first?.date += 0.001
                            objectsVisible.first?.removed = true
                        }
                        pending.remove(pos)
                    } else if entryNewestDate < objectNewest.date + 0.1 {
                        //local has newer entry, ignore server one
                    } else {
                        //same date, ignore server one
                        pending.remove(pos)
                    }
                }
                
                guard objectsVisible.isEmpty,
                      entryNewest.removed != true
                else {
                    // only insert newest visible entry
                    // either local has no corresponding entry,
                    // or we have removed all existing ones (which means they are older)
                    return
                }
                
                let object = BookBookmarkRealm()
                object.bookId = bookId
                
                object.pos_type = entryNewest.pos_type
                object.pos = entryNewest.pos
                
                object.title = entryNewest.title
                object.date = entryNewestDate
                object.removed = entryNewest.removed ?? false
                
                guard object.pos_type == "epubcfi",
                      object.pos.starts(with: "epubcfi(/") else { return }
                let firstStepStartIndex = object.pos.index(object.pos.startIndex, offsetBy: 9)
                guard let firstStepEndIndex = object.pos[firstStepStartIndex..<object.pos.endIndex].firstIndex(where: { elem in
                    elem == "/" || elem == ")"
                }) else { return }
                
                guard let firstStep = Int(object.pos[firstStepStartIndex..<firstStepEndIndex]) else { return }
                object.page = firstStep / 2
                
                realm.add(object)
            }
        }
        
        return pending.count
    }
    
    func syncHighlights(entries: [CalibreBookAnnotationHighlightEntry], forBookId bookId: String) -> Int {
        guard let realm = getRealm() else { return 0 }
        
        var pending = realm.objects(BookHighlightRealm.self).filter("bookId == %@", bookId).count
        try? realm.write {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
            
            entries.forEach { hl in
                guard hl.type == "highlight",
                      let highlightId = uuidCalibreToFolio(hl.uuid),
                      let date = dateFormatter.date(from: hl.timestamp)
                else { return }
                
                guard hl.removed != true else {
                    if let object = realm.object(ofType: BookHighlightRealm.self, forPrimaryKey: highlightId) {
                        if object.date <= date + 0.1 {
                            object.removed = true
                            object.date = date
                            pending -= 1
                        } else if date <= object.date + 0.1 {
                            
                        } else {
                            pending -= 1
                        }
                    }
                    return
                }
                
                guard let spineIndex = hl.spineIndex else { return }
                
                if let object = realm.object(ofType: BookHighlightRealm.self, forPrimaryKey: highlightId) {
                    if object.date <= date + 0.1 {
                        object.date = date
                        object.type = BookHighlightStyle.styleForClass(hl.style?["which"] ?? "yellow").rawValue
                        object.note = hl.notes
                        object.removed = false
                        pending -= 1
                    } else if date <= object.date + 0.1 {
                        
                    } else {
                        pending -= 1
                    }
                } else {
                    let highlightRealm = BookHighlightRealm()
                    
                    highlightRealm.bookId = bookId
                    highlightRealm.content = hl.highlightedText ?? "Unspecified"
                    highlightRealm.contentPost = ""
                    highlightRealm.contentPre = ""
                    highlightRealm.date = date
                    highlightRealm.highlightId = highlightId
                    highlightRealm.page = spineIndex + 1
                    highlightRealm.type = BookHighlightStyle.styleForClass(hl.style?["which"] ?? "yellow").rawValue
                    highlightRealm.startOffset = 0
                    highlightRealm.endOffset = 0
                    highlightRealm.ranges = hl.ranges
                    highlightRealm.note = hl.notes
                    highlightRealm.cfiStart = hl.startCfi
                    highlightRealm.cfiEnd = hl.endCfi
                    highlightRealm.spineName = hl.spineName
                    if let tocFamilyTitles = hl.tocFamilyTitles {
                        highlightRealm.tocFamilyTitles.append(objectsIn: tocFamilyTitles)
                    }
                    
                    realm.add(highlightRealm, update: .all)
                }
            }
        }
        
        return pending
    }
}

// MARK: - Mappings
extension BookBookmarkRealm {
    func toValue() -> BookBookmark {
        return BookBookmark(
            id: self._id.stringValue,
            bookId: self.bookId,
            page: self.page,
            pos_type: self.pos_type,
            pos: self.pos,
            title: self.title,
            date: self.date,
            removed: self.removed
        )
    }
    
    convenience init(value: BookBookmark) {
        self.init()
        if let objectId = try? ObjectId(string: value.id) {
            self._id = objectId
        }
        self.bookId = value.bookId
        self.page = value.page
        self.pos_type = value.pos_type
        self.pos = value.pos
        self.title = value.title
        self.date = value.date
        self.removed = value.removed
    }
}

extension BookHighlightRealm {
    func toValue() -> BookHighlight {
        return BookHighlight(
            id: self.highlightId,
            bookId: self.bookId,
            readerName: self.readerName,
            page: self.page,
            startOffset: self.startOffset,
            endOffset: self.endOffset,
            date: self.date,
            type: self.type,
            note: self.note,
            tocFamilyTitles: Array(self.tocFamilyTitles),
            content: self.content,
            contentPost: self.contentPost,
            contentPre: self.contentPre,
            cfiStart: self.cfiStart,
            cfiEnd: self.cfiEnd,
            spineName: self.spineName,
            ranges: self.ranges,
            removed: self.removed
        )
    }
    
    convenience init(value: BookHighlight) {
        self.init()
        self.highlightId = value.id
        self.bookId = value.bookId
        self.readerName = value.readerName
        self.page = value.page
        self.startOffset = value.startOffset
        self.endOffset = value.endOffset
        self.date = value.date
        self.type = value.type
        self.note = value.note
        self.tocFamilyTitles.removeAll()
        self.tocFamilyTitles.append(objectsIn: value.tocFamilyTitles)
        self.content = value.content
        self.contentPost = value.contentPost
        self.contentPre = value.contentPre
        self.cfiStart = value.cfiStart
        self.cfiEnd = value.cfiEnd
        self.spineName = value.spineName
        self.ranges = value.ranges
        self.removed = value.removed
    }
}
