//
//  CalibreLibraryManagerTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-23.
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

// The managers' state is main-thread state. Without this, the async tests run on
// the cooperative pool and race the managers' main-queue writes.
@MainActor
final class CalibreLibraryManagerTests: XCTestCase {
    private var container: AppContainer!
    private var libraryManager: CalibreLibraryManager!
    private var library: CalibreLibrary!
    private var server: CalibreServer!
    private var databaseService: DatabaseService!
    private var libraryRepository: LibraryRepositoryProtocol!

    override func setUpWithError() throws {
        // Set up in-memory Realm configuration to isolate each test
        container = MockAppContainerFactory.makeContainer(testName: "CalibreLibraryManagerTests")
        
        libraryManager = container.libraryManager
        databaseService = container.databaseService
        libraryRepository = container.libraryRepository
        
        server = CalibreServer(
            uuid: UUID(),
            name: "Test Calibre Server",
            baseUrl: "http://localhost",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        container.serverManager.calibreServers[server.id] = server
        try? container.serverManager.saveServer(server: server)
        
        library = CalibreLibrary(server: server, key: "test_lib", name: "Test Library")
        libraryManager.calibreLibraries[library.id] = library
        try? libraryRepository.saveLibrary(library)
        
        XCTAssertNotNil(server, "Mock server should be populated")
        XCTAssertNotNil(library, "Mock library should be populated")
    }

    override func tearDownWithError() throws {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        container = nil
        libraryManager = nil
        library = nil
        server = nil
        databaseService = nil
        libraryRepository = nil
        AppContainer.shared = nil
    }

    func testPopulateLibraries() throws {
        // Create a new mock library in repository
        let newLib = CalibreLibrary(server: server, key: "new_lib", name: "New Library")
        try libraryRepository.saveLibrary(newLib)
        
        // Clear in-memory dictionary
        libraryManager.calibreLibraries.removeAll()
        
        // Populate
        libraryManager.populateLibraries()
        
        // Assert
        XCTAssertNotNil(libraryManager.calibreLibraries[newLib.id])
        XCTAssertEqual(libraryManager.calibreLibraries[newLib.id]?.name, "New Library")
    }

    func testUpdateLibraryRealm() throws {
        var lib = library!
        lib.name = "Updated Library Name"
        
        try libraryManager.saveLibrary(library: lib)
        
        let allLibs = libraryRepository.getAllLibraries()
        let updated = allLibs.first { $0.id == lib.id }
        XCTAssertNotNil(updated)
        XCTAssertEqual(updated?.name, "Updated Library Name")
    }

    func testHideAndRestoreLibrary() throws {
        let libId = library.id
        
        // Hide
        libraryManager.hideLibrary(libraryId: libId)
        
        XCTAssertTrue(libraryManager.calibreLibraries[libId]?.hidden ?? false)
        
        // Verify in repository
        let allLibs = libraryRepository.getAllLibraries()
        let hiddenLib = allLibs.first { $0.id == libId }
        XCTAssertTrue(hiddenLib?.hidden ?? false)
        
        // Restore
        libraryManager.restoreLibrary(libraryId: libId)
        
        XCTAssertFalse(libraryManager.calibreLibraries[libId]?.hidden ?? true)
        XCTAssertEqual(libraryManager.calibreLibraries[libId]?.lastModified, Date(timeIntervalSince1970: 0))
        
        // Verify in repository
        let restoredLib = libraryRepository.getAllLibraries().first { $0.id == libId }
        XCTAssertFalse(restoredLib?.hidden ?? true)
    }

    func testQueryLibraryBookRealmCount() throws {
        let book = CalibreBook(id: 999, library: library)
        container.bookManager.updateBook(book: book)
        
        let count = libraryManager.queryLibraryBookRealmCount(library: library)
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    func testUpdateServerLibraryInfo() throws {
        let probeRequest = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false)
        
        let libraryMap = [
            "existingKey": "Updated Library Name",
            "newKey": "New Remote Library"
        ]
        
        let serverInfo = CalibreServerInfo(
            server: server,
            isPublic: false,
            url: URL(string: "http://localhost")!,
            reachable: true,
            probing: false,
            errorMsg: "",
            defaultLibrary: "existingKey",
            libraryMap: libraryMap,
            request: probeRequest
        )
        
        let existingLib = CalibreLibrary(server: server, key: "existingKey", name: "Old Name")
        libraryManager.calibreLibraries[existingLib.id] = existingLib
        try libraryRepository.saveLibrary(existingLib)
        
        libraryManager.updateServerLibraryInfo(serverInfo: serverInfo)
        
        XCTAssertEqual(libraryManager.calibreLibraries[existingLib.id]?.key, "existingKey")
        
        let newLibId = CalibreLibrary(server: server, key: "newKey", name: "New Remote Library").id
        XCTAssertNotNil(libraryManager.calibreLibraries[newLibId])
        XCTAssertEqual(libraryManager.calibreLibraries[newLibId]?.name, "New Remote Library")
    }

    func testProbeLibrarySuccess() async throws {
        let probeRequest = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false)
        let info = CalibreServerInfo(server: server, isPublic: false, url: URL(string: "http://localhost")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: library.id, libraryMap: [library.id: library.name], request: probeRequest)
        container.calibreServerInfoStaging = [server.uuid.uuidString: info]
        
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        
        for timeout in [10.0, 600.0] {
            for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
                let key = CalibreServerURLSessionKey(server: server, timeout: timeout, qos: qos)
                container.calibreServerService.metadataSessions[key] = mockSession
            }
        }
        
