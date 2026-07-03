//
//  CalibreActivityLogRealmMappers.swift
//  YetAnotherEBookReader
//
//  Realm boundary for activity-log write values.
//

import Foundation
import RealmSwift

extension CalibreActivityLogEntry {
    convenience init(startValue: ActivityLogStartValue) {
        self.init()
        apply(startValue)
    }

    func apply(_ value: ActivityLogStartValue) {
        type = value.type
        startDatetime = value.startDatetime
        bookId = value.bookId ?? 0
        libraryId = value.libraryId

        endpoingURL = value.request.endpointURL
        httpMethod = value.request.httpMethod
        httpBody = value.request.httpBody
        requestHeaders.removeAll()
        value.request.headers.forEach {
            requestHeaders.append($0.key)
            requestHeaders.append($0.value)
        }
    }

    func apply(_ value: ActivityLogFinishValue) {
        finishDatetime = value.finishDatetime
        errMsg = value.errMsg
    }

    static func predicate(matching value: ActivityLogFinishValue) -> NSPredicate {
        NSPredicate(
            format: "type = %@ AND startDatetime = %@ AND endpoingURL = %@",
            value.type,
            value.startDatetime as NSDate,
            value.request.endpointURL ?? ""
        )
    }
}
