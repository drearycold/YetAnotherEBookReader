//
//  ActivityLogRepositoryTests.swift
//  YetAnotherEBookReaderTests
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
final class ActivityLogRepositoryTests: XCTestCase {
    private var databaseService: DatabaseService!
    private var bookRepository: MockBookRepository!
    private var librarySnapshotProvider: MockCalibreLibrarySnapshotProvider!
    private var repository: RealmActivityLogRepository!

    private let startDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let finishDate = Date(timeIntervalSince1970: 1_700_000_005)
    private let request = ActivityLogRequestSnapshot(
        endpointURL: "http://calibre.local/ajax/books",
        httpMethod: "POST",
        httpBody: Data("payload".utf8),
        headers: [ActivityLogHeader(key: "Content-Type", value: "application/json")]
    )

    override func setUpWithError() throws {
        try super.setUpWithError()
        databaseService = DatabaseService()
        bookRepository = MockBookRepository()
        librarySnapshotProvider = MockCalibreLibrarySnapshotProvider()
        databaseService.setup(conf: MockDatabaseService.inMemoryConfiguration())
        repository = RealmActivityLogRepository(
            databaseService: databaseService,
            bookRepository: bookRepository,
            librarySnapshotProvider: librarySnapshotProvider
        )
    }

    override func tearDownWithError() throws {
        repository = nil
        librarySnapshotProvider = nil
        bookRepository = nil
        databaseService = nil
        try super.tearDownWithError()
    }

    func testIdenticalRequestsKeepIndependentIDsAndFirstCompletion() async throws {
        let first = start()
        let second = start()
        try await repository.writeActivityLogEvents([.start(first), .start(second)])
        let running = try entry(first.id)
        XCTAssertEqual(running.state, .inProgress(.running))
        XCTAssertNil(running.finishDatetime)
        XCTAssertEqual(running.result, ActivityLogResult())

        let success = ActivityLogResult(httpStatusCode: 200)
        let failure = ActivityLogResult(httpStatusCode: 403, errorCategory: .authentication, detail: "Access denied")
        try await repository.writeActivityLogEvents([
            .update(id: second.id, .finish(.failed, at: finishDate, result: failure)),
            .update(id: first.id, .finish(.succeeded, at: finishDate, result: success))
        ])
        try await repository.writeActivityLogEvents([
            .start(start(id: first.id, kind: .probe, libraryId: "other")),
            .update(id: first.id, .finish(.succeeded, at: finishDate, result: success)),
            .update(id: first.id, .finish(.failed, at: finishDate.addingTimeInterval(1), result: failure)),
            .update(id: first.id, .progress(.paused, revision: 3))
        ])

        XCTAssertEqual(entries().count, 2)
        let succeeded = try entry(first.id)
        XCTAssertEqual(succeeded.kind, first.kind)
        XCTAssertEqual(succeeded.libraryId, first.libraryId)
        XCTAssertEqual(succeeded.state, .finished(.succeeded))
        XCTAssertEqual(succeeded.startDatetime, startDate)
        XCTAssertEqual(succeeded.finishDatetime, finishDate)
        XCTAssertEqual(succeeded.result, success)
        XCTAssertEqual(succeeded.request, request)

        let failed = try entry(second.id)
        XCTAssertEqual(failed.state, .finished(.failed))
        XCTAssertEqual(failed.finishDatetime, finishDate)
        XCTAssertEqual(failed.result, failure)
    }

