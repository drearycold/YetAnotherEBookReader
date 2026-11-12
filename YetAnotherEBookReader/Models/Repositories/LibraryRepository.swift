//
//  LibraryRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/14.
//

import Foundation
import RealmSwift

protocol ServerResolver: AnyObject {
    func server(forUUID uuid: String) -> CalibreServer?
}

#if SC3_UI_TEST_FIXTURE
final class LibrarySettingsFailureFixtureRepository: RealmLibraryRepository {
    private var visibilityFailures: Set<Bool> = [true, false]
    private var failDiscoverability = true

    override func setLibraryHidden(id: String, serverID: String, hidden: Bool) throws {
        if visibilityFailures.remove(hidden) != nil { throw CocoaError(.fileWriteNoPermission) }
        try super.setLibraryHidden(id: id, serverID: serverID, hidden: hidden)
    }

    override func updateLibraryFlags(id: String, discoverable: Bool) throws {
        if failDiscoverability {
            failDiscoverability = false
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.updateLibraryFlags(id: id, discoverable: discoverable)
    }
}
#endif

protocol LibraryRepositoryProtocol {
    func getAllLibraries() -> [CalibreLibrary]
    func getLibrary(id: String) -> CalibreLibrary?
    func observeLibrary(id: String) -> AsyncStream<CalibreLibrary?>
    func saveLibrary(_ library: CalibreLibrary) throws
    func updateLibraryFlags(id: String, discoverable: Bool) throws
    func setLibraryHidden(id: String, serverID: String, hidden: Bool) throws
    func deleteLibrary(serverUUID: String, name: String) throws
    func countBooks(for library: CalibreLibrary) -> Int
}

class RealmLibraryRepository: LibraryRepositoryProtocol {
    private let databaseService: DatabaseService
    private weak var serverResolver: ServerResolver?
    
    init(databaseService: DatabaseService = .shared, serverResolver: ServerResolver) {
        self.databaseService = databaseService
        self.serverResolver = serverResolver
    }
    
    private func getRealm() -> Realm? {
        if Thread.isMainThread {
            return databaseService.realm
        } else if let conf = databaseService.realmConf {
            return try? Realm(configuration: conf)
        }
        return nil
    }

    private func mapLibraryRealm(_ libraryRealm: CalibreLibraryRealm) -> CalibreLibrary? {
        guard let serverUUID = libraryRealm.serverUUID,
              let server = serverResolver?.server(forUUID: serverUUID)
        else { return nil }

        return libraryRealm.toDomain(server: server)
    }
    
    func getAllLibraries() -> [CalibreLibrary] {
        guard let realm = getRealm() else { return [] }
        let librariesCached = realm.objects(CalibreLibraryRealm.self)

        return librariesCached.compactMap(mapLibraryRealm)
    }

    func getLibrary(id: String) -> CalibreLibrary? {
        guard let realm = getRealm(),
              let libraryRealm = realm.object(ofType: CalibreLibraryRealm.self, forPrimaryKey: id)
        else { return nil }

        return mapLibraryRealm(libraryRealm)
    }

    func observeLibrary(id: String) -> AsyncStream<CalibreLibrary?> {
        guard let realm = getRealm() else {
            return AsyncStream { continuation in
                continuation.yield(nil)
                continuation.finish()
            }
        }

        _ = realm.refresh()

        let results = realm.objects(CalibreLibraryRealm.self)
            .filter("primaryKey == %@", id)

        return AsyncStream { [weak self] continuation in
            let token = results.observe(on: DispatchQueue.main) { [weak self] change in
                guard let self else {
                    continuation.yield(nil)
                    return
                }
                switch change {
                case .initial(let collection), .update(let collection, _, _, _):
                    continuation.yield(collection.first.flatMap { self.mapLibraryRealm($0) })
                case .error:
                    continuation.yield(nil)
                }
            }
            continuation.onTermination = { _ in
                token.invalidate()
            }
        }
    }
    
    func saveLibrary(_ library: CalibreLibrary) throws {
        guard let realm = getRealm() else { throw ServerSettingsSaveError.unavailable }
        let libraryRealm = library.makeRealmObject()
        
        try realm.write {
            if realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: library.server.id)?.removed == true {
                throw ServerSettingsSaveError.stale
            }
            realm.add(libraryRealm, update: .all)
        }
    }

    func updateLibraryFlags(id: String, discoverable: Bool) throws {
        guard let realm = getRealm() else { throw ServerSettingsSaveError.unavailable }
        try realm.write {
            let libraryRealm = try currentLibrary(id: id, in: realm)
            guard !libraryRealm.hidden else { throw ServerSettingsSaveError.stale }
            libraryRealm.discoverable = discoverable
        }
    }

    func setLibraryHidden(id: String, serverID: String, hidden: Bool) throws {
        guard let realm = getRealm() else { throw ServerSettingsSaveError.unavailable }
        try realm.write {
            let library = try currentLibrary(id: id, in: realm)
            guard library.serverUUID == serverID, library.hidden != hidden else { throw ServerSettingsSaveError.stale }
            library.hidden = hidden
            if !hidden { library.lastModified = Date(timeIntervalSince1970: 0) }
        }
    }

    private func currentLibrary(id: String, in realm: Realm) throws -> CalibreLibraryRealm {
        guard let library = realm.object(ofType: CalibreLibraryRealm.self, forPrimaryKey: id),
              let serverID = library.serverUUID,
              realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: serverID)?.removed != true else {
            throw ServerSettingsSaveError.stale
        }
        return library
    }
    
    func deleteLibrary(serverUUID: String, name: String) throws {
        guard let realm = getRealm() else { throw ServerSettingsSaveError.unavailable }
        let primaryKey = CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID, libraryName: name)
        try realm.write {
            let object = try currentLibrary(id: primaryKey, in: realm)
            // Delete all books associated with this library
            let booksToDelete = realm.objects(CalibreBookRealm.self).filter("serverUUID == %@ AND libraryName == %@", serverUUID, name)
            realm.delete(booksToDelete)
            
            // Delete the library
            realm.delete(object)
        }
    }
    
    func countBooks(for library: CalibreLibrary) -> Int {
        guard let realm = getRealm() else { return 0 }
        return realm.objects(CalibreBookRealm.self).filter("serverUUID == %@ AND libraryName == %@", library.server.uuid.uuidString, library.name).count
    }
}