        let jsonResponse = """
        {
            "total_num": 42,
            "sort_order": "asc",
            "num_books_without_search": 0,
            "offset": 0,
            "num": 0,
            "sort": "title",
            "base_url": "/ajax/search/test_lib",
            "query": "",
            "library_id": "test_lib",
            "book_ids": [],
            "vl": ""
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, jsonResponse.data(using: .utf8)!)
        }
        
        let req = CalibreProbeLibraryRequest(library: library)
        let task = await libraryManager.probeLibrary(request: req)
        
        XCTAssertEqual(task.probeResult?.total_num, 42)
        
        let stagingInfo = libraryManager.calibreLibraryInfoStaging[library.id]
        XCTAssertNotNil(stagingInfo)
        XCTAssertEqual(stagingInfo?.totalNumber, 42)
        XCTAssertEqual(stagingInfo?.errorMessage, "Success")
    }

    func testProbeLibraryFailure() async throws {
        let probeRequest = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false)
        let info = CalibreServerInfo(server: server, isPublic: false, url: URL(string: "http://localhost")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: library.id, libraryMap: [library.id: library.name], request: probeRequest)
        container.calibreServerInfoStaging = [server.uuid.uuidString: info]
        
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        
        for timeout in [10.0, 600.0] {
            for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
                let key = CalibreServerURLSessionKey(server: server, timeout: timeout, qos: qos)
                container.calibreServerService.metadataSessions[key] = mockSession
            }
        }
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        
        let req = CalibreProbeLibraryRequest(library: library)
        let task = await libraryManager.probeLibrary(request: req)
        
        XCTAssertNil(task.probeResult)
        
        let stagingInfo = libraryManager.calibreLibraryInfoStaging[library.id]
        XCTAssertNotNil(stagingInfo)
        XCTAssertEqual(stagingInfo?.totalNumber, 0)
        XCTAssertEqual(stagingInfo?.errorMessage, "Failed")
    }

    func testRemoveLibrary() async throws {
        var book = CalibreBook(id: 777, library: library)
        book.inShelf = true
        container.bookManager.updateBook(book: book)
        container.bookManager.booksInShelf[book.inShelfId] = book
        
        try libraryRepository.saveLibrary(library)
        
        let dbLibBefore = libraryRepository.getAllLibraries().first { $0.id == library.id }
        XCTAssertNotNil(dbLibBefore)
        
        await libraryManager.removeLibrary(library: library)
        
        let dbLibAfter = libraryRepository.getAllLibraries().first { $0.id == library.id }
        XCTAssertNil(dbLibAfter)
        
        XCTAssertNil(container.bookManager.booksInShelf[book.inShelfId])
        XCTAssertFalse(libraryManager.librarySyncStatus[library.id]?.isSync ?? true)
    }

    /// A newer `last_modified` moves the library's generation, which the search and category caches
    /// compare theirs with: the library is saved and published.
    func testSyncLibraryPublishesAndSavesANewerLibrary() async throws {
        library.lastModified = Date(timeIntervalSince1970: 0)
        libraryManager.calibreLibraries[library.id] = library
        try libraryRepository.saveLibrary(library)
        configureReachableMockSession()
        let requests = MockURLProtocol.answer(Self.syncAnswers())

        let published = expectation(description: "the newer library is published")
        let updates = container.calibreUpdates()
        let observer = Task { @MainActor [libraryId = library.id] in
            for await update in updates {
                if case .library(let updatedLibrary) = update, updatedLibrary.id == libraryId {
                    XCTAssertEqual(updatedLibrary.lastModified, parseLastModified(Self.newestChange))
                    published.fulfill()
                    return
                }
            }
        }

        await libraryManager.syncLibrary(request: CalibreSyncLibraryRequest(library: library))

        await fulfillment(of: [published], timeout: 5.0)
        observer.cancel()
        XCTAssertEqual(requests.unexpected, [])
        let saved = try XCTUnwrap(libraryRepository.getLibrary(id: library.id))
        XCTAssertEqual(saved.lastModified, parseLastModified(Self.newestChange))
        XCTAssertEqual(saved.customColumnInfos["read_progress"]?.datatype, "int")
    }

    /// A sync reads the library's summary and categories, and nothing else: no book list.
    func testSyncLibraryReadsTheSummaryAndTheCategories() async throws {
        configureReachableMockSession()
        let requests = MockURLProtocol.answer(Self.syncAnswers())

        await libraryManager.syncLibrary(request: CalibreSyncLibraryRequest(library: library))

        XCTAssertEqual(requests.unexpected, [])
        XCTAssertEqual(
            Set(requests.answered),
            ["/ajax/search/test_lib", "/ajax/books/test_lib", "/ajax/categories/test_lib"]
        )
        let syncStatus = try XCTUnwrap(libraryManager.librarySyncStatus[library.id])
        XCTAssertFalse(syncStatus.isSync)
        XCTAssertFalse(syncStatus.isError)
        XCTAssertEqual(syncStatus.msg, "Success")
        XCTAssertEqual(syncStatus.cnt, 12)
        XCTAssertEqual(syncStatus.del, [])

        let columns = try XCTUnwrap(libraryManager.calibreLibraries[library.id]?.customColumnInfos)
        XCTAssertEqual(columns["read_progress"]?.name, "Read progress")
    }

    func testSyncLibraryRefreshesChangedCategoriesWithUpdatedGenerationAndPrunesDeletedCategories() async throws {
        let oldLastModified = Date(timeIntervalSince1970: 100)
        library.lastModified = oldLastModified
        libraryManager.calibreLibraries[library.id] = library
        try libraryRepository.saveLibrary(library)
        configureReachableMockSession()

        try container.categoryCacheRepository.saveLibraryCategoryResult(
            libraryId: library.id,
            categoryName: "Authors",
            result: LibraryCategoryResult(
                libraryId: library.id,
                categoryName: "Authors",
                items: [LibraryCategoryItem(name: "Old Author", averageRating: 1.0, count: 1, url: "old-author")],
                generation: oldLastModified,
                totalNumber: 1
            )
        )
        try container.categoryCacheRepository.saveLibraryCategoryResult(
            libraryId: library.id,
            categoryName: "Publisher",
            result: LibraryCategoryResult(
                libraryId: library.id,
                categoryName: "Publisher",
                items: [LibraryCategoryItem(name: "Removed Publisher", averageRating: 0.0, count: 1, url: "removed-publisher")],
                generation: oldLastModified,
                totalNumber: 1
            )
        )

        let requests = MockURLProtocol.answer(Self.syncAnswers(categories: """
        [
            {"name": "Authors", "url": "/ajax/category/Authors", "icon": "author", "is_category": true},
            {"name": "Tags", "url": "/ajax/category/Tags", "icon": "tag", "is_category": true}
        ]
        """, categoryItems: [
            "/ajax/category/Authors": Self.categoryItemsJSON(name: "Authors", items: [
                #"{"name": "New Author", "average_rating": 4.5, "count": 7, "url": "new-author", "has_children": false}"#
            ]),
            "/ajax/category/Tags": Self.categoryItemsJSON(name: "Tags", items: [
                #"{"name": "New Tag", "average_rating": 0.0, "count": 2, "url": "new-tag", "has_children": false}"#
            ])
        ]))

        await libraryManager.syncLibrary(
            request: CalibreSyncLibraryRequest(library: library)
        )

        // The category service writes from its own actor, and the main thread's Realm
        // sees those writes only after it refreshes on a run loop turn.
        let authors = try await waitForCachedCategory(named: "Authors") { result in
            result.items.map(\.name) == ["New Author"]
        }
        XCTAssertGreaterThan(authors.generation, oldLastModified)
        XCTAssertEqual(authors.items.map(\.name), ["New Author"])
        XCTAssertEqual(authors.items.first?.count, 7)

        let tags = try await waitForCachedCategory(named: "Tags") { result in
            result.items.map(\.name) == ["New Tag"]
        }
        XCTAssertEqual(tags.items.map(\.name), ["New Tag"])
        XCTAssertNil(
            try container.categoryCacheRepository.fetchLibraryCategoryResult(
                libraryId: library.id,
                categoryName: "Publisher"
            )
        )
        XCTAssertEqual(requests.unexpected, [])
    }

    /// A summary that didn't arrive says so, and changes nothing: no date, no count, and no book is
    /// taken for deleted.
    func testAFailedSummaryIsReportedAndChangesNothing() async throws {
        let oldLastModified = Date(timeIntervalSince1970: 100)
        library.lastModified = oldLastModified
        libraryManager.calibreLibraries[library.id] = library
        try libraryRepository.saveLibrary(library)
        configureReachableMockSession()
        var answers = Self.syncAnswers()
        answers.removeValue(forKey: "/ajax/search/test_lib")
        _ = MockURLProtocol.answer(answers)

        await libraryManager.syncLibrary(request: CalibreSyncLibraryRequest(library: library))

        let syncStatus = try XCTUnwrap(libraryManager.librarySyncStatus[library.id])
        XCTAssertFalse(syncStatus.isSync)
        XCTAssertTrue(syncStatus.isError)
        XCTAssertNotEqual(syncStatus.msg, "Success")
        XCTAssertNil(syncStatus.cnt)
        XCTAssertEqual(syncStatus.del, [])
        XCTAssertEqual(libraryManager.calibreLibraries[library.id]?.lastModified, oldLastModified)
    }

    /// calibre answers null for a book it no longer has. Settings lists it, but its record (here
    /// a shelf book's) stays; once calibre has it again, it's no longer listed.
    func testABookCalibreAnswersNullForIsListedNotRemoved() async throws {
        configureReachableMockSession()
        for id: Int32 in [101, 102] {
            var book = CalibreBook(id: id, library: library)
            book.inShelf = true
            container.bookManager.updateBook(book: book)
        }
        var answers = ["/ajax/books/test_lib": #"{"101": \#(Self.bookEntryJSON(title: "Kept")), "102": null}"#]
        _ = MockURLProtocol.answer(answers)

        await container.bookManager.getBooksMetadata(request: .init(library: library, books: [101, 102], getAnnotations: false))

        XCTAssertEqual(libraryManager.librarySyncStatus[library.id]?.del, [102])
        XCTAssertTrue(container.bookManager.bookExists(forPrimaryKey: CalibreBook(id: 102, library: library).inShelfId))

        answers["/ajax/books/test_lib"] = #"{"102": \#(Self.bookEntryJSON(title: "Back"))}"#
        _ = MockURLProtocol.answer(answers)

        await container.bookManager.getBooksMetadata(request: .init(library: library, books: [102], getAnnotations: false))

        XCTAssertEqual(libraryManager.librarySyncStatus[library.id]?.del, [])
    }

    func testPopulateLocalLibraryBooksWithFiles() throws {
        guard let documentDirectoryURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            XCTFail("Failed to get document directory")
            return
        }
        let localLibraryURL = documentDirectoryURL.appendingPathComponent("Local Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: localLibraryURL, withIntermediateDirectories: true)
        
        let testBookFile = localLibraryURL.appendingPathComponent("TestBook.epub")
        try? "EPUB Content".write(to: testBookFile, atomically: true, encoding: .utf8)
        
        var completionCount = 0
        var completionWasOnMainThread = false
        libraryManager.populateLocalLibraryBooks {
            completionCount += 1
            completionWasOnMainThread = Thread.isMainThread
        }

        XCTAssertNotNil(libraryManager.localLibrary)
        XCTAssertEqual(libraryManager.localLibrary?.name, "Local Library")
        XCTAssertEqual(completionCount, 1)
        XCTAssertTrue(completionWasOnMainThread)

        try? FileManager.default.removeItem(at: testBookFile)
    }

    private func configureReachableMockSession() {
        URLProtocol.registerClass(MockURLProtocol.self)

        let probeRequest = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false)
        let info = CalibreServerInfo(
            server: server,
            isPublic: false,
            url: URL(string: "http://localhost")!,
            reachable: true,
            probing: false,
            errorMsg: "Success",
            defaultLibrary: library.id,
            libraryMap: [library.id: library.name],
            request: probeRequest
        )
        container.calibreServerInfoStaging = [server.uuid.uuidString: info]

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        for timeout in [10.0, 600.0] {
            for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
                let key = CalibreServerURLSessionKey(server: server, timeout: timeout, qos: qos)
                container.calibreServerService.metadataSessions[key] = mockSession
            }
        }
    }

    private static let newestChange = "2026-06-23T18:00:00.123456+00:00"

    /// What calibre answers `syncLibrary` for the test library: 12 books, the newest book 101 with
    /// an int column made by `calibredb add_custom_column` ("display": {}), and the categories.
    private static func syncAnswers(categories: String = "[]", categoryItems: [String: String] = [:]) -> [String: String] {
        [
            "/ajax/search/test_lib": """
            {"total_num": 12, "sort_order": "desc", "num_books_without_search": 12, "offset": 0, "num": 1,
             "sort": "last_modified", "base_url": "/ajax/search/test_lib", "query": null,
             "library_id": "test_lib", "book_ids": [101], "vl": ""}
            """,
            "/ajax/books/test_lib": """
            {"101": {"last_modified": "\(newestChange)", "user_metadata": {"#read_progress": {
                "table": "custom_column_1", "column": "value", "datatype": "int", "is_multiple": null,
                "kind": "field", "name": "Read progress", "search_terms": ["#read_progress"],
                "label": "read_progress", "colnum": 1, "display": {}, "is_custom": true,
                "is_category": false, "link_column": "value", "category_sort": "value", "is_csp": false,
                "is_editable": true, "rec_index": 23, "#value#": null, "#extra#": null, "is_multiple2": {}}}}}
            """,
            "/ajax/categories/test_lib": categories
        ].merging(categoryItems) { $1 }
    }

    private static func categoryItemsJSON(name: String, items: [String]) -> String {
        """
        {"category_name": "\(name)", "base_url": "", "total_num": \(items.count), "offset": 0, "num": 10000,
         "sort": "name", "sort_order": "asc", "items": [\(items.joined(separator: ", "))]}
        """
    }

    private static func bookEntryJSON(title: String) -> String {
        """
        {"title": "\(title)", "uuid": "uuid-\(title)", "authors": ["Author"], "formats": ["epub"],
         "user_metadata": {}, "tags": [], "author_sort": "", "title_sort": "", "thumbnail": "",
         "timestamp": "", "user_categories": {}, "cover": "", "last_modified": "\(newestChange)",
         "application_id": 0, "author_sort_map": {}, "identifiers": {}, "languages": [], "pubdate": "",
         "rating": 0.0, "format_metadata": {}, "category_urls": {}}
        """
    }

    private func waitForCachedCategory(
        named categoryName: String,
        matching predicate: (LibraryCategoryResult) -> Bool
    ) async throws -> LibraryCategoryResult {
        for _ in 0..<50 {
            if let result = try container.categoryCacheRepository.fetchLibraryCategoryResult(
                libraryId: library.id,
                categoryName: categoryName
            ), predicate(result) {
                return result
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        return try XCTUnwrap(
            container.categoryCacheRepository.fetchLibraryCategoryResult(
                libraryId: library.id,
                categoryName: categoryName
            )
        )
    }
}
