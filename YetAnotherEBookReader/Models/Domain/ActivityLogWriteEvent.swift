//
//  ActivityLogWriteEvent.swift
//  YetAnotherEBookReader
//

import Foundation

struct ActivityID: Hashable, Sendable {
    // Keep the existing Realm string primary key and preserve historical IDs verbatim.
    let rawValue: String

    init(rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }
}

enum ActivityLogKind: String, Sendable {
    case bookMetadata, batchMetadata, bookManifest, updateMetadata
    case librarySummary, search, categories, probe
    case readingPosition, annotations, helper, download
}

enum ActivityLogProgress: String, Sendable {
    case running, paused
}

enum ActivityLogCompletion: String, Sendable {
    case succeeded, failed, cancelled, interrupted
}

enum ActivityLogState: Equatable, Sendable {
    case inProgress(ActivityLogProgress)
    case finished(ActivityLogCompletion)
    case legacy
}

enum ActivityLogErrorCategory: String, Sendable {
    case invalidRequest, transport, http, authentication, decoding, serverRejected, file, unknown
}

struct ActivityLogResult: Equatable, Sendable {
    var httpStatusCode: Int?
    var errorCategory: ActivityLogErrorCategory?
    var detail: String?
}

struct ActivityLogHeader: Equatable, Sendable {
    let key: String
    let value: String
}

struct ActivityLogRequestSnapshot: Equatable, Sendable {
    let endpointURL: String?
    let httpMethod: String?
    let httpBody: Data?
    let headers: [ActivityLogHeader]

    init(endpointURL: String?, httpMethod: String?, httpBody: Data?, headers: [ActivityLogHeader]) {
        self.endpointURL = endpointURL
        self.httpMethod = httpMethod
        self.httpBody = httpBody
        self.headers = headers
    }

    init(request: URLRequest) {
        self.init(
            endpointURL: request.url?.absoluteString,
            httpMethod: request.httpMethod,
            httpBody: request.httpBody,
            headers: (request.allHTTPHeaderFields ?? [:]).sorted { $0.key < $1.key }.map {
                ActivityLogHeader(key: $0.key, value: $0.value)
            }
        )
    }
}

struct ActivityLogStartValue: Equatable, Sendable {
    let id: ActivityID
    let kind: ActivityLogKind
    let request: ActivityLogRequestSnapshot
    let startDatetime: Date
    let libraryId: String?
    let bookIds: Set<Int32>
}

enum ActivityLogUpdate: Equatable, Sendable {
    // A start has revision 0. Callers order progress updates with increasing revisions.
    case progress(ActivityLogProgress, revision: Int)
    case finish(ActivityLogCompletion, at: Date, result: ActivityLogResult = .init())
}

struct ActivityLogSnapshot: Identifiable, Equatable, Sendable {
    let id: ActivityID
    let kind: ActivityLogKind?
    let state: ActivityLogState
    let startDatetime: Date
    let finishDatetime: Date?
    let result: ActivityLogResult
    let request: ActivityLogRequestSnapshot
    let libraryId: String?
    let bookIds: Set<Int32>
    let libraryName: String?
    let bookTitle: String?
    let legacyType: String?
    let legacyResult: String?
}

enum ActivityLogWriteEvent: Equatable, Sendable {
    case start(ActivityLogStartValue)
    case update(id: ActivityID, ActivityLogUpdate)

    // Temporary write adapter. Remove after AL2 service and AL3 download adoption in AL4.
    case legacyStart(ActivityLogLegacyStartValue)
    case legacyFinish(ActivityLogLegacyFinishValue)
}

struct ActivityLogLegacyStartValue: Equatable, Sendable {
    let type: String
    let request: ActivityLogRequestSnapshot
    let startDatetime: Date
    let bookId: Int32?
    let libraryId: String?
}

struct ActivityLogLegacyFinishValue: Equatable, Sendable {
    let type: String
    let endpointURL: String?
    let startDatetime: Date
    let finishDatetime: Date
    let errMsg: String
}