    func testProgressReplaysCannotUndoResumeAndOnlyCompletionSetsFinishDate() async throws {
        let activity = start(kind: .download)
        let pause = ActivityLogWriteEvent.update(id: activity.id, .progress(.paused, revision: 1))
        try await repository.writeActivityLogEvents([.start(activity), pause, pause])
        let paused = try entry(activity.id)
        XCTAssertEqual(paused.state, .inProgress(.paused))
        XCTAssertNil(paused.finishDatetime)
        XCTAssertEqual(paused.result, ActivityLogResult())

        try await repository.writeActivityLogEvents([
            .update(id: activity.id, .progress(.running, revision: 2)),
            pause,
            .update(id: activity.id, .progress(.paused, revision: 2))
        ])
        let resumed = try entry(activity.id)
        XCTAssertEqual(resumed.state, .inProgress(.running))
        XCTAssertNil(resumed.finishDatetime)

        try await repository.writeActivityLogEvents([.update(id: activity.id, .finish(.cancelled, at: finishDate))])
        XCTAssertEqual(try entry(activity.id).state, .finished(.cancelled))
        XCTAssertEqual(try entry(activity.id).finishDatetime, finishDate)
    }

    func testUpdatesForUnknownIDsDoNotCreateOrPrepopulateEntries() async throws {
        let activity = start()
        try await repository.writeActivityLogEvents([
            .update(id: activity.id, .progress(.paused, revision: 1)),
            .update(id: activity.id, .finish(.interrupted, at: finishDate))
        ])
        XCTAssertTrue(entries().isEmpty)

        try await repository.writeActivityLogEvents([.start(activity)])
        XCTAssertEqual(try entry(activity.id).state, .inProgress(.running))
        XCTAssertNil(try entry(activity.id).finishDatetime)

        try await repository.writeActivityLogEvents([.update(id: activity.id, .finish(.interrupted, at: finishDate))])
        XCTAssertEqual(try entry(activity.id).state, .finished(.interrupted))
        XCTAssertEqual(try entry(activity.id).finishDatetime, finishDate)
    }

    func testScopesIncludeBatchMembersAndIsolateMatchingBookIDsAcrossLibraries() async throws {
        let batch = start(kind: .batchMetadata, libraryId: "A", bookIds: [7, 9])
        let library = start(kind: .librarySummary, libraryId: "A", bookIds: [])
        let other = start(libraryId: "B", bookIds: [7])
        let global = start(libraryId: nil, bookIds: [])
        try await repository.writeActivityLogEvents([.start(batch), .start(library), .start(other), .start(global)])

        XCTAssertEqual(Set(entries().map(\.id)), [batch.id, library.id, other.id, global.id])
        XCTAssertEqual(Set(entries(libraryId: "A").map(\.id)), [batch.id, library.id])
        XCTAssertEqual(entries(libraryId: "A", bookId: 7).map(\.id), [batch.id])
        XCTAssertEqual(entries(libraryId: "A", bookId: 9).first?.bookIds, [7, 9])
        XCTAssertTrue(entries(libraryId: "A", bookId: 0).isEmpty)
        XCTAssertEqual(entries(libraryId: "B", bookId: 7).map(\.id), [other.id])
        XCTAssertEqual(entries(since: startDate).count, 4)
        XCTAssertTrue(entries(since: startDate.addingTimeInterval(1)).isEmpty)
    }

    func testResolvesBookTitleForScopedBatchThroughBookRepository() async throws {
        let library = TestFixtures.makeLibrary()
        var book = TestFixtures.makeBook(id: 42, library: library)
        book.title = "Mapped Activity Book"
        librarySnapshotProvider.calibreLibraries = [library.id: library]
        bookRepository.getBookReturn = book

        let batch = start(kind: .batchMetadata, libraryId: library.id, bookIds: [book.id, 43])
        try await repository.writeActivityLogEvents([.start(batch)])

        XCTAssertNil(entries(libraryId: library.id).first?.bookTitle)
        XCTAssertFalse(bookRepository.getBookCalled)
        let snapshot = entries(libraryId: library.id, bookId: book.id).first
        XCTAssertEqual(snapshot?.libraryName, library.name)
        XCTAssertEqual(snapshot?.bookTitle, book.title)
        XCTAssertEqual(bookRepository.getBookLibraryParam, library)
        XCTAssertEqual(bookRepository.getBookBookIdParam, book.id)
    }

