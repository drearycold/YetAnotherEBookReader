//
//  CalibreLibraryRealm.swift
//  YetAnotherEBookReader
//

import Foundation
import RealmSwift

class CalibreLibraryRealm: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var primaryKey: String?
    
    @Persisted var key: String?
    @Persisted var name: String? {
        didSet {
            updatePrimaryKey()
        }
    }
    @Persisted var serverUUID: String? {
        didSet {
            updatePrimaryKey()
        }
    }
    
    func updatePrimaryKey() {
        primaryKey = CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID ?? "-", libraryName: name ?? "-")
    }
    
    static func PrimaryKey(serverUUID: String, libraryName: String) -> String {
        return [libraryName, "@", serverUUID].joined()
    }
    
    @Persisted var customColumnsData: Data?
    
    @Persisted var autoUpdate = true
    @Persisted var discoverable = true
    @Persisted var hidden = false
    @Persisted var lastModified = Date(timeIntervalSince1970: 0)
}
