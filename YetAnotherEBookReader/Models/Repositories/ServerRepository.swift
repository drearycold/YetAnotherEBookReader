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
    func getDSReaderHelperStoredConfiguration(for serverId: String) -> DSReaderHelperStoredConfiguration?
    func replaceDSReaderHelper(_ helper: CalibreServerDSReaderHelper, ifCurrent expected: DSReaderHelperStoredConfiguration) throws -> Bool
}

class RealmServerRepository: ServerRepositoryProtocol {
    private enum StoreError: Error { case realmUnavailable }

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
        try realm.write {
            if let existing = realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: server.id) {
                existing.applyDomain(server)
            } else {
                realm.add(server.makeRealmObject())
            }
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
        _ = try writeDSReaderHelper(helper, for: serverId, ifCurrent: nil)
    }

    func getDSReaderHelperStoredConfiguration(for serverId: String) -> DSReaderHelperStoredConfiguration? {
        guard let server = getRealm()?.object(ofType: CalibreServerRealm.self, forPrimaryKey: serverId),
              !server.removed else { return nil }
        return storedHelperConfiguration(server)
    }

    func replaceDSReaderHelper(
        _ helper: CalibreServerDSReaderHelper,
        ifCurrent expected: DSReaderHelperStoredConfiguration
    ) throws -> Bool {
        try writeDSReaderHelper(helper, for: expected.connection.serverID, ifCurrent: expected)
    }

    private func storedHelperConfiguration(_ server: CalibreServerRealm) -> DSReaderHelperStoredConfiguration {
        .init(connection: .init(server.toDomain()), helper: server.dsreaderHelper?.toValue())
    }

    private func writeDSReaderHelper(
        _ helper: CalibreServerDSReaderHelper, for serverId: String, ifCurrent expected: DSReaderHelperStoredConfiguration?
    ) throws -> Bool {
        guard let realm = getRealm() else { throw StoreError.realmUnavailable }
        return try realm.write {
            guard let server = realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: serverId),
                  !server.removed else { return false }
            if let expected, storedHelperConfiguration(server) != expected { return false }
            if let existing = server.dsreaderHelper {
                existing.apply(helper)
            } else {
                server.dsreaderHelper = CalibreServerDSReaderHelperRealm(value: helper)
            }
            return true
        }
    }
}
