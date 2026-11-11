import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
final class ReadingHistoryRepositoryTests: XCTestCase {
    func testStatisticsRefreshesCachedRealmAfterObservedCommit() async throws {
        try await assertFreshRead(.statistics)
    }

    func testSessionPageRefreshesCachedRealmAfterObservedCommit() async throws {
        try await assertFreshRead(.sessions)
    }

    func testEndPositionRefreshesCachedRealmAfterObservedCommit() async throws {
        try await assertFreshRead(.endPosition)
    }

    private enum ReadPath {
        case statistics, sessions, endPosition
    }

    private func assertFreshRead(_ path: ReadPath) async throws {
        for legacy in [false, true] {
            let executor = FixedHistoryReadThread()
            executor.start()
            defer { executor.stop() }
            let fixture = try Fixture(executor: executor)
            let book = TestFixtures.makeBook()
            let originalID = try fixture.insert(book, start: 200, end: 260, legacy: legacy)
            let writer = legacy ? fixture.main : try fixture.sidecar(book.library.server)
            let configuration = writer.configuration
            let cacheKey = "HistoryFreshnessHeldRealm"

            // Establish and retain a read version on one NSThread without pumping a run loop.
            let initialCount = try await executor.read {
                let realm = try Realm(configuration: configuration)
                Thread.current.threadDictionary[cacheKey] = realm
                return realm.objects(BookDeviceReadingPositionHistoryRealm.self).count
            }
            XCTAssertEqual(initialCount, 1)

            let scope = ReadingHistoryScope(shelf: Self.shelf([book]), libraries: [:], bookID: book.inShelfId)
            let initial = expectation(description: "Observer initialized")
            let invalidated = expectation(description: "Commit invalidated history")
            let changes = fixture.repository.changes(in: scope, for: .sessions)
            let observer = Task {
                var initialized = false
                for await _ in changes {
                    if !initialized {
                        initialized = true
                        initial.fulfill()
                    } else {
                        invalidated.fulfill()
                        return
                    }
                }
            }
            defer { observer.cancel() }
            await fulfillment(of: [initial], timeout: 5)

            let insertedID = ObjectId.generate()
            let original = try XCTUnwrap(writer.object(
                ofType: BookDeviceReadingPositionHistoryRealm.self, forPrimaryKey: originalID
            ))
            try writer.write {
                original.endPosition?.epoch = 380
                original.endPosition?.lastReadChapter = "Updated Chapter"
                writer.add(Fixture.row(book, start: 400, end: 460, id: insertedID))
            }
            XCTAssertFalse(writer.isInWriteTransaction)
            await fulfillment(of: [invalidated], timeout: 5)

            // Notification delivery on its own queue must not accidentally refresh this thread.
            let stale = try await executor.read {
                let held = try XCTUnwrap(Thread.current.threadDictionary[cacheKey] as? Realm)
                return (
                    held.objects(BookDeviceReadingPositionHistoryRealm.self).count,
                    held.object(ofType: BookDeviceReadingPositionHistoryRealm.self,
                                forPrimaryKey: originalID)?.endPosition?.epoch
                )
            }
            XCTAssertEqual(stale.0, 1)
            XCTAssertEqual(stale.1, 260)
            let serverID = legacy ? nil : book.library.server.uuid

            switch path {
            case .statistics:
                let result = try await fixture.repository.statistics(
                    in: scope, window: Self.window(now: Date(timeIntervalSince1970: 1_000))
                )
                XCTAssertEqual(result.minutesByBook, [book.inShelfId: 4])
                XCTAssertEqual(result.minutesByDay.last, 4)
            case .sessions:
                let page = try await fixture.repository.sessions(in: scope, limit: 1)
                XCTAssertEqual(page.rows.map(\.id), [.init(serverUUID: serverID, objectID: insertedID.stringValue)])
                XCTAssertTrue(page.hasMore)
                let expanded = try await fixture.repository.sessions(in: scope, limit: 2)
                XCTAssertEqual(expanded.rows.last?.chapter, "Updated Chapter")
                XCTAssertEqual(expanded.rows.last?.timing.endEpoch, 380)
            case .endPosition:
                let updated = try await fixture.repository.endPosition(
                    for: .init(serverUUID: serverID, objectID: originalID.stringValue), in: scope
                )
                XCTAssertEqual(updated?.epoch, 380)
                XCTAssertEqual(updated?.lastReadChapter, "Updated Chapter")
                let inserted = try await fixture.repository.endPosition(
                    for: .init(serverUUID: serverID, objectID: insertedID.stringValue), in: scope
                )
                XCTAssertEqual(inserted?.epoch, 460)
            }
        }
    }

