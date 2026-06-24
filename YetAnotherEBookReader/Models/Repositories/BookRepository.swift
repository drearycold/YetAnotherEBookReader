//
//  BookRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/14.
//

import Foundation
import Combine
import RealmSwift

protocol BookRepositoryProtocol {
    func getBook(id: String) -> CalibreBook?
    func observeBook(id: String) -> AnyPublisher<CalibreBook?, Never>
    func saveBook(_ book: CalibreBook)
    func deleteBook(id: String)
    func getAllBooksInShelf() -> [CalibreBook]
    func bookExists(id: String) -> Bool
    func bulkUpdateBooks(records: [[String: Any]])
    func findDeletedBookIds(serverUUID: String, libraryName: String, activeIds: [String: Any]) -> [Int32]
    func countAndNeedUpdateBooks(serverUUID: String, libraryName: String) -> (count: Int, needUpdateIds: [Int32])
    func getBookRealm(id: String) -> CalibreBookRealm? // Legacy bridge
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
    
    func getBook(id: String) -> CalibreBook? {
        guard let realm = getRealm(),
              let bookRealm = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: id)
        else { return nil }

        return mapBookRealm(bookRealm)
    }

    func observeBook(id: String) -> AnyPublisher<CalibreBook?, Never> {
        guard let realm = getRealm() else {
            return Just(nil).eraseToAnyPublisher()
        }

        return realm.objects(CalibreBookRealm.self)
            .filter("primaryKey == %@", id)
            .changesetPublisher
            .map { [weak self] change -> CalibreBook? in
                guard let self = self else { return nil }
                switch change {
                case .initial(let collection), .update(let collection, _, _, _):
                    guard let bookRealm = collection.first else { return nil }
                    return self.mapBookRealm(bookRealm)
                case .error:
                    return nil
                }
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
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
    
    func getBookRealm(id: String) -> CalibreBookRealm? {
        guard let realm = getRealm() else { return nil }
        return realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: id)
    }
    
    func bulkUpdateBooks(records: [[String: Any]]) {
        guard let realm = getRealm() else { return }
        try? realm.write {
            records.forEach { record in
                realm.create(CalibreBookRealm.self, value: record, update: .modified)
            }
        }
    }
    
    func findDeletedBookIds(serverUUID: String, libraryName: String, activeIds: [String: Any]) -> [Int32] {
        guard let realm = getRealm() else { return [] }
        let objects = realm.objects(CalibreBookRealm.self).filter(
            "serverUUID == %@ AND libraryName == %@", serverUUID, libraryName
        )
        return objects
            .filter { $0.inShelf == false && activeIds[$0.idInLib.description] == nil }
            .map { $0.idInLib }
    }
    
    func countAndNeedUpdateBooks(serverUUID: String, libraryName: String) -> (count: Int, needUpdateIds: [Int32]) {
        guard let realm = getRealm() else { return (0, []) }
        let objects = realm.objects(CalibreBookRealm.self).filter(
            "serverUUID == %@ AND libraryName == %@", serverUUID, libraryName
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
