//
//  DSReaderHelperConnectorTests.swift
//  YetAnotherEBookReaderTests
//
//  Created on 2026/6/18.
//  P1/A09: Verifies that DSReaderHelperConnector.urlSession no longer uses
//  DispatchQueue.main.sync and can be safely accessed from background threads.
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
final class DSReaderHelperConnectorTests: XCTestCase {
    var container: AppContainer!
    var service: CalibreServerService!
    var server: CalibreServer!
    var library: CalibreLibrary!
    var dsreaderHelperServer: CalibreServerDSReaderHelper!

    override func setUp() async throws {
        try await super.setUp()

        container = MockAppContainerFactory.makeContainer(testName: "DSReaderHelperConnectorTests")
        service = container.calibreServerService
        server = CalibreServer(uuid: UUID(), name: "Server", baseUrl: "http://localhost", hasPublicUrl: false, publicUrl: "", hasAuth: true, username: "user", password: "pass")
        library = CalibreLibrary(server: server, key: "lib1", name: "Library 1")

        let probeRequest = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        let info = CalibreServerInfo(server: server, isPublic: false, url: URL(string: "http://localhost")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: library.id, libraryMap: [library.id: library.name], request: probeRequest)
        container.calibreServerInfoStaging = [server.uuid.uuidString: info]

        dsreaderHelperServer = CalibreServerDSReaderHelper(port: 8080)

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
        dsreaderHelperServer = nil
        MockURLProtocol.requestHandler = nil
        library = nil
        server = nil
        service = nil
        container = nil
        AppContainer.shared = nil
        try await super.tearDown()
    }

    func testUrlSessionReturnsCachedSessionFromService() {
        let connector = DSReaderHelperConnector(
            calibreServerService: service,
            server: server,
            dsreaderHelperServer: dsreaderHelperServer,
            goodreadsSync: nil
        )

        let session = connector.urlSession
        XCTAssertNotNil(session)
    }

    func testAdvancedQAEndpointUsesV2RouteAndHelperPort() throws {
        dsreaderHelperServer = CalibreServerDSReaderHelper(port: 8081)
        let connector = DSReaderHelperConnector(
            calibreServerService: service,
            server: server,
            dsreaderHelperServer: dsreaderHelperServer,
            goodreadsSync: nil
        )

        let endpoint = try XCTUnwrap(connector.endpointAdvancedQA()?.url)
        XCTAssertEqual(endpoint.port, 8081)
        XCTAssertEqual(endpoint.path, "/dshelper/2/qa/query")

        let statusEndpoint = try XCTUnwrap(connector.endpointAdvancedQAStatus()?.url)
        XCTAssertEqual(statusEndpoint.port, 8081)
        XCTAssertEqual(statusEndpoint.path, "/dshelper/2/qa/status")

        let jobsEndpoint = try XCTUnwrap(connector.endpointAdvancedQASyncJobs(page: 2, pageSize: 999,
                                                                              status: "error",
                                                                              libraryId: "lib 1")?.url)
        XCTAssertEqual(jobsEndpoint.path, "/dshelper/2/qa/sync-jobs")
        XCTAssertEqual(URLComponents(url: jobsEndpoint, resolvingAgainstBaseURL: false)?.queryItems,
                       [.init(name: "page", value: "2"), .init(name: "page_size", value: "100"),
                        .init(name: "status", value: "error"), .init(name: "library_id", value: "lib 1")])

        let detailEndpoint = try XCTUnwrap(connector.endpointAdvancedQASyncJob(jobId: 7, page: 3,
                                                                               pageSize: 999)?.url)
        XCTAssertEqual(detailEndpoint.path, "/dshelper/2/qa/sync-job/7")
        XCTAssertTrue(detailEndpoint.query?.contains("page_size=500") == true)
    }

    func testAdvancedQAStatusDecodesSyncSummaryWithoutLegacyBooks() async throws {
        dsreaderHelperServer = CalibreServerDSReaderHelper(port: 8081)
        let connector = DSReaderHelperConnector(calibreServerService: service, server: server,
                                                dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: nil)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200,
                                           httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            let json = #"{"enabled":false,"state":"disabled","libraries":[{"library_id":"lib1","display_name":"Library 1","sync":{"job_id":9,"status":"queued","total_books":3,"processed_books":1,"indexed_books":1,"error_count":0,"books":[{"book_id":1}]}}]}"#
            return (response, Data(json.utf8))
        }