    func testCrossServerIdentityAndAmbiguousLegacyAttribution() async throws {
        let fixture = try Fixture()
        let first = TestFixtures.makeBook()
        let second = TestFixtures.makeBook()
        let id = ObjectId.generate()
        try fixture.insert(first, start: 1_000, end: 1_120, id: id)
        try fixture.insert(second, start: 2_000, end: 2_180, id: id)
        let legacyID = try fixture.insert(first, start: 3_000, end: 3_240, legacy: true)

        let shelf = Self.shelf([first, second])
        let libraries = [first.library.id: first.library, second.library.id: second.library]
        let window = try Self.window(now: Date(timeIntervalSince1970: 4_000))
        let all = try await fixture.repository.statistics(in: .init(shelf: shelf, libraries: libraries), window: window)
        XCTAssertEqual(all.minutesByBook, [first.inShelfId: 2, second.inShelfId: 3])

        let onlyFirst = Self.shelf([first])
        let firstScope = ReadingHistoryScope(shelf: onlyFirst, libraries: libraries, bookID: first.inShelfId)
        let firstPage = try await fixture.repository.sessions(in: firstScope, limit: 30)
        XCTAssertEqual(firstPage.rows.map(\.id), [.init(serverUUID: first.library.server.uuid, objectID: id.stringValue)])
        let legacy = try await fixture.repository.endPosition(
            for: .init(serverUUID: nil, objectID: legacyID.stringValue), in: firstScope
        )
        XCTAssertNil(legacy)
        XCTAssertNotNil(fixture.main.object(ofType: BookDeviceReadingPositionHistoryRealm.self, forPrimaryKey: legacyID))

        let alias = TestFixtures.makeLibrary(server: first.library.server, key: first.library.key, name: "Alias")
        let ambiguous = ReadingHistoryScope(shelf: onlyFirst, libraries: [alias.id: alias], bookID: first.inShelfId)
        let ambiguousPage = try await fixture.repository.sessions(in: ambiguous, limit: 30)
        XCTAssertTrue(ambiguousPage.rows.isEmpty)
        let removed = ReadingHistoryScope(shelf: onlyFirst, libraries: libraries, bookID: second.inShelfId)
        let removedPage = try await fixture.repository.sessions(in: removed, limit: 30)
        XCTAssertTrue(removedPage.rows.isEmpty)
    }

