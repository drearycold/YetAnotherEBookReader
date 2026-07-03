//
//  DefaultServerScopedRealmConfigurationProvider.swift
//  YetAnotherEBookReader
//
//  Production implementation of `ServerScopedRealmConfigurationProviding`.
//  Delegates to `BookAnnotation.getBookPreferenceServerConfig(_:)`, which
//  is the long-standing default that writes a per-server `.realm` file
//  into Application Support.
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
        
        let newConfig = BookAnnotation.getBookPreferenceServerConfig(server)
        
        lock.lock()
        if let cachedConfig = cache[key] {
            lock.unlock()
            return cachedConfig
        }
        cache[key] = newConfig
        lock.unlock()
        
        return newConfig
    }
}
