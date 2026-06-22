//
//  ReadingPositionRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-14.
//

import Foundation
import RealmSwift

protocol ReadingPositionRepositoryProtocol: Sendable {
    func getPosition(forBookId bookId: String, deviceName: String?) -> BookDeviceReadingPosition?
    func getPositions(forBookId bookId: String) -> [BookDeviceReadingPosition]
    func savePosition(_ position: BookDeviceReadingPosition, forBookId bookId: String)
    func removePosition(deviceName: String, forBookId bookId: String)
    func removePosition(position: BookDeviceReadingPosition, forBookId bookId: String)
    func createInitial(deviceName: String, reader: ReaderType) -> BookDeviceReadingPosition
    func sessions(forBookId bookId: String, list startDateAfter: Date?) -> [BookDeviceReadingPositionHistory]
    func session(start readPosition: BookDeviceReadingPosition, forBookId bookId: String) -> Date?
    func session(end readPosition: BookDeviceReadingPosition, forBookId bookId: String)
    func syncPositions(entries lastReadPositions: [CalibreBookLastReadPositionEntry], forBookId bookId: String) -> [CalibreBookLastReadPositionEntry]
}

final class RealmReadingPositionRepository: ReadingPositionRepositoryProtocol, @unchecked Sendable {
    private let databaseService: DatabaseService
    private weak var modelData: ModelData?
    
    init(databaseService: DatabaseService = .shared, modelData: ModelData? = nil) {
        self.databaseService = databaseService
        self.modelData = modelData
    }
    
    private func getRealmConfiguration(forBookId bookId: String) -> Realm.Configuration? {
        let actualModelData = modelData ?? ModelData.shared
        
        // 1. If bookId is inShelfId (id^libraryName@serverUUID)
        if bookId.contains("@") && bookId.contains("^") {
            let components = bookId.components(separatedBy: "@")
            if components.count > 1 {
                let serverUUID = components[1]
                if let server = actualModelData?.calibreServers[serverUUID] {
                    return BookAnnotation.getBookPreferenceServerConfig(server)
                }
            }
        }
        
        // 2. If bookId is bookPrefId (libraryKey - id)
        let components = bookId.components(separatedBy: " - ")
        if components.count > 1 {
            let libraryKey = components[0]
            if let library = actualModelData?.calibreLibraries.values.first(where: { $0.key == libraryKey }) {
                return BookAnnotation.getBookPreferenceServerConfig(library.server)
            }
        }
        
        // Fallback
        return databaseService.realmConf
    }
    
    private func getRealm(forBookId bookId: String) -> Realm? {
        guard let config = getRealmConfiguration(forBookId: bookId) else { return nil }
        
        let cacheKey = "ReadingPositionRepositoryRealm-\(config.fileURL?.path ?? "default")"
        if let cachedRealm = Thread.current.threadDictionary[cacheKey] as? Realm {
            cachedRealm.refresh()
            return cachedRealm
        }
        
        guard let realm = try? Realm(configuration: config) else { return nil }
        Thread.current.threadDictionary[cacheKey] = realm
        return realm
    }
    
    func getPosition(forBookId bookId: String, deviceName: String?) -> BookDeviceReadingPosition? {
        guard let realm = getRealm(forBookId: bookId) else { return nil }
        var objects = realm.objects(BookDeviceReadingPositionRealm.self)
            .filter(NSPredicate(format: "bookId == %@", bookId))
            .sorted(byKeyPath: "epoch", ascending: false)
        
        if let deviceName = deviceName {
            objects = objects.filter(NSPredicate(format: "deviceId == %@", deviceName))
        }
        
        return objects.filter(NSPredicate(format: "takePrecedence == true"))
            .map({ $0.toDomain() })
            .first ?? objects.map({ $0.toDomain() }).first
    }
    
