//
//  CalibreSearchCache.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/3/14.
//

import Foundation
import RealmSwift

extension SortCriteria: PersistableEnum {}

class CalibreLibrarySearchFilterValues: Object {
    @Persisted var values: MutableSet<String>
}

class CalibreLibrarySearchValueObject: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId

    @Persisted var generation: Date     //correspond to library's lastModified
    
    //search results
    @Persisted var totalNumber = 0
    
    @Persisted var bookIds: List<Int32>
    
    override var description: String {
        return "Gen: \(generation) / Total: \(totalNumber) / IDs: \(bookIds.count)"
    }
}

class CalibreLibrarySearchObject: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId
    
    //search criteria
    @Persisted(indexed: true) var libraryId = ""
    
    @Persisted(indexed: true) var search = ""
    
    @Persisted var sortBy = SortCriteria.Modified
    @Persisted(indexed: true) var sortAsc = false
    
    @Persisted var filters: Map<String, CalibreLibrarySearchFilterValues?>
    
    //search results
    @Persisted var sources: Map<String, CalibreLibrarySearchValueObject?>
}

class CalibreLibraryCategoryItemObject: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId
    
    @Persisted(originProperty: "items") var assignee: LinkingObjects<CalibreLibraryCategoryObject>
    
    @Persisted(indexed: true) var name: String
    @Persisted var averageRating: Double
    @Persisted var count: Int
    @Persisted(indexed: true) var url: String
}

class CalibreLibraryCategoryObject: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId
    
    @Persisted var libraryId: String
    @Persisted var categoryName: String
    
    @Persisted var generation: Date
    @Persisted var totalNumber: Int
    
    @Persisted var items: List<CalibreLibraryCategoryItemObject>
}
