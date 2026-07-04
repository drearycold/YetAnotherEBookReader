//
//  ActivityLogRepositoryTests.swift
//  YetAnotherEBookReaderTests
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

final class ActivityLogRepositoryTests: XCTestCase {
    private var databaseService: DatabaseService!
    private var bookRepository: MockBookRepository!
    private var librarySnapshotProvider: MockCalibreLibrarySnapshotProvider!
    private var repository: RealmActivityLogRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        databaseService = DatabaseService()
        bookRepository = MockBookRepository()
        librarySnapshotProvider = MockCalibreLibrarySnapshotProvider()
        let config = MockDatabaseService.inMemoryConfiguration(
            identifier: "ActivityLogRepositoryTests-\(UUID().uuidString)"
        )
        databaseService.installTestConfiguration(config)
        repository = RealmActivityLogRepository(
            databaseService: databaseService,
            bookRepository: bookRepository,
            container: nil
        )
    }

    override func tearDownWithError() throws {
        repository = nil
        librarySnapshotProvider = nil
        bookRepository = nil
        databaseService = nil
        try super.tearDownWithError()
    }

    func testWriteStartAndFinishEventsPersistsEntry() async throws {
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let finishDate = Date(timeIntervalSince1970: 1_700_000_005)
        var request = URLRequest(url: URL(string: "http://calibre.local/ajax/books")!)
        request.httpMethod = "POST"
        request.httpBody = Data("payload".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        await repository.writeActivityLogEvents([
            .start(
                ActivityLogStartValue(
                    type: "Sync",
                    request: ActivityLogRequestSnapshot(request: request),
                    startDatetime: startDate,
                    bookId: 7,
                    libraryId: "library-id"
                )
            ),
            .finish(
                ActivityLogFinishValue(
                    type: "Sync",
                    request: ActivityLogRequestSnapshot(request: request),
                    startDatetime: startDate,
                    finishDatetime: finishDate,
                    errMsg: "Success"
                )
            )
        ])

        let entries = repository.fetchEntries(libraryId: "library-id", bookId: 7, since: .distantPast)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.type, "Sync")
        XCTAssertEqual(entries.first?.errMsg, "Success")
        XCTAssertEqual(entries.first?.endpointURL, "http://calibre.local/ajax/books")
        XCTAssertEqual(entries.first?.httpMethod, "POST")
        XCTAssertEqual(entries.first?.httpBodyString, "payload")
    }

    func testFetchEntriesMapsBookTitleThroughBookRepositoryLibraryLookup() async throws {
        let config = MockDatabaseService.inMemoryConfiguration(
            identifier: "ActivityLogRepositoryMappingTests-\(UUID().uuidString)"
        )
        databaseService.installTestConfiguration(config)

        let library = TestFixtures.makeLibrary()
        var book = TestFixtures.makeBook(id: 42, library: library)
        book.title = "Mapped Activity Book"
        librarySnapshotProvider.calibreLibraries = [library.id: library]
        bookRepository.getBookReturn = book
        repository = RealmActivityLogRepository(
            databaseService: databaseService,
            bookRepository: bookRepository,
            librarySnapshotProvider: librarySnapshotProvider
        )

        let request = URLRequest(url: URL(string: "http://calibre.local/ajax/books")!)
        await repository.writeActivityLogEvents([
            .start(
                ActivityLogStartValue(
                    type: "Metadata",
                    request: ActivityLogRequestSnapshot(request: request),
                    startDatetime: Date(timeIntervalSince1970: 1_700_000_010),
                    bookId: book.id,
                    libraryId: library.id
                )
            )
        ])

        let entries = repository.fetchEntries(libraryId: library.id, bookId: book.id, since: .distantPast)

        XCTAssertEqual(entries.first?.libraryName, library.name)
        XCTAssertEqual(entries.first?.bookTitle, "Mapped Activity Book")
        XCTAssertEqual(bookRepository.getBookLibraryParam, library)
        XCTAssertEqual(bookRepository.getBookBookIdParam, book.id)
    }

    func testDeleteAndCleanUseRepositoryBoundary() async throws {
        let oldDate = Date(timeIntervalSince1970: 1_600_000_000)
        let newDate = Date(timeIntervalSince1970: 1_700_000_000)
        let request = URLRequest(url: URL(string: "http://calibre.local/ajax/books")!)

        await repository.writeActivityLogEvents([
            .start(
                ActivityLogStartValue(
                    type: "Old",
                    request: ActivityLogRequestSnapshot(request: request),
                    startDatetime: oldDate,
                    bookId: nil,
                    libraryId: nil
                )
            ),
            .start(
                ActivityLogStartValue(
                    type: "New",
                    request: ActivityLogRequestSnapshot(request: request),
                    startDatetime: newDate,
                    bookId: nil,
                    libraryId: nil
                )
            )
        ])

        var entries = repository.fetchEntries(libraryId: nil, bookId: nil, since: .distantPast)
        XCTAssertEqual(entries.count, 2)

        let newEntry = try XCTUnwrap(entries.first { $0.type == "New" })
        await repository.removeCalibreActivity(id: newEntry.id)
        entries = repository.fetchEntries(libraryId: nil, bookId: nil, since: .distantPast)
        XCTAssertEqual(entries.map(\.type), ["Old"])

        await repository.cleanCalibreActivities(startDatetime: Date(timeIntervalSince1970: 1_650_000_000))
        entries = repository.fetchEntries(libraryId: nil, bookId: nil, since: .distantPast)
        XCTAssertTrue(entries.isEmpty)
    }
}

private final class MockCalibreLibrarySnapshotProvider: CalibreLibrarySnapshotProviding {
    var calibreLibraries: [String: CalibreLibrary] = [:]
}