    func getPositions(forBookId bookId: String) -> [BookDeviceReadingPosition] {
        guard let realm = getRealm(forBookId: bookId) else { return [] }
        let objects = realm.objects(BookDeviceReadingPositionRealm.self)
            .filter(NSPredicate(format: "bookId == %@", bookId))
            .sorted(byKeyPath: "epoch", ascending: false)
        return objects.map { $0.toDomain() }
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
        removePosition(position: position, forBookId: bookId)
        
        let existing = realm.objects(BookDeviceReadingPositionRealm.self)
            .filter(
                NSPredicate(
                    format: "bookId == %@ AND deviceId == %@ AND readerName == %@ AND structuralStyle == %@ AND positionTrackingStyle == %@ AND structuralRootPageNumber == %@",
                    bookId,
                    position.id,
                    position.readerName,
                    NSNumber(value: position.structuralStyle),
                    NSNumber(value: position.positionTrackingStyle),
                    NSNumber(value: position.structuralRootPageNumber)
                )
            )
        if existing.isEmpty {
            try? realm.write {
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
    
    func session(start readPosition: BookDeviceReadingPosition, forBookId bookId: String) -> Date? {
        guard let realm = getRealm(forBookId: bookId) else { return nil }
        let startDatetime = Date()
        
        let historyEntryFirst = realm.objects(BookDeviceReadingPositionHistoryRealm.self)
            .filter(NSPredicate(format: "bookId == %@", bookId))
            .sorted(by: [SortDescriptor(keyPath: "startDatetime", ascending: false)])
            .first
        
        try? realm.write {
            if let endPosition = historyEntryFirst?.endPosition, startDatetime.timeIntervalSince1970 < endPosition.epoch + 60 {
                historyEntryFirst?.endPosition?.takePrecedence = true
            } else if let startPosition = historyEntryFirst?.startPosition, startDatetime.timeIntervalSince1970 < startPosition.epoch + 300 {
                historyEntryFirst?.endPosition?.takePrecedence = true
            } else {
                let historyEntry = BookDeviceReadingPositionHistoryRealm()
                historyEntry.bookId = bookId
                historyEntry.startDatetime = startDatetime
                historyEntry.startPosition = readPosition.makeRealmObject(bookId: "\(bookId) - History")
                realm.add(historyEntry)
            }
        }
        return startDatetime
    }
    
    func session(end readPosition: BookDeviceReadingPosition, forBookId bookId: String) {
        guard let realm = getRealm(forBookId: bookId) else { return }
        guard let historyEntry = realm.objects(BookDeviceReadingPositionHistoryRealm.self)
            .filter(NSPredicate(format: "bookId == %@", bookId))
            .sorted(by: [SortDescriptor(keyPath: "startDatetime", ascending: false)])
            .first else { return }
            
        guard historyEntry.endPosition == nil || historyEntry.endPosition?.takePrecedence == true else { return }
        
        try? realm.write {
            let newEndPositionObject = readPosition.makeRealmObject(bookId: "\(bookId) - History")
            if let endPositionObject = historyEntry.endPosition {
                newEndPositionObject._id = endPositionObject._id
                realm.add(newEndPositionObject, update: .modified)
            } else {
                historyEntry.endPosition = newEndPositionObject
            }
        }
    }
    
    func syncPositions(entries lastReadPositions: [CalibreBookLastReadPositionEntry], forBookId bookId: String) -> [CalibreBookLastReadPositionEntry] {
        guard let realm = getRealm(forBookId: bookId) else { return [] }
        
        var devicesUpdated = [String: BookDeviceReadingPosition]()
        var devicesInserted = [String: BookDeviceReadingPosition]()
        var tasks = [CalibreBookLastReadPositionEntry]()
        
        var positionsToSave = [BookDeviceReadingPosition]()
        
        lastReadPositions.forEach { remoteEntry in
            guard let remotePosition = BookDeviceReadingPosition(entry: remoteEntry) else {
                return
            }
            
            guard let localPosition = self.getPosition(forBookId: bookId, deviceName: remoteEntry.device) else {
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
        
        self.getPositions(forBookId: bookId).forEach { localPos in
            guard devicesInserted[localPos.id] == nil else {
                return
            }
            
            if let position = devicesUpdated[localPos.id] {
                positionsToSave.append(position)
            } else {
                tasks.append(localPos.toEntry())
            }
        }
        
        if !positionsToSave.isEmpty {
            try? realm.write {
                for position in positionsToSave {
                    let existingToRemove = realm.objects(BookDeviceReadingPositionRealm.self)
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
                    if !existingToRemove.isEmpty {
                        realm.delete(existingToRemove)
                    }
                    
                    let exactMatch = realm.objects(BookDeviceReadingPositionRealm.self)
                        .filter(NSPredicate(
                            format: "bookId == %@ AND deviceId == %@ AND readerName == %@ AND structuralStyle == %@ AND positionTrackingStyle == %@ AND structuralRootPageNumber == %@",
                            bookId,
                            position.id,
                            position.readerName,
                            NSNumber(value: position.structuralStyle),
                            NSNumber(value: position.positionTrackingStyle),
                            NSNumber(value: position.structuralRootPageNumber)
                        ))
                    if exactMatch.isEmpty {
                        realm.add(position.managedObject(bookId: bookId))
                    }
                }
            }
        }
        
        return tasks
    }
}
