//
//  DatabaseMigrator.swift
//  YetAnotherEBookReader
//
//  Extracted from ModelData.tryInitializeDatabase() on 2026-06-24.
//  Owns the Realm schema v42→v140 migration history.
//

import Foundation
import RealmSwift

final class DatabaseMigrator {
    static let currentSchemaVersion: UInt64 = 140

    /// Build a fully-configured Realm.Configuration with all v42→v140 migration
    /// blocks and the application-support file path. The supplied `statusHandler`
    /// receives human-readable progress updates (currently only emitted from the
    /// v90 server-id migration).
    func makeConfiguration(statusHandler: @escaping (String) -> Void) throws -> Realm.Configuration {
        var conf = Realm.Configuration(
            schemaVersion: DatabaseMigrator.currentSchemaVersion,
            migrationBlock: { migration, oldSchemaVersion in
                if oldSchemaVersion < 138 {
                    migration.deleteData(forType: "CalibreUnifiedSearchObject")
                    migration.deleteData(forType: "CalibreUnifiedOffsets")
                }
                if oldSchemaVersion < 139 {
                    migration.deleteData(forType: "CalibreUnifiedCategoryObject")
                    migration.deleteData(forType: "CalibreUnifiedCategoryItemObject")
                }
                if oldSchemaVersion < 140 {
                    // Removed deprecated properties from CalibreLibrarySearchObject:
                    // generation, totalNumber, bookIds, books. Realm automatically
                    // drops removed columns during migration.
                }
                if oldSchemaVersion < 42 {  //CalibreServerRealm's hasPublicUrl and hasAuth
                    migration.enumerateObjects(ofType: CalibreServerRealm.className()) { oldObject, newObject in
                        //print("migrationBlock \(String(describing: oldObject)) \(String(describing: newObject))")
                        if let publicUrl = oldObject!["publicUrl"] as? String {
                            newObject!["hasPublicUrl"] = publicUrl.count > 0
                        }
                        if let username = oldObject!["username"] as? String, let password = oldObject!["password"] as? String {
                            newObject!["hasAuth"] = username.count > 0 && password.count > 0
                        }
                    }
                }
                if oldSchemaVersion < 44 {  //authos to first/second/more, tags to first/second/third/more
                    migration.enumerateObjects(ofType: CalibreBookRealm.className()) { oldObject, newObject in
                        if let authorsOld = oldObject?.dynamicList("authors") {
                            var authors = Array<DynamicObject>(authorsOld)
                            ["First", "Second", "Third"].forEach {
                                newObject?.setValue(authors.popFirst(), forKey: "author\($0)")

                            }
                            newObject?.dynamicList("authorsMore").append(objectsIn: authors)
                        }

                        if let tagsOld = oldObject?.dynamicList("tags") {
                            var tags = Array<DynamicObject>(tagsOld)
                            ["First", "Second", "Third"].forEach {
                                newObject?.setValue(tags.popFirst(), forKey: "tag\($0)")
                            }
                            newObject?.dynamicList("tagsMore").append(objectsIn: tags)
                        }

                    }
                }
                if oldSchemaVersion < 46 {
                    migration.enumerateObjects(ofType: CalibreBookRealm.className()) { oldObject, newObject in
                        if let lastModified = oldObject?.value(forKey: "lastModified") {
                            newObject?.setValue(lastModified, forKey: "lastModified")
                        }
                    }
                }
                if oldSchemaVersion < 80 {
                    migration.enumerateObjects(ofType: BookDeviceReadingPositionHistoryRealm.className()) { oldObject, newObject in
                        if let bookId = oldObject?.value(forKey: "bookId") as? Int32 {
                            if let libraryId = oldObject?.value(forKey: "libraryId") as? String,
                               let libraryName = libraryId.components(separatedBy: " - ").last {
                                newObject?.setValue("\(libraryName.replacingOccurrences(of: " ", with: "_")) - \(bookId)", forUndefinedKey: "bookId")
                            } else {
                                newObject?.setValue("Unknown - \(bookId)", forUndefinedKey: "bookId")
                            }
                        } else if let bookId = oldObject?.value(forKey: "bookId") as? String {
                            let components = bookId.components(separatedBy: " - ")
                            let newId = components.suffix(2).joined(separator: " - ")
                            newObject?.setValue(newId, forUndefinedKey: "bookId")
                        }
                    }
                }

                if oldSchemaVersion < 90 {
                    /**
                     migrate to UUID based server id
                     1. create new objects with valid UUID, remove old objects,
                     */
                    var servers = [UUID: (baseUrl: String, username: String?)]()
                    migration.enumerateObjects(ofType: CalibreServerRealm.className()) { oldObject, newObject in
                        guard let oldObject = oldObject, let newObject = newObject else { return }
                        guard let baseUrl = oldObject["baseUrl"] as? String else { return }

//                        if let newObject = newObject {
//                            migration.delete(newObject)
//                        }

                        let serverUUID = baseUrl.hasPrefix(".") ? CalibreServer.LocalServerUUID : .init()
//                        let uuidObject = oldObject.copy()
                        newObject["primaryKey"] = serverUUID.uuidString
//                        migration.create(CalibreServerRealm.className(), value: uuidObject)
                        print("\(#function) oldObject=\(oldObject) newObject=\(newObject)")

                        servers[serverUUID] = (baseUrl: baseUrl, username: oldObject["username"] as? String)
                    }

                    var libraries = [String: (serverUUID: UUID, baseUrl: String?, username: String?, key: String?, name: String?)]()
                    migration.enumerateObjects(ofType: CalibreLibraryRealm.className()) { oldObject, newObject in
                        guard let oldObject = oldObject, let newObject = newObject else { return }
                        guard let serverUUID = servers.first(where: {
                            $1.baseUrl == (oldObject["serverUrl"] as? String) && $1.username == (oldObject["serverUsername"] as? String)
                        })?.key else { return }

                        let primaryKey = CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID.uuidString, libraryName: (oldObject["name"] as? String) ?? "Calibre Library")

                        newObject["serverUUID"] = serverUUID.uuidString
                        newObject["primaryKey"] = primaryKey
                        print("\(#function) primaryKey=\(primaryKey) oldObject=\(oldObject) newObject=\(newObject)")

                        libraries[primaryKey] = (
                            serverUUID: serverUUID,
                            baseUrl: oldObject["serverUrl"] as? String,
                            username: oldObject["serverUsername"] as? String,
                            key: oldObject["key"] as? String,
                            name: oldObject["name"] as? String
                        )
                    }

                    var count = 0
                    migration.enumerateObjects(ofType: CalibreBookRealm.className()) { oldObject, newObject in
                        guard let oldObject = oldObject, let newObject = newObject else { return }

                        guard let libraryInfo = libraries.first(where: {
                            $1.baseUrl == (oldObject["serverUrl"] as? String)
                            && $1.username == (oldObject["serverUsername"] as? String)
                            && $1.key != nil
                            && $1.name == (oldObject["libraryName"] as? String)
                        })?.value else {
                            migration.delete(newObject)
                            return
                        }

                        let primaryKey = CalibreBookRealm.PrimaryKey(
                            serverUUID: libraryInfo.serverUUID.uuidString,
                            libraryName: (oldObject["libraryName"] as? String) ?? "Calibre Library",
                            id: (oldObject["id"] as! Int32).description
                        )

                        newObject["serverUUID"] = libraryInfo.serverUUID.uuidString
                        newObject["primaryKey"] = primaryKey
                        count += 1

                        print("\(#function) count=\(count) oldKey=\(oldObject["primaryKey"]!) newKey=\(newObject["primaryKey"]!)")

                        if count % 1000 == 0 {
                            statusHandler("Progress \(count)")
                        }
                    }

//                    fatalError("TODO")
                    statusHandler("Finalizing...")
                }

                if oldSchemaVersion < 104 {
                    migration.renameProperty(onType: CalibreBookRealm.className(), from: "id", to: "idInLib")
                }

                if oldSchemaVersion < 125 {
                    migration.renameProperty(onType: FolioReaderPreferenceRealm.className(), from: "structuralTocLevel", to: "structuralTrackingTocLevel")
                }

                if oldSchemaVersion < 128 {
                    if (oldSchemaVersion >= 125) {
                        migration.renameProperty(onType: FolioReaderPreferenceRealm.className(), from: "currentNavigationMenuBookListSyle", to: "currentNavigationMenuBookListStyle")
                    } else {
                        migration.renameProperty(onType: FolioReaderPreferenceRealm.className(), from: "currentNavigationBookListStyle", to: "currentNavigationMenuBookListStyle")
                    }
                }
                if oldSchemaVersion < 131 {
                    migration.enumerateObjects(ofType: ReadiumPreferenceRealm.className()) { oldObject, newObject in
                        newObject?["offsetFirstPage"] = oldObject?["offsetFirstPage"] as? Bool
                    }
                }
                if oldSchemaVersion < 133 {
                    var count = 0
                    migration.enumerateObjects(ofType: CalibreActivityLogEntry.className()) { oldObject, newObject in
                        newObject?["id"] = UUID().uuidString
                        count += 1
                    }
                    print("Migrated \(count) CalibreActivityLogEntry records.")
                }

                if oldSchemaVersion < 134 {
                    // Migrate CalibreServerDSReaderHelper into CalibreServerRealm
                    var newServersMap = [String: MigrationObject]()
                    migration.enumerateObjects(ofType: CalibreServerRealm.className()) { oldServer, newServer in
                        guard let oldServer = oldServer, let newServer = newServer else { return }
                        let primaryKey = oldServer["primaryKey"] as? String ?? ""
                        newServersMap[primaryKey] = newServer
                    }

                    migration.enumerateObjects(ofType: "CalibreServerDSReaderHelperRealm") { oldHelper, _ in
                        guard let oldHelper = oldHelper else { return }
                        let serverId = oldHelper["id"] as? String ?? ""
                        if let newServer = newServersMap[serverId] {
                            var newHelperDict: [String: Any] = [
                                "port": oldHelper["port"] ?? 0
                            ]
                            if let data = oldHelper["data"] {
                                newHelperDict["configurationData"] = data
                            }
                            newServer["dsreaderHelper"] = newHelperDict
                        }
                    }
                }

                if oldSchemaVersion < 135 {
                    // Fix missing primary keys in CalibreLibraryRealm
                    migration.enumerateObjects(ofType: CalibreLibraryRealm.className()) { oldObject, newObject in
                        guard let oldObject = oldObject, let newObject = newObject else { return }
                        let serverUUID = oldObject["serverUUID"] as? String ?? "-"
                        let libraryName = oldObject["name"] as? String ?? "-"
                        let primaryKey = CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName)
                        newObject["primaryKey"] = primaryKey
                    }
                }
            },
            shouldCompactOnLaunch: { fileSize, dataSize in
                return dataSize * 2 < fileSize || (dataSize + 33554432) < fileSize
            }
        )

        // Move legacy document-directory realm to application-support if needed.
        if let applicationSupportURL = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            conf.fileURL = applicationSupportURL.appendingPathComponent("default.realm")
            if let documentDirectoryURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
                let existingRealmURL = documentDirectoryURL.appendingPathComponent("default.realm")
                if FileManager.default.fileExists(atPath: existingRealmURL.path) {
                    try? FileManager.default.moveItem(at: existingRealmURL, to: conf.fileURL!)
                }
            }
        }

        // Force migration to run by opening the realm once.
        let _ = try Realm(configuration: conf)
        conf.migrationBlock = nil

        Realm.Configuration.defaultConfiguration = conf
        return conf
    }
}
