//
//  CalibreActivityLoggerTests.swift
//  YetAnotherEBookReaderTests
//

import XCTest
@testable import YetAnotherEBookReader

final class CalibreActivityLoggerTests: XCTestCase {
    func testLegacyAdapterBatchesRequestSnapshotsAndOriginalResult() async throws {
        let repository = MockActivityLogRepository()
        let logger = CalibreActivityLogger(
            repository: repository,
            flushDelayNanoseconds: 60_000_000_000
        )
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let finishDate = Date(timeIntervalSince1970: 1_700_000_010)
        var request = URLRequest(url: URL(string: "http://calibre.local/ajax/books")!)
        request.httpMethod = "POST"
        request.httpBody = Data("body".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        await logger.logStartCalibreActivity(
            type: "Sync",
            request: request,
            startDatetime: startDate,
            bookId: 42,
            libraryId: "library"
        )
        await logger.logFinishCalibreActivity(
            type: "Sync",
            request: request,
            startDatetime: startDate,
            finishDatetime: finishDate,
            errMsg: "Success"
        )
        await logger.flushPendingActivitiesForTesting()

        XCTAssertTrue(repository.writeActivityLogEventsCalled)
        XCTAssertEqual(repository.writeActivityLogEventsParam.count, 2)

        guard case .legacyStart(let startValue) = repository.writeActivityLogEventsParam[0],
              case .legacyFinish(let finishValue) = repository.writeActivityLogEventsParam[1]
        else {
            XCTFail("Expected start and finish events")
            return
        }

        XCTAssertEqual(startValue.type, "Sync")
        XCTAssertEqual(startValue.startDatetime, startDate)
        XCTAssertEqual(startValue.bookId, 42)
        XCTAssertEqual(startValue.libraryId, "library")
        XCTAssertEqual(startValue.request.endpointURL, "http://calibre.local/ajax/books")
        XCTAssertEqual(startValue.request.httpMethod, "POST")
        XCTAssertEqual(startValue.request.httpBody, Data("body".utf8))
        XCTAssertTrue(startValue.request.headers.contains(ActivityLogHeader(key: "Content-Type", value: "application/json")))

        XCTAssertEqual(finishValue.type, "Sync")
        XCTAssertEqual(finishValue.endpointURL, startValue.request.endpointURL)
        XCTAssertEqual(finishValue.startDatetime, startDate)
        XCTAssertEqual(finishValue.finishDatetime, finishDate)
        XCTAssertEqual(finishValue.errMsg, "Success")
    }

    func testTypedStartProgressAndFinishBatchUsesOneID() async {
        let repository = MockActivityLogRepository()
        let logger = CalibreActivityLogger(repository: repository, flushDelayNanoseconds: 60_000_000_000)
        let id = ActivityID()
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let request = URLRequest(url: URL(string: "http://calibre.local/ajax/books")!)
        let start = ActivityLogStartValue(
            id: id, kind: .batchMetadata, request: ActivityLogRequestSnapshot(request: request),
            startDatetime: startDate, libraryId: "library", bookIds: [1, 2]
        )
        let pause = ActivityLogUpdate.progress(.paused, revision: 1)
        let finish = ActivityLogUpdate.finish(
            .failed,
            at: startDate.addingTimeInterval(5),
            result: ActivityLogResult(httpStatusCode: 503, errorCategory: .http, detail: "Unavailable")
        )

        await logger.start(start)
        await logger.update(id: id, pause)
        await logger.update(id: id, finish)
        await logger.flushPendingActivitiesForTesting()

        XCTAssertEqual(repository.writeActivityLogEventsParam, [.start(start), .update(id: id, pause), .update(id: id, finish)])
    }

    func testLoggerDelegatesDeleteAndClean() async throws {
        let repository = MockActivityLogRepository()
        let logger = CalibreActivityLogger(repository: repository)
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)

        let id = ActivityID()
        await logger.removeCalibreActivity(id: id)
        await logger.cleanCalibreActivities(startDatetime: cutoff)

        XCTAssertTrue(repository.removeCalibreActivityCalled)
        XCTAssertEqual(repository.removeCalibreActivityIdParam, id)
        XCTAssertTrue(repository.cleanCalibreActivitiesCalled)
        XCTAssertEqual(repository.cleanCalibreActivitiesStartDatetimeParam, cutoff)
    }
}
