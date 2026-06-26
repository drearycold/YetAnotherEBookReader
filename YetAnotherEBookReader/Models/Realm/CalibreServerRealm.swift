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
        self.name = managedObject.name ?? managedObject.baseUrl!
        self.baseUrl = managedObject.baseUrl!
        self.hasPublicUrl = managedObject.hasPublicUrl
        self.publicUrl = managedObject.publicUrl ?? ""
        self.hasAuth = managedObject.hasAuth
        self.username = managedObject.username ?? ""
        self.password = managedObject.password ?? ""
        self.defaultLibrary = managedObject.defaultLibrary ?? ""
        self.removed = managedObject.removed
        self.uuid = UUID(uuidString: managedObject.primaryKey ?? "") ?? .init()
    }
    
    func managedObject() -> CalibreServerRealm {
        let serverRealm = CalibreServerRealm()
        serverRealm.name = self.name
        serverRealm.baseUrl = self.baseUrl
        serverRealm.hasPublicUrl = self.hasPublicUrl
        serverRealm.publicUrl = self.publicUrl
        serverRealm.hasAuth = self.hasAuth
        serverRealm.username = self.username
        serverRealm.password = self.password
        serverRealm.defaultLibrary = self.defaultLibrary
        serverRealm.removed = self.removed
        serverRealm.primaryKey = self.uuid.uuidString
        
        return serverRealm
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
