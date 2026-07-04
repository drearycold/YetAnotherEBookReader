//
//  BookRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/14.
//

import Foundation
import RealmSwift

protocol BookRepositoryProtocol {
    func primaryKey(for book: CalibreBook) -> String
    func primaryKey(library: CalibreLibrary, bookId: Int32) -> String
    func getBook(id: String) -> CalibreBook?
    func getBook(library: CalibreLibrary, bookId: Int32) -> CalibreBook?
    func observeBook(id: String) -> AsyncStream<CalibreBook?>
    func saveBook(_ book: CalibreBook)
    func deleteBook(id: String)
    func deleteBooks(library: CalibreLibrary, ids: [Int32])
    func getAllBooksInShelf() -> [CalibreBook]
    func bookExists(id: String) -> Bool
    func saveBookSyncRecords(_ records: [BookMetadataSyncRecord], library: CalibreLibrary)
    func persistMetadataEntries(
        library: CalibreLibrary,
        bookIds: [Int32],
        entries: [String: CalibreBookEntry?],
        json: NSDictionary,
        includeAnnotationBooks: Bool
    ) -> BookMetadataPersistenceResult
    func findDeletedBookIds(library: CalibreLibrary, activeIds: [String: CalibreCdbCmdListResult.DateValue]) -> [Int32]
    func countAndNeedUpdateBooks(library: CalibreLibrary) -> (count: Int, needUpdateIds: [Int32])
    #if DEBUG
    func resetBooks(serverUUID: String, libraryName: String)
    #endif
}

protocol LibraryResolver: AnyObject {
    func library(forServerUUID serverUUID: String, libraryName: String) -> CalibreLibrary?
}

class RealmBookRepository: BookRepositoryProtocol {
    private let databaseService: DatabaseService
    private weak var libraryResolver: LibraryResolver?
    
    init(databaseService: DatabaseService = .shared, libraryResolver: LibraryResolver) {
        self.databaseService = databaseService
        self.libraryResolver = libraryResolver
    }
    
    private func getRealm() -> Realm? {
        if Thread.isMainThread {
            return databaseService.realm
        } else if let conf = databaseService.realmConf {
            return try? Realm(configuration: conf)
        }
        return nil
    }

    private func mapBookRealm(_ bookRealm: CalibreBookRealm) -> CalibreBook? {
        guard let serverUUID = bookRealm.serverUUID,
              let libraryName = bookRealm.libraryName,
              let library = libraryResolver?.library(forServerUUID: serverUUID, libraryName: libraryName)
        else { return nil }

        return bookRealm.toDomain(library: library)
    }

    func primaryKey(for book: CalibreBook) -> String {
        primaryKey(library: book.library, bookId: book.id)
    }

    func primaryKey(library: CalibreLibrary, bookId: Int32) -> String {
        CalibreBookRealm.PrimaryKey(
            serverUUID: library.server.uuid.uuidString,
            libraryName: library.name,
            id: bookId.description
        )
    }
    
    func getBook(id: String) -> CalibreBook? {
        guard let realm = getRealm(),
              let bookRealm = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: id)
        else { return nil }

