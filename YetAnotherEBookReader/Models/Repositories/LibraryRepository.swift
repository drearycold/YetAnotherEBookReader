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
    func saveLibrary(_ library: CalibreLibrary) throws
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
    
    func getAllLibraries() -> [CalibreLibrary] {
        guard let realm = getRealm() else { return [] }
        let librariesCached = realm.objects(CalibreLibraryRealm.self)
        
        return librariesCached.compactMap { libraryRealm -> CalibreLibrary? in
            guard let serverUUID = libraryRealm.serverUUID,
                  let server = serverResolver?.server(forUUID: serverUUID)
            else { return nil }
            
            return libraryRealm.toDomain(server: server)
        }
    }
    
    func saveLibrary(_ library: CalibreLibrary) throws {
        guard let realm = getRealm() else { return }
        let libraryRealm = library.makeRealmObject()
        
        try realm.write {
            realm.add(libraryRealm, update: .all)
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
