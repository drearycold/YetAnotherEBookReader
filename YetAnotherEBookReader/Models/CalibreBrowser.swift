//
//  CalibreBrowser.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/11/5.
//

import Foundation
import RealmSwift

extension ModelData {
    func getBook(for primaryKey: String) -> CalibreBook? {
        if let obj = getBookRealm(forPrimaryKey: primaryKey),
           let book = convert(bookRealm: obj) {
            return book
        } else if let obj = searchLibraryResultsRealmMainThread?.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey),
                  let book = convert(bookRealm: obj) {
            return book
        }
        return nil
        
    }
    
    func mergeBookLists(results: inout [String : LibrarySearchResult], page: Int = 0, limit: Int = 100) -> [String] {
        guard let realm = try? Realm(configuration: realmConf),
              let realmSearch = searchLibraryResultsRealmLocalThread
        else { return [] }
        
        var merged = [String]()
        
        var startPage = page
        while startPage > 0 {
            if results.allSatisfy({ $0.value.pageOffset[startPage] != nil }) {
                break
            }
            startPage -= 1
        }
        
        var headIndex = [String: Int]()
        results.forEach {
            headIndex[$0.key] = $0.value.pageOffset[startPage] ?? 0
        }
        
        var heads = results.compactMap { entry -> CalibreBookRealm? in
            guard let headOffset = headIndex[entry.value.library.id],
                  headOffset < entry.value.bookIds.count
            else { return nil }
            let primaryKey = CalibreBookRealm.PrimaryKey(
                serverUUID: entry.value.library.server.uuid.uuidString,
                libraryName: entry.value.library.name,
                id: entry.value.bookIds[headOffset].description
            )
            
            return realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
            ?? realmSearch.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
        }
        heads.sort { lhs, rhs in
            lhs.lastModified < rhs.lastModified
        }
        
        while merged.count < limit, let head = heads.popLast() {
            merged.append(head.primaryKey!)
            
            let headLibraryId = CalibreLibraryRealm.PrimaryKey(serverUUID: head.serverUUID!, libraryName: head.libraryName!)
            headIndex[headLibraryId]? += 1
            guard let headOffset = headIndex[headLibraryId],
                  let searchResult = results[headLibraryId],
                  headOffset < searchResult.bookIds.count else { continue }
            
            let primaryKey = CalibreBookRealm.PrimaryKey(
                serverUUID: searchResult.library.server.uuid.uuidString,
                libraryName: searchResult.library.name,
                id: searchResult.bookIds[headOffset].description
            )
            
            guard let next = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
            ?? realmSearch.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
            else { continue }
            
            heads.append(next)
            heads.sort { lhs, rhs in
                lhs.lastModified < rhs.lastModified
            }
        }
        
        headIndex.forEach {
            results[$0.key]?.pageOffset[startPage + 1] = $0.value
        }
        
        return merged
    }
}
