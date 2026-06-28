//
//  ReadingPositionRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-14.
//

import Foundation
import RealmSwift
import OSLog

protocol ReadingPositionRepositoryProtocol: Sendable {
    func getPosition(forBookId bookId: String, policy: ReadingPositionSelectionPolicy) -> BookDeviceReadingPosition?
    func getPositions(forBookId bookId: String) -> [BookDeviceReadingPosition]
    func debugPositions(forBookId bookId: String) -> [BookDeviceReadingPosition]
    func historyBook(for library: CalibreLibrary, bookId: Int32) -> CalibreBook?
    func savePosition(_ position: BookDeviceReadingPosition, forBookId bookId: String)
    func removePosition(deviceName: String, forBookId bookId: String)
    func removePosition(position: BookDeviceReadingPosition, forBookId bookId: String)
    func createInitial(deviceName: String, reader: ReaderType) -> BookDeviceReadingPosition
    func sessions(forBookId bookId: String, list startDateAfter: Date?) -> [BookDeviceReadingPositionHistory]
    func beginSession(at position: BookDeviceReadingPosition, forBookId bookId: String) -> ReadingSessionHandle?
    func endSession(_ handle: ReadingSessionHandle, at position: BookDeviceReadingPosition)
    func syncPositions(entries lastReadPositions: [CalibreBookLastReadPositionEntry], forBookId bookId: String) -> [CalibreBookLastReadPositionEntry]
    func syncPositions(entries lastReadPositions: [CalibreBookLastReadPositionEntry], forBookId bookId: String, in realm: Realm) -> [CalibreBookLastReadPositionEntry]
    func getRealm(forBookId bookId: String) -> Realm?
}

final class RealmReadingPositionRepository: ReadingPositionRepositoryProtocol, @unchecked Sendable {
    private let databaseService: DatabaseService
    private weak var container: AppContainerProtocol?
    private let logger = Logger(subsystem: "YetAnotherEBookReader", category: "ReadingPositionRepository")

    init(databaseService: DatabaseService = .shared, container: AppContainerProtocol? = nil) {
        self.databaseService = databaseService
        self.container = container
    }
    
    private func getRealmConfiguration(forBookId bookId: String) -> Realm.Configuration? {
        let actualAppContainer = container ?? AppContainer.shared

        // 1. If bookId is inShelfId (id^libraryName@serverUUID)
        if bookId.contains("@") && bookId.contains("^") {
            let components = bookId.components(separatedBy: "@")
            if components.count > 1 {
                let serverUUID = components[1]
                if let server = actualAppContainer?.calibreServers[serverUUID] {
                    return actualAppContainer?.serverScopedRealmProvider.configuration(for: server)
                }
            }
        }

        // 2. If bookId is bookPrefId (libraryKey - id)
        let components = bookId.components(separatedBy: " - ")
        if components.count > 1 {
            let libraryKey = components[0]
            if let library = actualAppContainer?.calibreLibraries.values.first(where: { $0.key == libraryKey }) {
                return actualAppContainer?.serverScopedRealmProvider.configuration(for: library.server)
            }
        }

        // Fallback
        return databaseService.realmConf
    }
    
    func getRealm(forBookId bookId: String) -> Realm? {
        guard let config = getRealmConfiguration(forBookId: bookId) else { return nil }
        
        let cacheKey = "ReadingPositionRepositoryRealm-\(config.fileURL?.path ?? config.inMemoryIdentifier ?? "default")"
        if let cachedRealm = Thread.current.threadDictionary[cacheKey] as? Realm {
            cachedRealm.refresh()
            return cachedRealm
        }
        
        guard let realm = try? Realm(configuration: config) else { return nil }
        Thread.current.threadDictionary[cacheKey] = realm
        return realm
    }
    
    func getPosition(forBookId bookId: String, policy: ReadingPositionSelectionPolicy) -> BookDeviceReadingPosition? {
        let positions = getPositions(forBookId: bookId)
        return policy.select(from: positions)
    }
    
