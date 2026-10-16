//
//  CalibreServerContractTests.swift
//  YetAnotherEBookReaderTests
//
//  Contract tests: the app's own CalibreServerService against a real calibre-server, for what
//  hand-written mocks can't show (how the server stores, merges and refuses what the app sends).
//
//  They skip unless a server is configured. .github/scripts/calibre-contract-server.sh starts one
//  with a seeded library and prints these variables:
//
//    TEST_RUNNER_YABR_CALIBRE_URL=http://127.0.0.1:18080 \
//    TEST_RUNNER_YABR_CALIBRE_USER=contract-writer \
//    TEST_RUNNER_YABR_CALIBRE_PASSWORD=writer-pass \
//    TEST_RUNNER_YABR_CALIBRE_READONLY_USER=contract-reader \
//    TEST_RUNNER_YABR_CALIBRE_READONLY_PASSWORD=reader-pass \
//    TEST_RUNNER_YABR_CALIBRE_RESTRICTED_USER=contract-restricted \
//    TEST_RUNNER_YABR_CALIBRE_RESTRICTED_PASSWORD=restricted-pass \
//    xcodebuild test … -only-testing:YetAnotherEBookReaderTests/CalibreServerContractTests
//
//  The server keeps its state between runs, so every test writes under its own device name,
//  highlight id or bookmark title and only reads those back.
//
//  A test marked XCTExpectFailure would pin a known bug. It's strict: once the bug is fixed the
//  test passes, which fails it, so remove the marker with the fix.
//

import XCTest
@testable import YetAnotherEBookReader

@MainActor
final class CalibreServerContractTests: XCTestCase {
    private var container: AppContainer!
    private var service: CalibreServerService!
    private var library: CalibreLibrary!
    private var book: CalibreBook!

    override func setUp() async throws {
        try await super.setUp()

        let environment = ProcessInfo.processInfo.environment
        guard let baseUrl = environment["YABR_CALIBRE_URL"], let serverURL = URL(string: baseUrl) else {
            throw XCTSkip("A contract test: run against a calibre-server with TEST_RUNNER_YABR_CALIBRE_URL")
        }
        let username = environment["YABR_CALIBRE_USER"] ?? ""
        let password = environment["YABR_CALIBRE_PASSWORD"] ?? ""

        container = MockAppContainerFactory.makeContainer(testName: "CalibreServerContractTests")
        service = container.calibreServerService

        let server = CalibreServer(
            uuid: UUID(),
            name: "Contract",
            baseUrl: baseUrl,
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: !username.isEmpty,
            username: username,
            password: password
        )
        let probed = await probe(server, at: serverURL)
        XCTAssertTrue(probed.reachable, "probe: \(probed.errorMsg)")
        guard probed.reachable else { throw probed.error ?? CalibreAPIError.serverUnreachable }
        container.calibreServerInfoStaging = [server.uuid.uuidString: probed]

        library = CalibreLibrary(
            server: server,
            key: probed.defaultLibrary,
            name: probed.libraryMap[probed.defaultLibrary] ?? probed.defaultLibrary
        )
        book = try await firstBook(in: library)
    }

    override func tearDown() async throws {
        book = nil
        library = nil
        service = nil
        container = nil
        AppContainer.shared = nil
        try await super.tearDown()
    }

    /// calibre keeps one position per user, device and format, and stamps it with its own clock:
    /// the epoch the app sends is dropped. `syncPositions` takes a remote position whose epoch is
    /// newer, so across devices "latest" means latest uploaded, not latest read.
    func testReadingPositionRoundTripsStampedByTheServer() async throws {
        let device = "contract-\(UUID().uuidString)"
        let sentEpoch: Double = 1_000_000
        let uploadStart = Date().timeIntervalSince1970

        try await upload(CalibreBookLastReadPositionEntry(device: device, cfi: "/2/4/2", epoch: sentEpoch, pos_frac: 0.25))
        try await upload(CalibreBookLastReadPositionEntry(device: device, cfi: "/2/6/4", epoch: sentEpoch, pos_frac: 0.5))

        let positions = try await fetchAnnotations().last_read_positions.filter { $0.device == device }
        XCTAssertEqual(positions.count, 1, "one position per device")
        let position = try XCTUnwrap(positions.first)
        XCTAssertEqual(position.cfi, "/2/6/4")
        XCTAssertEqual(position.pos_frac, 0.5, accuracy: 0.0001)
        XCTAssertNotEqual(position.epoch, sentEpoch)
        XCTAssertGreaterThanOrEqual(position.epoch, uploadStart - 60, "stamped by the server's clock")
    }

