import Foundation
import RealmSwift

/// A snapshot of shelf membership and the persisted keys whose owners are known.
/// A nil source ID identifies the legacy main Realm.
struct ReadingHistoryScope: Equatable, Sendable {
    let booksBySource: [UUID?: [String: String]]

    init(shelf: [String: CalibreBook], libraries: [String: CalibreLibrary], bookID: String? = nil) {
        let books: [CalibreBook]
        if let bookID {
            books = shelf[bookID].map { [$0] } ?? []
        } else {
            books = Array(shelf.values)
        }
        guard !books.isEmpty else {
            booksBySource = [:]
            return
        }

        let keys = Set(books.map { $0.library.key })
        var librariesByKey: [String: [String: UUID]] = [:]
        for library in Array(libraries.values) + shelf.values.map(\.library) where keys.contains(library.key) {
            librariesByKey[library.key, default: [:]][library.id] = library.server.uuid
        }

        var sources: [UUID?: [String: String]] = [:]
        for book in books {
            let server = book.library.server.uuid
            let owners = librariesByKey[book.library.key, default: [:]]
            if owners.count == 1 {
                sources[nil, default: [:]][book.bookPrefId] = book.inShelfId
            }
            if !owners.contains(where: { $0.value == server && $0.key != book.library.id }) {
                sources[server, default: [:]][book.bookPrefId] = book.inShelfId
            }
        }
        booksBySource = sources
    }
}

struct ReadingHistorySessionSummary: Identifiable, Sendable {
    var id: ReadingHistorySessionID { timing.id }
    let timing: ReadingSessionTiming
    let chapter: String
    let page: Int

    static func newestFirst(_ first: Self, _ second: Self) -> Bool {
        if first.timing.startDatetime != second.timing.startDatetime {
            return first.timing.startDatetime > second.timing.startDatetime
        }
        return (first.id.objectID, first.id.serverUUID?.uuidString ?? "")
            > (second.id.objectID, second.id.serverUUID?.uuidString ?? "")
    }
}

struct ReadingHistoryPage: Sendable {
    let rows: [ReadingHistorySessionSummary]
    let hasMore: Bool
}

enum ReadingHistoryObservation: Equatable, Sendable {
    case statistics(since: Date)
    case sessions
}

@MainActor
protocol ReadingHistoryRepository {
    func statistics(in scope: ReadingHistoryScope, window: ReadingStatisticsWindow) async throws -> ReadingStatistics
    func sessions(in scope: ReadingHistoryScope, limit: Int) async throws -> ReadingHistoryPage
    func endPosition(for id: ReadingHistorySessionID, in scope: ReadingHistoryScope) async throws -> BookDeviceReadingPosition?
    func changes(in scope: ReadingHistoryScope, for observation: ReadingHistoryObservation) -> AsyncStream<Void>
}

final class RealmReadingHistoryRepository: ReadingHistoryRepository {
    private let databaseService: DatabaseService
    private let provider: ServerScopedRealmConfigurationProviding
    private let executor: ReadingHistoryReadExecuting
    private let observationQueue = DispatchQueue(label: "ReadingHistory.observe", qos: .userInitiated)

    init(
        databaseService: DatabaseService, provider: ServerScopedRealmConfigurationProviding,
        executor: ReadingHistoryReadExecuting = DetachedReadingHistoryReads()
    ) {
        self.databaseService = databaseService
        self.provider = provider
        self.executor = executor
    }

    func statistics(in scope: ReadingHistoryScope, window: ReadingStatisticsWindow) async throws -> ReadingStatistics {
        try Task.checkCancellation()
        let sources = try sources(for: scope)
        return try await executor.read {
            var statistics = ReadingStatistics.Accumulator(window: window)
            for source in sources {
                try Task.checkCancellation()
                let rows = try source.rows(in: source.openRealm())
                    .filter("startDatetime >= %@ AND startDatetime <= %@",
                            window.sessionStartRange.lowerBound as NSDate, window.now as NSDate)
                for row in rows {
                    try Task.checkCancellation()
                    guard let bookID = source.books[row.bookId], let end = row.endPosition else { continue }
                    statistics.add(source.timing(for: row, epoch: end.epoch), bookID: bookID)
                }
            }
            return statistics.result
        }
    }

    func sessions(in scope: ReadingHistoryScope, limit: Int) async throws -> ReadingHistoryPage {
        try Task.checkCancellation()
        guard limit > 0 else { return ReadingHistoryPage(rows: [], hasMore: false) }
        let sources = try sources(for: scope)
        return try await executor.read {
            var candidates = [ReadingHistorySessionSummary]()
            for source in sources {
                try Task.checkCancellation()
                let rows = try source.rows(in: source.openRealm())
                    .sorted(by: [
                        SortDescriptor(keyPath: "startDatetime", ascending: false),
                        SortDescriptor(keyPath: "_id", ascending: false)
                    ])
                var count = 0
                for row in rows {
                    try Task.checkCancellation()
                    guard let end = row.endPosition, end.epoch.isFinite,
                          row.startDatetime.timeIntervalSince1970.isFinite else { continue }
                    candidates.append(ReadingHistorySessionSummary(
                        timing: source.timing(for: row, epoch: end.epoch),
                        chapter: end.lastReadChapter, page: end.lastReadPage
                    ))
                    count += 1
                    if count > limit { break }
                }
            }
            let ordered = candidates.sorted(by: ReadingHistorySessionSummary.newestFirst)
            return ReadingHistoryPage(rows: Array(ordered.prefix(limit)), hasMore: ordered.count > limit)
        }
    }