    func getPositions(forBookId bookId: String) -> [BookDeviceReadingPosition] {
        guard let realm = getRealm(forBookId: bookId) else { return [] }
        let objects = realm.objects(BookDeviceReadingPositionRealm.self)
            .filter(NSPredicate(format: "bookId == %@", bookId))
            .sorted(byKeyPath: "epoch", ascending: false)
        return objects.map { $0.toDomain() }
    }

    func debugPositions(forBookId bookId: String) -> [BookDeviceReadingPosition] {
        guard let realm = getRealm(forBookId: bookId) else { return [] }

        let objects = realm.objects(BookDeviceReadingPositionRealm.self)
            .filter("NOT bookId ENDSWITH ' - History' AND bookId BEGINSWITH %@", bookId)
            .sorted(byKeyPath: "epoch", ascending: false)

        return objects.map { $0.toDomain() }
    }

    func historyBook(for library: CalibreLibrary, bookId: Int32) -> CalibreBook? {
        let primaryKey = CalibreBookRealm.PrimaryKey(
            serverUUID: library.server.uuid.uuidString,
            libraryName: library.name,
            id: bookId.description
        )

        guard let realm = Thread.isMainThread ? databaseService.realm : (databaseService.realmConf.flatMap { try? Realm(configuration: $0) }),
              let bookRealm = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
        else { return nil }

        return bookRealm.toDomain(library: library)
    }
    
    func removePosition(position: BookDeviceReadingPosition, forBookId bookId: String) {
        guard let realm = getRealm(forBookId: bookId) else { return }
        try? realm.write {
            let existing = realm.objects(BookDeviceReadingPositionRealm.self)
                .filter(NSPredicate(
                    format: "bookId == %@ AND deviceId == %@ AND readerName == %@ AND structuralStyle == %@ AND positionTrackingStyle == %@ AND structuralRootPageNumber == %@ AND epoch < %@",
                    bookId,
                    position.id,
                    position.readerName,
                    NSNumber(value: position.structuralStyle),
                    NSNumber(value: position.positionTrackingStyle),
                    NSNumber(value: position.structuralRootPageNumber),
                    NSNumber(value: position.epoch)
                ))
            if !existing.isEmpty {
                realm.delete(existing)
            }
        }
    }
    
    func savePosition(_ position: BookDeviceReadingPosition, forBookId bookId: String) {
        guard let realm = getRealm(forBookId: bookId) else { return }

        try? realm.write {
            let identityPredicate = NSPredicate(
                format: "bookId == %@ AND deviceId == %@ AND readerName == %@ AND structuralStyle == %@ AND positionTrackingStyle == %@ AND structuralRootPageNumber == %@",
                bookId,
                position.id,
                position.readerName,
                NSNumber(value: position.structuralStyle),
                NSNumber(value: position.positionTrackingStyle),
                NSNumber(value: position.structuralRootPageNumber)
            )
            let olderPositions = realm.objects(BookDeviceReadingPositionRealm.self)
                .filter(identityPredicate)
                .filter(NSPredicate(format: "epoch < %@", NSNumber(value: position.epoch)))
            if !olderPositions.isEmpty {
                realm.delete(olderPositions)
            }

            let existing = realm.objects(BookDeviceReadingPositionRealm.self)
                .filter(identityPredicate)
            if existing.isEmpty {
                realm.add(position.makeRealmObject(bookId: bookId))
            }
        }
    }
    
    func removePosition(deviceName: String, forBookId bookId: String) {
        guard let realm = getRealm(forBookId: bookId) else { return }
        let objs = realm.objects(BookDeviceReadingPositionRealm.self)
            .filter(NSPredicate(format: "bookId == %@ AND deviceId == %@", bookId, deviceName))
        if !objs.isEmpty {
            try? realm.write {
                realm.delete(objs)
            }
        }
    }
    
    func createInitial(deviceName: String, reader: ReaderType) -> BookDeviceReadingPosition {
        return BookDeviceReadingPosition(id: deviceName, readerName: reader.rawValue)
    }
    
