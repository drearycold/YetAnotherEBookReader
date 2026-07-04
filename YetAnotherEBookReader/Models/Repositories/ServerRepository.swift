//
//  ServerRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/14.
//

import Foundation
import RealmSwift

protocol ServerRepositoryProtocol {
    func getAllServers() -> [CalibreServer]
    func saveServer(_ server: CalibreServer) throws
    func deleteServer(id: String) throws
    
    // Server Plugin/Helper configurations
    func getDSReaderHelper(for serverId: String) -> CalibreServerDSReaderHelper?
    func saveDSReaderHelper(_ helper: CalibreServerDSReaderHelper, for serverId: String) throws
}

class RealmServerRepository: ServerRepositoryProtocol {
    private let databaseService: DatabaseService
    
    init(databaseService: DatabaseService = .shared) {
        self.databaseService = databaseService
    }
    
    private func getRealm() -> Realm? {
        if Thread.isMainThread {
            return databaseService.realm
        } else if let conf = databaseService.realmConf {
            return try? Realm(configuration: conf)
        }
        return nil
    }
    
    func getAllServers() -> [CalibreServer] {
        guard let realm = getRealm() else { return [] }
        return realm.objects(CalibreServerRealm.self).map { $0.toDomain() }
    }
    
    func saveServer(_ server: CalibreServer) throws {
        guard let realm = getRealm() else { return }
        let serverRealm = server.makeRealmObject()
        try realm.write {
            realm.add(serverRealm, update: .modified)
        }
    }
    
    func deleteServer(id: String) throws {
        guard let realm = getRealm(),
              let object = realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: id)
        else { return }
        try realm.write {
            // Delete all libraries associated with the server
            let librariesToDelete = realm.objects(CalibreLibraryRealm.self).filter("serverUUID == %@", id)
            realm.delete(librariesToDelete)
            
            // Delete the server itself
            realm.delete(object)
        }
    }
    
    func getDSReaderHelper(for serverId: String) -> CalibreServerDSReaderHelper? {
        guard let realm = getRealm(),
              let serverRealm = realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: serverId),
              let helper = serverRealm.dsreaderHelper else { return nil }
        return helper.toValue()
    }
    
    func saveDSReaderHelper(_ helper: CalibreServerDSReaderHelper, for serverId: String) throws {
        guard let realm = getRealm(),
              let serverRealm = realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: serverId)
        else { return }
        try realm.write {
            if let existing = serverRealm.dsreaderHelper {
                existing.apply(helper)
            } else {
                serverRealm.dsreaderHelper = CalibreServerDSReaderHelperRealm(value: helper)
            }
        }
    }
}
