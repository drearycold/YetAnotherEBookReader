//
//  AnnotationRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/14.
//

import Foundation
import RealmSwift
import OSLog

struct ActivityLogUIEntry: Identifiable, Hashable {
    let id: String
    let libraryName: String
    let bookTitle: String
    let type: String
    let errMsg: String
    let startDateString: String
    let finishDateString: String
    let startDateLongString: String
    let finishDateLongString: String
    let endpointURL: String
    let httpMethod: String
    let httpBodyString: String?
}

protocol ActivityLogRepositoryProtocol {
    func fetchEntries(libraryId: String?, bookId: Int32?, since: Date) -> [ActivityLogUIEntry]
    func observeEntries(libraryId: String?, bookId: Int32?, since: Date) -> AsyncStream<[ActivityLogUIEntry]>
}

final class RealmActivityLogRepository: ActivityLogRepositoryProtocol {
    private let databaseService: DatabaseService
    private let bookRepository: BookRepositoryProtocol
    private weak var container: AppContainerProtocol?

    init(
        databaseService: DatabaseService = .shared,
        bookRepository: BookRepositoryProtocol,
        container: AppContainerProtocol?
    ) {
        self.databaseService = databaseService
        self.bookRepository = bookRepository
        self.container = container
    }

    private func getRealm() -> Realm? {
        if Thread.isMainThread {
            return databaseService.realm
        }

        let key = "ActivityLogRepositoryRealm"
        if let cachedRealm = Thread.current.threadDictionary[key] as? Realm {
            cachedRealm.refresh()
            return cachedRealm
        }

        if let conf = databaseService.realmConf, let realm = try? Realm(configuration: conf) {
            Thread.current.threadDictionary[key] = realm
            return realm
        }
        return nil
    }

    private func predicate(libraryId: String?, bookId: Int32?, since: Date) -> NSPredicate {
        if let libraryId = libraryId {
            if let bookId = bookId {
                return NSPredicate(
                    format: "startDatetime >= %@ AND libraryId == %@ AND bookId == %d",
                    since as NSDate,
                    libraryId,
                    bookId
                )
            }
            return NSPredicate(format: "startDatetime >= %@ AND libraryId == %@", since as NSDate, libraryId)
        }

        return NSPredicate(format: "startDatetime >= %@", since as NSDate)
    }

    private func mapToUI(_ obj: CalibreActivityLogEntry) -> ActivityLogUIEntry {
        var libraryName = "No Entity"
        var bookTitle = ""

        if let libraryId = obj.libraryId,
           let library = container?.calibreLibraries[libraryId] {
            libraryName = library.name
            let primaryKey = CalibreBookRealm.PrimaryKey(
                serverUUID: library.server.uuid.uuidString,
                libraryName: library.name,
                id: obj.bookId.description
            )
            if let book = bookRepository.getBook(id: primaryKey) {
                bookTitle = book.title
            }
        }

        return ActivityLogUIEntry(
            id: obj.id,
            libraryName: libraryName,
            bookTitle: bookTitle,
            type: obj.type ?? "Unknown Type",
            errMsg: obj.errMsg ?? "Unknown Error",
            startDateString: obj.startDateByLocale ?? "Start Unknown",
            finishDateString: obj.finishDateByLocale ?? "Finish Unknown",
            startDateLongString: obj.startDateByLocaleLong ?? "Unknown",
            finishDateLongString: obj.finishDateByLocaleLong ?? "Unknown",
            endpointURL: obj.endpoingURL ?? "Unknown",
            httpMethod: obj.httpMethod ?? "GET",
            httpBodyString: obj.httpBody.flatMap { String(data: $0, encoding: .utf8) }
        )
    }

    func fetchEntries(libraryId: String?, bookId: Int32?, since: Date) -> [ActivityLogUIEntry] {
        guard let realm = getRealm() else { return [] }

        return realm.objects(CalibreActivityLogEntry.self)
            .filter(predicate(libraryId: libraryId, bookId: bookId, since: since))
            .sorted(byKeyPath: "startDatetime", ascending: false)
            .map(mapToUI)
    }

