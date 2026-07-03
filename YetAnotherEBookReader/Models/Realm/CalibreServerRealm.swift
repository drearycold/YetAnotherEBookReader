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

    @Persisted var dsreaderHelper: CalibreServerDSReaderHelperRealm?
}

extension CalibreServer: Persistable {
    init(managedObject: CalibreServerRealm) {
        self = managedObject.toDomain()
    }
    
    func managedObject() -> CalibreServerRealm {
        return self.makeRealmObject()
    }
}
