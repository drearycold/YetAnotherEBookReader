//
//  AnnotationRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/14.
//

import Foundation
import Combine
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
    func observeEntries(libraryId: String?, bookId: Int32?, since: Date) -> AnyPublisher<[ActivityLogUIEntry], Never>
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

    func observeEntries(libraryId: String?, bookId: Int32?, since: Date) -> AnyPublisher<[ActivityLogUIEntry], Never> {
        guard let realm = getRealm() else {
            return Just([]).eraseToAnyPublisher()
        }

        return realm.objects(CalibreActivityLogEntry.self)
            .filter(predicate(libraryId: libraryId, bookId: bookId, since: since))
            .sorted(byKeyPath: "startDatetime", ascending: false)
            .changesetPublisher
            .map { [weak self] change -> [ActivityLogUIEntry] in
                guard let self = self else { return [] }
                switch change {
                case .initial(let collection), .update(let collection, _, _, _):
                    return collection.map(self.mapToUI)
                case .error:
                    return []
                }
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
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
        guard let realm = getRealm() else { return }
        let highlightRealm = highlight.makeRealmObject()
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
        let state = AppPerformanceSignpost.begin("BookmarkMerge", "Entries: \(entries.count)")
        defer {
            AppPerformanceSignpost.end("BookmarkMerge", state, "Entries: \(entries.count)")
        }
        guard let realm = getRealm() else { return 0 }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
        
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
                
                let objects = localBookmarksByPos[pos] ?? []
                var hasVisible = !objects.filter({ !$0.removed }).isEmpty
                
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
                        for obj in objects {
                            if !obj.removed {
                                obj.date += 0.001
                                obj.removed = true
                            }
                        }
                        pending.remove(pos)
                        hasVisible = false
                    } else if entryNewestDate < objectNewest.date + 0.1 {
                        //local has newer entry, ignore server one
                    } else {
                        //same date, ignore server one
                        pending.remove(pos)
                    }
                }
                
                guard !hasVisible,
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
                localBookmarksByPos[pos, default: []].insert(object, at: 0)
            }
        }
        
        return pending.count
    }
    
    func syncHighlights(entries: [CalibreBookAnnotationHighlightEntry], forBookId bookId: String) -> Int {
        let state = AppPerformanceSignpost.begin("HighlightMerge", "Entries: \(entries.count)")
        defer {
            AppPerformanceSignpost.end("HighlightMerge", state, "Entries: \(entries.count)")
        }
        guard let realm = getRealm() else { return 0 }
        
        let highlightObjects = realm.objects(BookHighlightRealm.self).filter("bookId == %@", bookId)
        var localHighlightsById = [String: BookHighlightRealm]()
        for obj in highlightObjects {
            localHighlightsById[obj.highlightId] = obj
        }
        
        var pending = highlightObjects.count
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
        
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
                  let date = dateFormatter.date(from: entry.timestamp)
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
        
        try? realm.write {
            deduplicatedEntries.forEach { hl in
                let highlightId = hl.highlightId
                let date = hl.date
                let entry = hl.entry
                
                guard entry.removed != true else {
                    if let object = localHighlightsById[highlightId] {
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
                
                guard let spineIndex = entry.spineIndex else { return }
                
                if let object = localHighlightsById[highlightId] {
                    if object.date <= date + 0.1 {
                        object.date = date
                        object.type = BookHighlightStyle.styleForClass(entry.style?["which"] ?? "yellow").rawValue
                        object.note = entry.notes
                        object.removed = false
                        pending -= 1
                    } else if date <= object.date + 0.1 {
                        
                    } else {
                        pending -= 1
                    }
                } else {
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
                    localHighlightsById[highlightId] = highlightRealm
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
