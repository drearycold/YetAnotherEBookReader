//
//  AnnotationRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/14.
//

import Foundation
import RealmSwift
import OSLog

protocol AnnotationRepositoryProtocol {
    // Bookmarks CRUD
    func getBookmarks(forBookId bookId: String, excludeRemoved: Bool) -> [BookBookmark]
    /// The visible bookmark at `pos`.
    func getBookmark(byPos pos: String, bookId: String) -> BookBookmark?
    /// Adds a bookmark, or retitles the one at its position. The title is made unique in the
    /// book (`BookmarkMerge.uniqueTitle`). Returns 1 if added, 2 if retitled, 0 if unchanged,
    /// and the title it had.
    func saveBookmark(_ bookmark: BookBookmark) -> (Int, String?)
    func removeBookmark(pos: String, bookId: String)
    
    // Highlights CRUD
    func getHighlights(forBookId bookId: String, excludeRemoved: Bool) -> [BookHighlight]
    func getHighlight(byId id: String) -> BookHighlight?
    func saveHighlight(_ highlight: BookHighlight)
    func removeHighlight(id: String)
    func updateHighlightNote(id: String, note: String?)
    
    // Remote Sync (Calibre Server Merges)
    /// Merges calibre's bookmarks of one format (see `BookmarkMerge`) and returns the ones to
    /// upload to it.
    func syncBookmarks(entries: [CalibreBookAnnotationBookmarkEntry], forBookId bookId: String, posType: String) -> [CalibreBookAnnotationBookmarkEntry]
    func syncHighlights(entries: [CalibreBookAnnotationHighlightEntry], forBookId bookId: String) -> Int
}

extension AnnotationRepositoryProtocol {
    /// Moves `readerName`'s highlights stored under `fromBookId` to `toBookId`.
    /// From June 2026 YabrPDF saved new highlights under the book's shelf
    /// identity instead of its annotation id, so they were never read back.
    /// Returns how many moved.
    @discardableResult
    func refileHighlights(fromBookId: String, toBookId: String, readerName: String) -> Int {
        guard fromBookId != toBookId else { return 0 }
        let misfiled = getHighlights(forBookId: fromBookId, excludeRemoved: false).filter { $0.readerName == readerName }
        for var highlight in misfiled {
            highlight.bookId = toBookId
            saveHighlight(highlight)
        }
        return misfiled.count
    }
}

final class RealmAnnotationRepository: AnnotationRepositoryProtocol {
    private let databaseService: DatabaseService
    private let logger = Logger(subsystem: "io.github.drearycold.DSReader", category: "AnnotationRepository")
    private let highlightWriteQueue = DispatchQueue(label: "annotation-repository.highlight-write", qos: .userInitiated)
    
    init(databaseService: DatabaseService = .shared) {
        self.databaseService = databaseService
    }
    
