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
                if oldSchemaVersion < 125 {
                    migration.renameProperty(onType: FolioReaderPreferenceRealm.className(), from: "currentNavigationBookListStyle", to: "currentNavigationMenuBookListSyle")
                    migration.renameProperty(onType: FolioReaderPreferenceRealm.className(), from: "structuralTocLevel", to: "structuralTrackingTocLevel")
                }
            },
            objectTypes: [
                BookDeviceReadingPositionRealm.self,
                BookDeviceReadingPositionHistoryRealm.self,
                FolioReaderPreferenceRealm.self,
                BookHighlightRealm.self,
                BookBookmarkRealm.self,
                YabrPDFOptionsRealm.self,
                ReadiumPreferenceRealm.self
            ]
        )
    }
}

class ReadiumPreferenceStore {
    let realm: Realm
    
    init(server: CalibreServer) {
        let config = BookAnnotation.getBookPreferenceServerConfig(server)
        self.realm = try! Realm(configuration: config)
    }
    
    func load(id: String) -> ReadiumPreferenceRealm? {
        return realm.object(ofType: ReadiumPreferenceRealm.self, forPrimaryKey: id)
    }
    
    func save(id: String, from viewModel: YabrReaderSettingsViewModel) {
        try? realm.write {
            let obj = realm.object(ofType: ReadiumPreferenceRealm.self, forPrimaryKey: id) ?? ReadiumPreferenceRealm()
            if (obj.id == "") {
                obj.id = id
            }
            
            obj.themeMode = viewModel.themeMode
            obj.fontSizePercentage = viewModel.fontSizePercentage
            obj.fontFamily = viewModel.fontFamily
            obj.lineHeight = viewModel.lineHeight
            obj.pageMargins = viewModel.pageMargins
            obj.publisherStyles = viewModel.publisherStyles
            obj.scroll = viewModel.scroll
            obj.textAlign = viewModel.textAlign
            
            obj.columnCount = viewModel.columnCount
            obj.fontWeight = viewModel.fontWeight
            obj.letterSpacing = viewModel.letterSpacing
            obj.wordSpacing = viewModel.wordSpacing
            obj.hyphens = viewModel.hyphens
            obj.imageFilter = viewModel.imageFilter
            obj.textNormalization = viewModel.textNormalization
            obj.typeScale = viewModel.typeScale
            obj.paragraphIndent = viewModel.paragraphIndent
            obj.paragraphSpacing = viewModel.paragraphSpacing
            
            realm.add(obj, update: .all)
        }
    }
}