    func testObservationPublishesBatchUpdatesForTheSelectedBook() async throws {
        let batch = start(kind: .batchMetadata, libraryId: "A", bookIds: [7, 9])
        let other = start(libraryId: "B", bookIds: [9])
        try await repository.writeActivityLogEvents([.start(batch), .start(other)])

        let initial = expectation(description: "Running snapshot")
        let finished = expectation(description: "Completed snapshot")
        let stream = repository.observePage(query: .init(libraryId: "A", bookId: 9, since: .distantPast), limit: 30)
        let observation = Task {
            var iterator = stream.makeAsyncIterator()
            let running = await iterator.next()
            XCTAssertEqual(running?.entries.map(\.id), [batch.id])
            XCTAssertEqual(running?.entries.first?.state, .inProgress(.running))
            initial.fulfill()

            let updated = await iterator.next()
            XCTAssertEqual(updated?.entries.map(\.id), [batch.id])
            XCTAssertEqual(updated?.entries.first?.state, .finished(.succeeded))
            finished.fulfill()
        }
        defer { observation.cancel() }

        await fulfillment(of: [initial], timeout: 5)
        try await repository.writeActivityLogEvents([.update(id: batch.id, .finish(.succeeded, at: finishDate))])
        await fulfillment(of: [finished], timeout: 5)
    }

    func testLegacyDetailPreservesOriginalRequestAndDoesNotInferFailure() async throws {
        let legacyID = try insertHistoricalActivity(result: "Failed to connect", libraryId: "A", bookId: 7)
        try await repository.writeActivityLogEvents([.update(id: legacyID, .finish(.failed, at: finishDate))])
        let summary = repository.fetchPage(query: .init(libraryId: "A", bookId: 7, since: startDate), limit: 10)
        XCTAssertEqual(summary.entries.first?.state, .legacy)
        XCTAssertNil(summary.entries.first?.duration)
        let legacy = try entry(legacyID)
        XCTAssertEqual(legacy.state, .legacy)
        XCTAssertEqual(legacy.legacyType, "Old operation")
        XCTAssertEqual(legacy.legacyResult, "Failed to connect")
        XCTAssertEqual(legacy.finishDatetime, finishDate)
        XCTAssertEqual(legacy.request, request)
        let failures = repository.fetchPage(query: .init(libraryId: "A", bookId: 7, since: startDate,
                                                        filter: .init(failuresOnly: true)), limit: 10)
        XCTAssertTrue(failures.entries.isEmpty)
    }

    func testDeleteAndCleanUseRepositoryBoundary() async throws {
        let old = start(at: startDate.addingTimeInterval(-5))
        let new = start()
        try await repository.writeActivityLogEvents([.start(old), .start(new)])
        XCTAssertEqual(entries().map(\.id), [new.id, old.id])

        try await repository.writeActivityLogEvents([.remove(new.id)])
        XCTAssertEqual(entries().map(\.id), [old.id])

        try await repository.writeActivityLogEvents([.prune(before: startDate), .start(old)])
        XCTAssertTrue(entries().isEmpty)
    }

