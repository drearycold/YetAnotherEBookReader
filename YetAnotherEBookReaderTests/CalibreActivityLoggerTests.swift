//
//  CalibreActivityLoggerTests.swift
//  YetAnotherEBookReaderTests
//

import XCTest
@testable import YetAnotherEBookReader

final class CalibreActivityLoggerTests: XCTestCase {
    func testLoggerBatchesStartAndFinishEventsAsValues() async throws {
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

        guard case .start(let startValue) = repository.writeActivityLogEventsParam[0],
              case .finish(let finishValue) = repository.writeActivityLogEventsParam[1]
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
        XCTAssertEqual(finishValue.startDatetime, startDate)
        XCTAssertEqual(finishValue.finishDatetime, finishDate)
        XCTAssertEqual(finishValue.errMsg, "Success")
    }

    func testLoggerDelegatesDeleteAndClean() async throws {
        let repository = MockActivityLogRepository()
        let logger = CalibreActivityLogger(repository: repository)
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)

        await logger.removeCalibreActivity(id: "activity-id")
        await logger.cleanCalibreActivities(startDatetime: cutoff)

        XCTAssertTrue(repository.removeCalibreActivityCalled)
        XCTAssertEqual(repository.removeCalibreActivityIdParam, "activity-id")
        XCTAssertTrue(repository.cleanCalibreActivitiesCalled)
        XCTAssertEqual(repository.cleanCalibreActivitiesStartDatetimeParam, cutoff)
    }
}
