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
        try libraryManager.hideLibrary(libraryId: libId, serverID: server.id)
        
        XCTAssertTrue(libraryManager.calibreLibraries[libId]?.hidden ?? false)
        
        // Verify in repository
        let allLibs = libraryRepository.getAllLibraries()
        let hiddenLib = allLibs.first { $0.id == libId }
        XCTAssertTrue(hiddenLib?.hidden ?? false)
        
        // Restore
        try libraryManager.restoreLibrary(libraryId: libId, serverID: server.id)
        
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

    func testRegisterLibrariesFromRefresh() throws {
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
        
        XCTAssertTrue(libraryManager.registerLibraries(from: serverInfo))
        
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
        
        try libraryManager.removeLibrary(library: library)
        
        let dbLibAfter = libraryRepository.getAllLibraries().first { $0.id == library.id }
        XCTAssertNil(dbLibAfter)
        
        XCTAssertNil(container.bookManager.booksInShelf[book.inShelfId])
        XCTAssertNil(libraryManager.librarySyncStatus[library.id])
    }

    func testFailedLibraryRemovalKeepsShelfMetadataAndCachedFile() throws {
        var book = CalibreBook(id: 778, library: library)
        book.inShelf = true
        book.formats["EPUB"] = FormatInfo(filename: "sc3-fixture.epub", serverSize: 4,
            serverMTime: Date(), cached: true, cacheSize: 4, cacheMTime: Date())
        let url = try XCTUnwrap(getSavedUrl(book: book, format: .EPUB))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("EPUB".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        container.bookManager.updateBook(book: book)
        let repository = MockLibraryRepository()
        repository.deleteLibraryError = CocoaError(.fileWriteNoPermission)
        let manager = CalibreLibraryManager(container: container, databaseService: databaseService, libraryRepository: repository)
        manager.calibreLibraries[library.id] = library
        container.libraryManager = manager

        XCTAssertThrowsError(try manager.removeOrHideLibrary(libraryID: library.id, serverID: server.id))
        XCTAssertNotNil(container.booksInShelf[book.inShelfId])
        XCTAssertNotNil(container.bookRepository.getBook(library: library, bookId: book.id))
        XCTAssertFalse(manager.calibreLibraries[library.id]?.hidden ?? true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testInFlightLibrarySummaryPreservesNewVisibilityAndDiscoverability() async throws {
        configureReachableMockSession()
        _ = MockURLProtocol.answer(Self.syncAnswers())
        let reply = try XCTUnwrap(MockURLProtocol.requestHandler)
        let entered = expectation(description: "Summary request is in flight")
        let resume = DispatchSemaphore(value: 0)
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/ajax/search/test_lib" {
                entered.fulfill()
                guard resume.wait(timeout: .now() + 5) == .success else { throw URLError(.timedOut) }
            }
            return try reply(request)
        }
        defer {
            resume.signal()
            MockURLProtocol.requestHandler = nil
        }
        let syncing = Task { await libraryManager.syncLibrary(request: .init(library: library)) }
        await fulfillment(of: [entered], timeout: 3)
        try libraryManager.setDiscoverable(false, libraryID: library.id, serverID: server.id)
        try libraryManager.hideLibrary(libraryId: library.id, serverID: server.id)
        try libraryManager.restoreLibrary(libraryId: library.id, serverID: server.id)
        resume.signal()
        await syncing.value

        let persisted = try XCTUnwrap(libraryRepository.getLibrary(id: library.id))
        XCTAssertFalse(persisted.hidden)
        XCTAssertFalse(persisted.discoverable)
        XCTAssertFalse(libraryManager.calibreLibraries[library.id]?.discoverable ?? true)
        XCTAssertEqual(libraryManager.librarySyncStatus[library.id]?.msg, "Success")
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

    /// A deleted book changes no other book, so calibre's newest change stays put. A book count
    /// that changed since the last summary moves the generation instead, once, so the search and
    /// category caches are fetched again.
    func testAChangedBookCountMovesTheGenerationOnce() async throws {
        let newest = try XCTUnwrap(parseLastModified(Self.newestChange))
        library.lastModified = newest
        libraryManager.calibreLibraries[library.id] = library
        try libraryRepository.saveLibrary(library)
        libraryManager.librarySyncStatus[library.id] = .init(library: library, cnt: 13)
        configureReachableMockSession()
        _ = MockURLProtocol.answer(Self.syncAnswers())

        await libraryManager.syncLibrary(request: CalibreSyncLibraryRequest(library: library))

        let moved = try XCTUnwrap(libraryManager.calibreLibraries[library.id]?.lastModified)
        XCTAssertGreaterThan(moved, newest)
        let saved = try XCTUnwrap(libraryRepository.getLibrary(id: library.id))
        XCTAssertEqual(saved.lastModified.timeIntervalSince1970, moved.timeIntervalSince1970, accuracy: 0.0001)
        XCTAssertEqual(libraryManager.librarySyncStatus[library.id]?.cnt, 12)

        await libraryManager.syncLibrary(request: CalibreSyncLibraryRequest(library: library))

        XCTAssertEqual(libraryManager.calibreLibraries[library.id]?.lastModified, moved)
    }

    /// calibre names categories in the server's language. The sync keeps the field each one is
    /// searched by, from its URL, and saves it with the library.
    func testSyncLibraryKeepsTheFieldEachCategoryIsSearchedBy() async throws {
        configureReachableMockSession()
        let requests = MockURLProtocol.answer(Self.syncAnswers(categories: """
        [
            {"name": "全部书籍", "url": "/ajax/category/616c6c626f6f6b73/test_lib", "icon": "book.png", "is_category": false},
            {"name": "作者", "url": "/ajax/category/617574686f7273/test_lib", "icon": "user_profile.png", "is_category": true}
        ]
        """, categoryItems: [
            "/ajax/category/617574686f7273/test_lib": Self.categoryItemsJSON(name: "作者", items: [])
        ]))

        await libraryManager.syncLibrary(request: CalibreSyncLibraryRequest(library: library))

        XCTAssertEqual(requests.unexpected, [])
        XCTAssertEqual(libraryManager.calibreLibraries[library.id]?.categoryFields, ["作者": "authors"])
        XCTAssertEqual(libraryRepository.getLibrary(id: library.id)?.categoryFields, ["作者": "authors"])
        XCTAssertEqual(libraryManager.searchField(forCategory: "作者"), "authors")
        XCTAssertEqual(libraryManager.searchField(forCategory: "Tags"), "tags")
    }

    /// A category that couldn't be refreshed fails the sync, rather than showing it as a success.
    func testAFailedCategoryIsReported() async throws {
        configureReachableMockSession()
        let requests = MockURLProtocol.answer(Self.syncAnswers(categories: """
        [{"name": "Authors", "url": "/ajax/category/Authors", "icon": "author", "is_category": true}]
        """))

        await libraryManager.syncLibrary(request: CalibreSyncLibraryRequest(library: library))

        XCTAssertEqual(requests.unexpected, ["/ajax/category/Authors"])
        let syncStatus = try XCTUnwrap(libraryManager.librarySyncStatus[library.id])
        XCTAssertFalse(syncStatus.isSync)
        XCTAssertTrue(syncStatus.isError)
        XCTAssertNotEqual(syncStatus.msg, "Success")
        XCTAssertEqual(syncStatus.cnt, 12)
    }

    /// A library removed while its summary is read stays removed, and no categories are cached for it.
    func testARemovedLibraryIsNotSavedOrGivenCategories() async throws {
        configureReachableMockSession()
        let requests = MockURLProtocol.answer(Self.syncAnswers())
        try libraryManager.removeLibrary(library: library)

        await libraryManager.syncLibrary(request: CalibreSyncLibraryRequest(library: library))

        XCTAssertTrue(requests.answered.isEmpty)
        XCTAssertNil(libraryManager.calibreLibraries[library.id])
        XCTAssertNil(libraryRepository.getLibrary(id: library.id))
    }

    /// Browsing reads books with the same `ajax/books` request, and keeps the list of books
    /// unavailable on the server as well.
    func testBrowsingListsABookCalibreAnswersNullForAndClearsOneItHas() async throws {
        configureReachableMockSession()
        libraryManager.librarySyncStatus[library.id] = .init(library: library, del: [101])
        _ = MockURLProtocol.answer([
            "/ajax/search/test_lib": """
            {"total_num": 2, "sort_order": "asc", "num_books_without_search": 2, "offset": 0, "num": 2,
             "sort": "sort", "base_url": "/ajax/search/test_lib", "query": "browse",
             "library_id": "test_lib", "book_ids": [101, 102], "vl": ""}
            """,
            "/ajax/books/test_lib": #"{"101": \#(Self.bookEntryJSON(title: "Back")), "102": null}"#
        ])

        _ = try await container.librarySearchService.searchAndFetchMetadata(
            library: library,
            criteria: SearchCriteria(
                searchString: "browse",
                sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
                filterCriteriaCategory: [:]
            ),
            limit: 100,
            force: true
        )

        XCTAssertEqual(libraryManager.librarySyncStatus[library.id]?.del, [102])
    }

    /// calibre answers null for a book it no longer has. Settings lists it, but its record (here
    /// a shelf book's) stays; once calibre has it again, it's no longer listed. A book that failed
    /// to sync before is no longer listed as failed once it's read.
    func testABookCalibreAnswersNullForIsListedNotRemoved() async throws {
        configureReachableMockSession()
        for id: Int32 in [101, 102] {
            var book = CalibreBook(id: id, library: library)
            book.inShelf = true
            container.bookManager.updateBook(book: book)
        }
        libraryManager.librarySyncStatus[library.id] = .init(library: library, err: [101])
        var answers = ["/ajax/books/test_lib": #"{"101": \#(Self.bookEntryJSON(title: "Kept")), "102": null}"#]
        _ = MockURLProtocol.answer(answers)

        await container.bookManager.getBooksMetadata(request: .init(library: library, books: [101, 102], getAnnotations: false))

        XCTAssertEqual(libraryManager.librarySyncStatus[library.id]?.del, [102])
        XCTAssertEqual(libraryManager.librarySyncStatus[library.id]?.err, [])
        XCTAssertTrue(container.bookManager.bookExists(forPrimaryKey: CalibreBook(id: 102, library: library).inShelfId))

        answers["/ajax/books/test_lib"] = #"{"102": \#(Self.bookEntryJSON(title: "Back"))}"#
        _ = MockURLProtocol.answer(answers)

        await container.bookManager.getBooksMetadata(request: .init(library: library, books: [102], getAnnotations: false))

        XCTAssertEqual(libraryManager.librarySyncStatus[library.id]?.del, [])
    }

    /// A shelf larger than a batch is read in batches: calibre refuses a long request line.
    func testALargeShelfIsReadInBatches() async throws {
        configureReachableMockSession()
        let ids = (1...250).map(Int32.init)
        for id in ids {
            var book = CalibreBook(id: id, library: library)
            book.inShelf = true
            container.bookManager.updateBook(book: book)
        }
        let entries = Dictionary(uniqueKeysWithValues: ids.map { ($0, Self.bookEntryJSON(title: "Book \($0)")) })
        let batchSizes = BatchSizes()
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url, url.path == "/ajax/books/test_lib" else { throw URLError(.fileDoesNotExist) }
            let requested = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "ids" })?.value?
                .split(separator: ",")
                .compactMap { Int32(String($0)) } ?? []
            batchSizes.append(requested.count)
            let body = "{" + requested.map { "\"\($0)\": \(entries[$0] ?? "null")" }.joined(separator: ", ") + "}"
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        let results = await container.bookManager.getBooksMetadata(
            request: .init(library: library, books: ids + [1, 201, 250], getAnnotations: false))

        XCTAssertEqual(batchSizes.values, [200, 50])
        XCTAssertEqual(results.count, 250)
        XCTAssertTrue(results.values.allSatisfy { $0 == .updated })
        XCTAssertEqual(libraryManager.librarySyncStatus[library.id]?.del ?? [], [])
    }

    func testReplacingDatabaseBetweenMetadataBatchesKeepsFirstCommitAndStopsRest() async throws {
        configureReachableMockSession()
        let ids = (1...201).map(Int32.init)
        let books = ids.map { shelveForMetadataTest($0) }
        let original = try XCTUnwrap(databaseService.realm)
        let library = try XCTUnwrap(library)
        let batchReachedFollowUp = expectation(description: "First committed batch reached annotations")
        let release = DispatchSemaphore(value: 0)
        let answers = BatchSizes()
        defer { release.signal(); MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let body: String
            if url.path.hasPrefix("/book-get-annotations/") {
                batchReachedFollowUp.fulfill()
                guard release.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
                body = "{}"
            } else {
                let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value)
                let requested = query.split(separator: ",")
                answers.append(requested.count)
                body = "{" + requested.map { "\"\($0)\":\(Self.bookEntryJSON(title: "Committed \($0)"))" }.joined(separator: ",") + "}"
            }
            return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)), Data(body.utf8))
        }
        let refresh = Task { await container.bookManager.getBooksMetadata(
            request: .init(library: library, books: ids, getAnnotations: true)) }
        await fulfillment(of: [batchReachedFollowUp], timeout: 10)
        original.refresh()
        XCTAssertEqual(original.object(ofType: CalibreBookRealm.self, forPrimaryKey: books[0].inShelfId)?.title, "Committed 1")

        try databaseService.openMainRealm(conf: .init(inMemoryIdentifier: UUID().uuidString, schemaVersion: DatabaseSchema.version))
        try container.serverRepository.saveServer(library.server)
        try libraryRepository.saveLibrary(library)
        let last = try XCTUnwrap(books.last)
        container.bookRepository.saveBook(last)
        release.signal()
        let result = await refresh.value

        XCTAssertEqual(answers.values, [200])
        XCTAssertEqual(result[1], .updated)
        XCTAssertEqual(result[201], .superseded)
        XCTAssertEqual(container.bookRepository.getBook(id: last.inShelfId)?.title, last.title)
        original.refresh()
        XCTAssertEqual(original.object(ofType: CalibreBookRealm.self, forPrimaryKey: last.inShelfId)?.title, last.title)
    }

    func testMetadataAnswerDoesNotCrossDatabaseReplacement() async throws {
        configureReachableMockSession()
        let book = shelveForMetadataTest(101)
        let oldRealm = try XCTUnwrap(databaseService.realm)
        let (refresh, release) = try await holdMetadataAnswer(for: book, title: "Old connection answer")
        defer { release.signal() }

        let replacement = Realm.Configuration(inMemoryIdentifier: UUID().uuidString, schemaVersion: DatabaseSchema.version)
        try databaseService.openMainRealm(conf: replacement)
        try container.serverRepository.saveServer(book.library.server)
        try libraryRepository.saveLibrary(book.library)
        var sentinel = book
        sentinel.title = "Replacement database"
        container.bookRepository.saveBook(sentinel)
        release.signal()

        let result = await refresh.value
        XCTAssertNotEqual(result[book.id], .updated)
        databaseService.refreshMainRealm()
        XCTAssertEqual(container.bookRepository.getBook(id: book.inShelfId)?.title, sentinel.title)
        XCTAssertEqual(container.bookManager.booksInShelf[book.inShelfId]?.title, book.title)
        withExtendedLifetime(oldRealm) {}
    }

    func testPendingMetadataCannotFollowAConnectionChangeAndRestore() async throws {
        // Other cases share this class's Realm and register localhost.
        let original = server!
        server.baseUrl = "http://localhost:19775"
        try container.serverRepository.saveServer(server)
        container.calibreServers[server.id] = server
        libraryManager.updateServerSnapshot(server, connectionChanged: true)
        library = try XCTUnwrap(libraryManager.calibreLibraries[library.id])
        defer {
            try? container.serverRepository.saveServer(original)
            libraryManager.updateServerSnapshot(original, connectionChanged: true)
        }
        configureReachableMockSession()
        let book = shelveForMetadataTest(101)
        let (refresh, release) = try await holdMetadataAnswer(for: book, title: "Old credentials")
        defer { release.signal() }
        var changed = book.library.server
        changed.hasAuth = true
        changed.username = "replacement"
        changed.password = "replacement"
        try container.serverRepository.updateServer(changed, ifCurrent: book.library.server)
        libraryManager.updateServerSnapshot(changed, connectionChanged: true)
        try container.serverRepository.updateServer(book.library.server, ifCurrent: changed)
        libraryManager.updateServerSnapshot(book.library.server, connectionChanged: true)
        release.signal()
        let result = await refresh.value
        XCTAssertEqual(result[book.id], .superseded)
        XCTAssertEqual(container.bookRepository.getBook(id: book.inShelfId)?.title, book.title)
    }

    func testPendingMetadataCannotFollowHideAndRestore() async throws {
        configureReachableMockSession()
        let book = shelveForMetadataTest(101)
        let (refresh, release) = try await holdMetadataAnswer(for: book, title: "From retired library lifetime")
        defer { release.signal() }
        try libraryManager.hideLibrary(libraryId: library.id, serverID: server.id)
        try libraryManager.restoreLibrary(libraryId: library.id, serverID: server.id)
        release.signal()
        let result = await refresh.value
        XCTAssertEqual(result[book.id], .superseded)
        XCTAssertEqual(container.bookRepository.getBook(id: book.inShelfId)?.title, book.title)
    }

    func testPendingMetadataCannotRecreateARemovedLibraryOrBook() async throws {
        configureReachableMockSession()
        let book = shelveForMetadataTest(101)
        let (refresh, release) = try await holdMetadataAnswer(for: book, title: "Removed library response")
        defer { release.signal() }
        try libraryManager.removeLibrary(library: book.library)
        release.signal()

        let result = await refresh.value
        XCTAssertEqual(result[book.id], .superseded)
        XCTAssertNil(container.bookRepository.getBook(id: book.inShelfId))
        XCTAssertNil(container.bookManager.booksInShelf[book.inShelfId])
        XCTAssertNil(libraryManager.librarySyncStatus[book.library.id])
    }

    func testPendingMetadataCannotWriteToReinsertedBookOrSameIDOnAnotherServer() async throws {
        configureReachableMockSession()
        let book = shelveForMetadataTest(101)
        let otherServer = TestFixtures.makeServer(baseUrl: "http://other.test")
        let otherLibrary = TestFixtures.makeLibrary(server: otherServer, key: library.key, name: library.name)
        try container.serverRepository.saveServer(otherServer)
        container.calibreServers[otherServer.id] = otherServer
        try libraryRepository.saveLibrary(otherLibrary)
        container.calibreLibraries[otherLibrary.id] = otherLibrary
        var other = CalibreBook(id: book.id, library: otherLibrary)
        other.title = "Same ID on another server"
        container.bookRepository.saveBook(other)

        let (refresh, release) = try await holdMetadataAnswer(for: book, title: "Deleted row's answer")
        defer { release.signal() }
        container.bookRepository.deleteBook(id: book.inShelfId)
        var replacement = book
        replacement.title = "Reinserted row"
        container.bookManager.updateBook(book: replacement)
        release.signal()
        let result = await refresh.value
        XCTAssertEqual(result[book.id], .localBookMissing)
        XCTAssertEqual(container.bookRepository.getBook(id: book.inShelfId)?.title, replacement.title)
        XCTAssertEqual(container.bookManager.booksInShelf[book.inShelfId]?.title, replacement.title)
        XCTAssertEqual(container.bookRepository.getBook(id: other.inShelfId)?.title, other.title)
    }

    func testDelayedShelfMetadataKeepsNewerBrowseMetadataAndCachedFormats() async throws {
        configureReachableMockSession()
        container.bookManager.booksInShelf = [:]
        let book = shelveForMetadataTest(101)
        container.bookManager.isShelfLoaded = true
        let shelf = YabrShelfDataModel(unifiedSearchService: container.unifiedSearchService, container: container)
        let (initial, initialObserver) = observeRecentShelf(shelf, "Initial shelf rendered") {
            $0.books.contains { $0.id == book.inShelfId && $0.title == book.title }
        }
        defer { initialObserver.cancel() }
        await fulfillment(of: [initial], timeout: 5)
        let (refresh, release) = try await holdMetadataAnswer(for: book, title: "Older answer")
        defer { release.signal() }

        var newer = CalibreBookEntry()
        newer.title = "Newer Browse title"
        newer.authors = ["New Browse Author"]
        newer.last_modified = "2026-06-23T18:00:00.123999+00:00"
        let browse = try await container.librarySearchService.prepareRequest(library: book.library)
        try browse.cache.writeMetadataEntries(library: book.library,
            entries: [book.id.description: newer], json: [:], retainingExisting: [book.id],
            metadataBaseline: [book.id: book.lastUpdated])
        let browsedBook = try XCTUnwrap(browse.cache.fetchBooks(library: book.library, bookIds: [book.id])[book.id])
        var companion = CalibreBook(id: 103, library: book.library)
        companion.title = "Another title by the same author"
        companion.authors = newer.authors
        let criteria = SearchCriteria(searchString: "", sortCriteria: .init(), filterCriteriaCategory: ["Authors": ["New Browse Author"]])
        try container.searchCacheRepository.saveLibrarySourceResult(
            libraryId: book.library.id, search: criteria.searchString, sortBy: criteria.sortCriteria.by,
            sortAsc: criteria.sortCriteria.ascending, filters: criteria.filterCriteriaCategory, sourceUrl: browse.source,
            result: .init(generation: book.library.lastModified, totalNumber: 2, bookIds: [book.id, companion.id],
                          books: [browsedBook, companion]))
        let (presented, observer) = observeRecentShelf(shelf, "Recent rendered retained Browse metadata") {
            $0.books.contains { $0.id == book.inShelfId && $0.title == newer.title }
        }
        defer { observer.cancel() }
        let discovered = expectation(description: "Discover displayed the updated author section and book title")
        let sections = shelf.snapshots()
        let discoverObserver = Task { @MainActor in
            for await snapshot in sections {
                if snapshot.sections.contains(where: {
                    $0.title == "Author: New Browse Author" && $0.books.contains { $0.id == book.inShelfId && $0.title == newer.title }
                }) {
                    discovered.fulfill()
                    return
                }
            }
        }
        defer { discoverObserver.cancel() }
        release.signal()

        let result = await refresh.value
        XCTAssertEqual(result[book.id], .unchanged)
        databaseService.refreshMainRealm()
        let persisted = try XCTUnwrap(container.bookRepository.getBook(id: book.inShelfId))
        XCTAssertEqual(persisted.title, newer.title)
        XCTAssertEqual(container.bookManager.booksInShelf[book.inShelfId]?.title, newer.title)
        XCTAssertTrue(persisted.formats["EPUB"]?.cached == true)
        await fulfillment(of: [presented, discovered], timeout: 3)
    }

    func testRetainedMetadataWithNoShelfChangeDoesNotBroadcast() async throws {
        configureReachableMockSession()
        var book = shelveForMetadataTest(101)
        book.lastModified = try XCTUnwrap(parseLastModified("2026-06-23T18:00:00.123999Z"))
        container.bookManager.updateBook(book: book)
        _ = MockURLProtocol.answer(["/ajax/books/test_lib": #"{"101":\#(Self.bookEntryJSON(title: "Older answer"))}"#])
        let updates = recordRefreshPublications()

        let result = await container.bookManager.getBooksMetadata(
            request: .init(library: book.library, books: [book.id], getAnnotations: false))
        container.publishCalibreUpdate(.library(book.library))

        let count = await updates.value
        XCTAssertEqual(result[book.id], .unchanged)
        XCTAssertEqual(count, 0)
    }

    func testMetadataBatchDistinguishesNullMissingAndMalformedEntries() async throws {
        configureReachableMockSession()
        let books = [101, 102, 103, 104].map { shelveForMetadataTest(Int32($0)) }
        _ = MockURLProtocol.answer([
            "/ajax/books/test_lib": #"{"101": \#(Self.bookEntryJSON(title: "Updated")), "102":null, "104":{"title":42}}"#
        ])

        let results = await container.bookManager.getBooksMetadata(
            request: .init(library: library, books: books.map(\.id) + [101], getAnnotations: false))

        XCTAssertEqual(results[101], .updated)
        XCTAssertEqual(results[102], .unavailable)
        XCTAssertNotEqual(results[103], .unavailable)
        XCTAssertNotEqual(results[103], results[104])
        XCTAssertEqual(libraryManager.librarySyncStatus[library.id]?.del, [102])
        XCTAssertEqual(libraryManager.librarySyncStatus[library.id]?.err, [103, 104])
        XCTAssertEqual(container.bookManager.booksInShelf[books[0].inShelfId]?.title, "Updated")
        XCTAssertTrue(container.bookRepository.getBook(id: books[1].inShelfId)?.formats["EPUB"]?.cached == true)
    }

    func testDelayedNullCannotMarkANewerMetadataVersionUnavailable() async throws {
        configureReachableMockSession()
        let book = shelveForMetadataTest(101)
        let (refresh, release) = try await holdMetadataAnswer(for: book, title: nil)
        defer { release.signal() }
        var entry = CalibreBookEntry()
        entry.title = "Present in Browse"
        entry.last_modified = Self.newestChange
        try container.searchCacheRepository.writeMetadataEntries(library: book.library,
            entries: [book.id.description: entry], json: [:])
        release.signal()
        let result = await refresh.value
        XCTAssertEqual(result[book.id], .superseded)
        XCTAssertFalse(libraryManager.librarySyncStatus[library.id]?.del.contains(book.id) ?? false)
        databaseService.refreshMainRealm()
        XCTAssertEqual(container.bookRepository.getBook(id: book.inShelfId)?.title, entry.title)
    }

    func testOverlappingMetadataRequestsRespectServerVersionWhenAnswersArriveOutOfOrder() async throws {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [DeferredMetadataProtocol.self]
        configureReachableMockSession()
        let session = URLSession(configuration: sessionConfig)
        container.calibreServerService.metadataSessions[
            CalibreServerURLSessionKey(server: server, timeout: 600, qos: .default)] = session
        let book = shelveForMetadataTest(101)
        let first = expectation(description: "First request held")
        let second = expectation(description: "Second request held")
        let held = DeferredMetadataProtocol.Requests(first: first, second: second)
        DeferredMetadataProtocol.requests = held
        defer {
            DeferredMetadataProtocol.requests = nil
            session.invalidateAndCancel()
        }
        let request = CalibreBooksMetadataRequest(library: book.library, books: [book.id], getAnnotations: false)
        let older = Task { await container.bookManager.getBooksMetadata(request: request) }
        await fulfillment(of: [first], timeout: 10)
        let newer = Task { await container.bookManager.getBooksMetadata(request: request) }
        await fulfillment(of: [second], timeout: 10)

        try held.answer(1, body: #"{"101":\#(Self.bookEntryJSON(title: "New result", modified: "2026-06-23T18:00:00.123999Z"))}"#)
        let latest = await newer.value
        try held.answer(0, body: #"{"101":\#(Self.bookEntryJSON(title: "Old result"))}"#)
        let late = await older.value

        XCTAssertEqual(latest[book.id], .updated)
        XCTAssertEqual(late[book.id], .unchanged)
        databaseService.refreshMainRealm()
        XCTAssertEqual(container.bookRepository.getBook(id: book.inShelfId)?.title, "New result")
        XCTAssertEqual(container.bookManager.booksInShelf[book.inShelfId]?.title, "New result")
    }

    func testRetainedMetadataCannotClearANewerUnavailableAnswer() async throws {
        configureReachableMockSession()
        let first = expectation(description: "Old successful response held")
        let second = expectation(description: "New null response held")
        let held = DeferredMetadataProtocol.Requests(first: first, second: second)
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [DeferredMetadataProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        let key = CalibreServerURLSessionKey(server: server, timeout: 600, qos: .default)
        container.calibreServerService.metadataSessions[key] = session
        DeferredMetadataProtocol.requests = held
        defer {
            DeferredMetadataProtocol.requests = nil
            session.invalidateAndCancel()
        }

        var book = shelveForMetadataTest(101)
        book.lastModified = try XCTUnwrap(parseLastModified(Self.newestChange))
        let filename = "BS1-review-\(UUID().uuidString).epub"
        book.formats["EPUB"]?.filename = filename
        container.bookManager.updateBook(book: book)
        let file = try XCTUnwrap(getSavedUrl(book: book, format: .EPUB))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let cachedBytes = Data("Local EPUB fixture".utf8)
        try cachedBytes.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let request = CalibreBooksMetadataRequest(library: book.library, books: [book.id], getAnnotations: false)
        let older = Task { await container.bookManager.getBooksMetadata(request: request) }
        await fulfillment(of: [first], timeout: 5)
        let newer = Task { await container.bookManager.getBooksMetadata(request: request) }
        await fulfillment(of: [second], timeout: 5)
        try held.answer(1, body: #"{"101":null}"#)
        let unavailable = await newer.value
        XCTAssertEqual(unavailable[book.id], .unavailable)
        XCTAssertEqual(libraryManager.librarySyncStatus[library.id]?.del, [book.id])

        try held.answer(0, body: #"{"101":\#(Self.bookEntryJSON(title: "Old successful answer"))}"#)
        let late = await older.value
        XCTAssertEqual(late[book.id], .unchanged)
        XCTAssertEqual(libraryManager.librarySyncStatus[library.id]?.del, [book.id])
        XCTAssertEqual(container.bookRepository.getBook(id: book.inShelfId)?.title, book.title)
        XCTAssertTrue(container.bookManager.booksInShelf[book.inShelfId]?.formats["EPUB"]?.cached == true)
        XCTAssertEqual(try Data(contentsOf: file), cachedBytes)

        let recoveredConfiguration = URLSessionConfiguration.ephemeral
        recoveredConfiguration.protocolClasses = [MockURLProtocol.self]
        let recoveredSession = URLSession(configuration: recoveredConfiguration)
        container.calibreServerService.metadataSessions[key] = recoveredSession
        defer { recoveredSession.invalidateAndCancel(); MockURLProtocol.requestHandler = nil }
        _ = MockURLProtocol.answer([
            "/ajax/books/test_lib": #"{"101":\#(Self.bookEntryJSON(title: "Confirmed present", modified: "2026-06-23T18:00:00.123000Z"))}"#
        ])
        let recovered = await container.bookManager.getBooksMetadata(request: request)
        XCTAssertEqual(recovered[book.id], .unchanged)
        XCTAssertEqual(libraryManager.librarySyncStatus[library.id]?.del, [])
        XCTAssertEqual(container.bookRepository.getBook(id: book.inShelfId)?.title, book.title)
    }

    func testReaderCloseRefreshesShelfAndAcceptsTheCachedFormatsRemotePosition() async throws {
        configureReachableMockSession()
        let book = shelveForMetadataTest(101)
        let remote = BookDeviceReadingPosition(id: "other-device", readerName: ReaderType.YabrEPUB.rawValue,
            lastReadPage: 12, epoch: 1_700_000_001)
        let bookmark = TestFixtures.makeBookmark(bookId: book.bookPrefId, pos: "epubcfi(/4/2/4)", title: "Remote bookmark")
        let annotation = CalibreBookAnnotationsResult(last_read_positions: [remote.toEntry()],
            annotations_map: .init(bookmark: [bookmark.toCalibreBookAnnotationBookmarkEntry()], highlight: []))
        let response = try JSONEncoder().encode(["101:EPUB": annotation])
        let annotationRequested = expectation(description: "Reader-close issued the pinned annotation request")
        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let data: Data
            switch url.path {
            case "/ajax/books/test_lib":
                data = Data(#"{"101":\#(Self.bookEntryJSON(title: "Refreshed on close"))}"#.utf8)
            case "/book-get-annotations/test_lib/101-EPUB":
                annotationRequested.fulfill()
                data = response
            default:
                throw URLError(.unsupportedURL)
            }
            return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)), data)
        }
        defer { MockURLProtocol.requestHandler = nil }
        libraryManager.librarySyncStatus[library.id] = .init(library: library)
        let idle = expectation(description: "Reader-close refresh finished local merge")
        let statuses = libraryManager.librarySyncStatusSnapshots()
        let observer = Task { @MainActor in
            var started = false
            for await status in statuses {
                if status[self.library.id]?.isUpd == true { started = true }
                if started, status[self.library.id]?.isUpd == false {
                    idle.fulfill()
                    return
                }
            }
        }
        defer { observer.cancel() }
        await container.sessionManager.onBookReaderClosed(book: book,
            lastPosition: .init(readerName: ReaderType.YabrEPUB.rawValue))
        await fulfillment(of: [annotationRequested, idle], timeout: 10)
        XCTAssertEqual(container.bookManager.booksInShelf[book.inShelfId]?.title, "Refreshed on close")
        XCTAssertEqual(container.readingPositionRepository.getPositions(for: book).first { $0.id == remote.id }?.lastReadPage, 12)
        XCTAssertEqual(container.annotationRepository.getBookmarks(forBookId: book.bookPrefId, excludeRemoved: true).map(\.title),
                       [bookmark.title])
    }

    func testLaterPositionMergeRebuildsRecentProgressAndOrder() async throws {
        try await assertDeferredPositionRefresh(.commit)
    }

    func testCancellingBeforePositionMergeKeepsRecentProgress() async throws {
        try await assertDeferredPositionRefresh(.cancel)
    }

    func testRetiringDatabaseBeforePositionMergeKeepsRecentProgress() async throws {
        try await assertDeferredPositionRefresh(.retireDatabase)
    }

    private enum DeferredPositionAction { case commit, cancel, retireDatabase }

    private func assertDeferredPositionRefresh(_ action: DeferredPositionAction) async throws {
        configureReachableMockSession()
        container.bookManager.booksInShelf = [:]
        let book = shelveForMetadataTest(101)
        var other = shelveForMetadataTest(102)
        other.lastModified = Date(timeIntervalSince1970: 1_800_000_000)
        container.bookManager.updateBook(book: other)
        container.bookManager.isShelfLoaded = true
        let shelf = YabrShelfDataModel(unifiedSearchService: container.unifiedSearchService, container: container)
        let remote = BookDeviceReadingPosition(id: "remote", readerName: ReaderType.YabrEPUB.rawValue,
            lastReadPage: 12, lastProgress: 64, epoch: 1_900_000_000)
        let payload = CalibreBookAnnotationsResult(last_read_positions: [remote.toEntry()],
            annotations_map: .init(bookmark: [], highlight: []))
        let body = try JSONEncoder().encode(["101:EPUB": payload])
        let annotationRequested = expectation(description: "Annotation response is held")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal(); MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let data: Data
            switch url.path {
            case "/ajax/books/test_lib":
                data = Data(#"{"101":\#(Self.bookEntryJSON(title: "Early committed title"))}"#.utf8)
            case "/book-get-annotations/test_lib/101-EPUB":
                annotationRequested.fulfill()
                guard release.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
                data = body
            default:
                throw URLError(.unsupportedURL)
            }
            return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)), data)
        }
        let (earlyShelf, earlyObserver) = observeRecentShelf(shelf, "Early metadata rebuild displayed with old progress") {
            $0.books.first?.id == other.inShelfId &&
                $0.books.contains { $0.id == book.inShelfId && $0.title == "Early committed title" && $0.progress == 0 }
        }
        defer { earlyObserver.cancel() }
        let request = CalibreBooksMetadataRequest(library: book.library, books: [book.id], getAnnotations: true)
        let refresh = Task { await container.bookManager.getBooksMetadata(request: request) }
        await fulfillment(of: [annotationRequested, earlyShelf], timeout: 5)

        if action == .commit {
            let (reorderedShelf, observer) = observeRecentShelf(shelf, "Recent displayed the committed position") {
                $0.books.first?.id == book.inShelfId && $0.books.first?.progress == 64
            }
            defer { observer.cancel() }
            release.signal()
            let result = await refresh.value
            XCTAssertEqual(result[book.id], .updated)
            XCTAssertEqual(container.readingPositionRepository.getPositions(for: book).first?.lastProgress, 64)
            await fulfillment(of: [reorderedShelf], timeout: 3)
        } else {
            let updates = recordRefreshPublications()
            let original = databaseService.realm
            if action == .cancel {
                refresh.cancel()
            } else {
                try databaseService.openMainRealm(conf: .init(inMemoryIdentifier: UUID().uuidString, schemaVersion: DatabaseSchema.version))
            }
            release.signal()
            let result = await refresh.value
            XCTAssertEqual(result[book.id], action == .cancel ? .cancelled : .updated)
            container.publishCalibreUpdate(.library(book.library))
            let count = await updates.value
            XCTAssertEqual(count, 0)
            XCTAssertTrue(container.readingPositionRepository.getPositions(for: book).isEmpty)
            withExtendedLifetime(original) {}
        }
    }

    private func observeRecentShelf(
        _ shelf: YabrShelfDataModel, _ description: String,
        matching: @escaping (YabrShelfDataModel.RecentShelfSnapshot) -> Bool
    ) -> (XCTestExpectation, Task<Void, Never>) {
        let observed = expectation(description: description)
        let snapshots = shelf.recentSnapshots()
        let observer = Task { @MainActor in
            for await snapshot in snapshots where matching(snapshot) {
                observed.fulfill()
                return
            }
        }
        return (observed, observer)
    }

    private func recordRefreshPublications() -> Task<Int, Never> {
        let updates = container.calibreUpdates()
        return Task { @MainActor in
            var count = 0
            for await update in updates {
                switch update {
                case .shelf, .book: count += 1
                case .library: return count
                default: break
                }
            }
            return count
        }
    }

    private final class DeferredMetadataProtocol: URLProtocol, @unchecked Sendable {
        static var requests: Requests?

        final class Requests {
            private let lock = NSLock()
            private var pending = [DeferredMetadataProtocol]()
            private let first: XCTestExpectation
            private let second: XCTestExpectation

            init(first: XCTestExpectation, second: XCTestExpectation) {
                self.first = first
                self.second = second
            }

            func append(_ request: DeferredMetadataProtocol) {
                let count = lock.withLock { pending.append(request); return pending.count }
                if count == 1 { first.fulfill() }
                if count == 2 { second.fulfill() }
            }

            func answer(_ index: Int, body: String) throws {
                let entry = try XCTUnwrap(lock.withLock { pending.indices.contains(index) ? pending[index] : nil })
                let url = try XCTUnwrap(entry.request.url)
                let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                entry.client?.urlProtocol(entry, didReceive: response, cacheStoragePolicy: .notAllowed)
                entry.client?.urlProtocol(entry, didLoad: Data(body.utf8))
                entry.client?.urlProtocolDidFinishLoading(entry)
            }
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() { Self.requests?.append(self) }
        override func stopLoading() {}
    }

    private func shelveForMetadataTest(_ id: Int32) -> CalibreBook {
        var book = CalibreBook(id: id, library: library)
        book.title = "Local title \(id)"
        book.inShelf = true
        book.formats["EPUB"] = .init(filename: "Local.epub", serverSize: 0, serverMTime: .distantPast,
            cached: true, cacheSize: 42, cacheMTime: .distantPast)
        container.bookManager.updateBook(book: book)
        return book
    }

    private func holdMetadataAnswer(for book: CalibreBook, title: String?) async throws
        -> (Task<[Int32: BookMetadataRefreshResult], Never>, DispatchSemaphore) {
        let entered = expectation(description: "Metadata request reached the transport")
        let release = DispatchSemaphore(value: 0)
        var entry = CalibreBookEntry()
        entry.title = title ?? ""
        entry.last_modified = Self.newestChange
        let responseData = try JSONEncoder().encode([book.id.description: title == nil ? nil : entry])
        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            guard url.path == "/ajax/books/test_lib" else { throw URLError(.fileDoesNotExist) }
            entered.fulfill()
            guard release.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
            return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)), responseData)
        }
        let refresh = Task { await container.bookManager.getBooksMetadata(
            request: .init(library: book.library, books: [book.id], getAnnotations: false)) }
        await fulfillment(of: [entered], timeout: 10)
        return (refresh, release)
    }

    private final class BatchSizes: @unchecked Sendable {
        private let lock = NSLock()
        private var sizes = [Int]()

        func append(_ size: Int) {
            lock.lock()
            sizes.append(size)
            lock.unlock()
        }

        var values: [Int] {
            lock.lock()
            defer { lock.unlock() }
            return sizes
        }
    }

    func testPopulateLocalLibraryBooksWithFiles() async throws {
        guard let documentDirectoryURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            XCTFail("Failed to get document directory")
            return
        }
        let localLibraryURL = documentDirectoryURL.appendingPathComponent("Local Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: localLibraryURL, withIntermediateDirectories: true)
        
        let testBookFile = localLibraryURL.appendingPathComponent("TestBook.epub")
        try? "EPUB Content".write(to: testBookFile, atomically: true, encoding: .utf8)
        
        let completion = expectation(description: "Local scan completed")
        var completionCount = 0
        var completionWasOnMainThread = false
        libraryManager.populateLocalLibraryBooks { _ in
            completionCount += 1
            completionWasOnMainThread = Thread.isMainThread
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 5)

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

    private static func bookEntryJSON(title: String, modified: String = newestChange) -> String {
        """
        {"title": "\(title)", "uuid": "uuid-\(title)", "authors": ["Author"], "formats": ["epub"],
         "user_metadata": {}, "tags": [], "author_sort": "", "title_sort": "", "thumbnail": "",
         "timestamp": "", "user_categories": {}, "cover": "", "last_modified": "\(modified)",
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
