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

extension CalibreServer {
    /// Opens the per-server sidecar Realm using the AppContainer's
    /// configured provider. Callers that hold an AppContainer
    /// instance (i.e. anywhere outside the static `AppContainer.shared`
    /// global) should prefer this method so that the
    /// `ServerScopedRealmConfigurationProviding` that backs the
    /// container is honored. The previous `CalibreServer.realmPerf`
    /// extension routed every call through `AppContainer.shared` and
    /// therefore leaked state across test containers that shared a
    /// server UUID.
    func realm(in container: AppContainer) -> Realm {
        let config = container.serverScopedRealmProvider.configuration(for: self)
        let key = "CalibreServerRealm-\(ObjectIdentifier(container))-\(config.fileURL?.path ?? config.inMemoryIdentifier ?? "default")"
        if let cachedRealm = Thread.current.threadDictionary[key] as? Realm {
            return cachedRealm
        }
        let realm = try! Realm(configuration: config)
        Thread.current.threadDictionary[key] = realm
        return realm
    }
}
