//
//  DefaultServerScopedRealmConfigurationProvider.swift
//  YetAnotherEBookReader
//
//  Production implementation of `ServerScopedRealmConfigurationProviding`.
//  Writes a per-server `.realm` file into Application Support for
//  reading positions, reader preferences, annotations, and PDF options.
//

import Foundation
import RealmSwift

final class DefaultServerScopedRealmConfigurationProvider: ServerScopedRealmConfigurationProviding {
    private struct CacheKey: Hashable {
        let serverUUID: String
        let schemaVersion: UInt64
    }
    
    private var cache = [CacheKey: Realm.Configuration]()
    private let lock = NSLock()
    
    func configuration(for server: CalibreServer) -> Realm.Configuration {
        let key = CacheKey(serverUUID: server.uuid.uuidString, schemaVersion: DatabaseSchema.version)
        
        lock.lock()
        if let cachedConfig = cache[key] {
            lock.unlock()
            return cachedConfig
        }
        lock.unlock()
        
        let newConfig = makeConfiguration(for: server)
        
        lock.lock()
        if let cachedConfig = cache[key] {
            lock.unlock()
            return cachedConfig
        }
        cache[key] = newConfig
        lock.unlock()
        
        return newConfig
    }

    private func makeConfiguration(for server: CalibreServer) -> Realm.Configuration {
        let applicationSupportURL = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return Realm.Configuration(
            fileURL: applicationSupportURL.appendingPathComponent("\(server.uuid.uuidString).realm"),
            schemaVersion: DatabaseSchema.version,
            migrationBlock: { migration, oldSchemaVersion in
                if oldSchemaVersion < 125 {
                    migration.renameProperty(
                        onType: FolioReaderPreferenceRealm.className(),
                        from: "structuralTocLevel",
                        to: "structuralTrackingTocLevel"
                    )
                }

                if oldSchemaVersion < 128 {
                    if oldSchemaVersion >= 125 {
                        migration.renameProperty(
                            onType: FolioReaderPreferenceRealm.className(),
                            from: "currentNavigationMenuBookListSyle",
                            to: "currentNavigationMenuBookListStyle"
                        )
                    } else {
                        migration.renameProperty(
                            onType: FolioReaderPreferenceRealm.className(),
                            from: "currentNavigationBookListStyle",
                            to: "currentNavigationMenuBookListStyle"
                        )
                    }
                }

                if oldSchemaVersion < 131 {
                    migration.enumerateObjects(ofType: ReadiumPreferenceRealm.className()) { oldObject, newObject in
                        newObject?["offsetFirstPage"] = oldObject?["offsetFirstPage"] as? Bool
                    }
                }

                if oldSchemaVersion < 134 {
                    migration.enumerateObjects(ofType: PDFOptions.className()) { _, newObject in
                        newObject?["_id"] = ObjectId.generate()
                    }

                    // Legacy YabrPDFOptionsRealm migration, if any data exists in this realm.
                    var existingKeys = Set<String>()
                    migration.enumerateObjects(ofType: PDFOptions.className()) { oldObject, _ in
                        if let oldObject = oldObject,
                           let bookId = oldObject["bookId"] as? Int32,
                           let libraryName = oldObject["libraryName"] as? String {
                            existingKeys.insert("\(libraryName)_\(bookId)")
                        }
                    }

                    migration.enumerateObjects(ofType: "YabrPDFOptionsRealm") { oldObject, _ in
                        guard let oldObject = oldObject else { return }
                        let bookId = oldObject["bookId"] as? Int32 ?? 0
                        let libraryName = oldObject["libraryName"] as? String ?? ""
                        let key = "\(libraryName)_\(bookId)"

                        if !existingKeys.contains(key) {
                            let newObj = migration.create(PDFOptions.className())
                            newObj["_id"] = ObjectId.generate()
                            newObj["bookId"] = bookId
                            newObj["libraryName"] = libraryName

                            for key in [
                                "themeMode",
                                "selectedAutoScaler",
                                "pageMode",
                                "readingDirection",
                                "scrollDirection",
                                "hMarginAutoScaler",
                                "vMarginAutoScaler",
                                "hMarginDetectStrength",
                                "vMarginDetectStrength",
                                "marginOffset",
                                "lastScale",
                                "rememberInPagePosition"
                            ] {
                                newObj[key] = oldObject[key]
                            }
                            existingKeys.insert(key)
                        }
                    }
                }
            },
            objectTypes: [
                BookDeviceReadingPositionRealm.self,
                BookDeviceReadingPositionHistoryRealm.self,
                FolioReaderPreferenceRealm.self,
                BookHighlightRealm.self,
                BookBookmarkRealm.self,
                PDFOptions.self,
                ReadiumPreferenceRealm.self
            ]
        )
    }
}