    func observeEntries(libraryId: String?, bookId: Int32?, since: Date) -> AsyncStream<[ActivityLogUIEntry]> {
        guard let realm = getRealm() else {
            return AsyncStream { continuation in
                continuation.yield([])
                continuation.finish()
            }
        }

        let results = realm.objects(CalibreActivityLogEntry.self)
            .filter(predicate(libraryId: libraryId, bookId: bookId, since: since))
            .sorted(byKeyPath: "startDatetime", ascending: false)

        return AsyncStream { [weak self] continuation in
            continuation.yield(results.compactMap { self?.mapToUI($0) })
            let token = results.observe(on: DispatchQueue.main) { [weak self] change in
                guard let self else {
                    continuation.yield([])
                    return
                }
                switch change {
                case .initial:
                    break
                case .update(let collection, _, _, _):
                    continuation.yield(collection.map(self.mapToUI))
                case .error:
                    continuation.yield([])
                }
            }
            continuation.onTermination = { _ in
                token.invalidate()
            }
        }
    }
}

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
        let objects = realm.objects(BookBookmarkRealm.self).filter("bookId == %@ AND pos == %@", bookId, pos)
        return objects.first?.toDomain()
    }
    
    func saveBookmark(_ bookmark: BookBookmark) -> (Int, String?) {
        guard let realm = getRealm() else { return (0, nil) }
        
        var returnStatus = 0
        var oldTitle: String? = nil
        
        try? realm.write {
            // Check if pos exists
            let existing = realm.objects(BookBookmarkRealm.self).filter("bookId == %@ AND pos == %@ AND removed != true", bookmark.bookId, bookmark.pos)
            if let first = existing.first {
                oldTitle = first.title
                if first.title != bookmark.title {
                    first.applyDomain(bookmark)
                    returnStatus = 2 // updated title
                } else {
                    returnStatus = 0 // same
                }
            } else {
                let bookmarkRealm = bookmark.makeRealmObject()
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
    func syncBookmarks(entries: [CalibreBookAnnotationBookmarkEntry], forBookId bookId: String) -> Int {
        guard let realm = getRealm(forBookId: bookId) else { return 0 }
        return syncBookmarks(entries: entries, forBookId: bookId, using: realm)
    }
    
    private func syncBookmarks(entries: [CalibreBookAnnotationBookmarkEntry], forBookId bookId: String, using realm: Realm) -> Int {
        let state = AppPerformanceSignpost.begin("BookmarkMerge", "Entries: \(entries.count)")
        defer {
            AppPerformanceSignpost.end("BookmarkMerge", state, "Entries: \(entries.count)")
        }
        
        let bookObjects = realm.objects(BookBookmarkRealm.self).filter("bookId == %@", bookId)
        
        var pending = bookObjects.reduce(into: Set<String>()) { partialResult, object in
            partialResult.insert(object.pos)
        }
        
        var localBookmarksByPos = [String: [BookBookmarkRealm]]()
        for obj in bookObjects {
            localBookmarksByPos[obj.pos, default: []].append(obj)
        }
        for (pos, objs) in localBookmarksByPos {
            localBookmarksByPos[pos] = objs.sorted(by: { $0.date > $1.date })
        }
        
        struct RemoteNewestBookmark {
            let entry: CalibreBookAnnotationBookmarkEntry
            let date: Date
        }
        
        var newestRemoteByPos = [String: RemoteNewestBookmark]()
        for entry in entries {
            guard entry.type == "bookmark",
                  let date = parseAnnotationDate(entry.timestamp)
            else { continue }
            
            if let existing = newestRemoteByPos[entry.pos] {
                if date > existing.date {
                    newestRemoteByPos[entry.pos] = RemoteNewestBookmark(entry: entry, date: date)
                }
            } else {
                newestRemoteByPos[entry.pos] = RemoteNewestBookmark(entry: entry, date: date)
            }
        }
        
        struct BookmarkAction {
            enum ActionType {
                case remove(objects: [BookBookmarkRealm])
                case add(pos: String, posType: String, title: String, date: Date, removed: Bool, page: Int)
            }
            let type: ActionType
        }
        
        var actions = [BookmarkAction]()
        
        for (pos, newestRemote) in newestRemoteByPos {
            let entryNewest = newestRemote.entry
            let entryNewestDate = newestRemote.date
            
            let objects = localBookmarksByPos[pos] ?? []
            var hasVisible = !objects.filter({ !$0.removed }).isEmpty
            
            if let objectNewest = objects.first {
                let diff = objectNewest.date.timeIntervalSince(entryNewestDate)
                if abs(diff) < 0.1 {
                    // same date/approximate, ignore server
                    pending.remove(pos)
                } else if diff < -0.1 {
                    // server is newer by at least 0.1s -> remove local visible
                    let visibleObjects = objects.filter { !$0.removed }
                    if !visibleObjects.isEmpty {
                        actions.append(BookmarkAction(type: .remove(objects: visibleObjects)))
                    }
                    pending.remove(pos)
                    hasVisible = false
                } else {
                    // local is newer by at least 0.1s -> ignore server, keep pos in pending
                }
            }
            
            guard !hasVisible, entryNewest.removed != true else { continue }
            
            // Validate CFI and parse page before transaction
            guard entryNewest.pos_type == "epubcfi",
                  entryNewest.pos.starts(with: "epubcfi(/") else { continue }
            let firstStepStartIndex = entryNewest.pos.index(entryNewest.pos.startIndex, offsetBy: 9)
            guard let firstStepEndIndex = entryNewest.pos[firstStepStartIndex..<entryNewest.pos.endIndex].firstIndex(where: { elem in
                elem == "/" || elem == ")"
            }) else { continue }
            
            guard let firstStep = Int(entryNewest.pos[firstStepStartIndex..<firstStepEndIndex]) else { continue }
            let page = firstStep / 2
            
            actions.append(BookmarkAction(type: .add(
                pos: pos,
                posType: entryNewest.pos_type,
                title: entryNewest.title,
                date: entryNewestDate,
                removed: entryNewest.removed ?? false,
                page: page
            )))
        }
        
        if !actions.isEmpty {
            let changesBlock = {
                for action in actions {
                    switch action.type {
                    case .remove(let objects):
                        for obj in objects {
                            obj.date += 0.001
                            obj.removed = true
                        }
                    case .add(let pos, let posType, let title, let date, let removed, let page):
                        let object = BookBookmarkRealm()
                        object.bookId = bookId
                        object.pos_type = posType
                        object.pos = pos
                        object.title = title
                        object.date = date
                        object.removed = removed
                        object.page = page
                        
                        realm.add(object)
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
        
        return pending.count
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

// MARK: - Mappings
extension BookBookmarkRealm {
    func toValue() -> BookBookmark {
        return self.toDomain()
    }
    
    convenience init(value: BookBookmark) {
        self.init()
        let object = value.makeRealmObject()
        self._id = object._id
        self.bookId = object.bookId
        self.page = object.page
        self.pos_type = object.pos_type
        self.pos = object.pos
        self.title = object.title
        self.date = object.date
        self.removed = object.removed
    }
}

extension BookHighlightRealm {
    func toValue() -> BookHighlight {
        return self.toDomain()
    }
    
    convenience init(value: BookHighlight) {
        self.init()
        let object = value.makeRealmObject()
        self.highlightId = object.highlightId
        self.bookId = object.bookId
        self.readerName = object.readerName
        self.page = object.page
        self.startOffset = object.startOffset
        self.endOffset = object.endOffset
        self.date = object.date
        self.type = object.type
        self.note = object.note
        self.tocFamilyTitles.removeAll()
        self.tocFamilyTitles.append(objectsIn: object.tocFamilyTitles)
        self.content = object.content
        self.contentPost = object.contentPost
        self.contentPre = object.contentPre
        self.cfiStart = object.cfiStart
        self.cfiEnd = object.cfiEnd
        self.spineName = object.spineName
        self.ranges = object.ranges
        self.removed = object.removed
    }
}
