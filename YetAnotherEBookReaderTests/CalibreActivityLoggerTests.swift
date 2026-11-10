//
//  CalibreActivityLoggerTests.swift
//  YetAnotherEBookReaderTests
//

import XCTest
@testable import YetAnotherEBookReader

final class CalibreActivityLoggerTests: XCTestCase {
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

    func testRequestSnapshotRedactsCredentialsAndBoundsPayload() throws {
        var request = URLRequest(url: try XCTUnwrap(URL(string:
            "https://user:password@calibre.local/ajax/books?ids=7&api_key=secret&q=private#fragment")))
        request.setValue("Bearer credential", forHTTPHeaderField: "Authorization")
        request.setValue("session=credential", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"nested":{"token":"secret"},"notes":["private",123]}"#.utf8)

        let snapshot = ActivityLogRequestSnapshot(request: request)
        let endpoint = try XCTUnwrap(snapshot.endpointURL)
        XCTAssertTrue(endpoint.contains("ids=7"))
        for sensitive in ["user:", "password", "secret", "private", "#fragment"] {
            XCTAssertFalse(endpoint.contains(sensitive))
        }
        XCTAssertEqual(snapshot.headers.map(\.value), ["[redacted]", "application/json", "[redacted]"])
        let body = String(decoding: try XCTUnwrap(snapshot.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("nested"))
        XCTAssertFalse(body.contains("secret"))
        XCTAssertFalse(body.contains("private"))
        XCTAssertFalse(body.contains("123"))

        request.httpBody = Data(repeating: 65, count: 50_000)
        XCTAssertEqual(ActivityLogRequestSnapshot(request: request).httpBody, Data("Body omitted (50000 bytes)".utf8))
    }

    func testLoggerDelegatesDeleteAndClean() async throws {
        let repository = MockActivityLogRepository()
        let logger = CalibreActivityLogger(repository: repository)
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)

        let id = ActivityID()
        await logger.removeCalibreActivity(id: id)
        await logger.cleanCalibreActivities(startDatetime: cutoff)

        XCTAssertEqual(repository.writeActivityLogBatches, [[.remove(id)], [.prune(before: cutoff)]])
    }

    func testScheduledWriteAndOverlappingFlushesKeepStartAheadOfCompletion() async {
        let repository = MockActivityLogRepository()
        let firstWrite = expectation(description: "Scheduled write entered the repository")
        var release: AsyncStream<Void>.Continuation?
        let gate = AsyncStream<Void> { release = $0 }
        repository.beforeWrite = {
            if repository.writeActivityLogBatches.count == 1 {
                firstWrite.fulfill()
                for await _ in gate {}
            }
        }
        defer {
            release?.finish()
            repository.beforeWrite = nil
        }
        let logger = CalibreActivityLogger(repository: repository, flushDelayNanoseconds: 0)
        let activity = testActivity()
        await logger.start(activity)
        await fulfillment(of: [firstWrite], timeout: 5)

        let finish = ActivityLogUpdate.finish(.succeeded, at: Date())
        await logger.update(id: activity.id, finish)
        async let first = logger.flush()
        async let second = logger.flush()
        release?.finish()
        let results = await [first, second]

        XCTAssertEqual(results, [true, true])
        XCTAssertEqual(repository.writeActivityLogBatches, [[.start(activity)], [.update(id: activity.id, finish)]])
    }

    func testFlushReportsFailureOnlyForBarriersCoveringTheFailedBatch() async {
        let repository = MockActivityLogRepository()
        let firstWrite = expectation(description: "Start is in flight")
        var release: AsyncStream<Void>.Continuation?
        let gate = AsyncStream<Void> { release = $0 }
        repository.beforeWrite = {
            if repository.writeActivityLogBatches.count == 1 {
                firstWrite.fulfill()
                for await _ in gate {}
            } else {
                repository.writeFailuresRemaining = 1
            }
        }
        defer {
            release?.finish()
            repository.beforeWrite = nil
        }
        let logger = CalibreActivityLogger(repository: repository,
            flushDelayNanoseconds: 60_000_000_000, retryDelaysNanoseconds: [])
        let activity = testActivity()
        await logger.start(activity)
        let onlyStart = Task { await logger.flush() }
        await fulfillment(of: [firstWrite], timeout: 5)
        let finish = ActivityLogUpdate.finish(.succeeded, at: Date())
        await logger.update(id: activity.id, finish)
        let both = Task { await logger.flush() }
        release?.finish()
        let startResult = await onlyStart.value
        let bothResult = await both.value

        XCTAssertTrue(startResult)
        XCTAssertFalse(bothResult)
        XCTAssertEqual(repository.writeActivityLogBatches, [[.start(activity)], [.update(id: activity.id, finish)]])
    }

    func testTransientFailureRetriesTheSameBatchBeforeLaterEvents() async {
        let repository = MockActivityLogRepository()
        repository.writeFailuresRemaining = 1
        let logger = CalibreActivityLogger(repository: repository,
            flushDelayNanoseconds: 60_000_000_000, retryDelaysNanoseconds: [0, 0])
        let activity = testActivity()
        await logger.start(activity)
        let persistedStart = await logger.flush()
        XCTAssertTrue(persistedStart)

        let finish = ActivityLogUpdate.finish(.cancelled, at: Date())
        await logger.update(id: activity.id, finish)
        let persistedFinish = await logger.flush()
        XCTAssertTrue(persistedFinish)
        XCTAssertEqual(repository.writeActivityLogBatches,
                       [[.start(activity)], [.start(activity)], [.update(id: activity.id, finish)]])
    }

    func testExhaustedBatchReportsFailureAndLaterBatchCanPersist() async {
        let repository = MockActivityLogRepository()
        repository.writeFailuresRemaining = 3
        let logger = CalibreActivityLogger(repository: repository,
            flushDelayNanoseconds: 60_000_000_000, retryDelaysNanoseconds: [0, 0])
        let dropped = testActivity()
        await logger.start(dropped)
        let failed = await logger.flush()
        XCTAssertFalse(failed)

        let next = testActivity()
        await logger.start(next)
        let recovered = await logger.flush()
        XCTAssertTrue(recovered)
        XCTAssertEqual(repository.writeActivityLogBatches,
                       [[.start(dropped)], [.start(dropped)], [.start(dropped)], [.start(next)]])
    }

    private func testActivity() -> ActivityLogStartValue {
        ActivityLogStartValue(id: ActivityID(), kind: .download,
            request: .init(endpointURL: "https://calibre.local/get/EPUB/7/library",
                           httpMethod: "GET", httpBody: nil, headers: []),
            startDatetime: Date(), libraryId: "library", bookIds: [7], downloadFormat: "EPUB")
    }
}
