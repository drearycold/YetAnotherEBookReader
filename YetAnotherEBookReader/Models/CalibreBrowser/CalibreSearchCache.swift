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

class CalibreLibrarySearchObject: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId
    
    //search criteria
    @Persisted var libraryId = ""
    
    @Persisted var search = ""
    
    @Persisted var sortBy = SortCriteria.Modified
    @Persisted var sortAsc = false
    
    @Persisted var filters: Map<String, CalibreLibrarySearchFilterValues?>
    
    //search results
    @Persisted var totalNumber = 0
    
    @Persisted var bookIds: List<Int32>
    
    //books after getting metadata and annotations
    @Persisted var books: List<CalibreBookRealm>
    
    //runtime
    var generation = Date.now
    var loading = false
    var error = false
}

class CalibreLibraryCategoryItemObject: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId
    
    @Persisted(originProperty: "items") var assignee: LinkingObjects<CalibreLibraryCategoryObject>
    
    @Persisted var name: String
    @Persisted var averageRating: Double
    @Persisted var count: Int
    @Persisted var url: String
}

class CalibreUnifiedCategoryItemObject: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId
    
    @Persisted(originProperty: "items") var assignee: LinkingObjects<CalibreUnifiedCategoryObject>
    
    @Persisted var categoryName: String
    @Persisted var name: String
    @Persisted var averageRating: Double
    @Persisted var count: Int
    
    @Persisted var items: MutableSet<CalibreLibraryCategoryItemObject>
}


class CalibreLibraryCategoryObject: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId
    
    @Persisted var libraryId: String
    @Persisted var categoryName: String
    
    @Persisted var generation: Date
    @Persisted var totalNumber: Int
    
    @Persisted var items: List<CalibreLibraryCategoryItemObject>
}

class CalibreUnifiedCategoryObject: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId
    
    @Persisted var categoryName: String
    
    @Persisted var totalNumber: Int
    
    @Persisted var items: List<CalibreUnifiedCategoryItemObject>
}

class CalibreUnifiedOffsets: Object {
    @Persisted var offsets: List<Int>
    @Persisted var beenCutOff = false
    @Persisted var cutOffOffset = 0
    
    func setOffset(index: Int, offset: Int) {
        if index < offsets.endIndex {
            offsets[index] = offset
        } else {
            offsets.append(offset)
        }
    }
}

class CalibreUnifiedSearchObject: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId
    
    //search criteria
    @Persisted var search = ""
    
    @Persisted var sortBy = SortCriteria.Modified
    @Persisted var sortAsc = false
    
    @Persisted var filters: Map<String, CalibreLibrarySearchFilterValues?>
    
    @Persisted var libraryIds: MutableSet<String>
    
    
    //search results
    @Persisted var unifiedOffsets: Map<String, CalibreUnifiedOffsets?>
    
    @Persisted var totalNumber = 0
    
    @Persisted var books: List<CalibreBookRealm>
    
    //runtime
    var generation = Date.now
    var loading = false
    var error = false
    
    var parameters: String {
        return "search: \(search); sort by: \(sortBy.rawValue), asc: \(sortAsc);"
    }
}
