import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
final class RealmSearchCacheFreshnessTests: XCTestCase {
    func testLocalSearchAndBookReadsSeeImportMetadataAndDeletion() throws {
        let fixture = try Fixture()
        let library = fixture.library
        let store = fixture.store
        var imported = CalibreBook(id: 456, library: library)
        imported.title = "Imported Book"
        var otherBook = CalibreBook(id: imported.id, library: fixture.otherLibrary)
        otherBook.title = imported.title
        fixture.books.saveBook(otherBook)

        let id = imported.id
        let key = imported.inShelfId
        let criteria = SearchCriteria(searchString: "Imported", sortCriteria: .init(by: .Title),
                                      filterCriteriaCategory: [:])
        let allBooks = SearchCriteria(searchString: "", sortCriteria: criteria.sortCriteria, filterCriteriaCategory: [:])
        XCTAssertEqual(try store.searchLocalLibrary(library: library, criteria: criteria, offset: 0, limit: 10).bookIds, [])

        var entry = CalibreBookEntry()
        entry.title = "Renamed Book"
        entry.publisher = "Updated Publisher"
        let snapshots = try readAcrossCommits(
            configuration: fixture.configuration,
            commits: [
                { fixture.books.saveBook(imported) },
                { try store.writeMetadataEntries(library: library, entries: [id.description: entry], json: nil) },
                { fixture.books.deleteBook(id: key) }
            ],
            readState: { realm in
                realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: key)?.title
            },
            read: { step in
                // Make fetchBooks the first read after the metadata write.
                let updatedBook = step == 1 ? try store.fetchBooks(library: library, bookIds: [id])[id] : nil
                let result = try store.searchLocalLibrary(library: library, criteria: step == 2 ? allBooks : criteria,
                                                          offset: 0, limit: 10)
                let book = step == 1 ? updatedBook : try store.fetchBooks(library: library, bookIds: [id])[id]
                return (result, book)
            }
        )

