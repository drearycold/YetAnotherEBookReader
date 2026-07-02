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

protocol LibraryRepositoryProtocol {
    func getAllLibraries() -> [CalibreLibrary]
    func getLibrary(id: String) -> CalibreLibrary?
    func observeLibrary(id: String) -> AsyncStream<CalibreLibrary?>
    func saveLibrary(_ library: CalibreLibrary) throws
    func updateLibraryFlags(id: String, discoverable: Bool, autoUpdate: Bool) throws
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

        let results = realm.objects(CalibreLibraryRealm.self)
            .filter("primaryKey == %@", id)

        return AsyncStream { [weak self] continuation in
            continuation.yield(results.first.flatMap { self?.mapLibraryRealm($0) })
            let token = results.observe(on: DispatchQueue.main) { [weak self] change in
                guard let self else {
                    continuation.yield(nil)
                    return
                }
                switch change {
                case .initial:
                    break
                case .update(let collection, _, _, _):
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
        guard let realm = getRealm() else { return }
        let libraryRealm = library.makeRealmObject()
        
        try realm.write {
            realm.add(libraryRealm, update: .all)
        }
    }

    func updateLibraryFlags(id: String, discoverable: Bool, autoUpdate: Bool) throws {
        guard let realm = getRealm(),
              let libraryRealm = realm.object(ofType: CalibreLibraryRealm.self, forPrimaryKey: id)
        else { return }

        try realm.write {
            libraryRealm.discoverable = discoverable
            libraryRealm.autoUpdate = autoUpdate
        }
    }
    
    func deleteLibrary(serverUUID: String, name: String) throws {
        guard let realm = getRealm() else { return }
        let primaryKey = CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID, libraryName: name)
        let object = realm.object(ofType: CalibreLibraryRealm.self, forPrimaryKey: primaryKey)
        try realm.write {
            // Delete all books associated with this library
            let booksToDelete = realm.objects(CalibreBookRealm.self).filter("serverUUID == %@ AND libraryName == %@", serverUUID, name)
            realm.delete(booksToDelete)
            
            // Delete the library
            if let object = object {
                realm.delete(object)
            }
        }
    }
    
    func countBooks(for library: CalibreLibrary) -> Int {
        guard let realm = getRealm() else { return 0 }
        return realm.objects(CalibreBookRealm.self).filter("serverUUID == %@ AND libraryName == %@", library.server.uuid.uuidString, library.name).count
    }
}
