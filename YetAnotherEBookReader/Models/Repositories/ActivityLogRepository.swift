//
//  ActivityLogRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/14.
//

import Foundation
import RealmSwift

protocol ActivityLogRepositoryProtocol {
    @MainActor func fetchEntries(libraryId: String?, bookId: Int32?, since: Date) -> [ActivityLogSnapshot]
    @MainActor func observeEntries(libraryId: String?, bookId: Int32?, since: Date) -> AsyncStream<[ActivityLogSnapshot]>
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

    private func predicate(libraryId: String?, bookId: Int32?, since: Date) -> NSPredicate {
        if let libraryId = libraryId {
            if let bookId = bookId {
                return NSPredicate(
                    format: "startDatetime >= %@ AND libraryId == %@ AND ANY bookIds == %d",
                    since as NSDate,
                    libraryId,
                    bookId
                )
            }
            return NSPredicate(format: "startDatetime >= %@ AND libraryId == %@", since as NSDate, libraryId)
        }

        return NSPredicate(format: "startDatetime >= %@", since as NSDate)
    }

    @MainActor private func snapshot(_ entry: CalibreActivityLogEntry, scopedBookId: Int32?) -> ActivityLogSnapshot {
        let library = entry.libraryId.flatMap { librarySnapshotProvider?.calibreLibraries[$0] }
        let bookId = scopedBookId ?? (entry.bookIds.count == 1 ? entry.bookIds.first : nil)
        let bookTitle: String?
        if let library, let bookId {
            bookTitle = bookRepository.getBook(library: library, bookId: bookId)?.title
        } else {
            bookTitle = nil
        }
        return entry.toSnapshot(libraryName: library?.name, bookTitle: bookTitle)
    }

    @MainActor func fetchEntries(libraryId: String?, bookId: Int32?, since: Date) -> [ActivityLogSnapshot] {
        guard let realm = databaseService.realm else { return [] }
        realm.refresh()

        return realm.objects(CalibreActivityLogEntry.self)
            .filter(predicate(libraryId: libraryId, bookId: bookId, since: since))
            .sorted(byKeyPath: "startDatetime", ascending: false)
            .map { snapshot($0, scopedBookId: libraryId == nil ? nil : bookId) }
    }

    @MainActor func observeEntries(libraryId: String?, bookId: Int32?, since: Date) -> AsyncStream<[ActivityLogSnapshot]> {
        guard let realm = databaseService.realm else {
            return AsyncStream { continuation in
                continuation.yield([])
                continuation.finish()
            }
        }

        _ = realm.refresh()

        let results = realm.objects(CalibreActivityLogEntry.self)
            .filter(predicate(libraryId: libraryId, bookId: bookId, since: since))
            .sorted(byKeyPath: "startDatetime", ascending: false)

        return AsyncStream { [weak self] continuation in
            let token = results.observe { [weak self] change in
                guard let self else {
                    continuation.yield([])
                    return
                }
                switch change {
                case .initial(let collection), .update(let collection, _, _, _):
                    continuation.yield(collection.map {
                        self.snapshot($0, scopedBookId: libraryId == nil ? nil : bookId)
                    })
                case .error:
                    continuation.yield([])
                }
            }
            continuation.onTermination = { _ in
                token.invalidate()
            }
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
                                case .legacyStart(let value):
                                    guard value.startDatetime >= cutoff else { continue }
                                    realm.add(CalibreActivityLogEntry(legacyStart: value))
                                case .legacyFinish(let value):
                                    realm.objects(CalibreActivityLogEntry.self)
                                        .filter(CalibreActivityLogEntry.legacyPredicate(matching: value))
                                        .first?.apply(value)
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
