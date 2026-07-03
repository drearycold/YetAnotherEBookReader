//
//  ActivityLogWriteEvent.swift
//  YetAnotherEBookReader
//
//  Pure activity-log write values. Persistence-specific mapping belongs in
//  the persistence boundary.
//

import Foundation

struct ActivityLogHeader: Equatable, Sendable {
    let key: String
    let value: String
}

struct ActivityLogRequestSnapshot: Equatable, Sendable {
    let endpointURL: String?
    let httpMethod: String?
    let httpBody: Data?
    let headers: [ActivityLogHeader]

    init(request: URLRequest) {
        self.endpointURL = request.url?.absoluteString
        self.httpMethod = request.httpMethod
        self.httpBody = request.httpBody
        self.headers = request.allHTTPHeaderFields?.map {
            ActivityLogHeader(key: $0.key, value: $0.value)
        } ?? []
    }
}

struct ActivityLogStartValue: Equatable, Sendable {
    let type: String
    let request: ActivityLogRequestSnapshot
    let startDatetime: Date
    let bookId: Int32?
    let libraryId: String?
}

struct ActivityLogFinishValue: Equatable, Sendable {
    let type: String
    let request: ActivityLogRequestSnapshot
    let startDatetime: Date
    let finishDatetime: Date
    let errMsg: String
}

enum ActivityLogWriteEvent: Equatable, Sendable {
    case start(ActivityLogStartValue)
    case finish(ActivityLogFinishValue)
}
