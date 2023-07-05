//
//  BookPreference.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/30.
//

import Foundation
import RealmSwift

extension BookAnnotation {
    static func PrefId(library: CalibreLibrary, id: Int32) -> String {
        "\(library.key) - \(id)"
    }
    
    static func getBookPreferenceIndividualConfig(bookFileURL: URL) -> Realm.Configuration {
        return Realm.Configuration(
            fileURL: bookFileURL.deletingPathExtension().appendingPathExtension("db"),
            schemaVersion: ModelData.RealmSchemaVersion) { migration, oldSchemaVersion in
                if oldSchemaVersion < 109 {
                    migration.enumerateObjects(ofType: BookDeviceReadingPositionRealm.className()) { oldObject, newObject in
                        if let oldObject = oldObject,
                           let deviceId = oldObject["id"] as? String {
                            newObject?["deviceId"] = deviceId
                        }
                        newObject?["_id"] = ObjectId.generate()
                    }
                }
                
                if oldSchemaVersion < 113 {
                    migration.enumerateObjects(ofType: BookDeviceReadingPositionHistoryRealm.className()) { oldObject, newObject in
                        newObject?["_id"] = ObjectId.generate()
                    }
                }
                if oldSchemaVersion < 114 {
                    migration.enumerateObjects(ofType: BookBookmarkRealm.className()) { oldObject, newObject in
                        newObject?["_id"] = ObjectId.generate()
                    }
                }
            }
    }
    
    static func getBookPreferenceServerConfig(_ server: CalibreServer) -> Realm.Configuration {
        let applicationSupportURL = try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        
        return Realm.Configuration(
            fileURL: applicationSupportURL.appendingPathComponent("\(server.uuid.uuidString).realm"),
            schemaVersion: ModelData.RealmSchemaVersion,
            migrationBlock: { migration, oldSchemaVersion in
                
            },
            objectTypes: [
                BookDeviceReadingPositionRealm.self,
                BookDeviceReadingPositionHistoryRealm.self,
                FolioReaderPreferenceRealm.self,
                BookHighlightRealm.self,
                BookBookmarkRealm.self,
                YabrPDFOptionsRealm.self
            ]
        )
    }
}
