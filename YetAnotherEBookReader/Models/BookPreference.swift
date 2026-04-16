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
    
    static func getBookPreferenceServerConfig(_ server: CalibreServer) -> Realm.Configuration {
        let applicationSupportURL = try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        
        return Realm.Configuration(
            fileURL: applicationSupportURL.appendingPathComponent("\(server.uuid.uuidString).realm"),
            schemaVersion: ModelData.RealmSchemaVersion,
            migrationBlock: { migration, oldSchemaVersion in
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
                
                if oldSchemaVersion < 134 {
                    migration.enumerateObjects(ofType: PDFOptions.className()) { oldObject, newObject in
                        newObject?["_id"] = ObjectId.generate()
                    }
                    
                    // Legacy YabrPDFOptionsRealm migration (if any data exists in this realm)
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
                            
                            // Map all other properties
                            for key in ["themeMode", "selectedAutoScaler", "pageMode", "readingDirection", "scrollDirection", 
                                        "hMarginAutoScaler", "vMarginAutoScaler", "hMarginDetectStrength", "vMarginDetectStrength", 
                                        "marginOffset", "lastScale", "rememberInPagePosition"] {
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