        let status = try await connector.queryAdvancedQAStatus()
        XCTAssertEqual(status.libraries.first?.sync?.jobId, 9)
        XCTAssertEqual(status.libraries.first?.sync?.processedBooks, 1)
    }

    func testAdvancedQASyncJobsAndDetailDecodePagination() async throws {
        dsreaderHelperServer = CalibreServerDSReaderHelper(port: 8081)
        let connector = DSReaderHelperConnector(calibreServerService: service, server: server,
                                                dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: nil)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200,
                                           httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            if request.url?.path.contains("/sync-job/") == true {
                return (response, Data(#"{"job":{"job_id":5,"library_id":"lib1","status":"error","total_books":2,"processed_books":2},"books":[{"book_id":4,"format":"EPUB","external_id":"doc-4","status":"error","error":"bad book"}],"pagination":{"page":1,"page_size":100,"total":1,"has_next":false}}"#.utf8))
            }
            return (response, Data(#"{"items":[{"job_id":5,"library_id":"lib1","display_name":"Library 1","status":"error","total_books":2,"processed_books":2}],"pagination":{"page":1,"page_size":50,"total":1,"has_next":false}}"#.utf8))
        }

        let jobs = try await connector.queryAdvancedQASyncJobs()
        XCTAssertEqual(jobs.items.first?.jobId, 5)
        XCTAssertFalse(jobs.pagination.hasNext)
        let detail = try await connector.queryAdvancedQASyncJob(jobId: 5)
        XCTAssertEqual(detail.books.first?.externalId, "doc-4")
        XCTAssertEqual(detail.books.first?.error, "bad book")
    }

    func testAdvancedQAStatusControlsAvailability() async throws {
        dsreaderHelperServer = CalibreServerDSReaderHelper(port: 8081)
        let connector = DSReaderHelperConnector(calibreServerService: service, server: server,
                                                dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: nil)
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/dshelper/2/qa/status")
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200,
                                           httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, Data(#"{"enabled":true,"state":"ready","retrieval_scopes":{"version":1,"default":"current_book","items":[]}}"#.utf8))
        }

        let status = try await connector.queryAdvancedQAStatus()
        XCTAssertTrue(status.isReady)
        var helper = dsreaderHelperServer!
        helper.setAdvancedQAState(status: status, availability: .ready)
        XCTAssertTrue(helper.isAdvancedQAReady)
        XCTAssertEqual(helper.advancedQAStatus?.retrievalScopes?.defaultKind, "current_book")

        helper.setAdvancedQAState(status: .init(enabled: true, state: "unavailable"),
                                  availability: .unavailable)
        XCTAssertFalse(helper.isAdvancedQAReady)
        helper.setAdvancedQAState(status: .init(enabled: false, state: "disabled"),
                                  availability: .disabled)
        XCTAssertFalse(helper.isAdvancedQAReady)
    }

    func testMissingAdvancedQAStatusEndpointMeansUnsupportedLegacyPlugin() async {
        dsreaderHelperServer = CalibreServerDSReaderHelper(port: 8081)
        let connector = DSReaderHelperConnector(calibreServerService: service, server: server,
                                                dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: nil)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 404,
                                           httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let availability = await connector.detectAdvancedQAAvailability()
        XCTAssertEqual(availability, .unsupported)
    }

    func testAdvancedQAUsesDeployedWireContractAndMapsResponse() async throws {
        dsreaderHelperServer = CalibreServerDSReaderHelper(port: 8081)
        var testBook = CalibreBook(id: 42, library: library)
        testBook.title = "Book"
        let context = AdvancedQAContextBuilder.folio(
            book: testBook,
            selection: "term",
            location: .init(page: 3, href: "chapter.xhtml", cfi: "epubcfi(/6/2)")
        )
        let payload = AdvancedQARequest(query: "Explain", mode: .explain,
                                        responseLanguage: "zh-Hans",
                                        readerContext: context, referenceCandidates: [],
                                        retrievalScope: .init(kind: "selected_books", bookIds: [7, 8]))
        let connector = DSReaderHelperConnector(calibreServerService: service, server: server,
                                                dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: nil)
        MockURLProtocol.requestHandler = { request in
            let body = try XCTUnwrap(Self.bodyData(from: request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertNil(json["reader_context"])
            XCTAssertEqual((json["book"] as? [String: Any])?["library_id"] as? String, "lib1")
            XCTAssertEqual((json["book"] as? [String: Any])?["book_id"] as? Int, 42)
            XCTAssertEqual((json["position"] as? [String: Any])?["spine_index"] as? Int, 2)
            XCTAssertEqual(json["mode"] as? String, "explain")
            XCTAssertEqual(json["response_language"] as? String, "zh-Hans")
            XCTAssertEqual((json["retrieval_scope"] as? [String: Any])?["kind"] as? String, "selected_books")
            XCTAssertEqual((json["retrieval_scope"] as? [String: Any])?["book_ids"] as? [Int], [7, 8])
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200,
                                           httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, Data(#"{"answer":"Mapped answer","effective_scope":{},"evidence":[{"source":"reference","title":"Chapter","text":"Evidence"}],"contexts":[],"citations":[],"warnings":[],"backend":{}}"#.utf8))
        }

        let response = try await connector.queryAdvancedQA(payload)
        XCTAssertEqual(response.answer.text, "Mapped answer")
        XCTAssertEqual(response.evidence.first?.content, "Evidence")
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    func testUrlSessionAccessibleFromBackgroundThreadWithoutBlocking() {
        let connector = DSReaderHelperConnector(
            calibreServerService: service,
            server: server,
            dsreaderHelperServer: dsreaderHelperServer,
            goodreadsSync: nil
        )

        let expectation = expectation(description: "Background urlSession access completes")

        DispatchQueue.global(qos: .userInitiated).async {
            let session = connector.urlSession
            XCTAssertNotNil(session)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testUrlSessionConsistentAcrossMultipleBackgroundAccesses() {
        let connector = DSReaderHelperConnector(
            calibreServerService: service,
            server: server,
            dsreaderHelperServer: dsreaderHelperServer,
            goodreadsSync: nil
        )

        let count = 8
        let expectation = expectation(description: "All background accesses complete")
        expectation.expectedFulfillmentCount = count

        for _ in 0..<count {
            DispatchQueue.global(qos: .userInitiated).async {
                let session = connector.urlSession
                XCTAssertNotNil(session)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testAddToShelfSuccess() async throws {
        let goodreads = CalibreGoodreadsSyncPrefs.Goodreads(
            dateReadColumn: "",
            ratingColumn: "",
            readingProgressColumn: "",
            reviewTextColumn: "",
            tagMappingColumn: ""
        )
        let pluginPrefs = CalibreGoodreadsSyncPrefs.PluginPrefs(
            Goodreads: goodreads,
            Users: ["TestProfile": CalibreGoodreadsSyncPrefs.Shelves(shelves: [])]
        )

        let connector = DSReaderHelperConnector(
            calibreServerService: service,
            server: server,
            dsreaderHelperServer: dsreaderHelperServer,
            goodreadsSync: pluginPrefs
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            let query = request.url?.query ?? ""
            XCTAssertTrue(query.contains("goodreads_id=123"))
            XCTAssertTrue(query.contains("shelf_name=currently-reading"))
            XCTAssertTrue(query.contains("action=add"))

            return (response, Data("{}".utf8))
        }

        do {
            try await connector.addToShelf(goodreads_id: "123", shelfName: "currently-reading")
        } catch {
            XCTFail("Expected success, but got \(error)")
        }
    }

    func testAddToShelfFailureHttpStatus() async throws {
        let goodreads = CalibreGoodreadsSyncPrefs.Goodreads(
            dateReadColumn: "",
            ratingColumn: "",
            readingProgressColumn: "",
            reviewTextColumn: "",
            tagMappingColumn: ""
        )
        let pluginPrefs = CalibreGoodreadsSyncPrefs.PluginPrefs(
            Goodreads: goodreads,
            Users: ["TestProfile": CalibreGoodreadsSyncPrefs.Shelves(shelves: [])]
        )

        let connector = DSReaderHelperConnector(
            calibreServerService: service,
            server: server,
            dsreaderHelperServer: dsreaderHelperServer,
            goodreadsSync: pluginPrefs
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("Bad Request".utf8))
        }

        do {
            try await connector.addToShelf(goodreads_id: "123", shelfName: "currently-reading")
            XCTFail("Expected failure, but succeeded")
        } catch let error as CalibreAPIError {
            if case .httpStatus(let statusCode, _) = error {
                XCTAssertEqual(statusCode, 400)
            } else {
                XCTFail("Expected httpStatus error, but got \(error)")
            }
        } catch {
            XCTFail("Expected CalibreAPIError, but got \(error)")
        }
    }

    func testUpdateReadingProgressSuccess() async throws {
        let goodreads = CalibreGoodreadsSyncPrefs.Goodreads(
            dateReadColumn: "",
            ratingColumn: "",
            readingProgressColumn: "",
            reviewTextColumn: "",
            tagMappingColumn: ""
        )
        let pluginPrefs = CalibreGoodreadsSyncPrefs.PluginPrefs(
            Goodreads: goodreads,
            Users: ["TestProfile": CalibreGoodreadsSyncPrefs.Shelves(shelves: [])]
        )

        let connector = DSReaderHelperConnector(
            calibreServerService: service,
            server: server,
            dsreaderHelperServer: dsreaderHelperServer,
            goodreadsSync: pluginPrefs
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            let query = request.url?.query ?? ""
            XCTAssertTrue(query.contains("goodreads_id=123"))
            XCTAssertTrue(query.contains("percent=45.5"))

            return (response, Data("{}".utf8))
        }

        do {
            try await connector.updateReadingProgress(goodreads_id: "123", progress: 45.5)
        } catch {
            XCTFail("Expected success, but got \(error)")
        }
    }

    func testUpdateReadingProgressFailureHttpStatus() async throws {
        let goodreads = CalibreGoodreadsSyncPrefs.Goodreads(
            dateReadColumn: "",
            ratingColumn: "",
            readingProgressColumn: "",
            reviewTextColumn: "",
            tagMappingColumn: ""
        )
        let pluginPrefs = CalibreGoodreadsSyncPrefs.PluginPrefs(
            Goodreads: goodreads,
            Users: ["TestProfile": CalibreGoodreadsSyncPrefs.Shelves(shelves: [])]
        )

        let connector = DSReaderHelperConnector(
            calibreServerService: service,
            server: server,
            dsreaderHelperServer: dsreaderHelperServer,
            goodreadsSync: pluginPrefs
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("Internal Error".utf8))
        }

        do {
            try await connector.updateReadingProgress(goodreads_id: "123", progress: 45.5)
            XCTFail("Expected failure, but succeeded")
        } catch let error as CalibreAPIError {
            if case .httpStatus(let statusCode, _) = error {
                XCTAssertEqual(statusCode, 500)
            } else {
                XCTFail("Expected httpStatus error, but got \(error)")
            }
        } catch {
            XCTFail("Expected CalibreAPIError, but got \(error)")
        }
    }

    func testRefreshConfigurationAsyncSuccess() async throws {
        let connector = DSReaderHelperConnector(
            calibreServerService: service,
            server: server,
            dsreaderHelperServer: dsreaderHelperServer,
            goodreadsSync: nil
        )

        let payload = Data(#"{"dsreader_helper_prefs":{"plugin_prefs":{"Options":{"servicePort":8080}}}}"#.utf8)
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/dshelper/configuration")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, payload)
        }

        let received = try await connector.refreshConfiguration()
        XCTAssertEqual(received.id, server.uuid.uuidString)
        XCTAssertEqual(received.port, 8080)
        XCTAssertEqual(received.data, payload)
    }

    func testRefreshConfigurationAsyncThrowsForInvalidEndpoint() async throws {
        let unreachableServer = CalibreServer(
            uuid: UUID(),
            name: "Unreachable",
            baseUrl: "http://unreachable",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        let connector = DSReaderHelperConnector(
            calibreServerService: service,
            server: unreachableServer,
            dsreaderHelperServer: dsreaderHelperServer,
            goodreadsSync: nil
        )

        do {
            _ = try await connector.refreshConfiguration()
            XCTFail("Expected bad URL")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .badURL)
        } catch {
            XCTFail("Expected URLError, got \(error)")
        }
    }
}
