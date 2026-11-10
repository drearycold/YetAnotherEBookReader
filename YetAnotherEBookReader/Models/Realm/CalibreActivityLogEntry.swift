//
//  CalibreActivityLogEntry.swift
//  YetAnotherEBookReader
//

import Foundation
import RealmSwift

class CalibreActivityLogEntry: Object, Identifiable {
    @Persisted(primaryKey: true) var id = UUID().uuidString
    @Persisted var kind: String?
    @Persisted var status = "legacy"
    @Persisted var progressRevision = 0
    @Persisted var ownerProcessID: String?
    @Persisted var downloadFormat: String?
    @Persisted var progressChangesData: Data?

    @Persisted var startDatetime = Date.distantPast
    @Persisted var finishDatetime: Date?
    @Persisted var libraryId: String?
    @Persisted var bookIds: List<Int32>

    @Persisted var endpoingURL: String?
    @Persisted var httpMethod: String?
    @Persisted var httpBody: Data?
    @Persisted var requestHeaders: List<String> // Alternating keys and values.

    @Persisted var httpStatusCode: Int?
    @Persisted var errorCategory: String?
    @Persisted var resultDetail: String?
    @Persisted var requestDiagnosticsData: Data?

    // Historical type and result text for reading existing logs.
    @Persisted var type: String?
    @Persisted var errMsg: String?
}
