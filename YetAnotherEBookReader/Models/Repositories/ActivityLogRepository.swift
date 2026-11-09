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
    func writeActivityLogEvents(_ events: [ActivityLogWriteEvent]) async
    func removeCalibreActivity(id: ActivityID) async
    func cleanCalibreActivities(startDatetime: Date) async
}

final class RealmActivityLogRepository: ActivityLogRepositoryProtocol {
    private let databaseService: DatabaseService
    private let bookRepository: BookRepositoryProtocol
    private weak var librarySnapshotProvider: CalibreLibrarySnapshotProviding?
    private let writeQueue = DispatchQueue(label: "activity-log-repository.write", qos: .utility)

    init(
        databaseService: DatabaseService = .shared,
        bookRepository: BookRepositoryProtocol,
        container: AppContainerProtocol?
    ) {
        self.databaseService = databaseService
        self.bookRepository = bookRepository
        self.librarySnapshotProvider = container
    }

    init(
        databaseService: DatabaseService = .shared,
        bookRepository: BookRepositoryProtocol,
        librarySnapshotProvider: CalibreLibrarySnapshotProviding?
    ) {
        self.databaseService = databaseService
        self.bookRepository = bookRepository
        self.librarySnapshotProvider = librarySnapshotProvider
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

    func writeActivityLogEvents(_ events: [ActivityLogWriteEvent]) async {
        guard !events.isEmpty, let realmConf = databaseService.realmConf else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writeQueue.async {
                defer { continuation.resume() }
                autoreleasepool {
                    guard let realm = try? Realm(configuration: realmConf) else {
                        return
                    }

                    try? realm.write {
                        events.forEach { event in
                            switch event {
                            case .start(let value):
                                // The first start owns this ID. Unknown updates are dropped.
                                guard realm.object(ofType: CalibreActivityLogEntry.self, forPrimaryKey: value.id.rawValue) == nil else { return }
                                realm.add(CalibreActivityLogEntry(startValue: value))
                            case let .update(id, update):
                                realm.object(ofType: CalibreActivityLogEntry.self, forPrimaryKey: id.rawValue)?.apply(update)
                            case .legacyStart(let value):
                                realm.add(CalibreActivityLogEntry(legacyStart: value))
                            case .legacyFinish(let value):
                                realm.objects(CalibreActivityLogEntry.self)
                                    .filter(CalibreActivityLogEntry.legacyPredicate(matching: value))
                                    .first?.apply(value)
                            }
                        }
                    }
                }
            }
        }
    }

    func removeCalibreActivity(id: ActivityID) async {
        guard let realmConf = databaseService.realmConf else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writeQueue.async {
                defer { continuation.resume() }
                autoreleasepool {
                    guard let realm = try? Realm(configuration: realmConf),
                          let obj = realm.object(ofType: CalibreActivityLogEntry.self, forPrimaryKey: id.rawValue)
                    else {
                        return
                    }

                    try? realm.write {
                        realm.delete(obj)
                    }
                }
            }
        }
    }

    func cleanCalibreActivities(startDatetime: Date) async {
        guard let realmConf = databaseService.realmConf else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writeQueue.async {
                defer { continuation.resume() }
                autoreleasepool {
                    guard let realm = try? Realm(configuration: realmConf) else {
                        return
                    }

                    let activities = realm.objects(CalibreActivityLogEntry.self).filter(
                        NSPredicate(format: "startDatetime < %@", startDatetime as NSDate)
                    )

                    try? realm.write {
                        realm.delete(activities)
                    }
                }
            }
        }
    }
}