    func sessions(forBookId bookId: String, list startDateAfter: Date?) -> [BookDeviceReadingPositionHistory] {
        guard let realm = getRealm(forBookId: bookId) else { return [] }
        let results = realm.objects(BookDeviceReadingPositionHistoryRealm.self)
            .filter(
                startDateAfter == nil
                ? NSPredicate(format: "bookId == %@", bookId)
                : NSPredicate(format: "bookId == %@ AND startDatetime >= %@", bookId, startDateAfter! as NSDate)
            )
            .filter { $0.endPosition != nil }
        return results.map { $0.toDomain() }
    }
    
    func beginSession(at position: BookDeviceReadingPosition, forBookId bookId: String) -> ReadingSessionHandle? {
        guard let realm = getRealm(forBookId: bookId) else { return nil }
        let now = Date()
        
        let historyEntryFirst = realm.objects(BookDeviceReadingPositionHistoryRealm.self)
            .filter("bookId == %@", bookId)
            .sorted(by: [SortDescriptor(keyPath: "startDatetime", ascending: false)])
            .first
            
        if let historyEntry = historyEntryFirst {
            let historyIdStr = historyEntry._id.stringValue
            // 1. If endPosition exists, check if its end epoch is less than 60s ago
            if let endPosition = historyEntry.endPosition {
                if now.timeIntervalSince1970 < endPosition.epoch + 60 {
                    return ReadingSessionHandle(bookId: bookId, historyId: historyIdStr)
                }
            } else {
                // 2. If endPosition is nil, check if startDatetime is less than 300s ago
                if now.timeIntervalSince(historyEntry.startDatetime) < 300 {
                    return ReadingSessionHandle(bookId: bookId, historyId: historyIdStr)
                }
            }
        }
        
        // Create new history entry
        let historyEntry = BookDeviceReadingPositionHistoryRealm()
        historyEntry.bookId = bookId
        historyEntry.startDatetime = now
        historyEntry.startPosition = position.makeRealmObject(bookId: "\(bookId) - History")
        
        do {
            try realm.write {
                realm.add(historyEntry)
            }
            return ReadingSessionHandle(bookId: bookId, historyId: historyEntry._id.stringValue)
        } catch {
            return nil
        }
    }
    
    func endSession(_ handle: ReadingSessionHandle, at position: BookDeviceReadingPosition) {
        guard let realm = getRealm(forBookId: handle.bookId) else { return }
        guard let objectId = try? ObjectId(string: handle.historyId) else { return }
        guard let historyEntry = realm.object(ofType: BookDeviceReadingPositionHistoryRealm.self, forPrimaryKey: objectId) else { return }
        guard historyEntry.bookId == handle.bookId else { return }
        
        // If endPosition already exists, verify new position is not older
        if let existingEnd = historyEntry.endPosition, position.epoch < existingEnd.epoch {
            return
        }
        
        try? realm.write {
            let newEnd = position.makeRealmObject(bookId: "\(handle.bookId) - History")
            if let existingEnd = historyEntry.endPosition {
                newEnd._id = existingEnd._id
                realm.add(newEnd, update: .modified)
            } else {
                historyEntry.endPosition = newEnd
            }
        }
    }
    
    func syncPositions(entries lastReadPositions: [CalibreBookLastReadPositionEntry], forBookId bookId: String) -> [CalibreBookLastReadPositionEntry] {
        guard let realm = getRealm(forBookId: bookId) else { return [] }
        return syncPositions(entries: lastReadPositions, forBookId: bookId, in: realm)
    }
    
