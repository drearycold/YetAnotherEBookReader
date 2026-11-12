//
//  ServerRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/14.
//

import Foundation
import RealmSwift

enum ServerSettingsSaveError: Error {
    case unavailable
    case stale
    case duplicate
    case failed

    var message: String {
        switch self {
        case .unavailable: return "Settings storage is unavailable. Try again."
        case .stale: return "These settings have changed. Reopen them or connect again."
        case .duplicate: return "A server with this address and username already exists. Check the connection settings."
        case .failed: return "Could not save the settings. Try again."
        }
    }
}

protocol ServerRepositoryProtocol {
    func getAllServers() -> [CalibreServer]
    func saveServer(_ server: CalibreServer) throws
    func deleteServer(id: String) throws
    func insertServer(_ server: CalibreServer, libraries: [CalibreLibrary], helper: CalibreServerDSReaderHelper?) throws
    func updateServer(_ server: CalibreServer, ifCurrent expected: CalibreServer) throws
    func removeServerConfiguration(ifCurrent expected: CalibreServer) throws
    
    // Server Plugin/Helper configurations
    func getDSReaderHelper(for serverId: String) -> CalibreServerDSReaderHelper?
    func saveDSReaderHelper(_ helper: CalibreServerDSReaderHelper, for serverId: String) throws
    func getDSReaderHelperStoredConfiguration(for serverId: String) -> DSReaderHelperStoredConfiguration?
    func replaceDSReaderHelper(_ helper: CalibreServerDSReaderHelper, ifCurrent expected: DSReaderHelperStoredConfiguration) throws -> Bool
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
        guard let realm = getRealm() else { throw ServerSettingsSaveError.unavailable }
        try realm.write {
            if let existing = realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: server.id) {
                guard !existing.removed || server.removed else { throw ServerSettingsSaveError.stale }
                existing.applyDomain(server)
            } else {
                realm.add(server.makeRealmObject())
            }
        }
    }

    func insertServer(
        _ server: CalibreServer, libraries: [CalibreLibrary], helper: CalibreServerDSReaderHelper?
    ) throws {
        guard let realm = getRealm() else { throw ServerSettingsSaveError.unavailable }
        guard !server.removed, libraries.allSatisfy({ $0.server.id == server.id }),
              Set(libraries.map(\.id)).count == libraries.count else { throw ServerSettingsSaveError.stale }
        let serverObject = server.makeRealmObject()
        serverObject.dsreaderHelper = helper.map { CalibreServerDSReaderHelperRealm(value: $0) }
        let libraryObjects = libraries.map { $0.makeRealmObject() }
        try realm.write {
            guard realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: server.id) == nil,
                  libraries.allSatisfy({ realm.object(ofType: CalibreLibraryRealm.self, forPrimaryKey: $0.id) == nil }) else {
                throw ServerSettingsSaveError.stale
            }
            try checkDuplicateConnection(server, in: realm)
            realm.add(serverObject)
            realm.add(libraryObjects)
        }
    }

    func updateServer(_ server: CalibreServer, ifCurrent expected: CalibreServer) throws {
        guard let realm = getRealm() else { throw ServerSettingsSaveError.unavailable }
        guard server.id == expected.id, !server.removed else { throw ServerSettingsSaveError.stale }
        try realm.write {
            let object = try currentServer(expected, in: realm)
            try checkDuplicateConnection(server, in: realm)
            object.applyDomain(server)
        }
    }

    func removeServerConfiguration(ifCurrent expected: CalibreServer) throws {
        guard let realm = getRealm() else { throw ServerSettingsSaveError.unavailable }
        try realm.write {
            let server = try currentServer(expected, in: realm)
            let libraries = realm.objects(CalibreLibraryRealm.self).filter("serverUUID == %@", expected.id)
            for name in libraries.compactMap(\.name) {
                realm.delete(realm.objects(CalibreBookRealm.self)
                    .filter("serverUUID == %@ AND libraryName == %@", expected.id, name))
            }
            realm.delete(libraries)
            server.removed = true
        }
    }

    private func currentServer(_ expected: CalibreServer, in realm: Realm) throws -> CalibreServerRealm {
        guard let object = realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: expected.id),
              !object.removed, DSReaderHelperConnection(object.toDomain()) == DSReaderHelperConnection(expected),
              object.toDomain().name == expected.name else { throw ServerSettingsSaveError.stale }
        return object
    }

    private func checkDuplicateConnection(_ server: CalibreServer, in realm: Realm) throws {
        let matches = realm.objects(CalibreServerRealm.self)
            .filter("removed == false AND primaryKey != %@ AND baseUrl == %@", server.id, server.baseUrl)
        guard !matches.contains(where: { ($0.username ?? "") == server.username }) else {
            throw ServerSettingsSaveError.duplicate
        }
    }
    
    func deleteServer(id: String) throws {
        guard let realm = getRealm() else { throw ServerSettingsSaveError.unavailable }
        try realm.write {
            guard let object = realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: id) else {
                throw ServerSettingsSaveError.stale
            }
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
        guard try writeDSReaderHelper(helper, for: serverId, ifCurrent: nil) else {
            throw ServerSettingsSaveError.stale
        }
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
        guard let realm = getRealm() else { throw ServerSettingsSaveError.unavailable }
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

#if SC3_UI_TEST_FIXTURE
final class ServerSettingsFailureFixtureRepository: RealmServerRepository {
    private var failInsert = true
    private var failEdit = true
    private var failHelper = true

    override func insertServer(_ server: CalibreServer, libraries: [CalibreLibrary], helper: CalibreServerDSReaderHelper?) throws {
        if failInsert {
            failInsert = false
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.insertServer(server, libraries: libraries, helper: helper)
    }

    override func updateServer(_ server: CalibreServer, ifCurrent expected: CalibreServer) throws {
        if failEdit {
            failEdit = false
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.updateServer(server, ifCurrent: expected)
    }

    override func replaceDSReaderHelper(
        _ helper: CalibreServerDSReaderHelper, ifCurrent expected: DSReaderHelperStoredConfiguration
    ) throws -> Bool {
        if failHelper {
            failHelper = false
            throw CocoaError(.fileWriteNoPermission)
        }
        return try super.replaceDSReaderHelper(helper, ifCurrent: expected)
    }
}
#endif
