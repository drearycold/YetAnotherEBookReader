#if DEBUG
import Foundation
import RealmSwift

enum UITestingReadingHistoryFixture {
    static var isEnabled: Bool {
        UITestingConfiguration.isEnabled() && ProcessInfo.processInfo.arguments.contains("--ui-testing-history")
    }

    static func seed(book: CalibreBook, position: BookDeviceReadingPosition, configuration: Realm.Configuration) throws {
        guard isEnabled else { return }
        let realm = try Realm(configuration: configuration)
        let now = Date()
        try realm.write {
            realm.delete(realm.objects(BookDeviceReadingPositionHistoryRealm.self).filter("bookId == %@", book.bookPrefId))
            for index in 1...35 {
                let row = BookDeviceReadingPositionHistoryRealm()
                row.bookId = book.bookPrefId
                row.startDatetime = now.addingTimeInterval(-Double(index * 120))
                var end = position
                end.epoch = row.startDatetime.timeIntervalSince1970 + 60
                end.lastReadChapter = String(format: "History Session %02d", index)
                row.endPosition = end.makeRealmObject(bookId: "\(book.bookPrefId) - History")
                realm.add(row)
            }
        }
    }

    @MainActor
    static func update(book: CalibreBook, configuration: Realm.Configuration,
                       repository: BookRepositoryProtocol, manager: CalibreBookManager) throws {
        let realm = try Realm(configuration: configuration)
        if let row = realm.objects(BookDeviceReadingPositionHistoryRealm.self)
            .filter("bookId == %@", book.bookPrefId).sorted(byKeyPath: "startDatetime").first {
            try realm.write {
                row.endPosition?.lastReadChapter = "Updated History Session 35"
                row.endPosition?.epoch += 30
            }
        }
        var changed = book
        changed.title = "Updated History Book"
        repository.saveBook(changed)
        manager.booksInShelf[book.inShelfId] = changed
    }
}
#endif
