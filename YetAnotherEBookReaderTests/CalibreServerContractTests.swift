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
//    xcodebuild test … -only-testing:YetAnotherEBookReaderTests/CalibreServerContractTests
//
//  The server keeps its state between runs, so every test writes under its own device name or
//  highlight id and only reads those back.
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

    /// The task delegate answers calibre's Digest challenge with the saved credential, then gives
    /// up: credentials calibre rejects end as a cancelled request, which the probe reports as
    /// possibly needing authentication.
    ///
    /// The user is unknown rather than the password wrong: sessions are cached per server URL and
    /// username, so a wrong password for contract-writer would reuse the session that answers with
    /// the right one.
    func testRejectedCredentialsAreReportedByTheProbe() async throws {
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

        let probed = await probe(unknownUser, at: serverURL)

        XCTAssertFalse(probed.reachable)
        guard case .transport(let error) = probed.error else {
            return XCTFail("expected a cancelled request, got \(String(describing: probed.error))")
        }
        XCTAssertEqual(error.code, .cancelled)
        XCTAssertEqual(probed.errorMsg, "cancelled, server may require authentication")
    }

    // MARK: - Helpers

    private func probe(_ server: CalibreServer, at url: URL) async -> CalibreServerInfo {
        let request = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
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

    private func upload(_ entry: CalibreBookLastReadPositionEntry) async throws {
        let task = try service.buildSetLastReadPositionTask(library: library, bookId: book.id, format: .EPUB, entry: entry)
        let result = await service.setLastReadPositionByTask(task: task)
        if let error = result.error { throw error }
    }

    private func upload(highlights: [BookHighlight]) async throws {
        let entries = highlights.compactMap { $0.toCalibreBookAnnotationHighlightEntry() }
        XCTAssertEqual(entries.count, highlights.count, "every highlight converts")
        let task = try service.buildUpdateAnnotationsTask(library: library, bookId: book.id, format: .EPUB, highlights: entries, bookmarks: [])
        let result = await service.updateAnnotationByTask(task: task)
        if let error = result.error { throw error }
    }

    /// The book's positions and annotations, as the app's sync reads them.
    private func fetchAnnotations() async throws -> CalibreBookAnnotationsResult {
        let task = try XCTUnwrap(service.buildBooksMetadataTask(library: library, books: [book], getAnnotations: true))
        let result = await service.getAnnotations(task: task)
        if let error = result.error { throw error }
        return try XCTUnwrap(result.booksAnnotationsEntry?["\(book.id):\(Format.EPUB.rawValue)"])
    }

    private func storedHighlights(id: String) async throws -> [CalibreBookAnnotationHighlightEntry] {
        let calibreId = try XCTUnwrap(uuidFolioToCalibre(id))
        return (try await fetchAnnotations().annotations_map.highlight ?? []).filter { $0.uuid == calibreId }
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
