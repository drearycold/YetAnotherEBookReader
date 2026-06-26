//
//  CalibreSearchCache.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/3/14.
//

import Foundation
import RealmSwift

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
    @Persisted var libraryId = ""
    
    @Persisted var search = ""
    
    @Persisted var sortBy = SortCriteria.Modified
    @Persisted var sortAsc = false
    
    @Persisted var filters: Map<String, CalibreLibrarySearchFilterValues?>
    
    //search results
    @Persisted var sources: Map<String, CalibreLibrarySearchValueObject?>
    
    @available(*, deprecated, message: "use sources")
    @Persisted var generation: Date
    
    @available(*, deprecated, message: "use sources")
    @Persisted var totalNumber = 0
    
    @available(*, deprecated, message: "use sources")
    @Persisted var bookIds: List<Int32>
    
    //books after getting metadata and annotations
    @available(*, deprecated, message: "use sources")
    @Persisted var books: List<CalibreBookRealm>
    
    var loading = false
    var error = false
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