        XCTAssertEqual(snapshots[0].0.bookIds, [id])
        XCTAssertEqual(snapshots[0].0.totalNumber, 1)
        XCTAssertEqual(snapshots[0].1?.title, "Imported Book")
        XCTAssertEqual(snapshots[1].0.bookIds, [])
        XCTAssertEqual(snapshots[1].0.numBooksWithoutSearch, 1)
        XCTAssertEqual(snapshots[1].1?.title, "Renamed Book")
        XCTAssertEqual(snapshots[1].1?.publisher, "Updated Publisher")
        XCTAssertEqual(snapshots[2].0.numBooksWithoutSearch, 0)
        XCTAssertEqual(snapshots[2].0.bookIds, [])
        XCTAssertNil(snapshots[2].1)
        XCTAssertEqual(try store.fetchBooks(library: fixture.otherLibrary, bookIds: [id])[id]?.title, "Imported Book")
    }

    func testSearchCacheReadsCurrentSourcesAndBookValuesForTheRequestedCriteria() throws {
        let fixture = try Fixture()
        let store = fixture.store
        let library = fixture.library
        let libraryId = library.id
        let otherLibraryId = fixture.otherLibrary.id
        let filters: [String: Set<String>] = ["Tags": ["Fiction"]]
        let otherFilters: [String: Set<String>] = ["Tags": ["History"]]
        // LibrarySearchService replaces dots before using a URL as a Realm Map key.
        let base = "http://calibre_test"
        let alternate = "https://calibre_test"
        let initialGeneration = Date(timeIntervalSince1970: 100)
        let updatedGeneration = Date(timeIntervalSince1970: 200)
        let book = CalibreBook(id: 456, library: fixture.library)
        let key = book.inShelfId
        let initial = LibrarySourceSearchResult(generation: initialGeneration, totalNumber: 1,
                                                bookIds: [book.id], books: [book])
        try store.saveLibrarySourceResult(libraryId: libraryId, search: "story", sortBy: .Title,
                                          sortAsc: true, filters: filters, sourceUrl: base, result: initial)
        try store.saveLibrarySourceResult(libraryId: libraryId, search: "story", sortBy: .Title,
                                          sortAsc: true, filters: filters, sourceUrl: alternate, result: initial)
        try store.saveLibrarySourceResult(libraryId: libraryId, search: "story", sortBy: .Title,
                                          sortAsc: true, filters: otherFilters, sourceUrl: base,
                                          result: .init(totalNumber: 8, bookIds: [21]))
        try store.saveLibrarySourceResult(libraryId: otherLibraryId, search: "story", sortBy: .Title,
                                          sortAsc: true, filters: filters, sourceUrl: base,
                                          result: .init(totalNumber: 9, bookIds: [31]))

        var updatedBook = book
        updatedBook.title = "Updated Story"
        updatedBook.publisher = "New Press"
        let snapshots = try readAcrossCommits(
            configuration: fixture.configuration,
            commits: [
                {
                    fixture.books.saveBook(updatedBook)
                    try store.saveLibrarySourceResult(libraryId: libraryId, search: "story", sortBy: .Title,
                                                      sortAsc: true, filters: filters, sourceUrl: base,
                                                      result: .init(generation: updatedGeneration, totalNumber: 3,
                                                                    bookIds: [book.id]))
                },
                { fixture.books.deleteBook(id: key) }
            ],
            readState: { realm in
                realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: key)?.title
            },
            read: { _ in
                try store.fetchLibraryCachedResult(library: library, search: "story", sortBy: .Title,
                                                   sortAsc: true, filters: filters)
            }
        )

        let updated = try XCTUnwrap(snapshots[0])
        XCTAssertEqual(Set(updated.sources.keys), [base, alternate])
        XCTAssertEqual(updated.filters, filters)
        XCTAssertEqual(updated.sources[base]?.generation, updatedGeneration)
        XCTAssertEqual(updated.sources[base]?.totalNumber, 3)
        XCTAssertEqual(updated.sources[base]?.bookIds, [book.id])
        XCTAssertEqual(updated.sources[base]?.books.first?.title, "Updated Story")
        XCTAssertEqual(updated.sources[base]?.books.first?.publisher, "New Press")
        XCTAssertEqual(updated.sources[alternate]?.generation, initialGeneration)
        XCTAssertEqual(updated.sources[alternate]?.books.first?.title, "Updated Story")
        XCTAssertEqual(snapshots[1]?.sources[base]?.bookIds, [book.id])
        XCTAssertEqual(snapshots[1]?.sources[base]?.books.count, 0)
        XCTAssertEqual(snapshots[1]?.sources[alternate]?.books.count, 0)

        let otherCriteria = try store.fetchLibraryCachedResult(library: library, search: "story",
                                                               sortBy: .Title, sortAsc: true, filters: otherFilters)
        let otherLibrary = try store.fetchLibraryCachedResult(library: fixture.otherLibrary, search: "story",
                                                              sortBy: .Title, sortAsc: true, filters: filters)
        XCTAssertEqual(otherCriteria?.sources[base]?.bookIds, [21])
        XCTAssertEqual(otherLibrary?.sources[base]?.bookIds, [31])
    }

    func testCategoryResultSeesNewGenerationAndItems() throws {
        let result = try readUpdatedCategory { store, libraryId in
            try store.fetchLibraryCategoryResult(libraryId: libraryId, categoryName: "Tags")
        }
        XCTAssertEqual(result?.generation, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(result?.totalNumber, 5)
        XCTAssertEqual(result?.items.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(result?.items.map(\.count), [4, 2])
    }

    func testCategorySummariesSeeAllLibrariesAfterACommit() throws {
        let summaries = try readUpdatedCategory { store, _ in
            (try store.fetchCategorySummaries(), try store.fetchCategorySummaries(libraryIds: []))
        }
        let expected = [CategoryCacheSummary(categoryName: "Tags", itemsCount: 4, totalNumber: 12)]
        XCTAssertEqual(summaries.0, expected)
        XCTAssertEqual(summaries.1, expected)
    }

    func testScopedCategorySummariesSeeTheRequestedLibraryAfterACommit() throws {
        let summaries = try readUpdatedCategory { store, libraryId in
            try store.fetchCategorySummaries(libraryIds: [libraryId])
        }
        XCTAssertEqual(summaries, [CategoryCacheSummary(categoryName: "Tags", itemsCount: 2, totalNumber: 5)])
    }

    func testCategoryPageSeesCurrentItemsAndKeepsLibraryScope() throws {
        let (combined, scoped) = try readUpdatedCategory { store, libraryId in
            let combined = try store.fetchUnifiedCategoryItemsPage(
                categoryName: "Tags", searchString: "a", libraryIds: [], offset: 1, limit: 1
            )
            let scoped = try store.fetchUnifiedCategoryItemsPage(
                categoryName: "Tags", searchString: "a", libraryIds: [libraryId], offset: 0, limit: 2
            )
            return (combined, scoped)
        }
        XCTAssertEqual(combined.totalNumber, 12)
        XCTAssertEqual(combined.itemsCount, 3)
        XCTAssertEqual(combined.items.map(\.name), ["Beta"])
        XCTAssertEqual(combined.items.map(\.count), [2])
        XCTAssertTrue(combined.hasMore)
        XCTAssertEqual(combined.nextOffset, 2)
        XCTAssertEqual(scoped.totalNumber, 5)
        XCTAssertEqual(scoped.items.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(scoped.items.map(\.count), [4, 2])
        XCTAssertFalse(scoped.hasMore)
    }

    func testBookReadCanUseAnActiveWrite() throws {
        let fixture = try Fixture()
        let realm = try XCTUnwrap(fixture.database.realm)
        let book = CalibreBook(id: 456, library: fixture.library)
        realm.beginWrite()
        defer { realm.cancelWrite() }
        realm.add(book.makeRealmObject())

        XCTAssertEqual(try fixture.store.fetchBooks(library: fixture.library, bookIds: [book.id])[book.id]?.id, book.id)
        XCTAssertTrue(realm.isInWriteTransaction)
    }

    func testBookReadCanUseAnImmutableRealm() throws {
        let fixture = try Fixture()
        let book = CalibreBook(id: 456, library: fixture.library)
        fixture.books.saveBook(book)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Books.realm")
        try XCTUnwrap(fixture.database.realm).writeCopy(toFile: file)

        try autoreleasepool {
            let configuration = Realm.Configuration(fileURL: file, readOnly: true, schemaVersion: DatabaseSchema.version)
            let store = RealmSearchCacheStore(config: configuration, databaseService: fixture.database)
            let books = try store.fetchBooks(library: fixture.library, bookIds: [book.id])
            XCTAssertEqual(books[book.id]?.id, book.id)
        }
    }

    func testCacheWithoutConfigurationDoesNotUseTheDefaultRealm() throws {
        let fixture = try Fixture()
        let previousDefault = Realm.Configuration.defaultConfiguration
        Realm.Configuration.defaultConfiguration = fixture.configuration
        defer { Realm.Configuration.defaultConfiguration = previousDefault }

        let library = fixture.library
        let book = CalibreBook(id: 456, library: library)
        fixture.books.saveBook(book)
        let store = RealmSearchCacheStore(databaseService: DatabaseService())
        XCTAssertThrowsError(try store.fetchBooks(library: library, bookIds: [book.id])) {
            XCTAssertEqual($0 as? CacheContextError, .databaseUnavailable)
        }
        XCTAssertThrowsError(try store.fetchCategorySummaries()) {
            XCTAssertEqual($0 as? CacheContextError, .databaseUnavailable)
        }
        XCTAssertThrowsError(try store.saveLibrarySourceResult(
            libraryId: library.id, search: "sentinel", sortBy: .Title, sortAsc: true,
            filters: [:], sourceUrl: "source", result: .init(totalNumber: 1, bookIds: [book.id])
        )) { XCTAssertEqual($0 as? CacheContextError, .databaseUnavailable) }
        XCTAssertEqual(fixture.database.realm?.objects(CalibreLibrarySearchObject.self).count, 0)
    }

    func testStaleSourcePreflightDoesNotSkipARequiredSave() throws {
        let fixture = try Fixture()
        let store = fixture.store
        let library = fixture.library
        let save: @Sendable ([Int32]) throws -> Void = { ids in
            try store.saveLibrarySourceResult(
                libraryId: library.id, search: "story", sortBy: .Title, sortAsc: true,
                filters: [:], sourceUrl: "source", result: .init(totalNumber: ids.count, bookIds: ids)
            )
        }
        try save([1])

        let results = try readAcrossCommits(
            configuration: fixture.configuration,
            commits: [{ try save([2]) }],
            readState: { realm in
                guard let source = realm.objects(CalibreLibrarySearchObject.self).first?.sources["source"] ?? nil
                else { return [Int32]() }
                return Array(source.bookIds)
            },
            read: { _ in
                try save([1])
                return try store.fetchLibraryCachedResult(
                    library: library, search: "story", sortBy: .Title, sortAsc: true, filters: [:]
                )?.sources["source"]?.bookIds
            }
        )
        XCTAssertEqual(results[0], [1])
    }

    func testStaleSourcePreflightDoesNotDuplicateACriteriaRow() throws {
        let fixture = try Fixture()
        let store = fixture.store
        let library = fixture.library
        let save: @Sendable (String) throws -> Void = { source in
            try store.saveLibrarySourceResult(
                libraryId: library.id, search: "story", sortBy: .Title, sortAsc: true,
                filters: ["Tags": ["Fiction"]], sourceUrl: source, result: .init(totalNumber: 1, bookIds: [1])
            )
        }

        _ = try readAcrossCommits(
            configuration: fixture.configuration,
            commits: [{ try save("base") }],
            readState: { realm in realm.objects(CalibreLibrarySearchObject.self).count },
            read: { _ in try save("public") }
        )
        let realm = try XCTUnwrap(fixture.database.realm)
        realm.refresh()
        let rows = realm.objects(CalibreLibrarySearchObject.self)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(Set(try XCTUnwrap(rows.first).sources.keys), ["base", "public"])
    }

    func testOldSearchAnswerDoesNotOverwriteAnotherCommitOrRecreateTheSource() throws {
        let fixture = try Fixture()
        let library = fixture.library
        let store = fixture.store
        let scoped = try store.scoped(to: library, lifetime: nil)
        let initial = LibrarySourceSearchResult(generation: Date(timeIntervalSince1970: 1), totalNumber: 1, bookIds: [1])
        let newer = LibrarySourceSearchResult(generation: Date(timeIntervalSince1970: 2), totalNumber: 1, bookIds: [2])
        let late = LibrarySourceSearchResult(generation: initial.generation, totalNumber: 1, bookIds: [3])
        try store.saveLibrarySourceResult(libraryId: library.id, search: "story", sortBy: .Title, sortAsc: true,
                                          filters: [:], sourceUrl: "base", result: initial)

        let errors: [CacheContextError?] = try readAcrossCommits(
            configuration: fixture.configuration,
            commits: [
                {
                    try store.saveLibrarySourceResult(libraryId: library.id, search: "story", sortBy: .Title,
                                                      sortAsc: true, filters: [:], sourceUrl: "base", result: newer)
                },
                {
                    let realm = try XCTUnwrap(fixture.database.realm)
                    try realm.write { realm.delete(realm.objects(CalibreLibrarySearchObject.self)) }
                }
            ],
            readState: { realm in
                (realm.objects(CalibreLibrarySearchObject.self).first?.sources["base"] ?? nil)?.generation
            },
            read: { _ in
                do {
                    try scoped.saveLibrarySourceResult(libraryId: library.id, search: "story", sortBy: .Title,
                                                       sortAsc: true, filters: [:], sourceUrl: "base", result: late,
                                                       expecting: .previous(initial.sourceState))
                    return nil
                } catch let error as CacheContextError { return error }
            }
        )
        XCTAssertEqual(errors, [.superseded, .superseded])
        XCTAssertNil(try store.fetchLibraryCachedResult(library: library, search: "story", sortBy: .Title,
                                                        sortAsc: true, filters: [:]))
    }

    func testOldCategoryAnswerAndMetadataDoNotReplaceNewerCommittedValues() throws {
        let fixture = try Fixture()
        let library = fixture.library
        let store = fixture.store
        let scoped = try store.scoped(to: library, lifetime: nil)
        let category = LibraryCategoryResult(libraryId: library.id, categoryName: "Tags", items: [],
                                             generation: Date(timeIntervalSince1970: 2), totalNumber: 1)
        let lateCategory = LibraryCategoryResult(libraryId: library.id, categoryName: "Tags", items: [],
                                                 generation: Date(timeIntervalSince1970: 1), totalNumber: 0)
        var newer = CalibreBookEntry()
        newer.title = "Current"
        newer.last_modified = "2026-01-02T00:00:00+00:00"
        var older = newer
        older.title = "Late"
        older.last_modified = "2026-01-01T00:00:00+00:00"
        let late = older
        let key = CalibreBook(id: 456, library: library).inShelfId

        let results = try readAcrossCommits(
            configuration: fixture.configuration,
            commits: [{
                try store.saveLibraryCategoryResult(libraryId: library.id, categoryName: "Tags", result: category)
                try store.writeMetadataEntries(library: library, entries: ["456": newer], json: nil)
            }],
            readState: { realm in realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: key)?.title },
            read: { _ in
                let conflict: CacheContextError?
                do {
                    try scoped.saveLibraryCategoryResult(libraryId: library.id, categoryName: "Tags",
                                                         result: lateCategory, expecting: .previous(nil))
                    conflict = nil
                } catch let error as CacheContextError { conflict = error }
                try scoped.writeMetadataEntries(library: library, entries: ["456": late], json: nil)
                return (conflict, try scoped.fetchBooks(library: library, bookIds: [456])[456]?.title)
            }
        )
        XCTAssertEqual(results[0].0, .superseded)
        XCTAssertEqual(results[0].1, "Current")
        XCTAssertEqual(try store.fetchLibraryCategoryResult(libraryId: library.id, categoryName: "Tags"), category)
    }

    func testLibraryRecreationRejectsOldMetadataAndSearchWrites() throws {
        let fixture = try Fixture()
        let library = fixture.library
        let store = fixture.store
        let scoped = try store.scoped(to: library, lifetime: nil)
        let key = library.id
        let results = try readAcrossCommits(
            configuration: fixture.configuration,
            commits: [{
                let realm = try XCTUnwrap(fixture.database.realm)
                let row = try XCTUnwrap(realm.object(ofType: CalibreLibraryRealm.self, forPrimaryKey: key))
                try realm.write {
                    realm.delete(row)
                    realm.add(library.makeRealmObject())
                }
            }],
            readState: { realm in realm.object(ofType: CalibreLibraryRealm.self, forPrimaryKey: key)?.id },
            read: { _ in
                let book = CalibreBook(id: 456, library: library)
                let changes: [() throws -> Void] = [
                    { try scoped.writeMetadataEntries(library: library, entries: ["456": CalibreBookEntry()], json: nil) },
                    {
                        try scoped.saveLibrarySourceResult(
                            libraryId: key, search: "", sortBy: .Title, sortAsc: true, filters: [:], sourceUrl: "base",
                            result: .init(totalNumber: 1, bookIds: [book.id], books: [book]), expecting: .previous(nil)
                        )
                    }
                ]
                return try changes.map { change -> CacheContextError? in
                    do { try change(); return nil }
                    catch let error as CacheContextError { return error }
                }
            }
        )
        XCTAssertEqual(results[0], [.superseded, .superseded])
        XCTAssertTrue(try store.fetchBooks(library: library, bookIds: [456]).isEmpty)
        XCTAssertNil(try store.fetchLibraryCachedResult(library: library, search: "", sortBy: .Title,
                                                        sortAsc: true, filters: [:]))
    }

    func testSearchCacheMapsEachServerUsingTheCapturedLibraryValue() throws {
        let fixture = try Fixture()
        let store = fixture.store
        let first = fixture.library
        let second = TestFixtures.makeLibrary(server: TestFixtures.makeServer(), key: first.key, name: first.name)
        for (library, title) in [(first, "First book"), (second, "Second book")] {
            var book = CalibreBook(id: 456, library: library)
            book.title = title
            try store.saveLibrarySourceResult(libraryId: library.id, search: "", sortBy: .Title, sortAsc: true,
                                              filters: [:], sourceUrl: "source",
                                              result: .init(totalNumber: 1, bookIds: [book.id], books: [book]))
        }
        let cache = try store.snapshot()
        let firstBook = try cache.fetchLibraryCachedResult(
            library: first, search: "", sortBy: .Title, sortAsc: true, filters: [:]
        )?.sources["source"]?.books.first
        var capturedSecond = second
        capturedSecond.server.name = "Captured server name"
        let secondBook = try cache.fetchLibraryCachedResult(
            library: capturedSecond, search: "", sortBy: .Title, sortAsc: true, filters: [:]
        )?.sources["source"]?.books.first
        XCTAssertEqual(firstBook?.title, "First book")
        XCTAssertEqual(secondBook?.title, "Second book")
        XCTAssertEqual(secondBook?.library.server.uuid, second.server.uuid)
        XCTAssertEqual(secondBook?.library.server.name, "Captured server name")
    }

    private func readUpdatedCategory<Value: Sendable>(
        read: @escaping @Sendable (RealmSearchCacheStore, String) throws -> Value
    ) throws -> Value {
        let fixture = try Fixture()
        let store = fixture.store
        let libraryId = fixture.library.id
        let otherLibraryId = fixture.otherLibrary.id
        func save(_ libraryId: String, generation: TimeInterval, total: Int, items: [(String, Int)]) throws {
            try store.saveLibraryCategoryResult(
                libraryId: libraryId, categoryName: "Tags",
                result: LibraryCategoryResult(
                    libraryId: libraryId, categoryName: "Tags",
                    items: items.map { LibraryCategoryItem(name: $0.0, averageRating: 0, count: $0.1,
                                                          url: "http://calibre.test/\(libraryId)/\($0.0)") },
                    generation: Date(timeIntervalSince1970: generation), totalNumber: total
                )
            )
        }

        try save(libraryId, generation: 100, total: 1, items: [("Alpha", 1)])
        try save(otherLibraryId, generation: 100, total: 7, items: [("Alpha", 6), ("Gamma", 1)])
        let results = try readAcrossCommits(
            configuration: fixture.configuration,
            commits: [{ try save(libraryId, generation: 200, total: 5, items: [("Alpha", 4), ("Beta", 2)]) }],
            readState: { realm in
                realm.objects(CalibreLibraryCategoryObject.self)
                    .filter("libraryId == %@ AND categoryName == %@", libraryId, "Tags").first?.generation
            },
            read: { _ in try read(store, libraryId) }
        )
        return results[0]
    }

    private final class Fixture: LibraryResolver {
        let database = DatabaseService()
        let configuration = Realm.Configuration(inMemoryIdentifier: UUID().uuidString, schemaVersion: DatabaseSchema.version)
        let library: CalibreLibrary
        let otherLibrary: CalibreLibrary
        let calibreLibraries: [String: CalibreLibrary]
        lazy var store = RealmSearchCacheStore(databaseService: database)
        lazy var books = RealmBookRepository(databaseService: database, libraryResolver: self)

        init() throws {
            let server = TestFixtures.makeServer(baseUrl: ".")
            library = TestFixtures.makeLibrary(server: server, key: "local", name: "Local Fixture")
            otherLibrary = TestFixtures.makeLibrary(server: server, key: "other", name: "Other Fixture")
            calibreLibraries = [library.id: library, otherLibrary.id: otherLibrary]
            try database.openMainRealm(conf: configuration)
            let realm = try XCTUnwrap(database.realm)
            try realm.write {
                realm.add(server.makeRealmObject())
                realm.add(library.makeRealmObject())
                realm.add(otherLibrary.makeRealmObject())
            }
        }

        func library(forServerUUID serverUUID: String, libraryName: String) -> CalibreLibrary? {
            calibreLibraries[CalibreLibrary.identity(serverUUID: serverUUID, libraryName: libraryName)]
        }
    }

    private enum ReadEvent<State: Sendable, Value: Sendable>: Sendable {
        case ready(State)
        case read(stale: State, value: Value)
    }

    private enum FixtureError: Error {
        case commitTimedOut
        case readTimedOut
        case unexpectedEvent
    }

    private final class ReadEvents<Event: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private let available = DispatchSemaphore(value: 0)
        private var pending: [Result<Event, Error>] = []

        func send(_ event: Result<Event, Error>) {
            lock.withLock { pending.append(event) }
            available.signal()
        }

        func next() throws -> Event {
            guard available.wait(timeout: .now() + 10) == .success else { throw FixtureError.readTimedOut }
            return try lock.withLock { pending.removeFirst() }.get()
        }
    }

    private func readAcrossCommits<State: Equatable & Sendable, Value: Sendable>(
        configuration: Realm.Configuration,
        commits: [() throws -> Void],
        readState: @escaping @Sendable (Realm) throws -> State,
        read: @escaping @Sendable (Int) throws -> Value
    ) throws -> [Value] {
        let committed = DispatchSemaphore(value: 0)
        let stopped = DispatchSemaphore(value: 0)
        let steps = commits.indices
        let events = ReadEvents<ReadEvent<State, Value>>()
        let worker = Thread {
            defer { stopped.signal() }
            autoreleasepool {
                do {
                    let held = try Realm(configuration: configuration)
                    for step in steps {
                        // Establish a fresh baseline for the next independent commit on this same thread.
                        if step > 0 { held.refresh() }
                        events.send(.success(.ready(try readState(held))))
                        guard committed.wait(timeout: .now() + 10) == .success else {
                            throw FixtureError.commitTimedOut
                        }
                        if Thread.current.isCancelled { break }
                        let stale = try readState(held)
                        events.send(.success(.read(stale: stale, value: try read(step))))
                    }
                } catch {
                    events.send(.failure(error))
                }
            }
        }
        worker.start()
        defer {
            worker.cancel()
            committed.signal()
            XCTAssertEqual(stopped.wait(timeout: .now() + 10), .success, "Fixed read thread did not stop")
        }

        var values: [Value] = []
        for commit in commits {
            guard case .ready(let before) = try events.next() else { throw FixtureError.unexpectedEvent }
            try autoreleasepool {
                let writer = try Realm(configuration: configuration)
                XCTAssertEqual(try readState(writer), before)
                try commit()
                XCTAssertFalse(writer.isInWriteTransaction)
                XCTAssertNotEqual(try readState(writer), before, "Writer must commit a different value")
            }
            committed.signal()
            guard case let .read(stale, value) = try events.next() else { throw FixtureError.unexpectedEvent }
            XCTAssertEqual(stale, before, "The held Realm must still be stale before the repository call")
            values.append(value)
        }
        return values
    }
}