    private func getRealm(forBookId bookId: String) -> Realm? {
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
    
    private func getRealm() -> Realm? {
        return getRealm(forBookId: "")
    }

    private func parseAnnotationDate(_ timestamp: String) -> Date? {
        parseLastModified(timestamp)
    }

    private func resetCachedBackgroundRealm() {
        Thread.current.threadDictionary.removeObject(forKey: "AnnotationRepositoryRealm")
    }

    private func openFreshRealmForWrite() -> Realm? {
        guard let conf = databaseService.realmConf else { return nil }
        return try? Realm(configuration: conf)
    }

    private func performWriteWithRetry(
        in realm: Realm?,
        operation: (Realm) throws -> Void
    ) {
        guard let realm else { return }

        do {
            try realm.write {
                try operation(realm)
            }
            return
        } catch {
            logger.error("Annotation write failed, retrying with a fresh Realm: \(error.localizedDescription)")
        }

        resetCachedBackgroundRealm()

        guard let conf = databaseService.realmConf else { return }

        do {
            let freshRealm = try Realm(configuration: conf)
            Thread.current.threadDictionary["AnnotationRepositoryRealm"] = freshRealm
            try freshRealm.write {
                try operation(freshRealm)
            }
        } catch {
            logger.fault("Annotation write retry failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Bookmarks CRUD
    func getBookmarks(forBookId bookId: String, excludeRemoved: Bool) -> [BookBookmark] {
        guard let realm = getRealm() else { return [] }
        var results = realm.objects(BookBookmarkRealm.self).filter("bookId == %@", bookId)
        if excludeRemoved {
            results = results.filter("removed != true")
        }
        return results.map { $0.toDomain() }
    }
    
    func getBookmark(byPos pos: String, bookId: String) -> BookBookmark? {
        guard let realm = getRealm() else { return nil }
        let objects = realm.objects(BookBookmarkRealm.self).filter("bookId == %@ AND pos == %@ AND removed != true", bookId, pos)
        return objects.first?.toDomain()
    }
    
    func saveBookmark(_ bookmark: BookBookmark) -> (Int, String?) {
        guard let realm = getRealm() else { return (0, nil) }
        
        var returnStatus = 0
        var oldTitle: String? = nil
        
        try? realm.write {
            let visible = realm.objects(BookBookmarkRealm.self).filter("bookId == %@ AND removed != true", bookmark.bookId)
            let existing = visible.filter("pos == %@", bookmark.pos).first
            // calibre keeps one bookmark per title.
            let taken = Set(visible.filter { $0._id != existing?._id }.map(\.title))
            var saved = bookmark
            saved.title = BookmarkMerge.uniqueTitle(bookmark.title, avoiding: taken)
            
            if let existing {
                oldTitle = existing.title
                guard existing.title != saved.title else { return }
                // To calibre a new title is a new bookmark: remove the old title, so it goes from
                // the server and other devices too.
                existing.removed = true
                existing.date = Date()
                saved.id = ObjectId.generate().stringValue
                realm.add(saved.makeRealmObject())
                returnStatus = 2 // updated title
            } else {
                realm.add(saved.makeRealmObject(), update: .modified)
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
        return results.map { $0.toDomain() }
    }
    
    func getHighlight(byId id: String) -> BookHighlight? {
        guard let realm = getRealm() else { return nil }
        let object = realm.object(ofType: BookHighlightRealm.self, forPrimaryKey: id)
        return object?.toDomain()
    }
    
    func saveHighlight(_ highlight: BookHighlight) {
        let highlightRealm = highlight.makeRealmObject()
        highlightWriteQueue.sync {
            performWriteWithRetry(in: openFreshRealmForWrite()) { realm in
                realm.add(highlightRealm, update: .all)
            }
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
    func syncBookmarks(entries: [CalibreBookAnnotationBookmarkEntry], forBookId bookId: String, posType: String) -> [CalibreBookAnnotationBookmarkEntry] {
        guard let realm = getRealm(forBookId: bookId) else { return [] }
        return syncBookmarks(entries: entries, forBookId: bookId, posType: posType, using: realm)
    }
    
    private func syncBookmarks(entries: [CalibreBookAnnotationBookmarkEntry], forBookId bookId: String, posType: String, using realm: Realm) -> [CalibreBookAnnotationBookmarkEntry] {
        let state = AppPerformanceSignpost.begin("BookmarkMerge", "Entries: \(entries.count)")
        defer {
            AppPerformanceSignpost.end("BookmarkMerge", state, "Entries: \(entries.count)")
        }
        
        // A background Realm cached for this thread doesn't advance on its own.
        if !realm.isInWriteTransaction {
            realm.refresh()
        }
        let local = realm.objects(BookBookmarkRealm.self).filter("bookId == %@", bookId).map { $0.toDomain() }
        let plan = BookmarkMerge.plan(local: Array(local), remote: entries, posType: posType, bookId: bookId)
        guard !plan.updated.isEmpty || !plan.inserted.isEmpty else { return plan.upload }
        
        let changesBlock = {
            for bookmark in plan.updated {
                guard let id = try? ObjectId(string: bookmark.id),
                      let object = realm.object(ofType: BookBookmarkRealm.self, forPrimaryKey: id)
                else { continue }
                object.applyDomain(bookmark)
            }
            for bookmark in plan.inserted {
                realm.add(bookmark.makeRealmObject())
            }
        }
        
        if realm.isInWriteTransaction {
            changesBlock()
        } else {
            do {
                try realm.write {
                    changesBlock()
                }
            } catch {
                // The upload describes the merged bookmarks: without them it would rename or
                // remove bookmarks on the server that are unchanged here.
                logger.error("Bookmark merge failed: \(error.localizedDescription)")
                return []
            }
        }
        
        return plan.upload
    }
    
    func syncHighlights(entries: [CalibreBookAnnotationHighlightEntry], forBookId bookId: String) -> Int {
        guard let realm = getRealm(forBookId: bookId) else { return 0 }
        return syncHighlights(entries: entries, forBookId: bookId, using: realm)
    }
    
    private func syncHighlights(entries: [CalibreBookAnnotationHighlightEntry], forBookId bookId: String, using realm: Realm) -> Int {
        let state = AppPerformanceSignpost.begin("HighlightMerge", "Entries: \(entries.count)")
        defer {
            AppPerformanceSignpost.end("HighlightMerge", state, "Entries: \(entries.count)")
        }
        
        let highlightObjects = realm.objects(BookHighlightRealm.self).filter("bookId == %@", bookId)
        var localHighlightsById = [String: BookHighlightRealm]()
        for obj in highlightObjects {
            localHighlightsById[obj.highlightId] = obj
        }
        
        var pending = highlightObjects.count
        
        struct DeduplicatedHighlight {
            let entry: CalibreBookAnnotationHighlightEntry
            let highlightId: String
            let date: Date
        }
        
        // Pre-reduce duplicates by UUID using the newest timestamp
        var latestEntries = [String: DeduplicatedHighlight]()
        entries.forEach { entry in
            guard entry.type == "highlight",
                  let highlightId = uuidCalibreToFolio(entry.uuid),
                  let date = parseAnnotationDate(entry.timestamp)
            else { return }
            
            // Exclude invalid non-removed entries: non-removed highlights must have spineIndex
            if entry.removed != true {
                guard entry.spineIndex != nil else { return }
            }
            
            if let existing = latestEntries[highlightId] {
                if date > existing.date {
                    latestEntries[highlightId] = DeduplicatedHighlight(entry: entry, highlightId: highlightId, date: date)
                }
            } else {
                latestEntries[highlightId] = DeduplicatedHighlight(entry: entry, highlightId: highlightId, date: date)
            }
        }
        let deduplicatedEntries = Array(latestEntries.values)
        
        struct HighlightAction {
            let existingObject: BookHighlightRealm?
            let date: Date
            let entry: CalibreBookAnnotationHighlightEntry
            let isUpdate: Bool
        }
        
        var actions = [HighlightAction]()
        
        deduplicatedEntries.forEach { hl in
            let highlightId = hl.highlightId
            let date = hl.date
            let entry = hl.entry
            
            if entry.removed == true {
                if let object = localHighlightsById[highlightId] {
                    if object.date <= date + 0.1 {
                        actions.append(HighlightAction(existingObject: object, date: date, entry: entry, isUpdate: true))
                        pending -= 1
                    } else if date <= object.date + 0.1 {
                        // no-op
                    } else {
                        pending -= 1
                    }
                }
            } else {
                if let object = localHighlightsById[highlightId] {
                    if object.date <= date + 0.1 {
                        actions.append(HighlightAction(existingObject: object, date: date, entry: entry, isUpdate: true))
                        pending -= 1
                    } else if date <= object.date + 0.1 {
                        // no-op
                    } else {
                        pending -= 1
                    }
                } else {
                    actions.append(HighlightAction(existingObject: nil, date: date, entry: entry, isUpdate: false))
                }
            }
        }
        
        if !actions.isEmpty {
            let changesBlock = {
                for action in actions {
                    let date = action.date
                    let entry = action.entry
                    
                    if action.isUpdate, let object = action.existingObject {
                        if entry.removed == true {
                            object.removed = true
                            object.date = date
                        } else {
                            object.date = date
                            object.type = BookHighlightStyle.styleForClass(entry.style?["which"] ?? "yellow").rawValue
                            object.note = entry.notes
                            object.removed = false
                        }
                    } else {
                        guard let spineIndex = entry.spineIndex else { continue }
                        let highlightId = uuidCalibreToFolio(entry.uuid) ?? ""
                        
                        let highlightRealm = BookHighlightRealm()
                        highlightRealm.bookId = bookId
                        highlightRealm.content = entry.highlightedText ?? "Unspecified"
                        highlightRealm.contentPost = ""
                        highlightRealm.contentPre = ""
                        highlightRealm.date = date
                        highlightRealm.highlightId = highlightId
                        highlightRealm.page = spineIndex + 1
                        highlightRealm.type = BookHighlightStyle.styleForClass(entry.style?["which"] ?? "yellow").rawValue
                        highlightRealm.startOffset = 0
                        highlightRealm.endOffset = 0
                        highlightRealm.ranges = entry.ranges
                        highlightRealm.note = entry.notes
                        highlightRealm.cfiStart = entry.startCfi
                        highlightRealm.cfiEnd = entry.endCfi
                        highlightRealm.spineName = entry.spineName
                        if let tocFamilyTitles = entry.tocFamilyTitles {
                            highlightRealm.tocFamilyTitles.append(objectsIn: tocFamilyTitles)
                        }
                        
                        realm.add(highlightRealm, update: .all)
                    }
                }
            }
            
            if realm.isInWriteTransaction {
                changesBlock()
            } else {
                try? realm.write {
                    changesBlock()
                }
            }
        }
        
        return pending
    }
}
