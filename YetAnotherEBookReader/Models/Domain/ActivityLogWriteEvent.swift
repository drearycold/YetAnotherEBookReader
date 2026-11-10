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

enum ActivityLogKind: String, CaseIterable, Sendable {
    case bookMetadata, batchMetadata, bookManifest, updateMetadata
    case librarySummary, search, categories, probe
    case readingPosition, annotations, helper, download
}

enum ActivityLogProgress: String, Codable, Sendable {
    case running, paused
}

enum ActivityLogCompletion: String, Sendable {
    case succeeded, failed, cancelled, interrupted
}

enum ActivityLogState: Equatable, Sendable {
    case inProgress(ActivityLogProgress)
    case finished(ActivityLogCompletion)
    case legacy

    func elapsed(from start: Date, to finish: Date?) -> TimeInterval? {
        guard case .finished(let completion) = self, completion != .interrupted else { return nil }
        return finish.map { max(0, $0.timeIntervalSince(start)) }
    }
}

enum ActivityLogErrorCategory: String, Sendable {
    case invalidRequest, transport, http, authentication, decoding, serverRejected, file, unknown
}

struct ActivityLogResult: Equatable, Sendable {
    var httpStatusCode: Int?
    var errorCategory: ActivityLogErrorCategory?
    var detail: String?
    var requests: [ActivityLogRequestDiagnostic] = []
}

struct ActivityLogRequestDiagnostic: Codable, Equatable, Sendable {
    let request: ActivityLogRequestSnapshot
    let responseURL: String?
    let httpStatusCode: Int?
    let duration: TimeInterval
}

struct ActivityLogHeader: Codable, Equatable, Sendable {
    let key: String
    let value: String
}

struct ActivityLogRequestSnapshot: Codable, Equatable, Sendable {
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
            endpointURL: Self.redactedURL(request.url),
            httpMethod: request.httpMethod,
            httpBody: Self.bodyPreview(request.httpBody),
            headers: (request.allHTTPHeaderFields ?? [:]).sorted { $0.key < $1.key }.map {
                let value = Self.safeHeaders.contains($0.key.lowercased()) ? String($0.value.prefix(256)) : "[redacted]"
                return ActivityLogHeader(key: $0.key, value: value)
            }
        )
    }

    private static let safeHeaders: Set<String> = ["accept", "accept-encoding", "content-type", "content-length", "range"]
    private static let safeQueryItems: Set<String> = [
        "ids", "library_id", "sort", "sort_order", "num", "offset", "category_urls", "action"
    ]
    private static let bodyLimit = 4096

    static func redactedURL(_ url: URL?) -> String? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        components.user = nil
        components.password = nil
        components.fragment = nil
        if let query = components.queryItems {
            components.queryItems = query.map { item in
                guard item.value != nil, !safeQueryItems.contains(item.name.lowercased()) else { return item }
                return URLQueryItem(name: item.name, value: "[redacted]")
            }
        }
        return components.string
    }

    private static func bodyPreview(_ body: Data?) -> Data? {
        guard let body, !body.isEmpty else { return nil }
        // Request bodies may contain arbitrary annotations, reading data or plugin credentials.
        // Keep only bounded structural diagnostics. Never copy raw body text into the log.
        guard body.count <= bodyLimit, let json = try? JSONSerialization.jsonObject(with: body),
              let preview = try? JSONSerialization.data(withJSONObject: redactedJSON(json), options: [.sortedKeys]),
              preview.count <= bodyLimit else {
            return Data("Body omitted (\(body.count) bytes)".utf8)
        }
        return preview
    }

    private static func redactedJSON(_ value: Any) -> Any {
        if let fields = value as? [String: Any] {
            return fields.mapValues(redactedJSON)
        }
        if let items = value as? [Any] {
            return items.map(redactedJSON)
        }
        return value is NSNull ? NSNull() : "[redacted]"
    }
}

enum ActivityLogRetention {
    static func cutoff(at date: Date = Date()) -> Date {
        date.addingTimeInterval(-7 * 24 * 60 * 60)
    }
}

struct ActivityLogProgressChange: Codable, Equatable, Sendable {
    let progress: ActivityLogProgress
    let revision: Int
    let date: Date
}

struct ActivityLogStartValue: Equatable, Sendable {
    let id: ActivityID
    let kind: ActivityLogKind
    let request: ActivityLogRequestSnapshot
    let startDatetime: Date
    let libraryId: String?
    let bookIds: Set<Int32>
    var downloadFormat: String?
}

enum ActivityLogUpdate: Equatable, Sendable {
    // A start has revision 0. Callers order progress updates with increasing revisions.
    case progress(ActivityLogProgress, revision: Int, at: Date = Date())
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
    var downloadFormat: String?
    var progressChanges: [ActivityLogProgressChange] = []
}

struct ActivityLogFilter: Equatable, Sendable {
    var kind: ActivityLogKind?
    var failuresOnly = false

    var isActive: Bool { kind != nil || failuresOnly }
}

struct ActivityLogQuery: Equatable, Sendable {
    let libraryId: String?
    let bookId: Int32?
    let since: Date
    var filter = ActivityLogFilter()
}

struct ActivityLogSummary: Identifiable, Equatable, Sendable {
    let id: ActivityID
    let kind: ActivityLogKind?
    let state: ActivityLogState
    let startDatetime: Date
    let finishDatetime: Date?
    let libraryName: String?
    let bookTitle: String?
    let legacyType: String?
    let downloadFormat: String?
    let resultPreview: String?

    var duration: TimeInterval? {
        state.elapsed(from: startDatetime, to: finishDatetime)
    }
}

struct ActivityLogPage: Equatable, Sendable {
    var entries: [ActivityLogSummary] = []
    var hasMore = false
}

enum ActivityLogWriteEvent: Equatable, Sendable {
    case start(ActivityLogStartValue)
    case update(id: ActivityID, ActivityLogUpdate)
    case remove(ActivityID)
    case prune(before: Date)
    case recoverAndPrune(at: Date)
}