    func syncPositions(entries lastReadPositions: [CalibreBookLastReadPositionEntry], forBookId bookId: String, in realm: Realm) -> [CalibreBookLastReadPositionEntry] {
        let state = AppPerformanceSignpost.begin("PositionMerge", "Entries: \(lastReadPositions.count)")
        defer {
            AppPerformanceSignpost.end("PositionMerge", state, "Entries: \(lastReadPositions.count)")
        }
        
        let localRealms = Array(realm.objects(BookDeviceReadingPositionRealm.self).filter("bookId == %@", bookId))
        let localPositions = localRealms.map { $0.toDomain() }.sorted(by: { $0.epoch > $1.epoch })
        
        var latestLocalByDevice = [String: BookDeviceReadingPosition]()
        for pos in localPositions {
            if latestLocalByDevice[pos.id] == nil {
                latestLocalByDevice[pos.id] = pos
            }
        }
        
        var devicesUpdated = [String: BookDeviceReadingPosition]()
        var devicesInserted = [String: BookDeviceReadingPosition]()
        var tasks = [CalibreBookLastReadPositionEntry]()
        
        var positionsToSave = [BookDeviceReadingPosition]()
        
        lastReadPositions.forEach { remoteEntry in
            guard let remotePosition = BookDeviceReadingPosition(entry: remoteEntry) else {
                return
            }
            
            guard let localPosition = latestLocalByDevice[remoteEntry.device] else {
                positionsToSave.append(remotePosition)
                devicesInserted[remoteEntry.device] = remotePosition
                return
            }
            
            guard localPosition.epoch < remotePosition.epoch else {
                if localPosition.epoch == remotePosition.epoch {
                    devicesUpdated[remoteEntry.device] = remotePosition
                }
                return
            }
            
            devicesUpdated[remoteEntry.device] = remotePosition
        }
        
        localPositions.forEach { localPos in
            guard devicesInserted[localPos.id] == nil else {
                return
            }
            
            if let position = devicesUpdated[localPos.id] {
                positionsToSave.append(position)
            } else {
                tasks.append(localPos.toEntry())
            }
        }
        
        // Index local realms by identity
        var localRealmsByIdentity = [PositionIdentity: [BookDeviceReadingPositionRealm]]()
        for obj in localRealms {
            let identity = obj.identity
            localRealmsByIdentity[identity, default: []].append(obj)
        }
        // Sort each by epoch descending
        for (identity, objs) in localRealmsByIdentity {
            localRealmsByIdentity[identity] = objs.sorted(by: { $0.epoch > $1.epoch })
        }
        
        // Deduplicate positionsToSave by identity
        var uniquePositionsToSave = [PositionIdentity: BookDeviceReadingPosition]()
        for pos in positionsToSave {
            let id = pos.identity
            if let existing = uniquePositionsToSave[id] {
                if pos.epoch > existing.epoch {
                    uniquePositionsToSave[id] = pos
                }
            } else {
                uniquePositionsToSave[id] = pos
            }
        }
        
        if !uniquePositionsToSave.isEmpty {
            let changesBlock = {
                var realmsToDelete = [BookDeviceReadingPositionRealm]()
                var realmsToAdd = [BookDeviceReadingPositionRealm]()
                
                for (_, position) in uniquePositionsToSave {
                    let identity = position.identity
                    let realmsForIdentity = localRealmsByIdentity[identity] ?? []
                    
                    let toDelete = realmsForIdentity.filter { $0.epoch < position.epoch }
                    realmsToDelete.append(contentsOf: toDelete)
                    
                    let hasNewerOrEqual = realmsForIdentity.contains { $0.epoch >= position.epoch }
                    if !hasNewerOrEqual {
                        realmsToAdd.append(position.makeRealmObject(bookId: bookId))
                    }
                }
                
                if !realmsToDelete.isEmpty {
                    realm.delete(realmsToDelete)
                }
                for newObj in realmsToAdd {
                    realm.add(newObj)
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
        
        return tasks
    }
}

// MARK: - Position Identity Helpers

struct PositionIdentity: Hashable, Equatable {
    let deviceId: String
    let readerName: String
    let structuralStyle: Int
    let positionTrackingStyle: Int
    let structuralRootPageNumber: Int
}

extension BookDeviceReadingPosition {
    var identity: PositionIdentity {
        PositionIdentity(
            deviceId: id,
            readerName: readerName,
            structuralStyle: structuralStyle,
            positionTrackingStyle: positionTrackingStyle,
            structuralRootPageNumber: structuralRootPageNumber
        )
    }
}

extension BookDeviceReadingPositionRealm {
    var identity: PositionIdentity {
        PositionIdentity(
            deviceId: deviceId,
            readerName: readerName,
            structuralStyle: structuralStyle,
            positionTrackingStyle: positionTrackingStyle,
            structuralRootPageNumber: structuralRootPageNumber
        )
    }
}
