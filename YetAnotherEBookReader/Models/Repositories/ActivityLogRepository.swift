//
//  ActivityLogRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/14.
//

import Foundation
import RealmSwift

protocol ActivityLogRepositoryProtocol {
    @MainActor func fetchPage(query: ActivityLogQuery, limit: Int) -> ActivityLogPage
    @MainActor func observePage(query: ActivityLogQuery, limit: Int) -> AsyncStream<ActivityLogPage>
    @MainActor func fetchDetail(id: ActivityID, bookId: Int32?, since: Date) -> ActivityLogSnapshot?
    @MainActor func observeDetail(id: ActivityID, bookId: Int32?, since: Date) -> AsyncStream<ActivityLogSnapshot?>
    func writeActivityLogEvents(_ events: [ActivityLogWriteEvent]) async throws
}

final class RealmActivityLogRepository: ActivityLogRepositoryProtocol {
    private let databaseService: DatabaseService
    private let bookRepository: BookRepositoryProtocol
    private weak var librarySnapshotProvider: CalibreLibrarySnapshotProviding?
    private let writeQueue = DispatchQueue(label: "activity-log-repository.write", qos: .utility)
    private let ownerProcessID: String
    private var retainedSince = Date.distantPast // Owned by writeQueue.

    // Shared across repositories and repeated database bootstrap in this process.
    private static let processID = UUID().uuidString

    convenience init(
        databaseService: DatabaseService = .shared,
        bookRepository: BookRepositoryProtocol,
        container: AppContainerProtocol?
    ) {
        self.init(databaseService: databaseService, bookRepository: bookRepository, librarySnapshotProvider: container)
    }

    init(
        databaseService: DatabaseService = .shared,
        bookRepository: BookRepositoryProtocol,
        librarySnapshotProvider: CalibreLibrarySnapshotProviding?,
        ownerProcessID: String? = nil
    ) {
        self.databaseService = databaseService
        self.bookRepository = bookRepository
        self.librarySnapshotProvider = librarySnapshotProvider
        self.ownerProcessID = ownerProcessID ?? Self.processID
    }

    @MainActor private func pageResults(_ query: ActivityLogQuery, in realm: Realm) -> Results<CalibreActivityLogEntry> {
        var results = realm.objects(CalibreActivityLogEntry.self).filter("startDatetime >= %@", query.since as NSDate)
        if let libraryId = query.libraryId {
            results = results.filter("libraryId == %@", libraryId)
            if let bookId = query.bookId {
                results = results.filter("ANY bookIds == %d", bookId)
            }
        } else if query.bookId != nil {
            // Calibre's numeric book IDs only have meaning within a library.
            results = results.filter(NSPredicate(value: false))
        }
        if let kind = query.filter.kind {
            results = results.filter("kind == %@", kind.rawValue)
        }
        if query.filter.failuresOnly {
            results = results.filter("kind != nil AND status == %@", ActivityLogCompletion.failed.rawValue)
        }
        return results.sorted(by: [
            SortDescriptor(keyPath: "startDatetime", ascending: false),
            SortDescriptor(keyPath: "id", ascending: true)
        ])
    }

    @MainActor private func titles(_ entry: CalibreActivityLogEntry, bookId: Int32?) -> (library: String?, book: String?) {
        let library = entry.libraryId.flatMap { librarySnapshotProvider?.calibreLibraries[$0] }
        let scopedId = bookId ?? (entry.bookIds.count == 1 ? entry.bookIds.first : nil)
        if let library, let scopedId {
            return (library.name, bookRepository.getBook(library: library, bookId: scopedId)?.title)
        }
        return (library?.name, nil)
    }

    @MainActor private func page(_ results: Results<CalibreActivityLogEntry>, bookId: Int32?, limit: Int) -> ActivityLogPage {
        let limit = max(1, limit)
        return ActivityLogPage(entries: results.prefix(limit).map { entry in
            let names = titles(entry, bookId: bookId)
            return entry.toSummary(libraryName: names.library, bookTitle: names.book)
        }, hasMore: results.count > limit)
    }

    @MainActor private func detail(_ entry: CalibreActivityLogEntry?, bookId: Int32?) -> ActivityLogSnapshot? {
        guard let entry else { return nil }
        let names = titles(entry, bookId: bookId)
        return entry.toSnapshot(libraryName: names.library, bookTitle: names.book)
    }

    @MainActor func fetchPage(query: ActivityLogQuery, limit: Int) -> ActivityLogPage {
        guard let realm = databaseService.realm else { return .init() }
        realm.refresh()
        return page(pageResults(query, in: realm), bookId: query.bookId, limit: limit)
    }