    func testRecoveryOnlyInterruptsPreviousProcessAndPrunesBeforeReplayedStarts() async throws {
        let previous = RealmActivityLogRepository(databaseService: databaseService,
            bookRepository: bookRepository, librarySnapshotProvider: nil, ownerProcessID: "previous")
        let running = start()
        let paused = start(kind: .download)
        let finished = start()
        let stale = start(at: startDate.addingTimeInterval(-8 * 24 * 60 * 60))
        _ = try insertHistoricalActivity(result: "Old", libraryId: "library", bookId: 8)
        try await previous.writeActivityLogEvents([
            .start(running), .start(paused), .start(finished), .start(stale),
            .update(id: paused.id, .progress(.paused, revision: 1, at: finishDate)),
            .update(id: finished.id, .finish(.succeeded, at: finishDate))
        ])
        let current = start()
        let recoveredAt = finishDate.addingTimeInterval(1)
        try await repository.writeActivityLogEvents([
            .start(current), .recoverAndPrune(at: recoveredAt), .start(stale),
            .update(id: paused.id, .progress(.running, revision: 2, at: recoveredAt))
        ])
        try await repository.writeActivityLogEvents([.recoverAndPrune(at: recoveredAt.addingTimeInterval(1))])

        XCTAssertEqual(try entry(running.id).state, .finished(.interrupted))
        XCTAssertEqual(try entry(paused.id).finishDatetime, recoveredAt)
        XCTAssertEqual(try entry(paused.id).state, .finished(.interrupted))
        XCTAssertEqual(try entry(paused.id).progressChanges, [.init(progress: .paused, revision: 1, date: finishDate)])
        XCTAssertEqual(try entry(finished.id).finishDatetime, finishDate)
        XCTAssertEqual(try entry(finished.id).state, .finished(.succeeded))
        XCTAssertEqual(try entry(current.id).state, .inProgress(.running))
        XCTAssertNil(try entry(current.id).finishDatetime)
        XCTAssertFalse(entries().contains { $0.id == stale.id })
        XCTAssertEqual(entries().filter { $0.state == .legacy }.count, 1)
    }

    func testWriteReportsMissingDatabaseConfiguration() async {
        let unavailable = RealmActivityLogRepository(databaseService: DatabaseService(),
            bookRepository: bookRepository, container: nil)
        do {
            try await unavailable.writeActivityLogEvents([.start(start())])
            XCTFail("A missing Realm configuration must be observable")
        } catch DatabaseBootstrapError.realmConfigurationMissing {
        } catch {
            XCTFail("Unexpected failure: \(error)")
        }
    }

    func testLargePagesBoundTitleLookupsAndHaveStableTies() async throws {
        let library = TestFixtures.makeLibrary()
        librarySnapshotProvider.calibreLibraries = [library.id: library]
        let starts = (0..<240).map { index in
            start(id: ActivityID(rawValue: String(format: "%04d", index)), libraryId: library.id)
        }
        try await repository.writeActivityLogEvents(starts.reversed().map(ActivityLogWriteEvent.start))
        let query = ActivityLogQuery(libraryId: library.id, bookId: 7, since: startDate)
        let initial = repository.fetchPage(query: query, limit: 30)
        XCTAssertEqual(initial.entries.map(\.id), Array(starts.prefix(30)).map(\.id))
        XCTAssertTrue(initial.hasMore)
        XCTAssertEqual(bookRepository.getBookInLibraryCount, 30)

        let newest = start(libraryId: library.id, at: startDate.addingTimeInterval(1))
        let detail = String(repeating: "A", count: 400)
        let diagnostic = ActivityLogRequestDiagnostic(request: request, responseURL: nil, httpStatusCode: 503, duration: 1)
        try await repository.writeActivityLogEvents([
            .start(newest), .remove(starts[0].id),
            .update(id: starts[1].id, .finish(.failed, at: finishDate, result: .init(detail: detail, requests: [diagnostic])))
        ])
        let expanded = repository.fetchPage(query: query, limit: 60)
        XCTAssertEqual(expanded.entries.map(\.id), [newest.id] + starts[1..<60].map(\.id))
        XCTAssertEqual(bookRepository.getBookInLibraryCount, 90)
        XCTAssertEqual(expanded.entries[1].resultPreview, String(detail.prefix(160)) + "…")
        XCTAssertEqual(expanded.entries[1].duration, finishDate.timeIntervalSince(startDate))
        let full = try entry(starts[1].id)
        XCTAssertEqual(full.result.detail, detail)
        XCTAssertEqual(full.result.requests, [diagnostic])
    }

