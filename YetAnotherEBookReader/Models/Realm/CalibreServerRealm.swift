//
//  CalibreServerRealm.swift
//  YetAnotherEBookReader
//

import Foundation
import RealmSwift

class CalibreServerRealm: Object {
    @Persisted(primaryKey: true) var primaryKey: String?
    
    @Persisted var name: String?
    @Persisted var baseUrl: String?
    @Persisted var hasPublicUrl = false
    @Persisted var publicUrl: String?
    
    @Persisted var hasAuth = false
    @Persisted var username: String?
    @Persisted var password: String?

    @Persisted var defaultLibrary: String?

    @Persisted var removed = false

    @Persisted var dsreaderHelper: CalibreServerDSReaderHelper?
}

extension CalibreServer: Persistable {
    init(managedObject: CalibreServerRealm) {
        self = managedObject.toDomain()
    }
    
    func managedObject() -> CalibreServerRealm {
        return self.makeRealmObject()
    }
}

extension CalibreServer {
    var realmPerf: Realm {
        let key = "realmPerf-\(self.uuid.uuidString)"
        if let cachedRealm = Thread.current.threadDictionary[key] as? Realm {
            return cachedRealm
        }
        let realm = try! Realm(configuration: BookAnnotation.getBookPreferenceServerConfig(self))
        Thread.current.threadDictionary[key] = realm
        return realm
    }
}