    func testSameEndPositionsStaySeparateAndWindowUsesBothRealms() async throws {
        let fixture = try Fixture()
        let book = TestFixtures.makeBook()
        let window = try Self.window(now: XCTUnwrap(ISO8601DateFormatter().date(from: "2024-11-05T07:30:00Z")),
                                     zone: "America/Los_Angeles")
        let earliest = try XCTUnwrap(ISO8601DateFormatter().date(from: "2024-10-28T07:00:00Z")).timeIntervalSince1970
        let latest = window.now.timeIntervalSince1970
        let duplicatedPrimaryKey = ObjectId.generate()
        for legacy in [true, false] {
            try fixture.insert(book, start: earliest, end: earliest + 300, legacy: legacy, id: duplicatedPrimaryKey)
            try fixture.insert(book, start: earliest + 60, end: earliest + 300, legacy: legacy)
            try fixture.insert(book, start: earliest - 1, end: earliest + 120, legacy: legacy)
            try fixture.insert(book, start: latest, end: latest, legacy: legacy)
            try fixture.insert(book, start: latest + 1, end: latest + 121, legacy: legacy)
        }

        let scope = ReadingHistoryScope(shelf: Self.shelf([book]), libraries: [:], bookID: book.inShelfId)
        let first = try await fixture.repository.sessions(in: scope, limit: 30)
        let repeatRead = try await fixture.repository.sessions(in: scope, limit: 30)
        XCTAssertEqual(first.rows.count, 10)
        XCTAssertEqual(first.rows.map(\.id), repeatRead.rows.map(\.id))
        XCTAssertEqual(Set(first.rows.map(\.id)).count, 10)
        let statistics = try await fixture.repository.statistics(in: scope, window: window)
        XCTAssertEqual(statistics.minutesByDay, [18, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(statistics.minutesByBook, [book.inShelfId: 18])

        var replay = ReadingStatistics.Accumulator(window: window)
        for row in first.rows + repeatRead.rows { replay.add(row.timing, bookID: book.inShelfId) }
        XCTAssertEqual(replay.result.minutesByDay, statistics.minutesByDay)
    }

    func testMergedPrefixAndOnDemandPositionAfterInsertUpdateAndDelete() async throws {
        let fixture = try Fixture()
        let book = TestFixtures.makeBook()
        let other = TestFixtures.makeBook(id: 2, library: book.library)
        let scope = ReadingHistoryScope(shelf: Self.shelf([book, other]), libraries: [:], bookID: book.inShelfId)
        let tied = ObjectId.generate()
        let newestLegacy = try fixture.insert(book, start: 300, end: 360, legacy: true, id: tied)
        let newestServer = try fixture.insert(book, start: 300, end: 360, id: tied)
        let older = try fixture.insert(book, start: 200, end: 260, legacy: true)
        let unrelated = try fixture.insert(other, start: 400, end: 460)

        let first = try await fixture.repository.sessions(in: scope, limit: 1)
        XCTAssertTrue(first.hasMore)
        let firstID = try XCTUnwrap(first.rows.first?.id)
        XCTAssertEqual(firstID, .init(serverUUID: book.library.server.uuid, objectID: newestServer.stringValue))

        let more = try await fixture.repository.sessions(in: scope, limit: 3)
        XCTAssertFalse(more.hasMore)
        XCTAssertEqual(more.rows.map(\.id.objectID), [newestServer, newestLegacy, older].map(\.stringValue))

        let realm = try fixture.sidecar(book.library.server)
        let row = try XCTUnwrap(realm.object(ofType: BookDeviceReadingPositionHistoryRealm.self, forPrimaryKey: newestServer))
        try realm.write {
            row.endPosition?.lastReadChapter = "Updated"
            row.endPosition?.cfi = "/retained/full/position"
        }
        let detail = try await fixture.repository.endPosition(for: firstID, in: scope)
        XCTAssertEqual(detail?.lastReadChapter, "Updated")
        XCTAssertEqual(detail?.cfi, "/retained/full/position")
        let outside = try await fixture.repository.endPosition(
            for: .init(serverUUID: book.library.server.uuid, objectID: unrelated.stringValue), in: scope
        )
        XCTAssertNil(outside)

        let inserted = try fixture.insert(book, start: 500, end: 560)
        try realm.write { realm.delete(row) }
        let deleted = try await fixture.repository.endPosition(for: firstID, in: scope)
        XCTAssertNil(deleted)
        let refreshed = try await fixture.repository.sessions(in: scope, limit: 3)
        XCTAssertEqual(refreshed.rows.map(\.id.objectID), [inserted, newestLegacy, older].map(\.stringValue))
    }

    func testSyntheticShelfBatchesSidecarAndSeparatesPageFromTotals() async throws {
        let fixture = try Fixture()
        let library = TestFixtures.makeLibrary()
        let books = (1...64).map { TestFixtures.makeBook(id: Int32($0), library: library) }
        let realm = try fixture.sidecar(library.server)
        let start: TimeInterval = 1_730_764_000
        try realm.write {
            for (index, book) in books.enumerated() {
                for _ in 0..<(index == 0 ? 512 : 32) {
                    realm.add(Fixture.row(book, start: start, end: start + 60, id: ObjectId.generate()))
                }
            }
        }
        let shelf = Self.shelf(books)
        let window = try Self.window(now: Date(timeIntervalSince1970: start + 60))
        let scopeClock = ProcessInfo.processInfo.systemUptime
        let global = ReadingHistoryScope(shelf: shelf, libraries: [:])
        let scopeTime = ProcessInfo.processInfo.systemUptime - scopeClock
        let before = fixture.provider.requests
        let clock = ProcessInfo.processInfo.systemUptime
        let statistics = try await fixture.repository.statistics(in: global, window: window)
        let statisticsTime = ProcessInfo.processInfo.systemUptime - clock
        let requests = fixture.provider.requests - before
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(statistics.minutesByBook.count, 64)
        XCTAssertEqual(statistics.minutesByBook.values.reduce(0, +), 2_528)

        let book = try XCTUnwrap(books.first)
        let one = ReadingHistoryScope(shelf: shelf, libraries: [:], bookID: book.inShelfId)
        let pageClock = ProcessInfo.processInfo.systemUptime
        let page = try await fixture.repository.sessions(in: one, limit: 30)
        let measurement = XCTAttachment(string: """
            Main actor scope preparation: \(scopeTime) s
            Statistics query and aggregation: \(statisticsTime) s, \(requests) sidecar requests
            First page: \(ProcessInfo.processInfo.systemUptime - pageClock) s, \(page.rows.count) summaries
            """)
        measurement.name = "Synthetic history read"
        measurement.lifetime = .keepAlways
        add(measurement)
        XCTAssertEqual(page.rows.count, 30)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(statistics.minutesByBook[book.inShelfId], 512)
    }

    func testScopedObservationSeesCompletionAndLinkedEndPositionChanges() async throws {
        let fixture = try Fixture()
        let book = TestFixtures.makeBook()
        let scope = ReadingHistoryScope(shelf: Self.shelf([book]), libraries: [:], bookID: book.inShelfId)
        let sessions = fixture.repository.changes(in: scope, for: .sessions)
        let statistics = fixture.repository.changes(in: scope, for: .statistics(since: Date(timeIntervalSince1970: 100)))
        let sessionEvents = ["initial", "completion", "chapter edit", "epoch edit", "deletion"]
            .map { expectation(description: "Sessions: \($0)") }
        let statisticsEvents = ["initial", "completion", "epoch edit", "deletion"]
            .map { expectation(description: "Statistics: \($0)") }
        var sessionCount = 0
        var statisticsCount = 0
        let observer = Task {
            for await _ in sessions {
                guard sessionEvents.indices.contains(sessionCount) else {
                    XCTFail("Unexpected session invalidation")
                    return
                }
                sessionEvents[sessionCount].fulfill()
                sessionCount += 1
            }
        }
        let statsObserver = Task {
            for await _ in statistics {
                guard statisticsEvents.indices.contains(statisticsCount) else {
                    XCTFail("Unexpected statistics invalidation")
                    return
                }
                statisticsEvents[statisticsCount].fulfill()
                statisticsCount += 1
            }
        }
        defer { observer.cancel(); statsObserver.cancel() }
        await fulfillment(of: [sessionEvents[0], statisticsEvents[0]], timeout: 5)

        let realm = try fixture.sidecar(book.library.server)
        let unfinished = Fixture.row(book, start: 200, end: 260, id: ObjectId.generate())
        let end = unfinished.endPosition
        unfinished.endPosition = nil
        try realm.write { realm.add(unfinished) }
        try realm.write { unfinished.endPosition = end }
        await fulfillment(of: [sessionEvents[1], statisticsEvents[1]], timeout: 5)

        let other = TestFixtures.makeBook(id: 2, library: book.library)
        let otherScope = ReadingHistoryScope(shelf: Self.shelf([other]), libraries: [:], bookID: other.inShelfId)
        let otherChanges = fixture.repository.changes(in: otherScope, for: .sessions)
        let otherInitial = expectation(description: "Other book observer initialized")
        let otherInserted = expectation(description: "Other book changed on the same Realm")
        let otherObserver = Task {
            var initial = true
            for await _ in otherChanges {
                if initial { otherInitial.fulfill(); initial = false }
                else { otherInserted.fulfill(); return }
            }
        }
        defer { otherObserver.cancel() }
        await fulfillment(of: [otherInitial], timeout: 5)
        try fixture.insert(other, start: 210, end: 270)
        await fulfillment(of: [otherInserted], timeout: 5)
        XCTAssertEqual(sessionCount, 2)
        XCTAssertEqual(statisticsCount, 2)

        try realm.write { unfinished.endPosition?.lastReadChapter = "Chapter edit" }
        await fulfillment(of: [sessionEvents[2]], timeout: 5)
        XCTAssertEqual(statisticsCount, 2)

        try realm.write { unfinished.endPosition?.epoch = 320 }
        await fulfillment(of: [sessionEvents[3], statisticsEvents[2]], timeout: 5)

        try realm.write { realm.delete(unfinished) }
        await fulfillment(of: [sessionEvents[4], statisticsEvents[3]], timeout: 5)
    }

    private static func shelf(_ books: [CalibreBook]) -> [String: CalibreBook] {
        Dictionary(uniqueKeysWithValues: books.map { ($0.inShelfId, $0) })
    }

    private static func window(now: Date, zone: String = "UTC") throws -> ReadingStatisticsWindow {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return ReadingStatisticsWindow(now: now, calendar: calendar, previousDays: 7)
    }

    private final class CountingProvider: ServerScopedRealmConfigurationProviding {
        private let base = InMemoryServerScopedRealmConfigurationProvider(identifierPrefix: UUID().uuidString)
        private(set) var requests = 0

        func configuration(forServerUUID uuid: UUID) -> Realm.Configuration {
            requests += 1
            return base.configuration(forServerUUID: uuid)
        }
    }

    @MainActor
    private final class Fixture {
        let provider = CountingProvider()
        let main: Realm
        let repository: RealmReadingHistoryRepository
        private var sidecars: [UUID: Realm] = [:]

        init(executor: ReadingHistoryReadExecuting = DetachedReadingHistoryReads()) throws {
            let database = DatabaseService()
            let configuration = Realm.Configuration(
                inMemoryIdentifier: UUID().uuidString,
                schemaVersion: DatabaseSchema.version,
                objectTypes: [BookDeviceReadingPositionHistoryRealm.self, BookDeviceReadingPositionRealm.self]
            )
            main = try Realm(configuration: configuration)
            database.configure(conf: configuration)
            repository = RealmReadingHistoryRepository(databaseService: database, provider: provider, executor: executor)
        }

        func sidecar(_ server: CalibreServer) throws -> Realm {
            if let realm = sidecars[server.uuid] { return realm }
            let realm = try Realm(configuration: provider.configuration(for: server))
            sidecars[server.uuid] = realm
            return realm
        }

        @discardableResult
        func insert(_ book: CalibreBook, start: TimeInterval, end: TimeInterval,
                    legacy: Bool = false, id: ObjectId = ObjectId.generate()) throws -> ObjectId {
            let realm = legacy ? main : try sidecar(book.library.server)
            try realm.write { realm.add(Self.row(book, start: start, end: end, id: id)) }
            return id
        }

        static func row(_ book: CalibreBook, start: TimeInterval, end: TimeInterval,
                        id: ObjectId) -> BookDeviceReadingPositionHistoryRealm {
            let row = BookDeviceReadingPositionHistoryRealm()
            row._id = id
            row.bookId = book.bookPrefId
            row.startDatetime = Date(timeIntervalSince1970: start)
            row.startPosition = TestFixtures.makeReadingPosition(epoch: start).makeRealmObject(bookId: book.bookPrefId)
            row.endPosition = TestFixtures.makeReadingPosition(epoch: end).makeRealmObject(bookId: book.bookPrefId)
            return row
        }
    }
}

/// A serial DispatchQueue can change threads. This worker retains one actual NSThread.
/// The condition protects queued jobs and shutdown. Realm references stay in that thread's dictionary.
private final class FixedHistoryReadThread: Thread, ReadingHistoryReadExecuting, @unchecked Sendable {
    private let condition = NSCondition()
    private var jobs: [@Sendable () -> Void] = []
    private var stopping = false
    private let stopped = DispatchSemaphore(value: 0)

    override func main() {
        defer { stopped.signal() }
        while true {
            condition.lock()
            while jobs.isEmpty && !stopping { condition.wait() }
            if stopping {
                condition.unlock()
                return
            }
            let job = jobs.removeFirst()
            condition.unlock()
            autoreleasepool(invoking: job)
        }
    }

    func read<Value: Sendable>(_ operation: @escaping @Sendable () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            condition.lock()
            jobs.append {
                continuation.resume(with: Result { try operation() })
            }
            condition.signal()
            condition.unlock()
        }
    }

    func stop() {
        condition.lock()
        stopping = true
        condition.signal()
        condition.unlock()
        XCTAssertEqual(stopped.wait(timeout: .now() + 5), .success)
    }
}