    func testFiltersMatchOnlyTypedFailuresInTheRequestedScope() async throws {
        let failure = start(kind: .batchMetadata, libraryId: "A", bookIds: [7, 9])
        let interrupted = start(kind: .batchMetadata, libraryId: "A", bookIds: [7])
        let cancelled = start(kind: .batchMetadata, libraryId: "A", bookIds: [7])
        let otherKind = start(kind: .download, libraryId: "A", bookIds: [7])
        let otherLibrary = start(kind: .batchMetadata, libraryId: "B", bookIds: [7])
        try await repository.writeActivityLogEvents([
            .start(failure), .start(interrupted), .start(cancelled), .start(otherKind), .start(otherLibrary),
            .update(id: failure.id, .finish(.failed, at: finishDate)),
            .update(id: interrupted.id, .finish(.interrupted, at: finishDate)),
            .update(id: cancelled.id, .finish(.cancelled, at: finishDate)),
            .update(id: otherKind.id, .finish(.failed, at: finishDate)),
            .update(id: otherLibrary.id, .finish(.failed, at: finishDate))
        ])
        let filter = ActivityLogFilter(kind: .batchMetadata, failuresOnly: true)
        for bookId: Int32 in [7, 9] {
            let query = ActivityLogQuery(libraryId: "A", bookId: bookId, since: startDate, filter: filter)
            let page = repository.fetchPage(query: query, limit: 10)
            XCTAssertEqual(page.entries.map(\.id), [failure.id])
            XCTAssertFalse(page.hasMore)
        }
        let global = ActivityLogQuery(libraryId: nil, bookId: nil, since: startDate, filter: filter)
        XCTAssertEqual(Set(repository.fetchPage(query: global, limit: 10).entries.map(\.id)), [failure.id, otherLibrary.id])
        let library = repository.fetchPage(query: .init(libraryId: "A", bookId: nil, since: startDate), limit: 10)
        let recovered = try XCTUnwrap(library.entries.first { $0.id == interrupted.id })
        XCTAssertEqual(recovered.state, .finished(.interrupted))
        XCTAssertNil(recovered.duration, "Recovery time is not the elapsed duration of an interrupted operation")
        let unscopedBook = ActivityLogQuery(libraryId: nil, bookId: 7, since: startDate)
        XCTAssertTrue(repository.fetchPage(query: unscopedBook, limit: 10).entries.isEmpty)
    }

    func testObservedPrefixRebalancesAfterInsertStatusChangeAndRemoval() async throws {
        let first = start(id: ActivityID(rawValue: "a"))
        let second = start(id: ActivityID(rawValue: "b"))
        let third = start(id: ActivityID(rawValue: "c"))
        let newest = start(at: startDate.addingTimeInterval(1))
        try await repository.writeActivityLogEvents([.start(third), .start(second), .start(first)])
        let query = ActivityLogQuery(libraryId: "library", bookId: 7, since: startDate)
        let stream = repository.observePage(query: query, limit: 2)
        let initial = expectation(description: "First live page")
        let inserted = expectation(description: "Insert and update in one transaction")
        let deleted = expectation(description: "Deletion refills the page")
        let task = Task {
            var iterator = stream.makeAsyncIterator()
            let before = await iterator.next()
            XCTAssertEqual(before?.entries.map(\.id), [first.id, second.id])
            XCTAssertEqual(before?.hasMore, true)
            initial.fulfill()
            let after = await iterator.next()
            XCTAssertEqual(after?.entries.map(\.id), [newest.id, first.id])
            XCTAssertEqual(after?.entries.last?.state, .finished(.failed))
            inserted.fulfill()
            let remaining = await iterator.next()
            XCTAssertEqual(remaining?.entries.map(\.id), [newest.id, second.id])
            XCTAssertEqual(remaining?.hasMore, false)
            deleted.fulfill()
        }
        defer { task.cancel() }
        await fulfillment(of: [initial], timeout: 5)
        try await repository.writeActivityLogEvents([
            .start(newest), .update(id: first.id, .finish(.failed, at: finishDate))
        ])
        await fulfillment(of: [inserted], timeout: 5)
        try await repository.writeActivityLogEvents([.remove(first.id), .remove(third.id)])
        await fulfillment(of: [deleted], timeout: 5)
    }

