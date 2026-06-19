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
    
    var startDateByLocale: String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: startDatetime)
    }
    var startDateByLocaleLong: String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .long
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: startDatetime)
    }
    
    var finishDateByLocale: String? {
        guard let finishDatetime = finishDatetime else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: finishDatetime)
    }
    
    var finishDateByLocaleLong: String? {
        guard let finishDatetime = finishDatetime else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .long
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: finishDatetime)
    }
}