        return mapBookRealm(bookRealm)
    }

    func getBook(library: CalibreLibrary, bookId: Int32) -> CalibreBook? {
        getBook(id: primaryKey(library: library, bookId: bookId))
    }

    func observeBook(id: String) -> AsyncStream<CalibreBook?> {
        guard let realm = getRealm() else {
            return AsyncStream { continuation in
                continuation.yield(nil)
                continuation.finish()
            }
        }

        _ = realm.refresh()

        let results = realm.objects(CalibreBookRealm.self)
            .filter("primaryKey == %@", id)

        return AsyncStream { [weak self] continuation in
            let token = results.observe(on: DispatchQueue.main) { [weak self] change in
                guard let self else {
                    continuation.yield(nil)
                    return
                }
                switch change {
                case .initial(let collection), .update(let collection, _, _, _):
                    continuation.yield(collection.first.flatMap { self.mapBookRealm($0) })
                case .error:
                    continuation.yield(nil)
                }
            }
            continuation.onTermination = { _ in
                token.invalidate()
            }
        }
    }
    
    func saveBook(_ book: CalibreBook) {
        guard let realm = getRealm() else { return }
        let bookRealm = book.makeRealmObject()
        try? realm.write {
            realm.add(bookRealm, update: .modified)
        }
    }
    
    func deleteBook(id: String) {
        guard let realm = getRealm(),
              let object = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: id)
        else { return }
        try? realm.write {
            realm.delete(object)
        }
    }

    func deleteBooks(library: CalibreLibrary, ids: [Int32]) {
        guard let realm = getRealm() else { return }
        let keys = ids.map { primaryKey(library: library, bookId: $0) }
        try? realm.write {
            keys.compactMap {
                realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: $0)
            }.forEach {
                realm.delete($0)
            }
        }
    }
    
    func getAllBooksInShelf() -> [CalibreBook] {
        guard let realm = getRealm() else { return [] }
        let booksInShelfRealm = realm.objects(CalibreBookRealm.self).filter("inShelf = true")
        return booksInShelfRealm.compactMap { bookRealm -> CalibreBook? in
            guard let serverUUID = bookRealm.serverUUID,
                  let libraryName = bookRealm.libraryName,
                  let library = libraryResolver?.library(forServerUUID: serverUUID, libraryName: libraryName)
            else { return nil }
            return bookRealm.toDomain(library: library)
        }
    }
    
    func bookExists(id: String) -> Bool {
        guard let realm = getRealm() else { return false }
        return realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: id) != nil
    }
    
    func saveBookSyncRecords(_ records: [BookMetadataSyncRecord], library: CalibreLibrary) {
        guard let realm = getRealm() else { return }
        let serverUUID = library.server.uuid.uuidString
        let libraryName = library.name
        try? realm.write {
            records.forEach { record in
                realm.create(
                    CalibreBookRealm.self,
                    value: [
                        "primaryKey": primaryKey(library: library, bookId: record.id),
                        "serverUUID": serverUUID,
                        "libraryName": libraryName,
                        "lastModified": record.lastModified,
                        "idInLib": record.id
                    ],
                    update: .modified
                )
            }
        }
    }

    func persistMetadataEntries(
        library: CalibreLibrary,
        bookIds: [Int32],
        entries: [String: CalibreBookEntry?],
        json: NSDictionary,
        includeAnnotationBooks: Bool
    ) -> BookMetadataPersistenceResult {
        guard let realm = getRealm() else { return .init() }
        var result = BookMetadataPersistenceResult()

        try? realm.write {
            bookIds.forEach { bookId in
                guard let object = realm.object(
                    ofType: CalibreBookRealm.self,
                    forPrimaryKey: primaryKey(library: library, bookId: bookId)
                ) else { return }

                if let entryOptional = entries[bookId.description],
                   let entry = entryOptional,
                   let root = json[bookId.description] as? NSDictionary {
                    object.applyMetadataEntry(entry, root: root)
                    result.booksUpdated.insert(object.idInLib)
                    if object.inShelf {
                        result.booksInShelf.append(object.toDomain(library: library))
                    } else if includeAnnotationBooks {
                        result.booksAnnotation.append(object.toDomain(library: library))
                    }
                } else {
                    object.lastSynced = object.lastModified
                    result.booksDeleted.insert(object.idInLib)
                }
            }
        }

        return result
    }
    
    func findDeletedBookIds(library: CalibreLibrary, activeIds: [String: CalibreCdbCmdListResult.DateValue]) -> [Int32] {
        guard let realm = getRealm() else { return [] }
        let objects = realm.objects(CalibreBookRealm.self).filter(
            "serverUUID == %@ AND libraryName == %@",
            library.server.uuid.uuidString,
            library.name
        )
        return objects
            .filter { $0.inShelf == false && activeIds[$0.idInLib.description] == nil }
            .map { $0.idInLib }
    }
    
    func countAndNeedUpdateBooks(library: CalibreLibrary) -> (count: Int, needUpdateIds: [Int32]) {
        guard let realm = getRealm() else { return (0, []) }
        let objects = realm.objects(CalibreBookRealm.self).filter(
            "serverUUID == %@ AND libraryName == %@",
            library.server.uuid.uuidString,
            library.name
        )
        let count = objects.count
        let objectsNeedUpdate = objects.filter("lastSynced < lastModified")
        let needUpdateIds = objectsNeedUpdate
            .sorted(byKeyPath: "lastModified", ascending: false)
            .map { $0.idInLib }
        return (count, Array(needUpdateIds))
    }

    #if DEBUG
    func resetBooks(serverUUID: String, libraryName: String) {
        guard let realm = getRealm() else { return }
        let books = realm.objects(CalibreBookRealm.self)
            .filter("serverUUID == %@ AND libraryName == %@", serverUUID, libraryName)
        try? realm.write {
            books.forEach {
                $0.lastModified = .init(timeIntervalSince1970: 0)
                $0.lastSynced = .init(timeIntervalSince1970: 0)
                $0.title = "__RESET__"
            }
        }
    }
    #endif
}
