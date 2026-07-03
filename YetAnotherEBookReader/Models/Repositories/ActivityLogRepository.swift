//
//  ActivityLogRepository.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/14.
//

import Foundation
import RealmSwift

struct ActivityLogUIEntry: Identifiable, Hashable {
    let id: String
    let libraryName: String
    let bookTitle: String
    let type: String
    let errMsg: String
    let startDateString: String
    let finishDateString: String
    let startDateLongString: String
    let finishDateLongString: String
    let endpointURL: String
    let httpMethod: String
    let httpBodyString: String?
}

protocol ActivityLogRepositoryProtocol {
    func fetchEntries(libraryId: String?, bookId: Int32?, since: Date) -> [ActivityLogUIEntry]
    func observeEntries(libraryId: String?, bookId: Int32?, since: Date) -> AsyncStream<[ActivityLogUIEntry]>
    func writeActivityLogEvents(_ events: [ActivityLogWriteEvent]) async
    func removeCalibreActivity(id: String) async
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

    private func getRealm() -> Realm? {
        if Thread.isMainThread {
            return databaseService.realm
        }

        guard let conf = databaseService.realmConf else { return nil }

        let configurationIdentifier = conf.inMemoryIdentifier
            ?? conf.fileURL?.absoluteString
            ?? "default"
        let key = "ActivityLogRepositoryRealm-\(configurationIdentifier)"
        if let cachedRealm = Thread.current.threadDictionary[key] as? Realm {
            cachedRealm.refresh()
            return cachedRealm
        }

        if let realm = try? Realm(configuration: conf) {
            Thread.current.threadDictionary[key] = realm
            return realm
        }
        return nil
    }

    private func predicate(libraryId: String?, bookId: Int32?, since: Date) -> NSPredicate {
        if let libraryId = libraryId {
            if let bookId = bookId {
                return NSPredicate(
                    format: "startDatetime >= %@ AND libraryId == %@ AND bookId == %d",
                    since as NSDate,
                    libraryId,
                    bookId
                )
            }
            return NSPredicate(format: "startDatetime >= %@ AND libraryId == %@", since as NSDate, libraryId)
        }

        return NSPredicate(format: "startDatetime >= %@", since as NSDate)
    }

    private func formattedDate(
        _ date: Date?,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style,
        fallback: String
    ) -> String {
        guard let date else { return fallback }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = dateStyle
        dateFormatter.timeStyle = timeStyle
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: date)
    }

    private func mapToUI(_ obj: CalibreActivityLogEntry) -> ActivityLogUIEntry {
        var libraryName = "No Entity"
        var bookTitle = ""

        if let libraryId = obj.libraryId,
           let library = librarySnapshotProvider?.calibreLibraries[libraryId] {
            libraryName = library.name
            if let book = bookRepository.getBook(library: library, bookId: obj.bookId) {
                bookTitle = book.title
            }
        }

        return ActivityLogUIEntry(
            id: obj.id,
            libraryName: libraryName,
            bookTitle: bookTitle,
            type: obj.type ?? "Unknown Type",
            errMsg: obj.errMsg ?? "Unknown Error",
            startDateString: formattedDate(
                obj.startDatetime,
                dateStyle: .short,
                timeStyle: .medium,
                fallback: "Start Unknown"
            ),
            finishDateString: formattedDate(
                obj.finishDatetime,
                dateStyle: .short,
                timeStyle: .medium,
                fallback: "Finish Unknown"
            ),
            startDateLongString: formattedDate(
                obj.startDatetime,
                dateStyle: .long,
                timeStyle: .long,
                fallback: "Unknown"
            ),
            finishDateLongString: formattedDate(
                obj.finishDatetime,
                dateStyle: .long,
                timeStyle: .long,
                fallback: "Unknown"
            ),
            endpointURL: obj.endpoingURL ?? "Unknown",
            httpMethod: obj.httpMethod ?? "GET",
            httpBodyString: obj.httpBody.flatMap { String(data: $0, encoding: .utf8) }
        )
    }

    func fetchEntries(libraryId: String?, bookId: Int32?, since: Date) -> [ActivityLogUIEntry] {
        guard let realm = getRealm() else { return [] }
        realm.refresh()

        return realm.objects(CalibreActivityLogEntry.self)
            .filter(predicate(libraryId: libraryId, bookId: bookId, since: since))
            .sorted(byKeyPath: "startDatetime", ascending: false)
            .map(mapToUI)
    }

    func observeEntries(libraryId: String?, bookId: Int32?, since: Date) -> AsyncStream<[ActivityLogUIEntry]> {
        guard let realm = getRealm() else {
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
            let token = results.observe(on: DispatchQueue.main) { [weak self] change in
                guard let self else {
                    continuation.yield([])
                    return
                }
                switch change {
                case .initial(let collection), .update(let collection, _, _, _):
                    continuation.yield(collection.map(self.mapToUI))
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
                                realm.add(CalibreActivityLogEntry(startValue: value))
                            case .finish(let value):
                                guard let previous = realm.objects(CalibreActivityLogEntry.self)
                                    .filter(CalibreActivityLogEntry.predicate(matching: value))
                                    .first
                                else { return }

                                previous.apply(value)
                            }
                        }
                    }
                }
            }
        }
    }

    func removeCalibreActivity(id: String) async {
        guard let realmConf = databaseService.realmConf else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writeQueue.async {
                defer { continuation.resume() }
                autoreleasepool {
                    guard let realm = try? Realm(configuration: realmConf),
                          let obj = realm.object(ofType: CalibreActivityLogEntry.self, forPrimaryKey: id)
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