    @MainActor func observePage(query: ActivityLogQuery, limit: Int) -> AsyncStream<ActivityLogPage> {
        // Observe the ordered query as a live prefix. Inserts and deletions shift the prefix
        // atomically, including at the load-more boundary. Map only the requested rows.
        let results = databaseService.realm.map { pageResults(query, in: $0) }
        return observe(results, unavailable: ActivityLogPage(), keyPaths: [
            "id", "startDatetime", "finishDatetime", "status", "kind", "libraryId", "bookIds",
            "type", "errMsg", "downloadFormat", "resultDetail", "httpStatusCode"
        ]) { self.page($0, bookId: query.bookId, limit: limit) }
    }

    @MainActor func fetchDetail(id: ActivityID, bookId: Int32?, since: Date) -> ActivityLogSnapshot? {
        guard let realm = databaseService.realm else { return nil }
        realm.refresh()
        let entry = realm.object(ofType: CalibreActivityLogEntry.self, forPrimaryKey: id.rawValue)
        guard let entry, entry.startDatetime >= since else { return nil }
        return detail(entry, bookId: bookId)
    }

    @MainActor func observeDetail(id: ActivityID, bookId: Int32?, since: Date) -> AsyncStream<ActivityLogSnapshot?> {
        let results = databaseService.realm?.objects(CalibreActivityLogEntry.self)
            .filter("id == %@ AND startDatetime >= %@", id.rawValue, since as NSDate)
        return observe(results, unavailable: nil) { self.detail($0.first, bookId: bookId) }
    }

    @MainActor private func observe<Value: Sendable>(
        _ results: Results<CalibreActivityLogEntry>?,
        unavailable: Value,
        keyPaths: [String]? = nil,
        snapshot: @escaping @MainActor (Results<CalibreActivityLogEntry>) -> Value
    ) -> AsyncStream<Value> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            guard let results else {
                continuation.yield(unavailable)
                continuation.finish()
                return
            }
            let token = results.observe(keyPaths: keyPaths) { change in
                switch change {
                case .initial(let collection), .update(let collection, _, _, _):
                    continuation.yield(snapshot(collection))
                case .error:
                    continuation.yield(unavailable)
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in token.invalidate() }
        }
    }

    func writeActivityLogEvents(_ events: [ActivityLogWriteEvent]) async throws {
        guard !events.isEmpty else { return }
        guard let realmConf = databaseService.realmConf else {
            throw DatabaseBootstrapError.realmConfigurationMissing
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writeQueue.async {
                continuation.resume(with: Result {
                    try autoreleasepool {
                        let realm = try Realm(configuration: realmConf)
                        var cutoff = self.retainedSince
                        try realm.write {
                            for event in events {
                                switch event {
                                case .start(let value):
                                    guard value.startDatetime >= cutoff,
                                          realm.object(ofType: CalibreActivityLogEntry.self, forPrimaryKey: value.id.rawValue) == nil
                                    else { continue }
                                    realm.add(CalibreActivityLogEntry(startValue: value, ownerProcessID: self.ownerProcessID))
                                case let .update(id, update):
                                    if let entry = realm.object(ofType: CalibreActivityLogEntry.self, forPrimaryKey: id.rawValue),
                                       entry.ownerProcessID == self.ownerProcessID {
                                        entry.apply(update)
                                    }
                                case .remove(let id):
                                    if let entry = realm.object(ofType: CalibreActivityLogEntry.self, forPrimaryKey: id.rawValue) {
                                        realm.delete(entry)
                                    }
                                case .prune(let before):
                                    cutoff = max(cutoff, before)
                                    self.prune(realm, before: cutoff)
                                case .recoverAndPrune(let date):
                                    cutoff = max(cutoff, ActivityLogRetention.cutoff(at: date))
                                    self.prune(realm, before: cutoff)
                                    self.recover(realm, at: date)
                                }
                            }
                        }
                        // Publish the retention watermark only after the transaction commits.
                        self.retainedSince = cutoff
                    }
                })
            }
        }
    }

    private func prune(_ realm: Realm, before cutoff: Date) {
        realm.delete(realm.objects(CalibreActivityLogEntry.self)
            .filter("startDatetime < %@", cutoff as NSDate))
    }

    private func recover(_ realm: Realm, at date: Date) {
        let unfinished = realm.objects(CalibreActivityLogEntry.self).filter(
            "kind != nil AND status IN %@ AND (ownerProcessID == nil OR ownerProcessID != %@)",
            [ActivityLogProgress.running.rawValue, ActivityLogProgress.paused.rawValue], ownerProcessID
        )
        // Copy the collection before changing the fields its predicate uses.
        for entry in Array(unfinished) {
            entry.apply(.finish(.interrupted, at: date, result: .init(detail: "The app closed before the operation finished.")))
        }
    }
}
