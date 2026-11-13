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
    func commitBookFiles(saving books: [CalibreBook], deleting ids: Set<String>) throws
    func localBooks(library: CalibreLibrary, filename: String, format: Format) throws -> [CalibreBook]
    func getAllBooksInShelf() -> [CalibreBook]
    func bookExists(id: String) -> Bool
    func persistMetadataEntries(
        library: CalibreLibrary,
        bookIds: [Int32],
        entries: [String: CalibreBookEntry?],
        json: NSDictionary,
        includeAnnotationBooks: Bool
    ) -> BookMetadataPersistenceResult
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

    func commitBookFiles(saving books: [CalibreBook], deleting ids: Set<String>) throws {
        guard let realm = getRealm(), !realm.configuration.readOnly, !realm.isInWriteTransaction else {
            throw ImportError.loadMetaFail
        }
        let records = books.map { $0.makeRealmObject() }
        try realm.write {
            for id in ids {
                if let book = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: id) {
                    realm.delete(book)
                }
            }
            realm.add(records, update: .modified)
        }
    }

    func localBooks(library: CalibreLibrary, filename: String, format: Format) throws -> [CalibreBook] {
        guard let realm = getRealm() else { throw ImportError.loadMetaFail }
        if !realm.isInWriteTransaction && !realm.configuration.readOnly { realm.refresh() }
        return realm.objects(CalibreBookRealm.self)
            .filter("serverUUID == %@ AND libraryName == %@", library.server.id, library.name)
            .compactMap {
                guard $0.formats()[format.rawValue]?.filename == filename else { return nil }
                return $0.toDomain(library: library)
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

    /// Applies an `ajax/books` answer to the books already recorded. One whose entry is null is
    /// reported in `booksDeleted` (calibre answers null for a book it no longer has, or one a
    /// restricted user may not see) and isn't asked for again until it changes.
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
    
    #if DEBUG
    func resetBooks(serverUUID: String, libraryName: String) {
        guard let realm = getRealm() else { return }
        let books = realm.objects(CalibreBookRealm.self)
            .filter("serverUUID == %@ AND libraryName == %@", serverUUID, libraryName)
        try? realm.write {
            books.forEach {
                $0.lastSynced = .distantPast
            }
        }
    }
    #endif
}
