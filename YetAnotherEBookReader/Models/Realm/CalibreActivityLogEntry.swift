//
//  CalibreActivityLogEntry.swift
//  YetAnotherEBookReader
//

import Foundation
import RealmSwift

class CalibreActivityLogEntry: Object, Identifiable {
    @Persisted(primaryKey: true) var id = UUID().uuidString
    @Persisted var type: String?
    
    @Persisted var startDatetime = Date.distantPast
    @Persisted var finishDatetime: Date?
    
    //book or library, not both
    @Persisted var bookId: Int32 = 0
    @Persisted var libraryId: String?
    
    @Persisted var endpoingURL: String?
    @Persisted var httpMethod: String?
    @Persisted var httpBody: Data?       //if any
    @Persisted var requestHeaders = List<String>()     //key1, value1, key2, value2, ...
    
    @Persisted var errMsg: String?
}