    /// Two devices can upload one highlight in either order; calibre keeps the newest timestamp,
    /// so a device that hasn't synced yet can't overwrite a newer edit.
    func testAnOlderHighlightDoesNotReplaceANewerOne() async throws {
        let id = UUID().uuidString
        let now = Date()

        try await upload(highlights: [highlight(id: id, date: now, content: "newer", note: "new note")])
        try await upload(highlights: [highlight(id: id, date: now.addingTimeInterval(-3600), content: "older", note: "old note")])

        let stored = try await storedHighlights(id: id)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.highlightedText, "newer")
        XCTAssertEqual(stored.first?.notes, "new note")
        XCTAssertEqual(uuidCalibreToFolio(stored.first?.uuid), id, "the highlight id survives the round trip")
    }

    /// A removal is a newer copy marked removed. A stale copy from a device that missed it
    /// doesn't bring the highlight back, and the tombstone decodes as the app expects.
    func testARemovedHighlightStaysRemoved() async throws {
        let id = UUID().uuidString
        let now = Date()

        try await upload(highlights: [highlight(id: id, date: now, content: "to remove")])
        try await upload(highlights: [highlight(id: id, date: now.addingTimeInterval(60), content: "to remove", removed: true)])
        try await upload(highlights: [highlight(id: id, date: now.addingTimeInterval(30), content: "stale copy")])

        let stored = try await storedHighlights(id: id)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.removed, true)
    }

    /// Bookmarks merge like highlights: the newest timestamp wins, and a removal stays removed.
    func testAnOlderBookmarkDoesNotReplaceANewerOne() async throws {
        let title = "Contract \(UUID().uuidString)"
        let now = Date()

        try await upload(bookmarks: [bookmark(title: title, pos: "epubcfi(/6/4)", date: now)])
        try await upload(bookmarks: [bookmark(title: title, pos: "epubcfi(/6/4)", date: now.addingTimeInterval(-3600))])
        try await upload(bookmarks: [bookmark(title: title, pos: "epubcfi(/6/4)", date: now.addingTimeInterval(60), removed: true)])
        try await upload(bookmarks: [bookmark(title: title, pos: "epubcfi(/6/4)", date: now.addingTimeInterval(30))])

        let stored = try await storedBookmarks(title: title)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.removed, true)
    }

    /// calibre tells bookmarks apart by title, not position: two with one title are one bookmark
    /// to the server, and only the newer is kept. So the app gives each of a book's bookmarks a
    /// title of its own, and merges calibre's by title (`BookmarkMerge`).
    func testBookmarksWithOneTitleAreOneBookmark() async throws {
        let title = "Chapter \(UUID().uuidString)"
        let now = Date()

        try await upload(bookmarks: [bookmark(title: title, pos: "epubcfi(/6/4)", date: now.addingTimeInterval(-60))])
        try await upload(bookmarks: [bookmark(title: title, pos: "epubcfi(/6/8)", date: now)])

        let stored = try await storedBookmarks(title: title)
        XCTAssertEqual(stored.map(\.pos), ["epubcfi(/6/8)"])
    }

    /// Two devices keep each bookmark through calibre, syncing as `BookMetadataSyncWorker` does:
    /// - two bookmarks a device titles alike get numbers, and both reach the other device;
    /// - a retitled bookmark's old title is removed, so it isn't a second bookmark there;
    /// - a removal reaches the other device and stays removed.
    /// Once they agree, neither uploads anything.
    func testTwoDevicesKeepEachBookmark() async throws {
        let chapter = "Chapter \(UUID().uuidString)"
        let deviceA = makeBookmarkDevice(), deviceB = makeBookmarkDevice()
        for pos in ["epubcfi(/6/4)", "epubcfi(/6/8)"] {
            _ = deviceA.saveBookmark(bookmark(title: chapter, pos: pos, date: Date()))
        }

        var uploaded = try await syncBookmarks(deviceA, titled: chapter)
        XCTAssertEqual(uploaded.map(\.title), [chapter, "\(chapter) #2"])
        _ = try await syncBookmarks(deviceB, titled: chapter)
        XCTAssertEqual(visibleBookmarks(deviceB, titled: chapter), ["epubcfi(/6/4)": chapter, "epubcfi(/6/8)": "\(chapter) #2"])
        uploaded = try await syncBookmarks(deviceA, titled: chapter)
        XCTAssertTrue(uploaded.isEmpty, "\(uploaded.map(\.title))")

        var retitled = try XCTUnwrap(deviceA.getBookmark(byPos: "epubcfi(/6/8)", bookId: book.bookPrefId))
        retitled.title = "\(chapter) storm"
        retitled.date = Date()
        XCTAssertEqual(deviceA.saveBookmark(retitled).0, 2)
        uploaded = try await syncBookmarks(deviceA, titled: chapter)
        XCTAssertEqual(uploaded.map(\.title), ["\(chapter) #2", "\(chapter) storm"])
        _ = try await syncBookmarks(deviceB, titled: chapter)
        XCTAssertEqual(visibleBookmarks(deviceB, titled: chapter), ["epubcfi(/6/4)": chapter, "epubcfi(/6/8)": "\(chapter) storm"])

        deviceB.removeBookmark(pos: "epubcfi(/6/4)", bookId: book.bookPrefId)
        uploaded = try await syncBookmarks(deviceB, titled: chapter)
        XCTAssertEqual(uploaded.map(\.removed), [true])
        _ = try await syncBookmarks(deviceA, titled: chapter)
        XCTAssertEqual(visibleBookmarks(deviceA, titled: chapter), ["epubcfi(/6/8)": "\(chapter) storm"])

        for device in [deviceA, deviceB] {
            uploaded = try await syncBookmarks(device, titled: chapter)
            XCTAssertTrue(uploaded.isEmpty, "\(uploaded.map(\.title))")
        }
        let stored = (try await fetchAnnotations().annotations_map.bookmark ?? []).filter { $0.title.hasPrefix(chapter) }
        XCTAssertEqual(stored.filter { $0.removed != true }.map(\.title), ["\(chapter) storm"])
    }

    /// Positions and annotations are the user's own data: calibre lets a read-only account
    /// (which can't change the library) save them.
    func testAReadOnlyUserStillSavesItsReadingPosition() async throws {
        let readOnly = try await library(as: "READONLY", named: "Read-only")
        let device = "contract-readonly-\(UUID().uuidString)"

        try await upload(CalibreBookLastReadPositionEntry(device: device, cfi: "/2/4/2", epoch: 0, pos_frac: 0.75), in: readOnly)

        let positions = try await fetchAnnotations(in: readOnly).last_read_positions.filter { $0.device == device }
        XCTAssertEqual(positions.map(\.cfi), ["/2/4/2"])
    }

    /// The task delegate answers calibre's Digest challenge with the server's credential, then
    /// gives up: credentials calibre rejects end as a cancelled request, which the probe reports as
    /// possibly needing authentication.
    ///
    /// setUp already cached a session for the right password. A changed password gets a session
    /// of its own, which answers with it, and the right password still works afterwards.
    func testAWrongPasswordIsReportedByTheProbe() async throws {
        let server = library.server
        guard server.hasAuth, let serverURL = URL(string: server.baseUrl) else {
            throw XCTSkip("Needs a calibre-server with authentication")
        }
        var wrongPassword = server
        wrongPassword.password = "wrong-\(UUID().uuidString)"

        assertRejected(await probe(wrongPassword, at: serverURL))

        let probedAgain = await probe(server, at: serverURL)
        XCTAssertTrue(probedAgain.reachable, "the right password: \(probedAgain.errorMsg)")
    }

    func testAnUnknownUserIsReportedByTheProbe() async throws {
        let server = library.server
        guard server.hasAuth, let serverURL = URL(string: server.baseUrl) else {
            throw XCTSkip("Needs a calibre-server with authentication")
        }
        let unknownUser = CalibreServer(
            uuid: UUID(),
            name: "Unknown user",
            baseUrl: server.baseUrl,
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: true,
            username: "contract-nobody-\(UUID().uuidString)",
            password: server.password
        )

        assertRejected(await probe(unknownUser, at: serverURL))
    }

    // MARK: - Library sync

    /// `CalibreLibraryManager.syncLibrary` reads the library's summary: the number of books and the
    /// newest change, which is the search and category caches' generation.
    func testTheSummaryCountsTheBooksAndDatesTheNewestChange() async throws {
        let summary = try await service.getLibrarySummary(library: library)

        XCTAssertGreaterThanOrEqual(summary.bookCount, 1)
        let lastModified = try XCTUnwrap(summary.lastModified)
        let task = try XCTUnwrap(service.buildBooksMetadataTask(library: library, books: [book]))
        let metadata = await service.getBooksMetadata(task: task)
        let entry = try XCTUnwrap(metadata.booksMetadataEntry?[book.id.description] ?? nil)
        let bookLastModified = try XCTUnwrap(parseLastModified(entry.last_modified), entry.last_modified)
        XCTAssertGreaterThanOrEqual(lastModified, bookLastModified)
    }

    /// The summary reads the custom columns from a book's `user_metadata`: calibre lists every
    /// column on every book, valued or not. One made with `calibredb add_custom_column` has
    /// `"display": {}`.
    func testTheSummaryReadsTheCustomColumns() async throws {
        let summary = try await service.getLibrarySummary(library: library)

        let column = try XCTUnwrap(summary.customColumnInfos?["read_progress"], "\(String(describing: summary.customColumnInfos))")
        XCTAssertEqual(column.datatype, "int")
        XCTAssertEqual(column.name, "Read progress")
        XCTAssertEqual(column.display.description, "")
    }

    /// calibre's `cdb` interface refuses a user with a per-library restriction. The summary's
    /// requests answer within the restriction, which here matches no book.
    func testARestrictedUserGetsTheSummaryOfWhatItMaySee() async throws {
        let restricted = try await library(as: "RESTRICTED", named: "Restricted")

        let summary = try await service.getLibrarySummary(library: restricted)

        XCTAssertEqual(summary, CalibreLibrarySummary(bookCount: 0))
    }

    func testTheCategoriesAreRead() async throws {
        let categories = try await service.getLibraryCategories(library: library)

        XCTAssertTrue(categories.contains { $0.name == "Authors" && $0.is_category }, "\(categories.map(\.name))")
        // The URL names the field the category is searched by (`CalibreLibraryCategory.field`).
        XCTAssertEqual(categories.first { $0.name == "Authors" }?.field, "authors")
    }

    /// A filter keyed by a category's name, as calibre gives it, finds the category's books: the
    /// query uses the field the category's URL names. calibre names categories in the server's
    /// language, so the name isn't a field: run in Chinese (`CALIBRE_OVERRIDE_LANG=zh_CN`), it
    /// calls Authors "作者", and `作者:"=…"` finds nothing.
    func testACategoryFilterFindsTheCategorysBooks() async throws {
        let categories = try await service.getLibraryCategories(library: library)
        var library: CalibreLibrary = library
        library.categoryFields = categories.filter(\.is_category).reduce(into: [:]) { $0[$1.name] = $1.field }
        let authors = try XCTUnwrap(categories.first { $0.field == "authors" })
        let authorItems = try await container.libraryCategoryService.fetchAndCacheCategory(library: library, category: authors)
        let author = try XCTUnwrap(authorItems.items.first)

        let criteria = SearchCriteria(
            searchString: "",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [authors.name: [author.name]]
        )
        let task = try XCTUnwrap(
            service.buildLibrarySearchTasks(library: library, searchCriteria: criteria, parameters: [:]).first { $0.booksListUrl.isHTTP }
        )
        let (data, _) = try await service.validatedData(from: task.booksListUrl, server: library.server)
        let result = try service.decodePayload(CalibreLibraryBooksResult.SearchResult.self, from: data)

        XCTAssertGreaterThan(author.count, 0)
        XCTAssertEqual(result.total_num, author.count, "\(task.booksListUrl)")
    }

    /// A whole sync through the manager: the summary and categories, and no book taken for deleted.
    func testASyncReadsTheLibrary() async throws {
        let libraryManager = container.libraryManager
        libraryManager.calibreLibraries[library.id] = library

        await libraryManager.syncLibrary(request: .init(library: library))

        let status = try XCTUnwrap(libraryManager.librarySyncStatus[library.id])
        XCTAssertFalse(status.isError, status.msg ?? "")
        XCTAssertEqual(status.msg, "Success")
        XCTAssertGreaterThanOrEqual(status.cnt ?? 0, 1)
        XCTAssertEqual(status.del, [])
        XCTAssertNotNil(libraryManager.calibreLibraries[library.id]?.customColumnInfos["read_progress"])
    }

    /// calibre answers null for a book it doesn't have. The app reports that book as deleted on
    /// the server, per book, and keeps its record: a shelf book's files are still the user's.
    func testABookCalibreDoesNotHaveIsReportedDeleted() async throws {
        let missingId = Int32.random(in: 900_000 ..< 1_000_000)
        let bookManager = container.bookManager
        for id in [book.id, missingId] {
            var shelved = CalibreBook(id: id, library: library)
            shelved.inShelf = true
            bookManager.updateBook(book: shelved)
        }

        await bookManager.getBooksMetadata(request: .init(library: library, books: [book.id, missingId], getAnnotations: false))

        XCTAssertEqual(container.librarySyncStatus[library.id]?.del, [missingId])
        XCTAssertEqual(bookManager.booksInShelf[book.inShelfId]?.title, "Contract Test Book")
        XCTAssertTrue(bookManager.bookExists(forPrimaryKey: CalibreBook(id: missingId, library: library).inShelfId))
    }

    /// calibre answers a book a restricted user may not see as it does a deleted one, which is why
    /// the app doesn't delete a book on that answer.
    func testABookOutOfARestrictedUsersReachIsAnsweredNull() async throws {
        let restricted = try await library(as: "RESTRICTED", named: "Restricted")
        let task = try XCTUnwrap(service.buildBooksMetadataTask(library: restricted, books: [CalibreBook(id: book.id, library: restricted)]))

        let result = await service.getBooksMetadata(task: task)

        XCTAssertNil(result.error)
        let entry = try XCTUnwrap(result.booksMetadataEntry?[book.id.description], "the book is in the answer")
        XCTAssertNil(entry)
    }

    // MARK: - Metadata

    func testBookMetadataIsRead() async throws {
        let task = try XCTUnwrap(service.buildBooksMetadataTask(library: library, books: [book]))
        let result = await service.getBooksMetadata(task: task)
        XCTAssertNil(result.error)

        let entry = try XCTUnwrap(result.booksMetadataEntry?[book.id.description] ?? nil)
        XCTAssertEqual(entry.title, "Contract Test Book")
        XCTAssertEqual(entry.authors, ["Test Author"])
        XCTAssertGreaterThan(entry.format_metadata["epub"]?.size ?? 0, 0, "\(entry.format_metadata)")
    }

    /// The Goodreads sync writes reading progress to a custom column (`updateMetadata`).
    func testAMetadataWriteIsReadBack() async throws {
        let progress = Int.random(in: 1 ... 99)

        try await service.updateMetadata(library: library, bookId: book.id, metadata: [["#read_progress", progress]])

        let updated = try await service.getMetadata(oldbook: book)
        XCTAssertEqual((updated.userMetadatas["read_progress"] ?? nil) as? Int, progress)
    }

    /// calibre answers a read-only user's change with 403 "The user … does not have permission to
    /// make changes"; the app reports any 401 or 403 as a failed login.
    func testAReadOnlyUsersMetadataWriteIsRefused() async throws {
        let readOnly = try await library(as: "READONLY", named: "Read-only")

        do {
            try await service.updateMetadata(library: readOnly, bookId: book.id, metadata: [["#read_progress", 1]])
            XCTFail("a read-only user changed the metadata")
        } catch CalibreAPIError.authFailed {
        }
    }

    // MARK: - Downloads

    /// `BookDownloadManager` downloads the EPUB with the server's credentials and saves it where
    /// the readers look (`getSavedUrl`). calibre writes the book's current metadata into the file
    /// it sends, so its size can differ from the `format_metadata` size.
    func testADownloadSavesTheEPUB() async throws {
        let savedURL = try XCTUnwrap(getSavedUrl(book: book, format: .EPUB))
        try? FileManager.default.removeItem(at: savedURL)
        defer { try? FileManager.default.removeItem(at: savedURL) }

        let downloads = container.downloadManager
        guard case .success = downloads.startDownload(book, format: .EPUB) else {
            return XCTFail("the download didn't start")
        }

        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline,
              downloads.activeDownloads.values.contains(where: \.isDownloading) || !FileManager.default.fileExists(atPath: savedURL.path) {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let data = try Data(contentsOf: savedURL)
        XCTAssertEqual(data.prefix(4), Data([0x50, 0x4B, 0x03, 0x04]), "an EPUB is a zip")
        XCTAssertTrue(String(decoding: data.prefix(64), as: UTF8.self).contains("mimetypeapplication/epub+zip"))
    }

    // MARK: - Helpers

    private func assertRejected(_ probed: CalibreServerInfo, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(probed.reachable, file: file, line: line)
        guard case .transport(let error) = probed.error else {
            return XCTFail("expected a cancelled request, got \(String(describing: probed.error))", file: file, line: line)
        }
        XCTAssertEqual(error.code, .cancelled, file: file, line: line)
        XCTAssertEqual(probed.errorMsg, "cancelled, server may require authentication", file: file, line: line)
    }

    private func probe(_ server: CalibreServer, at url: URL) async -> CalibreServerInfo {
        let request = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false)
        let info = CalibreServerInfo(server: server, isPublic: false, url: url, reachable: false, probing: true, errorMsg: "", defaultLibrary: "", libraryMap: [:], request: request)
        return await service.probeServerReachability(serverInfo: info)
    }

    /// The seeded library's first book, cached as an EPUB so the app asks for its EPUB annotations.
    private func firstBook(in library: CalibreLibrary) async throws -> CalibreBook {
        let url = try service.makeEndpointURL(
            server: library.server,
            path: "/ajax/search/\(library.key)",
            queryItems: [URLQueryItem(name: "num", value: "1")]
        )
        let (data, _) = try await service.validatedData(from: url, server: library.server, timeout: 30)
        let search = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let bookId = try XCTUnwrap((search["book_ids"] as? [NSNumber])?.first, "the library has no book")

        var book = CalibreBook(id: bookId.int32Value, library: library)
        book.inShelf = true
        book.formats[Format.EPUB.rawValue] = FormatInfo(
            filename: "contract.epub",
            serverSize: 0,
            serverMTime: Date(),
            cached: true,
            cacheSize: 0,
            cacheMTime: Date(),
            manifest: nil
        )
        return book
    }

    /// The library as another seeded user sees it (`YABR_CALIBRE_<user>_USER` and `_PASSWORD`), its
    /// server probed and staged like setUp's.
    private func library(as user: String, named name: String) async throws -> CalibreLibrary {
        let environment = ProcessInfo.processInfo.environment
        guard let username = environment["YABR_CALIBRE_\(user)_USER"],
              let password = environment["YABR_CALIBRE_\(user)_PASSWORD"],
              let serverURL = URL(string: library.server.baseUrl) else {
            throw XCTSkip("Needs the \(name) user: TEST_RUNNER_YABR_CALIBRE_\(user)_USER and _PASSWORD")
        }
        let server = CalibreServer(
            uuid: UUID(),
            name: name,
            baseUrl: library.server.baseUrl,
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: true,
            username: username,
            password: password
        )
        let probed = await probe(server, at: serverURL)
        guard probed.reachable else { throw probed.error ?? CalibreAPIError.serverUnreachable }
        container.calibreServerInfoStaging[server.uuid.uuidString] = probed
        return CalibreLibrary(server: server, key: library.key, name: library.name)
    }

    private func upload(_ entry: CalibreBookLastReadPositionEntry, in library: CalibreLibrary? = nil) async throws {
        let task = try service.buildSetLastReadPositionTask(library: library ?? self.library, bookId: book.id, format: .EPUB, entry: entry)
        let result = await service.setLastReadPositionByTask(task: task)
        if let error = result.error { throw error }
    }

    private func upload(highlights: [BookHighlight] = [], bookmarks: [BookBookmark] = []) async throws {
        let highlightEntries = highlights.compactMap { $0.toCalibreBookAnnotationHighlightEntry() }
        XCTAssertEqual(highlightEntries.count, highlights.count, "every highlight converts")
        let task = try service.buildUpdateAnnotationsTask(
            library: library,
            bookId: book.id,
            format: .EPUB,
            highlights: highlightEntries,
            bookmarks: bookmarks.map { $0.toCalibreBookAnnotationBookmarkEntry() }
        )
        let result = await service.updateAnnotationByTask(task: task)
        if let error = result.error { throw error }
    }

    /// The book's positions and annotations, as the app's sync reads them.
    private func fetchAnnotations(in library: CalibreLibrary? = nil) async throws -> CalibreBookAnnotationsResult {
        var book = self.book!
        if let library {
            book = CalibreBook(id: book.id, library: library)
            book.inShelf = true
            book.formats = self.book.formats
        }
        let task = try XCTUnwrap(service.buildBooksMetadataTask(library: book.library, books: [book], getAnnotations: true))
        let result = await service.getAnnotations(task: task)
        if let error = result.error { throw error }
        return try XCTUnwrap(result.booksAnnotationsEntry?["\(book.id):\(Format.EPUB.rawValue)"])
    }

    /// A device's bookmarks: its own in-memory database.
    private func makeBookmarkDevice() -> RealmAnnotationRepository {
        let databaseService = DatabaseService()
        databaseService.setup(conf: MockDatabaseService.inMemoryConfiguration())
        return RealmAnnotationRepository(databaseService: databaseService)
    }

    /// Syncs a device's bookmarks as `BookMetadataSyncWorker` does: merges the server's and
    /// uploads what the merge returns. The server keeps earlier runs' bookmarks, so only those
    /// whose title starts with `prefix` take part. Returns the upload.
    private func syncBookmarks(_ device: RealmAnnotationRepository, titled prefix: String) async throws -> [CalibreBookAnnotationBookmarkEntry] {
        let remote = (try await fetchAnnotations().annotations_map.bookmark ?? []).filter { $0.title.hasPrefix(prefix) }
        let upload = device.syncBookmarks(entries: remote, forBookId: book.bookPrefId, posType: "epubcfi")
        if !upload.isEmpty {
            let task = try service.buildUpdateAnnotationsTask(library: library, bookId: book.id, format: .EPUB, highlights: [], bookmarks: upload)
            let result = await service.updateAnnotationByTask(task: task)
            if let error = result.error { throw error }
        }
        return upload
    }

    private func visibleBookmarks(_ device: RealmAnnotationRepository, titled prefix: String) -> [String: String] {
        let bookmarks = device.getBookmarks(forBookId: book.bookPrefId, excludeRemoved: true).filter { $0.title.hasPrefix(prefix) }
        return Dictionary(bookmarks.map { ($0.pos, $0.title) }) { [$0, $1].sorted().joined(separator: " + ") }
    }

    private func storedHighlights(id: String) async throws -> [CalibreBookAnnotationHighlightEntry] {
        let calibreId = try XCTUnwrap(uuidFolioToCalibre(id))
        return (try await fetchAnnotations().annotations_map.highlight ?? []).filter { $0.uuid == calibreId }
    }

    private func storedBookmarks(title: String) async throws -> [CalibreBookAnnotationBookmarkEntry] {
        (try await fetchAnnotations().annotations_map.bookmark ?? []).filter { $0.title == title }
    }

    private func bookmark(title: String, pos: String, date: Date, removed: Bool = false) -> BookBookmark {
        BookBookmark(bookId: book.bookPrefId, page: 1, pos_type: "epubcfi", pos: pos, title: title, date: date, removed: removed)
    }

    private func highlight(id: String, date: Date, content: String, note: String? = nil, removed: Bool = false) -> BookHighlight {
        BookHighlight(
            id: id,
            bookId: book.bookPrefId,
            readerName: ReaderType.YabrEPUB.rawValue,
            page: 1,
            startOffset: 0,
            endOffset: 10,
            date: date,
            type: 0,
            note: note,
            content: content,
            cfiStart: "/2/4/2:0",
            cfiEnd: "/2/4/2:10",
            spineName: "index.html",
            removed: removed
        )
    }
}