    func testDetailObservationSurvivesListWindowAndEmitsNilOnDeletion() async throws {
        let target = start(kind: .download)
        let later = start(at: startDate.addingTimeInterval(1))
        try await repository.writeActivityLogEvents([.start(target), .start(later)])
        let query = ActivityLogQuery(libraryId: nil, bookId: nil, since: startDate)
        XCTAssertEqual(repository.fetchPage(query: query, limit: 1).entries.map(\.id), [later.id])

        let started = expectation(description: "Running")
        let paused = expectation(description: "Paused")
        let completed = expectation(description: "Completed")
        let removed = expectation(description: "Removed")
        let updates = repository.observeDetail(id: target.id, bookId: nil, since: startDate)
        let task = Task {
            var iterator = updates.makeAsyncIterator()
            let running = await iterator.next()
            XCTAssertEqual((running ?? nil)?.state, .inProgress(.running))
            started.fulfill()
            let pause = await iterator.next()
            XCTAssertEqual((pause ?? nil)?.state, .inProgress(.paused))
            paused.fulfill()
            let success = await iterator.next()
            XCTAssertEqual((success ?? nil)?.state, .finished(.succeeded))
            completed.fulfill()
            let deletion = await iterator.next()
            if case .none = deletion { XCTFail("Deletion must emit a nil detail before the stream ends") }
            XCTAssertNil(deletion ?? nil)
            removed.fulfill()
        }
        defer { task.cancel() }
        await fulfillment(of: [started], timeout: 5)
        try await repository.writeActivityLogEvents([.update(id: target.id, .progress(.paused, revision: 1))])
        await fulfillment(of: [paused], timeout: 5)
        try await repository.writeActivityLogEvents([.update(id: target.id, .finish(.succeeded, at: finishDate))])
        await fulfillment(of: [completed], timeout: 5)
        try await repository.writeActivityLogEvents([.remove(target.id)])
        await fulfillment(of: [removed], timeout: 5)
        XCTAssertNil(repository.fetchDetail(id: target.id, bookId: nil, since: startDate))
    }

    private func insertHistoricalActivity(result: String, libraryId: String, bookId: Int32) throws -> ActivityID {
        let realm = try XCTUnwrap(databaseService.realm)
        let entry = CalibreActivityLogEntry()
        entry.type = "Old operation"
        entry.startDatetime = startDate
        entry.finishDatetime = finishDate
        entry.libraryId = libraryId
        entry.bookIds.append(bookId)
        entry.errMsg = result
        entry.endpoingURL = request.endpointURL
        entry.httpMethod = request.httpMethod
        entry.httpBody = request.httpBody
        entry.requestHeaders.append(objectsIn: request.headers.flatMap { [$0.key, $0.value] })
        try realm.write { realm.add(entry) }
        return ActivityID(rawValue: entry.id)
    }

    private func start(
        id: ActivityID = ActivityID(),
        kind: ActivityLogKind = .bookMetadata,
        libraryId: String? = "library",
        bookIds: Set<Int32> = [7],
        at date: Date? = nil
    ) -> ActivityLogStartValue {
        ActivityLogStartValue(
            id: id, kind: kind, request: request, startDatetime: date ?? startDate, libraryId: libraryId, bookIds: bookIds
        )
    }

    private func entries(
        libraryId: String? = nil, bookId: Int32? = nil, since: Date = .distantPast
    ) -> [ActivityLogSnapshot] {
        repository.fetchTestSnapshots(libraryId: libraryId, bookId: bookId, since: since)
    }

    private func entry(_ id: ActivityID) throws -> ActivityLogSnapshot {
        try XCTUnwrap(repository.fetchDetail(id: id, bookId: nil, since: .distantPast))
    }
}

private final class MockCalibreLibrarySnapshotProvider: CalibreLibrarySnapshotProviding {
    var calibreLibraries: [String: CalibreLibrary] = [:]
}
