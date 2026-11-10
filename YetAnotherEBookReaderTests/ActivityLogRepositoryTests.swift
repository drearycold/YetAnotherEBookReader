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
        let stream = repository.observeEntries(libraryId: "A", bookId: 9, since: .distantPast)
        let observation = Task {
            var iterator = stream.makeAsyncIterator()
            let running = await iterator.next()
            XCTAssertEqual(running?.map(\.id), [batch.id])
            XCTAssertEqual(running?.first?.state, .inProgress(.running))
            initial.fulfill()

            let updated = await iterator.next()
            XCTAssertEqual(updated?.map(\.id), [batch.id])
            XCTAssertEqual(updated?.first?.state, .finished(.succeeded))
            finished.fulfill()
        }
        defer { observation.cancel() }

        await fulfillment(of: [initial], timeout: 5)
        try await repository.writeActivityLogEvents([.update(id: batch.id, .finish(.succeeded, at: finishDate))])
        await fulfillment(of: [finished], timeout: 5)
    }

    func testLegacyAdapterPreservesTextAndCannotChangeTypedRecord() async throws {
        let typed = start(libraryId: "A", bookIds: [7])
        let legacyStart = ActivityLogLegacyStartValue(
            type: "Get Book Metadata", request: request, startDatetime: startDate, bookId: 7, libraryId: "A"
        )
        try await repository.writeActivityLogEvents([.start(typed), .legacyStart(legacyStart)])
        let legacyID = try XCTUnwrap(entries(libraryId: "A", bookId: 7).first { $0.state == .legacy }?.id)

        let legacyFinish = ActivityLogLegacyFinishValue(
            type: legacyStart.type, endpointURL: request.endpointURL, startDatetime: startDate,
            finishDatetime: finishDate, errMsg: "Success"
        )
        try await repository.writeActivityLogEvents([
            .legacyFinish(legacyFinish),
            .update(id: legacyID, .finish(.failed, at: finishDate.addingTimeInterval(2)))
        ])
        let legacy = try entry(legacyID)
        XCTAssertEqual(legacy.state, .legacy)
        XCTAssertEqual(legacy.legacyType, legacyStart.type)
        XCTAssertEqual(legacy.legacyResult, "Success")
        XCTAssertEqual(legacy.finishDatetime, finishDate)
        XCTAssertEqual(legacy.result, ActivityLogResult())
        XCTAssertEqual(legacy.request, request)

        XCTAssertEqual(try entry(typed.id).state, .inProgress(.running))
        XCTAssertNil(try entry(typed.id).finishDatetime)
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
        let legacy = ActivityLogLegacyStartValue(type: "Old", request: request, startDatetime: startDate,
                                                 bookId: 8, libraryId: "library")
        try await previous.writeActivityLogEvents([
            .start(running), .start(paused), .start(finished), .start(stale), .legacyStart(legacy),
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
        repository.fetchEntries(libraryId: libraryId, bookId: bookId, since: since)
    }

    private func entry(_ id: ActivityID) throws -> ActivityLogSnapshot {
        try XCTUnwrap(entries().first { $0.id == id })
    }
}

private final class MockCalibreLibrarySnapshotProvider: CalibreLibrarySnapshotProviding {
    var calibreLibraries: [String: CalibreLibrary] = [:]
}
