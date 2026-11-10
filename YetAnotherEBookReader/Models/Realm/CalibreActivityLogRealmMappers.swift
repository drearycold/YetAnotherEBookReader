//
//  CalibreActivityLogRealmMappers.swift
//  YetAnotherEBookReader
//

import Foundation
import RealmSwift

extension CalibreActivityLogEntry {
    convenience init(startValue: ActivityLogStartValue, ownerProcessID: String) {
        self.init()
        id = startValue.id.rawValue
        kind = startValue.kind.rawValue
        self.ownerProcessID = ownerProcessID
        downloadFormat = startValue.downloadFormat
        status = ActivityLogProgress.running.rawValue
        startDatetime = startValue.startDatetime
        libraryId = startValue.libraryId
        bookIds.append(objectsIn: startValue.bookIds.sorted())
        storeRequest(startValue.request)
    }

    private var activityState: ActivityLogState {
        if let progress = ActivityLogProgress(rawValue: status) {
            return .inProgress(progress)
        }
        if let completion = ActivityLogCompletion(rawValue: status) {
            return .finished(completion)
        }
        return .legacy
    }

    func apply(_ update: ActivityLogUpdate) {
        // Terminal and legacy records are immutable through the typed API.
        guard case .inProgress = activityState else { return }
        switch update {
        case let .progress(progress, revision, date):
            guard revision > progressRevision else { return }
            progressRevision = revision
            status = progress.rawValue
            var changes = progressChanges
            changes.append(.init(progress: progress, revision: revision, date: date))
            progressChangesData = try? JSONEncoder().encode(changes)
        case let .finish(completion, date, result):
            status = completion.rawValue
            finishDatetime = date
            httpStatusCode = result.httpStatusCode
            errorCategory = result.errorCategory?.rawValue
            resultDetail = result.detail
            if !result.requests.isEmpty {
                requestDiagnosticsData = try? JSONEncoder().encode(result.requests)
            }
        }
    }

    private var progressChanges: [ActivityLogProgressChange] {
        progressChangesData.flatMap {
            try? JSONDecoder().decode([ActivityLogProgressChange].self, from: $0)
        } ?? []
    }

    func toSummary(libraryName: String?, bookTitle: String?) -> ActivityLogSummary {
        let detail = activityState == .legacy ? errMsg : resultDetail
        let preview: String?
        if let detail, !detail.isEmpty {
            let prefix = detail.prefix(160)
            preview = String(prefix) + (prefix.endIndex == detail.endIndex ? "" : "…")
        } else {
            preview = httpStatusCode.map { "HTTP \($0)" }
        }
        return ActivityLogSummary(
            id: ActivityID(rawValue: id),
            kind: kind.flatMap(ActivityLogKind.init(rawValue:)),
            state: activityState,
            startDatetime: startDatetime,
            finishDatetime: finishDatetime,
            libraryName: libraryName,
            bookTitle: bookTitle,
            legacyType: type,
            downloadFormat: downloadFormat,
            resultPreview: preview
        )
    }

    func toSnapshot(libraryName: String?, bookTitle: String?) -> ActivityLogSnapshot {
        let headers = stride(from: 0, to: requestHeaders.count - 1, by: 2).map { index in
            ActivityLogHeader(key: requestHeaders[index], value: requestHeaders[index + 1])
        }
        let diagnostics = requestDiagnosticsData.flatMap {
            try? JSONDecoder().decode([ActivityLogRequestDiagnostic].self, from: $0)
        } ?? []
        return ActivityLogSnapshot(
            id: ActivityID(rawValue: id),
            kind: kind.flatMap(ActivityLogKind.init(rawValue:)),
            state: activityState,
            startDatetime: startDatetime,
            finishDatetime: finishDatetime,
            result: ActivityLogResult(
                httpStatusCode: httpStatusCode,
                errorCategory: errorCategory.flatMap(ActivityLogErrorCategory.init(rawValue:)),
                detail: resultDetail,
                requests: diagnostics
            ),
            request: ActivityLogRequestSnapshot(
                endpointURL: endpoingURL,
                httpMethod: httpMethod,
                httpBody: httpBody,
                headers: headers
            ),
            libraryId: libraryId,
            bookIds: Set(bookIds),
            libraryName: libraryName,
            bookTitle: bookTitle,
            legacyType: type,
            legacyResult: errMsg,
            downloadFormat: downloadFormat,
            progressChanges: progressChanges
        )
    }

    private func storeRequest(_ request: ActivityLogRequestSnapshot) {
        endpoingURL = request.endpointURL
        httpMethod = request.httpMethod
        httpBody = request.httpBody
        requestHeaders.append(objectsIn: request.headers.flatMap { [$0.key, $0.value] })
    }
}
