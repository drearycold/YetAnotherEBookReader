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
    
    //books after getting metadata and annotations
    @Persisted var books: List<CalibreBookRealm>
    
    override var description: String {
        return "Gen: \(generation) / Total: \(totalNumber) / IDs: \(bookIds.count) / Books: \(books.count)"
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

class CalibreUnifiedCategoryItemObject: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId
    
    @Persisted(originProperty: "items") var assignee: LinkingObjects<CalibreUnifiedCategoryObject>
    
    @Persisted(indexed: true) var categoryName: String
    @Persisted(indexed: true) var name: String
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
    
    @Persisted(indexed: true) var categoryName: String
    @Persisted(indexed: true) var search: String
    
    @Persisted var totalNumber: Int
    @Persisted var itemsCount: Int
    @Persisted var items: List<CalibreUnifiedCategoryItemObject>
    
    var key: CalibreUnifiedCategoryKey {
        .init(categoryName: categoryName, search: search)
    }
}

class CalibreUnifiedOffsets: Object {
    @Persisted var beenCutOff = false
    @Persisted var beenConsumed = false

    @Persisted var cutOffOffset = 0
    @Persisted var offset = 0
    @Persisted var generation: Date
    
    @Persisted var searchObject: CalibreLibrarySearchObject?
    @Persisted var searchObjectSource: String = ""
    
    @Persisted(originProperty: "unifiedOffsets") var assignee: LinkingObjects<CalibreUnifiedSearchObject>
    
    override var description: String {
        return "O:\(offset) CO:\(beenCutOff) CS:\(beenConsumed) S:\(searchObjectSource)"
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
    
    @Persisted var limitNumber = 100
    
    @Persisted var books: List<CalibreBookRealm>
    
    //runtime
    var loading = false
    
    var parameters: String {
        return "search: \(search); sort by: \(sortBy.rawValue), asc: \(sortAsc);"
    }
    
    func resetList() {
        self.books.removeAll()
        self.unifiedOffsets.forEach {
            $0.value?.beenCutOff = false
            $0.value?.beenConsumed = false
            $0.value?.offset = 0
        }
    }
}

struct CalibreUnifiedSearchRuntime {
    var indexMap: [String: Int] = [:]
    var objectNotificationToken: NotificationToken?
    
    var loading = false
    var error = false
}
