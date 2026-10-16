//
//  CalibreServerServiceTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Codex on 2026/6/17.
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
final class CalibreServerServiceTests: XCTestCase {
    var container: AppContainer!
    var service: CalibreServerService!
    var server: CalibreServer!
    var library: CalibreLibrary!

    override func setUp() async throws {
        try await super.setUp()

        container = MockAppContainerFactory.makeContainer(testName: "CalibreServerServiceTests")
        service = container.calibreServerService
        server = CalibreServer(uuid: UUID(), name: "Server", baseUrl: "http://localhost", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        library = CalibreLibrary(server: server, key: "lib1", name: "Library 1")

        let probeRequest = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false)
        let info = CalibreServerInfo(server: server, isPublic: false, url: URL(string: "http://localhost")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: library.id, libraryMap: [library.id: library.name], request: probeRequest)
        container.calibreServerInfoStaging = [server.uuid.uuidString: info]

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)

        for timeout in [10.0, 600.0] {
            for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
                let key = CalibreServerURLSessionKey(server: server, timeout: timeout, qos: qos)
                service.metadataSessions[key] = mockSession
            }
        }
    }

    override func tearDown() async throws {
        library = nil
        server = nil
        service = nil
        container = nil
        AppContainer.shared = nil
        try await super.tearDown()
    }

    func testBuildLibrarySearchTasksUsesOrWithinCategoryAndAndAcrossCategories() throws {
        let criteria = SearchCriteria(
            searchString: "swift",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: [
                "Tags": Set(["Programming", "Food"]),
                "Authors": Set(["Casey"])
            ]
        )

        let tasks = service.buildLibrarySearchTasks(
            library: library,
            searchCriteria: criteria,
            parameters: [:]
        )

        let task = try XCTUnwrap(tasks.first { $0.booksListUrl.scheme != "file" })
        let queryItems = try XCTUnwrap(
            URLComponents(url: task.booksListUrl, resolvingAgainstBaseURL: false)?.queryItems
        )
        let query = try XCTUnwrap(queryItems.first { $0.name == "query" }?.value)

        XCTAssertTrue(query.contains("swift"))
        XCTAssertTrue(query.contains(" AND "))
        XCTAssertTrue(query.contains("authors:\"=Casey\""))
        XCTAssertTrue(
            query.contains("tags:\"=Programming\" OR tags:\"=Food\"")
            || query.contains("tags:\"=Food\" OR tags:\"=Programming\"")
        )
    }

    /// calibre names categories in the server's language. A filter keyed by such a name searches
    /// the field calibre gave for it, not the name.
    func testBuildLibrarySearchTasksSearchesTheFieldCalibreNamedForACategory() throws {
        var library: CalibreLibrary = library
        library.categoryFields = ["作者": "authors", "评分": "rating"]
        let criteria = SearchCriteria(
            searchString: "",
            sortCriteria: LibrarySearchSort(by: .Title, ascending: true),
            filterCriteriaCategory: ["作者": Set(["Test Author"]), "评分": Set(["★★★★"])]
        )

        let tasks = service.buildLibrarySearchTasks(library: library, searchCriteria: criteria, parameters: [:])

        let task = try XCTUnwrap(tasks.first { $0.booksListUrl.scheme != "file" })
        let query = try XCTUnwrap(
            URLComponents(url: task.booksListUrl, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "query" }?.value
        )
        XCTAssertTrue(query.contains("authors:\"=Test Author\""), query)
        XCTAssertTrue(query.contains("rating:4"), query)
        XCTAssertFalse(query.contains("作者"), query)
    }

    func testValidatedDataMapsUnauthorizedToAuthFailed() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("unauthorized".utf8))
        }

        let request = URLRequest(url: URL(string: "http://localhost/protected")!)

        do {
            _ = try await service.validatedData(for: request, server: server)
            XCTFail("Expected auth failure")
        } catch let error as CalibreAPIError {
            guard case .authFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    /// A summary asks `ajax/search` for the newest change, then `ajax/books` for that book, and
    /// reads the columns from its `user_metadata`, shaped as calibre 9.11 sends them: a column made
    /// with `calibredb add_custom_column` has `"display": {}`, and `is_multiple` is a separator.
    func testGetLibrarySummaryReadsTheCountTheNewestChangeAndTheColumns() async throws {
        var requested = [String]()
        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            requested.append(url.path)
            let json: String
            switch (url.path, Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })) {
            case ("/ajax/search/lib1", ["sort": "last_modified", "sort_order": "desc", "num": "1"]):
                json = Self.searchJSON(bookIds: [7], count: 12)
            case ("/ajax/books/lib1", ["ids": "7", "category_urls": "false"]):
                json = Self.booksJSON
            default:
                return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }

        let summary = try await service.getLibrarySummary(library: library)

        XCTAssertEqual(requested, ["/ajax/search/lib1", "/ajax/books/lib1"])
        XCTAssertEqual(summary.bookCount, 12)
        XCTAssertEqual(summary.lastModified, parseLastModified("2026-10-14T09:46:20.123456+00:00"))
        let columns = try XCTUnwrap(summary.customColumnInfos)
        XCTAssertEqual(Set(columns.keys), ["read_progress", "genre", "stars"])
        XCTAssertEqual(columns["read_progress"]?.name, "Read progress")
        XCTAssertEqual(columns["read_progress"]?.datatype, "int")
        XCTAssertEqual(columns["read_progress"]?.display.description, "")
        XCTAssertEqual(columns["read_progress"]?.isMultiple, false)
        XCTAssertEqual(columns["genre"]?.isMultiple, true)
        XCTAssertEqual(columns["genre"]?.multipleSeps["ui_to_list"], ",")
        XCTAssertEqual(columns["stars"]?.datatype, "rating")
        XCTAssertEqual(columns["stars"]?.display.description, "How good")
        XCTAssertEqual(columns["stars"]?.display.allowHalfStars, true)
        XCTAssertEqual(columns["stars"]?.num, 3)
    }

    /// An empty library has no book to describe its columns or date its last change.
    func testGetLibrarySummaryOfAnEmptyLibrary() async throws {
        var requested = [String]()
        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            requested.append(url.path)
            guard url.path == "/ajax/search/lib1" else {
                return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(Self.searchJSON(bookIds: [], count: 0).utf8))
        }

        let summary = try await service.getLibrarySummary(library: library)

        XCTAssertEqual(requested, ["/ajax/search/lib1"])
        XCTAssertEqual(summary, CalibreLibrarySummary(bookCount: 0))
    }

    /// The newest book can be deleted between the two requests: calibre answers null for it.
    func testGetLibrarySummaryWhenTheNewestBookIsGone() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let json = url.path == "/ajax/search/lib1" ? Self.searchJSON(bookIds: [7], count: 1) : #"{"7": null}"#
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }

        let summary = try await service.getLibrarySummary(library: library)

        XCTAssertEqual(summary, CalibreLibrarySummary(bookCount: 1))
    }

    func testGetLibrarySummaryFailureThrowsTheServersAnswer() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 422,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/plain"]
            )!
            return (response, Data("bad search request".utf8))
        }

        do {
            _ = try await service.getLibrarySummary(library: library)
            XCTFail("Expected failure, but received value")
        } catch {
            XCTAssertEqual(error.localizedDescription, "bad search request")
        }
    }

    private static func searchJSON(bookIds: [Int32], count: Int) -> String {
        """
        {"total_num": \(count), "sort_order": "desc", "num_books_without_search": \(count), "offset": 0,
         "num": \(bookIds.count), "sort": "last_modified", "base_url": "/ajax/search/lib1", "query": null,
         "library_id": "lib1", "book_ids": \(bookIds), "vl": ""}
        """
    }

    private static let booksJSON = """
    {"7": {"title": "Seven", "last_modified": "2026-10-14T09:46:20.123456+00:00", "user_metadata": {
        "#read_progress": {"table": "custom_column_1", "column": "value", "datatype": "int", "is_multiple": null,
            "kind": "field", "name": "Read progress", "search_terms": ["#read_progress"], "label": "read_progress",
            "colnum": 1, "display": {}, "is_custom": true, "is_category": false, "link_column": "value",
            "category_sort": "value", "is_csp": false, "is_editable": true, "rec_index": 23,
            "#value#": 42, "#extra#": null, "is_multiple2": {}},
        "#genre": {"table": "custom_column_2", "column": "value", "datatype": "text", "is_multiple": "|",
            "kind": "field", "name": "Genre", "search_terms": ["#genre"], "label": "genre", "colnum": 2,
            "display": {}, "is_custom": true, "is_category": true, "link_column": "value", "category_sort": "value",
            "is_csp": false, "is_editable": true, "rec_index": 24, "#value#": ["Fantasy", "SF"], "#extra#": null,
            "is_multiple2": {"cache_to_list": "|", "ui_to_list": ",", "list_to_ui": ", "}},
        "#stars": {"table": "custom_column_3", "column": "value", "datatype": "rating", "is_multiple": null,
            "kind": "field", "name": "Stars", "search_terms": ["#stars"], "label": "stars", "colnum": 3,
            "display": {"description": "How good", "allow_half_stars": true}, "is_custom": true,
            "is_category": true, "link_column": "value", "category_sort": "value", "is_csp": false,
            "is_editable": true, "rec_index": 25, "#value#": null, "#extra#": null, "is_multiple2": {}}
    }}}
    """

    func testGetMetadataSuccess() async throws {
        let task = CalibreBookTask(
            server: server,
            bookId: 123,
            inShelfId: "shelf123",
            url: URL(string: "http://localhost/get/json/123/lib1")!
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let json = """
            {
                "title": "Mock Book",
                "uuid": "mock-uuid-1234",
                "authors": ["Author One"],
                "formats": ["epub"],
                "user_metadata": {},
                "tags": [],
                "author_sort": "",
                "title_sort": "",
                "thumbnail": "",
                "timestamp": "",
                "user_categories": {},
                "cover": "",
                "last_modified": "",
                "application_id": 0,
                "author_sort_map": {},
                "identifiers": {},
                "languages": [],
                "pubdate": "",
                "rating": 0.0,
                "format_metadata": {},
                "category_urls": {}
            }
            """
            return (response, Data(json.utf8))
        }

        let (_, receivedEntry) = try await service.getMetadata(task: task)
        XCTAssertEqual(receivedEntry.title, "Mock Book")
        XCTAssertEqual(receivedEntry.uuid, "mock-uuid-1234")
    }

    func testGetMetadataAsyncTaskSuccess() async throws {
        let task = CalibreBookTask(
            server: server,
            bookId: 123,
            inShelfId: "shelf123",
            url: URL(string: "http://localhost/get/json/123/lib1")!
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let json = """
            {
                "title": "Async Mock Book",
                "uuid": "async-mock-uuid",
                "authors": ["Author One"],
                "formats": ["epub"],
                "user_metadata": {},
                "tags": [],
                "author_sort": "",
                "title_sort": "",
                "thumbnail": "",
                "timestamp": "",
                "user_categories": {},
                "cover": "",
                "last_modified": "",
                "application_id": 0,
                "author_sort_map": {},
                "identifiers": {},
                "languages": [],
                "pubdate": "",
                "rating": 0.0,
                "format_metadata": {},
                "category_urls": {}
            }
            """
            return (response, Data(json.utf8))
        }

        let (_, entry) = try await service.getMetadata(task: task)
        XCTAssertEqual(entry.title, "Async Mock Book")
        XCTAssertEqual(entry.uuid, "async-mock-uuid")
    }

    func testGetMetadataFailureHttpStatus() async throws {
        let task = CalibreBookTask(
            server: server,
            bookId: 123,
            inShelfId: "shelf123",
            url: URL(string: "http://localhost/get/json/123/lib1")!
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await service.getMetadata(task: task)
            XCTFail("Expected failure, but received value")
        } catch let receivedError as CalibreAPIError {
            guard case .httpStatus(let statusCode, _) = receivedError else {
                return XCTFail("Expected httpStatus error, but got \(receivedError)")
            }
            XCTAssertEqual(statusCode, 404)
        }
    }

    func testGetMetadataFailureDecode() async throws {
        let task = CalibreBookTask(
            server: server,
            bookId: 123,
            inShelfId: "shelf123",
            url: URL(string: "http://localhost/get/json/123/lib1")!
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("invalid json".utf8))
        }

        do {
            _ = try await service.getMetadata(task: task)
            XCTFail("Expected failure, but received value")
        } catch let receivedError as CalibreAPIError {
            guard case .decoding = receivedError else {
                return XCTFail("Expected decoding error, but got \(receivedError)")
            }
            // expected
        }
    }

    func testGetAnnotationsAsyncSuccess() async throws {
        let request = CalibreBooksMetadataRequest(library: library, books: [123], getAnnotations: true)
        let task = CalibreBooksTask(
            request: request,
            metadataUrl: URL(string: "http://localhost/metadata")!,
            lastReadPositionUrl: URL(string: "http://localhost/last_read")!,
            annotationsUrl: URL(string: "http://localhost/annotations")!
        )

        let mockJSON = """
        {
            "123:epub": {
                "last_read_positions": [],
                "annotations_map": {
                    "bookmark": [],
                    "highlight": []
                }
            }
        }
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(mockJSON.utf8))
        }

        let receivedTask = await service.getAnnotations(task: task)
        XCTAssertNil(receivedTask.error)
        XCTAssertNotNil(receivedTask.booksAnnotationsEntry?["123:epub"])
    }

    func testGetAnnotationsAsyncFailure() async throws {
        let request = CalibreBooksMetadataRequest(library: library, books: [123], getAnnotations: true)
        let task = CalibreBooksTask(
            request: request,
            metadataUrl: URL(string: "http://localhost/metadata")!,
            lastReadPositionUrl: URL(string: "http://localhost/last_read")!,
            annotationsUrl: URL(string: "http://localhost/annotations")!
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("internal error".utf8))
        }

        let result = await service.getAnnotations(task: task)
        if case .httpStatus(let statusCode, _) = result.error {
            XCTAssertEqual(statusCode, 500)
        } else {
            XCTFail("Expected httpStatus error, but got \(String(describing: result.error))")
        }
    }

    func testGetBooksMetadataAsyncSuccess() async throws {
        let request = CalibreBooksMetadataRequest(library: library, books: [123], getAnnotations: false)
        let task = CalibreBooksTask(
            request: request,
            metadataUrl: URL(string: "http://localhost/metadata")!,
            lastReadPositionUrl: URL(string: "http://localhost/last_read")!,
            annotationsUrl: URL(string: "http://localhost/annotations")!
        )

        let mockJSON = """
        {
            "123": {
                "title": "Mock Book",
                "uuid": "mock-uuid-1234",
                "authors": ["Author One"],
                "formats": ["epub"],
                "user_metadata": {},
                "tags": [],
                "author_sort": "",
                "title_sort": "",
                "thumbnail": "",
                "timestamp": "",
                "user_categories": {},
                "cover": "",
                "last_modified": "",
                "application_id": 0,
                "author_sort_map": {},
                "identifiers": {},
                "languages": [],
                "pubdate": "",
                "rating": 0.0,
                "format_metadata": {},
                "category_urls": {}
            }
        }
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(mockJSON.utf8))
        }

        let receivedTask = await service.getBooksMetadata(task: task)
        XCTAssertNil(receivedTask.error)
        let entry = receivedTask.booksMetadataEntry?["123"] as? CalibreBookEntry
        XCTAssertEqual(entry?.title, "Mock Book")
    }

    func testGetBooksMetadataAsyncFailure() async throws {
        let request = CalibreBooksMetadataRequest(library: library, books: [123], getAnnotations: false)
        let task = CalibreBooksTask(
            request: request,
            metadataUrl: URL(string: "http://localhost/metadata")!,
            lastReadPositionUrl: URL(string: "http://localhost/last_read")!,
            annotationsUrl: URL(string: "http://localhost/annotations")!
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 403,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("Forbidden".utf8))
        }

        let result = await service.getBooksMetadata(task: task)
        if case .authFailed = result.error {
            // expected
        } else {
            XCTFail("Expected authFailed error, but got \(String(describing: result.error))")
        }
    }

    func testGetLastReadPositionAsyncSuccessFromHTTP() async throws {
        let request = CalibreBooksMetadataRequest(library: library, books: [123], getAnnotations: true)
        let task = CalibreBooksTask(
            request: request,
            metadataUrl: URL(string: "http://localhost/metadata")!,
            lastReadPositionUrl: URL(string: "http://localhost/last_read")!,
            annotationsUrl: URL(string: "http://localhost/annotations")!
        )

        let mockData = Data("last-read-data".utf8)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, mockData)
        }

        let receivedTask = try await service.getLastReadPosition(task: task)
        XCTAssertEqual(receivedTask.lastReadPositionsData, mockData)
    }

    func testGetLastReadPositionAsyncSuccess() async throws {
        let request = CalibreBooksMetadataRequest(library: library, books: [123], getAnnotations: true)
        let task = CalibreBooksTask(
            request: request,
            metadataUrl: URL(string: "http://localhost/metadata")!,
            lastReadPositionUrl: URL(string: "http://localhost/last_read")!,
            annotationsUrl: URL(string: "http://localhost/annotations")!
        )
        let mockData = Data("async-last-read-data".utf8)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, mockData)
        }

        let result = try await service.getLastReadPosition(task: task)
        XCTAssertEqual(result.lastReadPositionsData, mockData)
    }

    func testGetLastReadPositionAsyncFailure() async throws {
        let request = CalibreBooksMetadataRequest(library: library, books: [123], getAnnotations: true)
        let task = CalibreBooksTask(
            request: request,
            metadataUrl: URL(string: "http://localhost/metadata")!,
            lastReadPositionUrl: URL(string: "http://localhost/last_read")!,
            annotationsUrl: URL(string: "http://localhost/annotations")!
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("bad request".utf8))
        }

        do {
            _ = try await service.getLastReadPosition(task: task)
            XCTFail("Expected failure, but received value")
        } catch let receivedError as CalibreAPIError {
            guard case .httpStatus(let statusCode, _) = receivedError else {
                return XCTFail("Expected httpStatus error, but got \(receivedError)")
            }
            XCTAssertEqual(statusCode, 400)
        }
    }

    func testGetMetadataDataAsyncSuccess() async throws {
        let task = CalibreBookTask(
            server: server,
            bookId: 123,
            inShelfId: "shelf123",
            url: URL(string: "http://localhost/get/json/123/lib1")!
        )

        let mockData = Data("metadata-new-data".utf8)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, mockData)
        }

        let (_, receivedData, _) = try await service.getMetadataData(task: task)
        XCTAssertEqual(receivedData, mockData)
    }

    func testGetMetadataDataAsyncFailure() async throws {
        let task = CalibreBookTask(
            server: server,
            bookId: 123,
            inShelfId: "shelf123",
            url: URL(string: "http://localhost/get/json/123/lib1")!
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 502,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("Bad Gateway".utf8))
        }

        do {
            _ = try await service.getMetadataData(task: task)
            XCTFail("Expected failure, but received value")
        } catch let receivedError as CalibreAPIError {
            guard case .httpStatus(let statusCode, _) = receivedError else {
                return XCTFail("Expected httpStatus error, but got \(receivedError)")
            }
            XCTAssertEqual(statusCode, 502)
        }
    }

    func testThrowingTaskBuilders() throws {
        // test set last read position builder
        let entry = CalibreBookLastReadPositionEntry(
            device: "device1",
            cfi: "cfi-1",
            epoch: 123456789.0,
            pos_frac: 0.5
        )

        let setTask = try service.buildSetLastReadPositionTask(
            library: library,
            bookId: 123,
            format: .EPUB,
            entry: entry
        )

        XCTAssertEqual(setTask.bookId, 123)
        XCTAssertEqual(setTask.format, .EPUB)
        XCTAssertEqual(setTask.urlRequest.url?.absoluteString, "http://localhost/book-set-last-read-position/lib1/123/EPUB")
        XCTAssertEqual(setTask.urlRequest.httpMethod, "POST")

        // test update annotations builder
        let highlight = CalibreBookAnnotationHighlightEntry(
            type: "highlight",
            timestamp: "2026-06-20T00:00:00Z",
            uuid: "uuid-1",
            removed: false,
            ranges: nil,
            startCfi: nil,
            endCfi: nil,
            highlightedText: nil,
            style: nil,
            spineName: nil,
            spineIndex: nil,
            tocFamilyTitles: nil,
            notes: nil
        )
        let bookmark = CalibreBookAnnotationBookmarkEntry(
            type: "bookmark",
            timestamp: "2026-06-20T00:00:00Z",
            pos_type: "epubcfi",
            pos: "cfi",
            title: "bm-title",
            removed: false
        )

        let updateTask = try service.buildUpdateAnnotationsTask(
            library: library,
            bookId: 123,
            format: .EPUB,
            highlights: [highlight],
            bookmarks: [bookmark]
        )

        XCTAssertEqual(updateTask.bookId, 123)
        XCTAssertEqual(updateTask.format, .EPUB)
        XCTAssertEqual(updateTask.urlRequest.url?.absoluteString, "http://localhost/book-update-annotations/lib1/123/EPUB")
        XCTAssertEqual(updateTask.urlRequest.httpMethod, "POST")
    }

    func testUpdateAnnotationByTaskAsyncSuccess() async throws {
        let highlight = CalibreBookAnnotationHighlightEntry(
            type: "highlight",
            timestamp: "2026-06-20T00:00:00Z",
            uuid: "uuid-1",
            removed: false,
            ranges: nil,
            startCfi: nil,
            endCfi: nil,
            highlightedText: nil,
            style: nil,
            spineName: nil,
            spineIndex: nil,
            tocFamilyTitles: nil,
            notes: nil
        )
        let updateTask = try service.buildUpdateAnnotationsTask(
            library: library,
            bookId: 123,
            format: .EPUB,
            highlights: [highlight],
            bookmarks: []
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("success".utf8))
        }

        let receivedTask = await service.updateAnnotationByTask(task: updateTask)
        XCTAssertNil(receivedTask.error)
        XCTAssertEqual(receivedTask.data, Data("success".utf8))
    }

    func testUpdateAnnotationByTaskAsyncFailure() async throws {
        let highlight = CalibreBookAnnotationHighlightEntry(
            type: "highlight",
            timestamp: "2026-06-20T00:00:00Z",
            uuid: "uuid-1",
            removed: false,
            ranges: nil,
            startCfi: nil,
            endCfi: nil,
            highlightedText: nil,
            style: nil,
            spineName: nil,
            spineIndex: nil,
            tocFamilyTitles: nil,
            notes: nil
        )
        let updateTask = try service.buildUpdateAnnotationsTask(
            library: library,
            bookId: 123,
            format: .EPUB,
            highlights: [highlight],
            bookmarks: []
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("internal error".utf8))
        }

        let result = await service.updateAnnotationByTask(task: updateTask)
        if case .httpStatus(let statusCode, _) = result.error {
            XCTAssertEqual(statusCode, 500)
        } else {
            XCTFail("Expected httpStatus error, but got \(String(describing: result.error))")
        }
    }

    func testSetLastReadPositionByTaskAsyncSuccess() async throws {
        let entry = CalibreBookLastReadPositionEntry(
            device: "device1",
            cfi: "cfi-1",
            epoch: 123456789.0,
            pos_frac: 0.5
        )
        let setTask = try service.buildSetLastReadPositionTask(
            library: library,
            bookId: 123,
            format: .EPUB,
            entry: entry
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("success".utf8))
        }

        let receivedTask = await service.setLastReadPositionByTask(task: setTask)
        XCTAssertNil(receivedTask.error)
        XCTAssertEqual(receivedTask.data, Data("success".utf8))
    }

    func testSetLastReadPositionByTaskAsyncFailure() async throws {
        let entry = CalibreBookLastReadPositionEntry(
            device: "device1",
            cfi: "cfi-1",
            epoch: 123456789.0,
            pos_frac: 0.5
        )
        let setTask = try service.buildSetLastReadPositionTask(
            library: library,
            bookId: 123,
            format: .EPUB,
            entry: entry
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("unauthorized".utf8))
        }

        let result = await service.setLastReadPositionByTask(task: setTask)
        if case .authFailed = result.error {
            // expected
        } else {
            XCTFail("Expected authFailed error, but got \(String(describing: result.error))")
        }
    }

    func testGetMetadataAsyncSuccess() async throws {
        var book = CalibreBook(id: 123, library: library)
        book.title = "Test Book"
        book.authors = ["Author 1"]
        let cachedMTime = Date(timeIntervalSince1970: 100)
        book.formats = [
            "EPUB": FormatInfo(
                serverSize: 100,
                serverMTime: Date(timeIntervalSince1970: 50),
                cached: true,
                cacheSize: 99,
                cacheMTime: cachedMTime
            )
        ]

        var entry = CalibreBookEntry()
        entry.title = "Updated Title"
        entry.publisher = "Publisher X"
        entry.series = "Series Y"
        entry.series_index = 2.0
        entry.pubdate = "2026-06-20T10:00:00Z"
        entry.timestamp = "2026-06-20T10:00:00Z"
        entry.last_modified = "2026-06-20T10:00:00Z"
        entry.tags = ["Tag1"]
        entry.format_metadata = ["EPUB": CalibreBookFormatMetadataEntry(size: 200, mtime: "2026-06-20T10:00:00Z")]
        entry.rating = 4.5
        entry.authors = ["Author A"]
        entry.identifiers = ["goodreads": "12345"]
        entry.comments = "New Comments"

        let jsonEncoder = JSONEncoder()
        let payload = try jsonEncoder.encode(entry)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, payload)
        }

        let result = try await service.getMetadata(oldbook: book)
        XCTAssertEqual(result.title, "Updated Title")
        XCTAssertEqual(result.publisher, "Publisher X")
        XCTAssertEqual(result.rating, 9)
        XCTAssertEqual(result.formats["EPUB"]?.serverSize, 200)
        XCTAssertEqual(result.formats["EPUB"]?.cached, true)
        XCTAssertEqual(result.formats["EPUB"]?.cacheSize, 99)
        XCTAssertEqual(result.formats["EPUB"]?.cacheMTime, cachedMTime)
    }

    func testGetMetadataAsyncFailure() async throws {
        var book = CalibreBook(id: 123, library: library)
        book.title = "Test Book"
        book.authors = ["Author 1"]
        book.formats = ["EPUB": FormatInfo(serverSize: 100, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date())]

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("Not Found".utf8))
        }

        do {
            _ = try await service.getMetadata(oldbook: book)
            XCTFail("Expected error, but succeeded")
        } catch {
            // expected
        }
    }

    func testGetBookManifestAsyncSuccess() async throws {
        var book = CalibreBook(id: 123, library: library)
        book.title = "Test Book"
        book.authors = ["Author 1"]

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("manifest-data".utf8))
        }

        let data = try await service.getBookManifest(book: book, format: .EPUB)
        XCTAssertEqual(String(data: data, encoding: .utf8), "manifest-data")
    }

    func testGetBookManifestAsyncFailure() async throws {
        var book = CalibreBook(id: 123, library: library)
        book.title = "Test Book"
        book.authors = ["Author 1"]

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await service.getBookManifest(book: book, format: .EPUB)
            XCTFail("Expected error, but succeeded")
        } catch {
            // expected
        }
    }

    func testUpdateMetadataAsyncSuccess() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        try await service.updateMetadata(library: library, bookId: 123, metadata: [])
    }

    func testUpdateMetadataAsyncFailure() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        do {
            try await service.updateMetadata(library: library, bookId: 123, metadata: [])
            XCTFail("Expected error, but succeeded")
        } catch {
            // expected
        }
    }

    func testGetLibraryCategoriesAsyncFailure() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await service.getLibraryCategories(library: library)
            XCTFail("Expected failure, but received value")
        } catch {
            // expected
        }
    }

    func testStartDownloadFailureMissingFormatInfo() async throws {
        var book = CalibreBook(id: 123, library: library)
        book.title = "Test Book"
        book.authors = ["Author 1"]
        book.formats = [:] // no EPUB format

        let result = container.downloadManager.startDownload(book, format: .EPUB)
        if case .failure(let error) = result {
            XCTAssertEqual(error, DownloadStartError.missingFormatInfo)
        } else {
            XCTFail("Expected failure, got success")
        }
    }

    func testStartDownloadFailureFileAlreadyExists() async throws {
        var book = CalibreBook(id: 123, library: library)
        book.title = "Test Book"
        book.authors = ["Author 1"]
        book.formats = ["EPUB": FormatInfo(serverSize: 100, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date())]

        // Let's mock a file at the saved URL
        guard let savedURL = getSavedUrl(book: book, format: .EPUB) else {
            return XCTFail("Unable to get saved URL")
        }

        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: savedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileManager.createFile(atPath: savedURL.path, contents: Data("test".utf8))
        defer {
            try? fileManager.removeItem(at: savedURL)
        }

        let result = container.downloadManager.startDownload(book, format: .EPUB, overwrite: false)
        if case .failure(let error) = result {
            XCTAssertEqual(error, DownloadStartError.fileAlreadyExists)
        } else {
            XCTFail("Expected failure, got success")
        }
    }

    func testProbeServerReachabilitySuccess() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let json = """
            {
                "default_library": "lib1",
                "library_map": {"lib1": "Library 1"}
            }
            """
            return (response, json.data(using: .utf8)!)
        }

        let probeRequest = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false)
        let info = CalibreServerInfo(server: server, isPublic: false, url: URL(string: "http://localhost")!, reachable: false, probing: false, errorMsg: "", defaultLibrary: "", libraryMap: [:], request: probeRequest)

        let result = await service.probeServerReachability(serverInfo: info)
        XCTAssertTrue(result.reachable)
        XCTAssertEqual(result.defaultLibrary, "lib1")
        XCTAssertEqual(result.libraryMap["lib1"], "Library 1")
        XCTAssertEqual(result.errorMsg, "Success")
    }

    func testProbeLibrarySuccess() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let json = """
            {
                "total_num": 10,
                "sort_order": "asc",
                "num_books_without_search": 10,
                "offset": 0,
                "num": 0,
                "sort": "title",
                "base_url": "/ajax/search/lib1",
                "query": "",
                "library_id": "lib1",
                "book_ids": [],
                "vl": ""
            }
            """
            return (response, json.data(using: .utf8)!)
        }

        let resultTask = await service.probeLibrary(library: library)
        XCTAssertNotNil(resultTask.probeResult)
        XCTAssertEqual(resultTask.probeResult?.total_num, 10)
    }

    func testGetLibraryCategoriesSuccess() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            guard url.path == "/ajax/categories/lib1" else {
                return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let json = """
            [
                {"name": "Authors", "url": "/ajax/categories/authors", "icon": "author", "is_category": true}
            ]
            """
            return (response, json.data(using: .utf8)!)
        }

        let categories = try await service.getLibraryCategories(library: library)
        XCTAssertEqual(categories.count, 1)
        XCTAssertEqual(categories.first?.name, "Authors")
    }

    func testValidatedDataAsyncSuccess() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"ok":true}"#.utf8))
        }

        let (receivedData, response) = try await service.validatedData(for: URLRequest(url: URL(string: "http://localhost/ok")!), server: server)
        XCTAssertEqual(receivedData, Data(#"{"ok":true}"#.utf8))
        XCTAssertEqual(response.statusCode, 200)
    }

    func testValidatedDataAsyncMapsNon2xxStatus() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 503,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/plain"]
            )!
            return (response, Data("unavailable".utf8))
        }

        do {
            _ = try await service.validatedData(for: URLRequest(url: URL(string: "http://localhost/failure")!), server: server)
            XCTFail("Expected failure")
        } catch let receivedError as CalibreAPIError {
            guard case .httpStatus(let statusCode, let body) = receivedError else {
                return XCTFail("Expected httpStatus, got \(receivedError)")
            }
            XCTAssertEqual(statusCode, 503)
            XCTAssertEqual(body.flatMap { String(data: $0, encoding: .utf8) }, "unavailable")
        }
    }

    func testValidatedDataAsyncMapsUnauthorizedToAuthFailed() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 403,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await service.validatedData(for: URLRequest(url: URL(string: "http://localhost/auth")!), server: server)
            XCTFail("Expected failure")
        } catch let receivedError as CalibreAPIError {
            guard case .authFailed = receivedError else {
                return XCTFail("Expected authFailed, got \(receivedError)")
            }
        }
    }

    func testValidatedDataAsyncMapsTransportError() async throws {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.badServerResponse)
        }

        do {
            _ = try await service.validatedData(for: URLRequest(url: URL(string: "http://localhost/bad-response")!), server: server)
            XCTFail("Expected failure")
        } catch let receivedError as CalibreAPIError {
            guard case .transport(let error) = receivedError else {
                return XCTFail("Expected transport error, got \(receivedError)")
            }
            XCTAssertEqual(error.code, .badServerResponse)
        }
    }

    func testProbeServerReachabilityAsyncSuccessPreservesErrorField() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let json = """
            {
                "default_library": "lib1",
                "library_map": {"lib1": "Library 1"}
            }
            """
            return (response, Data(json.utf8))
        }

        let request = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false)
        let info = CalibreServerInfo(server: server, isPublic: false, url: URL(string: "http://localhost")!, reachable: false, probing: false, errorMsg: "", defaultLibrary: "", libraryMap: [:], request: request)
        let result = await service.probeServerReachability(serverInfo: info)
        XCTAssertTrue(result.reachable)
        XCTAssertEqual(result.defaultLibrary, "lib1")
        XCTAssertEqual(result.libraryMap["lib1"], "Library 1")
        XCTAssertNil(result.error)
    }

    func testProbeServerReachabilityAsyncReportsNoLibraryAsUnsupportedPayload() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"default_library":null,"library_map":{}}"#.utf8))
        }

        let request = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false)
        let info = CalibreServerInfo(server: server, isPublic: false, url: URL(string: "http://localhost")!, reachable: false, probing: false, errorMsg: "", defaultLibrary: "", libraryMap: [:], request: request)
        let result = await service.probeServerReachability(serverInfo: info)
        XCTAssertFalse(result.reachable)
        XCTAssertEqual(result.errorMsg, "Server has no library")
        guard case .unsupportedPayload = result.error else {
            return XCTFail("Expected unsupportedPayload, got \(String(describing: result.error))")
        }
    }

    func testProbeServerReachabilityAsyncReportsHttpFailure() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("server down".utf8))
        }

        let request = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false)
        let info = CalibreServerInfo(server: server, isPublic: false, url: URL(string: "http://localhost")!, reachable: false, probing: false, errorMsg: "", defaultLibrary: "", libraryMap: [:], request: request)
        let result = await service.probeServerReachability(serverInfo: info)
        XCTAssertFalse(result.reachable)
        XCTAssertEqual(result.errorMsg, "server down")
        guard case .httpStatus(let statusCode, _) = result.error else {
            return XCTFail("Expected httpStatus, got \(String(describing: result.error))")
        }
        XCTAssertEqual(statusCode, 500)
    }

    // MARK: - Session cache

    /// A session's task delegate answers calibre's challenge with the password the session was
    /// created with, so a changed password for the same URL and username needs its own session.
    func testSessionsAreNotSharedAcrossPasswords() throws {
        let saved = authenticatedServer(password: "old-pass")
        var changed = saved
        changed.password = "new-pass"
        XCTAssertEqual(saved, changed, "a server's identity leaves the password out")

        let savedSession = service.urlSession(server: saved)
        let changedSession = service.urlSession(server: changed)

        XCTAssertFalse(savedSession === changedSession)
        XCTAssertTrue(service.urlSession(server: changed) === changedSession, "the same password reuses its session")
        let credential = try XCTUnwrap((changedSession.delegate as? CalibreServerTaskDelegate)?.userCredential)
        XCTAssertEqual(credential.user, "reader")
        XCTAssertEqual(credential.password, "new-pass")
    }

    func testANewPasswordRetiresTheOldPasswordsSessions() async throws {
        let saved = authenticatedServer(password: "old-pass")
        var changed = saved
        changed.password = "new-pass"
        let savedSessions = [
            service.urlSession(server: saved),
            service.urlSession(server: saved, timeout: 10, qos: .background)
        ]

        let changedSession = service.urlSession(server: changed)

        let cachedKeys = service.metadataSessions.keys.filter { $0.server == saved }
        XCTAssertEqual(cachedKeys.map(\.server.password), ["new-pass"])
        for session in savedSessions {
            await waitUntilInvalidated(session)
        }
        XCTAssertNotNil(changedSession.delegate)
    }

    func testARetiredSessionStaysValidUntilItsRequestEnds() async throws {
        let saved = authenticatedServer(password: "old-pass")
        var changed = saved
        changed.password = "new-pass"

        let leased = await service.withURLSession(server: saved) { session -> URLSession in
            _ = service.urlSession(server: changed)
            // Creating a task in an invalidated session raises, which would stop the test host.
            session.dataTask(with: URL(string: "http://127.0.0.1:9")!).cancel()
            return session
        }

        await waitUntilInvalidated(leased)
    }

    func testRetiringAServerInvalidatesItsSessions() async throws {
        let removed = authenticatedServer(password: "pass")
        let sessions = [
            service.urlSession(server: removed),
            service.urlSession(server: removed, qos: .background)
        ]

        service.retireSessions(for: removed)

        XCTAssertFalse(service.metadataSessions.keys.contains { $0.server == removed })
        for session in sessions {
            await waitUntilInvalidated(session)
        }
    }

    private func authenticatedServer(password: String) -> CalibreServer {
        CalibreServer(uuid: UUID(), name: "Auth", baseUrl: "http://calibre.example:8080", hasPublicUrl: false, publicUrl: "", hasAuth: true, username: "reader", password: password)
    }

    /// An invalidated session lets go of its delegate once the invalidation is delivered.
    private func waitUntilInvalidated(_ session: URLSession, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(10)
        while session.delegate != nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(session.delegate, "the session is invalidated", file: file, line: line)
    }
}
