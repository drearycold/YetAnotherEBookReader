//
//  CalibreServerServiceTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Codex on 2026/6/17.
//

import XCTest
import Combine
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
final class CalibreServerServiceTests: XCTestCase {
    var container: AppContainer!
    var service: CalibreServerService!
    var server: CalibreServer!
    var library: CalibreLibrary!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()

        container = MockAppContainerFactory.makeContainer(testName: "CalibreServerServiceTests")
        service = container.calibreServerService
        cancellables = []

        server = CalibreServer(uuid: UUID(), name: "Server", baseUrl: "http://localhost", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        library = CalibreLibrary(server: server, key: "lib1", name: "Library 1")

        let probeRequest = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
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
        cancellables = nil
        library = nil
        server = nil
        service = nil
        container = nil
        AppContainer.shared = nil
        try await super.tearDown()
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

    func testGetCustomColumnsPublisherReturnsServerBodyAsErrmsg() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 422,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/plain"]
            )!
            return (response, Data("bad custom columns request".utf8))
        }

        let expectation = expectation(description: "publisher emits result")
        var received: CalibreSyncLibraryResult?
        let request = CalibreSyncLibraryRequest(library: library, autoUpdateOnly: false, incremental: false)

        service.getCustomColumnsPublisher(request: request)
            .sink { result in
                received = result
                expectation.fulfill()
            }
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(received?.errmsg, "bad custom columns request")
    }

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

        let expectation = expectation(description: "getMetadata emits success")
        var receivedEntry: CalibreBookEntry?
        var receivedError: CalibreAPIError?

        service.getMetadata(task: task)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { task, entry in
                    receivedEntry = entry
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNil(receivedError, "Expected no error, got \(String(describing: receivedError))")
        XCTAssertEqual(receivedEntry?.title, "Mock Book")
        XCTAssertEqual(receivedEntry?.uuid, "mock-uuid-1234")
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

        let expectation = expectation(description: "getMetadata emits failure status")
        var receivedError: CalibreAPIError?

        service.getMetadata(task: task)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { _, _ in
                    XCTFail("Expected failure, but received value")
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNotNil(receivedError)
        if case .httpStatus(let statusCode, _) = receivedError {
            XCTAssertEqual(statusCode, 404)
        } else {
            XCTFail("Expected httpStatus error, but got \(String(describing: receivedError))")
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

        let expectation = expectation(description: "getMetadata emits failure decode")
        var receivedError: CalibreAPIError?

        service.getMetadata(task: task)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { _, _ in
                    XCTFail("Expected failure, but received value")
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNotNil(receivedError)
        if case .decoding = receivedError {
            // expected
        } else {
            XCTFail("Expected decoding error, but got \(String(describing: receivedError))")
        }
    }

    func testGetAnnotationsPublisherSuccess() async throws {
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

        let expectation = expectation(description: "getAnnotations publisher success")
        var receivedTask: CalibreBooksTask?
        var receivedError: CalibreAPIError?

        service.getAnnotations(task: task)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { task in
                    receivedTask = task
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNil(receivedError)
        XCTAssertNotNil(receivedTask)
        XCTAssertNotNil(receivedTask?.booksAnnotationsEntry?["123:epub"])
    }

    func testGetAnnotationsPublisherFailure() async throws {
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

        let expectation = expectation(description: "getAnnotations publisher failure")
        var receivedError: CalibreAPIError?

        service.getAnnotations(task: task)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { _ in
                    XCTFail("Expected failure, but received value")
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNotNil(receivedError)
        if case .httpStatus(let statusCode, _) = receivedError {
            XCTAssertEqual(statusCode, 500)
        } else {
            XCTFail("Expected httpStatus error, but got \(String(describing: receivedError))")
        }
    }

    func testGetBooksMetadataPublisherSuccess() async throws {
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

        let expectation = expectation(description: "getBooksMetadata publisher success")
        var receivedTask: CalibreBooksTask?
        var receivedError: CalibreAPIError?

        service.getBooksMetadata(task: task)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { task in
                    receivedTask = task
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNil(receivedError)
        XCTAssertNotNil(receivedTask)
        let entry = receivedTask?.booksMetadataEntry?["123"] as? CalibreBookEntry
        XCTAssertEqual(entry?.title, "Mock Book")
    }

    func testGetBooksMetadataPublisherFailure() async throws {
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

        let expectation = expectation(description: "getBooksMetadata publisher failure")
        var receivedError: CalibreAPIError?

        service.getBooksMetadata(task: task)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { _ in
                    XCTFail("Expected failure, but received value")
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNotNil(receivedError)
        if case .authFailed = receivedError {
            // expected
        } else {
            XCTFail("Expected authFailed error, but got \(String(describing: receivedError))")
        }
    }

    func testGetLastReadPositionPublisherSuccess() async throws {
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

        let expectation = expectation(description: "getLastReadPosition publisher success")
        var receivedTask: CalibreBooksTask?
        var receivedError: CalibreAPIError?

        service.getLastReadPosition(task: task)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { task in
                    receivedTask = task
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNil(receivedError)
        XCTAssertNotNil(receivedTask)
        XCTAssertEqual(receivedTask?.lastReadPositionsData, mockData)
    }

    func testGetLastReadPositionPublisherFailure() async throws {
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

        let expectation = expectation(description: "getLastReadPosition publisher failure")
        var receivedError: CalibreAPIError?

        service.getLastReadPosition(task: task)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { _ in
                    XCTFail("Expected failure, but received value")
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNotNil(receivedError)
        if case .httpStatus(let statusCode, _) = receivedError {
            XCTAssertEqual(statusCode, 400)
        } else {
            XCTFail("Expected httpStatus error, but got \(String(describing: receivedError))")
        }
    }

    func testGetMetadataNewPublisherSuccess() async throws {
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

        let expectation = expectation(description: "getMetadataNew publisher success")
        var receivedData: Data?
        var receivedError: CalibreAPIError?

        service.getMetadataNew(task: task)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { task, data, response in
                    receivedData = data
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNil(receivedError)
        XCTAssertEqual(receivedData, mockData)
    }

    func testGetMetadataNewPublisherFailure() async throws {
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

        let expectation = expectation(description: "getMetadataNew publisher failure")
        var receivedError: CalibreAPIError?

        service.getMetadataNew(task: task)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { _, _, _ in
                    XCTFail("Expected failure, but received value")
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNotNil(receivedError)
        if case .httpStatus(let statusCode, _) = receivedError {
            XCTAssertEqual(statusCode, 502)
        } else {
            XCTFail("Expected httpStatus error, but got \(String(describing: receivedError))")
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

    func testUpdateAnnotationByTaskPublisherSuccess() async throws {
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

        let expectation = expectation(description: "updateAnnotationByTask publisher success")
        var receivedTask: CalibreBookUpdateAnnotationsTask?
        var receivedError: CalibreAPIError?

        service.updateAnnotationByTask(task: updateTask)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { task in
                    receivedTask = task
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNil(receivedError)
        XCTAssertNotNil(receivedTask)
        XCTAssertEqual(receivedTask?.data, Data("success".utf8))
    }

    func testUpdateAnnotationByTaskPublisherFailure() async throws {
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

        let expectation = expectation(description: "updateAnnotationByTask publisher failure")
        var receivedError: CalibreAPIError?

        service.updateAnnotationByTask(task: updateTask)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { _ in
                    XCTFail("Expected failure, but received value")
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNotNil(receivedError)
        if case .httpStatus(let statusCode, _) = receivedError {
            XCTAssertEqual(statusCode, 500)
        } else {
            XCTFail("Expected httpStatus error, but got \(String(describing: receivedError))")
        }
    }

    func testSetLastReadPositionByTaskPublisherSuccess() async throws {
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

        let expectation = expectation(description: "setLastReadPositionByTask publisher success")
        var receivedTask: CalibreBookSetLastReadPositionTask?
        var receivedError: CalibreAPIError?

        service.setLastReadPositionByTask(task: setTask)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { task in
                    receivedTask = task
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNil(receivedError)
        XCTAssertNotNil(receivedTask)
        XCTAssertEqual(receivedTask?.data, Data("success".utf8))
    }

    func testSetLastReadPositionByTaskPublisherFailure() async throws {
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

        let expectation = expectation(description: "setLastReadPositionByTask publisher failure")
        var receivedError: CalibreAPIError?

        service.setLastReadPositionByTask(task: setTask)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { _ in
                    XCTFail("Expected failure, but received value")
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNotNil(receivedError)
        if case .authFailed = receivedError {
            // expected
        } else {
            XCTFail("Expected authFailed error, but got \(String(describing: receivedError))")
        }
    }

    func testGetMetadataAsyncSuccess() async throws {
        var book = CalibreBook(id: 123, library: library)
        book.title = "Test Book"
        book.authors = ["Author 1"]
        book.formats = ["EPUB": FormatInfo(serverSize: 100, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date())]

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

    func testSyncLibraryPublisherFailure() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let expectation = expectation(description: "syncLibraryPublisher failure")
        var receivedError: CalibreAPIError?

        let request = CalibreSyncLibraryRequest(library: library, autoUpdateOnly: false, incremental: false)
        let resultPrev = CalibreSyncLibraryResult(request: request, result: [:])

        service.syncLibraryPublisher(resultPrev: resultPrev)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { _ in
                    XCTFail("Expected failure, but received value")
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNotNil(receivedError)
    }

    func testGetLibraryCategoriesPublisherFailure() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let expectation = expectation(description: "getLibraryCategoriesPublisher failure")
        var receivedError: CalibreAPIError?

        let request = CalibreSyncLibraryRequest(library: library, autoUpdateOnly: false, incremental: false)
        let resultPrev = CalibreSyncLibraryResult(request: request, result: [:])

        service.getLibraryCategoriesPublisher(resultPrev: resultPrev)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { _ in
                    XCTFail("Expected failure, but received value")
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNotNil(receivedError)
    }

    func testStartDownloadNewFailureMissingFormatInfo() async throws {
        var book = CalibreBook(id: 123, library: library)
        book.title = "Test Book"
        book.authors = ["Author 1"]
        book.formats = [:] // no EPUB format

        let result = container.downloadManager.startDownloadNew(book, format: .EPUB)
        if case .failure(let error) = result {
            XCTAssertEqual(error, DownloadStartError.missingFormatInfo)
        } else {
            XCTFail("Expected failure, got success")
        }
    }

    func testStartDownloadNewFailureFileAlreadyExists() async throws {
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

        let result = container.downloadManager.startDownloadNew(book, format: .EPUB, overwrite: false)
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

        let probeRequest = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
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

    func testSyncLibrarySuccess() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let json = """
            {
                "book_ids": [1, 2],
                "data": {
                    "last_modified": {
                        "1": {"v": "2023-07-25T03:11:04+00:00"},
                        "2": {"v": "2023-07-25T03:11:04+00:00"}
                    }
                }
            }
            """
            return (response, json.data(using: .utf8)!)
        }

        let syncReq = CalibreSyncLibraryRequest(library: library, autoUpdateOnly: false, incremental: true)
        let resultPrev = CalibreSyncLibraryResult(request: syncReq, result: [:])

        let result = await service.syncLibrary(resultPrev: resultPrev)
        XCTAssertEqual(result.list.book_ids, [1, 2])
        XCTAssertEqual(result.errmsg, "")
    }

    func testGetLibraryCategoriesSuccess() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
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

        let syncReq = CalibreSyncLibraryRequest(library: library, autoUpdateOnly: false, incremental: false)
        let resultPrev = CalibreSyncLibraryResult(request: syncReq, result: [:])

        let result = await service.getLibraryCategories(resultPrev: resultPrev)
        XCTAssertEqual(result.categories.count, 1)
        XCTAssertEqual(result.categories.first?.name, "Authors")
        XCTAssertEqual(result.errmsg, "")
    }
}
