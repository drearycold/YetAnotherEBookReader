//
//  BookRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/14.
//

import Foundation
import RealmSwift

protocol BookRepositoryProtocol {
    func getBook(id: String) -> CalibreBook?
    func saveBook(_ book: CalibreBook)
    func deleteBook(id: String)
    func getAllBooksInShelf() -> [CalibreBook]
    func bookExists(id: String) -> Bool
    func getBookRealm(id: String) -> CalibreBookRealm? // Legacy bridge
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
        if let conf = databaseService.realmConf {
            return try? Realm(configuration: conf)
        }
        return databaseService.realm
    }
    
    func getBook(id: String) -> CalibreBook? {
        guard let realm = getRealm(),
              let bookRealm = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: id)
        else { return nil }
        
        guard let serverUUID = bookRealm.serverUUID,
              let libraryName = bookRealm.libraryName,
              let library = libraryResolver?.library(forServerUUID: serverUUID, libraryName: libraryName)
        else { return nil }
        
        return CalibreBook(managedObject: bookRealm, library: library)
    }
    
    func saveBook(_ book: CalibreBook) {
        guard let realm = getRealm() else { return }
        let bookRealm = book.managedObject()
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
            return CalibreBook(managedObject: bookRealm, library: library)
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
}
