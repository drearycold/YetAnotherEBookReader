//
//  BookRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/14.
//

import Foundation
import RealmSwift

struct LocalBookStorageScope: Sendable {
    let library: CalibreLibrary
    let database: DatabaseService.CacheConfiguration
    let lifetime: CacheLibraryLifetime
}

protocol BookRepositoryProtocol {
    func primaryKey(for book: CalibreBook) -> String
    func primaryKey(library: CalibreLibrary, bookId: Int32) -> String
    func getBook(id: String) -> CalibreBook?
    func getBook(library: CalibreLibrary, bookId: Int32) -> CalibreBook?
    func observeBook(id: String) -> AsyncStream<CalibreBook?>
    func saveBook(_ book: CalibreBook)
    func deleteBook(id: String)
    func localFileBook(scope: LocalBookStorageScope, id: String) throws -> CalibreBook?
    func localFileBooks(scope: LocalBookStorageScope) throws -> [CalibreBook]
    func localFileOwners(scope: LocalBookStorageScope, filename: String, format: Format) throws -> [CalibreBook]
    func commitLocalBookFiles(scope: LocalBookStorageScope, saving books: [CalibreBook], deleting ids: Set<String>,
                              cancelled: () -> Bool) throws
    func mergeLocalPublication(scope: LocalBookStorageScope, id: String, format: Format, filename: String,
                               version: Date, fallbackTitle: String?, title: String?, cancelled: () -> Bool) throws -> CalibreBook?
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

extension BookRepositoryProtocol {
    func localFileBook(scope: LocalBookStorageScope, id: String) throws -> CalibreBook? { getBook(id: id) }

    func localFileBooks(scope: LocalBookStorageScope) throws -> [CalibreBook] {
        getAllBooksInShelf().filter { $0.library.id == scope.library.id }
    }

    func localFileOwners(scope: LocalBookStorageScope, filename: String, format: Format) throws -> [CalibreBook] {
        try localFileBooks(scope: scope).filter { $0.formats[format.rawValue]?.filename == filename }
    }

    func commitLocalBookFiles(scope: LocalBookStorageScope, saving books: [CalibreBook], deleting ids: Set<String>,
                              cancelled: () -> Bool) throws {
        throw ImportError.loadMetaFail
    }

    func mergeLocalPublication(scope: LocalBookStorageScope, id: String, format: Format, filename: String,
                               version: Date, fallbackTitle: String?, title: String?, cancelled: () -> Bool) throws -> CalibreBook? {
        throw ImportError.loadMetaFail
    }
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

    private func openLocalRealm(_ scope: LocalBookStorageScope) throws -> Realm {
        guard (try? scope.lifetime.checkCurrent()) != nil else { throw ImportError.cancelled }
        guard databaseService.cacheConfigurationSnapshot?.id == scope.database.id else { throw ImportError.cancelled }
        let realm = try Realm(configuration: scope.database.configuration)
        if !realm.isInWriteTransaction && !realm.configuration.readOnly { realm.refresh() }
        try checkLocalLibrary(scope, in: realm)
        return realm
    }

    private func checkLocalLibrary(_ scope: LocalBookStorageScope, in realm: Realm) throws {
        guard (try? scope.lifetime.checkCurrent()) != nil else { throw ImportError.cancelled }
        let library = scope.library
        guard let row = realm.object(ofType: CalibreLibraryRealm.self, forPrimaryKey: library.id),
              !row.hidden, (row.key ?? row.name) == library.key,
              let server = realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: library.server.id),
              !server.removed, server.baseUrl == library.server.baseUrl else { throw ImportError.cancelled }
    }

    private func localFileRows(_ scope: LocalBookStorageScope, in realm: Realm) -> Results<CalibreBookRealm> {
        realm.objects(CalibreBookRealm.self)
            .filter("serverUUID == %@ AND libraryName == %@", scope.library.server.id, scope.library.name)
    }

    func localFileBook(scope: LocalBookStorageScope, id: String) throws -> CalibreBook? {
        let realm = try openLocalRealm(scope)
        return realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: id)?.toDomain(library: scope.library)
    }

    func localFileBooks(scope: LocalBookStorageScope) throws -> [CalibreBook] {
        let realm = try openLocalRealm(scope)
        return localFileRows(scope, in: realm).map { $0.toDomain(library: scope.library) }
    }

    func localFileOwners(scope: LocalBookStorageScope, filename: String, format: Format) throws -> [CalibreBook] {
        let realm = try openLocalRealm(scope)
        return localFileRows(scope, in: realm).compactMap {
            let book = $0.toDomain(library: scope.library)
            return book.formats[format.rawValue]?.filename == filename ? book : nil
        }
    }

    func commitLocalBookFiles(scope: LocalBookStorageScope, saving books: [CalibreBook], deleting ids: Set<String>,
                              cancelled: () -> Bool) throws {
        let realm = try openLocalRealm(scope)
        try writeLocalFiles(scope: scope, realm: realm, cancelled: cancelled) {
            for id in ids {
                if let book = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: id) { realm.delete(book) }
            }
            realm.add(books.map { $0.makeRealmObject() }, update: .modified)
        }
    }

    func mergeLocalPublication(scope: LocalBookStorageScope, id: String, format: Format, filename: String,
                               version: Date, fallbackTitle: String?, title: String?, cancelled: () -> Bool) throws -> CalibreBook? {
        let realm = try openLocalRealm(scope)
        return try writeLocalFiles(scope: scope, realm: realm, cancelled: cancelled) {
            guard let row = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: id),
                  row.inShelf, row.lastSynced == version else { return nil }
            let book = row.toDomain(library: scope.library)
            guard let info = book.formats[format.rawValue], info.cached, info.filename == filename else { return nil }
            if let title, row.title == fallbackTitle { row.title = title }
            return row.toDomain(library: scope.library)
        }
    }

    private func writeLocalFiles<T>(scope: LocalBookStorageScope, realm: Realm,
                                    cancelled: () -> Bool, _ body: () throws -> T) throws -> T {
        guard !realm.configuration.readOnly, !realm.isInWriteTransaction else { throw ImportError.loadMetaFail }
        realm.beginWrite()
        do {
            return try databaseService.withCurrentConfiguration(scope.database.id) {
                try checkLocalLibrary(scope, in: realm)
                guard !cancelled() else { throw ImportError.cancelled }
                let value = try body()
                guard !cancelled() else { throw ImportError.cancelled }
                try realm.commitWrite()
                return value
            }
        } catch {
            if realm.isInWriteTransaction { realm.cancelWrite() }
            throw error
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