    func endPosition(for id: ReadingHistorySessionID, in scope: ReadingHistoryScope) async throws -> BookDeviceReadingPosition? {
        try Task.checkCancellation()
        guard let books = scope.booksBySource[id.serverUUID] else { return nil }
        let source = try source(for: id.serverUUID, books: books)
        return try await executor.read {
            guard let key = try? ObjectId(string: id.objectID) else { return nil }
            let realm = try source.openRealm()
            guard let row = realm.object(ofType: BookDeviceReadingPositionHistoryRealm.self, forPrimaryKey: key),
                  source.books[row.bookId] != nil, let end = row.endPosition, end.epoch.isFinite else { return nil }
            return end.toDomain()
        }
    }

    /// Initial delivery follows registration of all source notifications. A write during
    /// registration is covered by that initial read. Subsequent invalidations coalesce.
    func changes(in scope: ReadingHistoryScope, for observation: ReadingHistoryObservation) -> AsyncStream<Void> {
        let sources = (try? sources(for: scope)) ?? []
        let registration = HistoryNotifications(queue: observationQueue)
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            registration.start(sources: sources, observation: observation, continuation: continuation)
            continuation.onTermination = { _ in registration.cancel() }
        }
    }

    private func sources(for scope: ReadingHistoryScope) throws -> [HistorySource] {
        try scope.booksBySource.sorted { ($0.key?.uuidString ?? "") < ($1.key?.uuidString ?? "") }
            .map { try source(for: $0.key, books: $0.value) }
    }

    private func source(for server: UUID?, books: [String: String]) throws -> HistorySource {
        guard let configuration = server.map(provider.configuration(forServerUUID:)) ?? databaseService.realmConf else {
            throw DatabaseBootstrapError.realmConfigurationMissing
        }
        return HistorySource(server: server, configuration: configuration, books: books)
    }
}

protocol ReadingHistoryReadExecuting: Sendable {
    func read<Value: Sendable>(_ operation: @escaping @Sendable () throws -> Value) async throws -> Value
}

struct DetachedReadingHistoryReads: ReadingHistoryReadExecuting {
    func read<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try autoreleasepool(invoking: operation)
        }
        return try await withTaskCancellationHandler(operation: {
            let value = try await worker.value
            try Task.checkCancellation()
            return value
        }, onCancel: {
            worker.cancel()
        })
    }
}

private struct HistorySource: Sendable {
    let server: UUID?
    let configuration: Realm.Configuration
    let books: [String: String]

    func openRealm() throws -> Realm {
        let realm = try Realm(configuration: configuration)
        // Realm can reuse a thread-cached instance which still holds an earlier read version.
        realm.refresh()
        return realm
    }

    func rows(in realm: Realm) -> Results<BookDeviceReadingPositionHistoryRealm> {
        realm.objects(BookDeviceReadingPositionHistoryRealm.self)
            .filter("bookId IN %@ AND endPosition != nil", Array(books.keys))
    }

    func timing(for row: BookDeviceReadingPositionHistoryRealm, epoch: TimeInterval) -> ReadingSessionTiming {
        ReadingSessionTiming(
            id: ReadingHistorySessionID(serverUUID: server, objectID: row._id.stringValue),
            startDatetime: row.startDatetime, endEpoch: epoch
        )
    }
}

/// Registration, callbacks and token destruction all run on the same serial queue.
private final class HistoryNotifications: @unchecked Sendable {
    private let queue: DispatchQueue
    private var tokens = [NotificationToken]()

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func start(
        sources: [HistorySource],
        observation: ReadingHistoryObservation,
        continuation: AsyncStream<Void>.Continuation
    ) {
        queue.async {
            guard !sources.isEmpty else {
                continuation.yield()
                continuation.finish()
                return
            }
            var remaining = sources.count
            func ready() {
                remaining -= 1
                if remaining == 0 { continuation.yield() }
            }

            for source in sources {
                guard let realm = try? Realm(configuration: source.configuration, queue: self.queue) else {
                    ready()
                    continue
                }
                var rows = source.rows(in: realm)
                var paths = ["bookId", "startDatetime", "endPosition", "endPosition.epoch"]
                switch observation {
                case let .statistics(since):
                    rows = rows.filter("startDatetime >= %@", since as NSDate)
                case .sessions:
                    paths += ["endPosition.lastReadChapter", "endPosition.lastReadPage"]
                }
                var started = false
                let token = rows.observe(keyPaths: paths, on: self.queue) { change in
                    switch change {
                    case .initial, .error:
                        if !started {
                            started = true
                            ready()
                        }
                    case .update:
                        if remaining == 0 { continuation.yield() }
                    }
                }
                self.tokens.append(token)
            }
        }
    }

    func cancel() {
        queue.async {
            self.tokens.forEach { $0.invalidate() }
            self.tokens.removeAll()
        }
    }
}
