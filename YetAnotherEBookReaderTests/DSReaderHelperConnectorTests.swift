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

        let probeRequest = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false)
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

            return (response, Data("42".utf8))
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

            return (response, Data("42".utf8))
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

    func testV1CollectsLibraryColumnsAndPreservesOtherPreferences() async throws {
        let since = Date()
        let second = CalibreLibrary(server: server, key: "Second_测试", name: "Second 测试")
        let hidden = CalibreLibrary(server: server, key: "hidden_key", name: "Hidden", hidden: true)
        let old = CalibreDSReaderHelperConfiguration(
            count_pages_prefs: .init(library_config: [hidden.key: .init(customColumnPages: "#hidden")])
        )
        let scope = makeRequest(
            libraries: [library, second, hidden], baseURL: URL(string: "http://localhost/prefix/")!,
            saved: .init(port: 8080, configurationData: try JSONEncoder().encode(old))
        )
        let global = """
        {
            "dsreader_helper_prefs": {"plugin_prefs": {"Options": {
                "servicePort": 9090, "goodreadsSyncEnabled": true, "dictViewerEnabled": true,
                "dictViewerLibraryName": "Dictionary"
            }}},
            "count_pages_prefs": {"plugin_prefs": {}},
            "goodreads_sync_prefs": {"plugin_prefs": {
                "SchemaVersion": 1, "Goodreads": {"dateReadColumn": "", "ratingColumn": "#rating",
                "readingProgressColumn": "", "reviewTextColumn": "", "tagMappingColumn": "#tags"},
                "Users": {"Default": {"shelves": []}}
            }}
        }
        """
        let columns: (String, String) throws -> String = { key, column in
            let config = CalibreDSReaderHelperConfiguration(
                count_pages_prefs: .init(library_config: [key: .init(customColumnPages: column)])
            )
            return String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        }
        let log = MockURLProtocol.answer([
            "/prefix/dshelper/1/configuration/_": global,
            "/prefix/dshelper/1/configuration/\(library.key)": try columns(library.key, "#one"),
            "/prefix/dshelper/1/configuration/\(second.key)": try columns(second.key, "#two")
        ])

        let payload = try await DSReaderHelperConfigurationLoader.load(service: service, request: scope)
        let config = payload.configuration
        XCTAssertEqual(config.dsreader_helper_prefs?.plugin_prefs.Options.servicePort, 9090)
        XCTAssertEqual(config.dsreader_helper_prefs?.plugin_prefs.Options.dictViewerLibraryName, "Dictionary")
        XCTAssertEqual(config.goodreads_sync_prefs?.plugin_prefs.profileName, "Default")
        XCTAssertEqual(config.goodreads_sync_prefs?.plugin_prefs.ratingColumnName, "#rating")
        XCTAssertEqual(library.pluginCountPagesConfiguration(configuration: config).customColumnPages, "#one")
        XCTAssertEqual(second.pluginCountPagesConfiguration(configuration: config).customColumnPages, "#two")
        XCTAssertEqual(hidden.pluginCountPagesConfiguration(configuration: config).customColumnPages, "#hidden")
        XCTAssertEqual(try JSONDecoder().decode(CalibreDSReaderHelperConfiguration.self, from: payload.data), config)
        XCTAssertTrue(log.unexpected.isEmpty)

        let entries = await helperActivities(since: since)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(Set(entries.compactMap(\.libraryId)), [library.id, second.id])
        XCTAssertTrue(entries.allSatisfy { $0.state == .finished(.succeeded) && $0.result.httpStatusCode == 200 })
    }

    func testAnEmptyGlobal404ProbesLegacyAndValidatesTheResponse() async throws {
        let since = Date()
        let data = Data(#"{"dsreader_helper_prefs":{"plugin_prefs":{"Options":{"servicePort":8080}}}}"#.utf8)
        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.port, 8080)
            switch url.path {
            case "/dshelper/1/configuration/_":
                return try Self.reply(request, code: 404, contentType: "text/plain")
            case "/dshelper/configuration":
                return try Self.reply(request, code: 200, data: data)
            default:
                throw URLError(.badURL)
            }
        }

        let result = try await DSReaderHelperConfigurationLoader.load(service: service, request: makeRequest())
        XCTAssertEqual(result.data, data)
        XCTAssertEqual(result.configuration.dsreader_helper_prefs?.plugin_prefs.Options.servicePort, 8080)

        let entries = await helperActivities(since: since)
        XCTAssertEqual(entries.count, 2)
        let attemptedV1 = entries.first { $0.request.endpointURL?.hasSuffix("/1/configuration/_") == true }
        XCTAssertEqual(attemptedV1?.state, .finished(.failed))
        XCTAssertEqual(attemptedV1?.result.httpStatusCode, 404)
        let legacy = entries.first { $0.request.endpointURL?.hasSuffix("/dshelper/configuration") == true }
        XCTAssertEqual(legacy?.state, .finished(.succeeded))
        XCTAssertEqual(legacy?.result.httpStatusCode, 200)
    }

    func testMalformedLegacyResponseThrowsAndLogsFailure() async throws {
        let since = Date()
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/dshelper/1/configuration/_" {
                return try Self.reply(request, code: 404, contentType: "text/plain")
            }
            return try Self.reply(request, code: 200, data: Data("garbled".utf8))
        }

        await assertHelperDownloadFails(makeRequest())
        let entries = await helperActivities(since: since)
        XCTAssertEqual(entries.count, 2)
        let legacy = entries.first { $0.request.endpointURL?.hasSuffix("/dshelper/configuration") == true }
        XCTAssertEqual(legacy?.state, .finished(.failed))
        XCTAssertEqual(legacy?.result.errorCategory, .decoding)
        XCTAssertEqual(legacy?.result.httpStatusCode, 200)
    }

    func testAuthenticationTransportAndOtherGlobalErrorsDoNotProbeLegacy() async throws {
        let failures: [(Int?, URLError?, ActivityLogErrorCategory, ActivityLogCompletion)] = [
            (401, nil, .authentication, .failed),
            (403, nil, .authentication, .failed),
            (404, nil, .http, .failed), // The body is present, unlike an unregistered Calibre route.
            (500, nil, .http, .failed),
            (200, nil, .decoding, .failed),
            (nil, URLError(.timedOut), .transport, .failed),
            (nil, URLError(.cancelled), .transport, .cancelled)
        ]
        for (code, transport, category, outcome) in failures {
            let since = Date()
            MockURLProtocol.requestHandler = { request in
                XCTAssertEqual(request.url?.path, "/dshelper/1/configuration/_")
                if let transport { throw transport }
                return try Self.reply(request, code: XCTUnwrap(code), data: Data("private server response".utf8))
            }
            await assertHelperDownloadFails(makeRequest())
            let entries = await helperActivities(since: since)
            XCTAssertEqual(entries.count, 1)
            XCTAssertEqual(entries.first?.state, .finished(outcome))
            XCTAssertEqual(entries.first?.result.errorCategory, category)
            XCTAssertEqual(entries.first?.result.httpStatusCode, code)
            XCTAssertFalse(entries.first?.result.detail?.contains("private server response") ?? false)
        }
    }

    func testMissingLibraryConfigurationAbortsTheAggregateAndKeepsTheSavedValue() async throws {
        let since = Date()
        let available = (0..<4).map {
            CalibreLibrary(server: server, key: "lib-\($0)", name: "Library \($0)")
        }
        let failed = CalibreLibrary(server: server, key: "missing", name: "Z Missing")
        let global = #"{"dsreader_helper_prefs":{"plugin_prefs":{"Options":{"servicePort":8080}}},"count_pages_prefs":{"plugin_prefs":{}}}"#
        var replies = ["/dshelper/1/configuration/_": global, "/dshelper/1/configuration/missing": "{}"]
        for library in available {
            let config = CalibreDSReaderHelperConfiguration(
                count_pages_prefs: .init(library_config: [library.key: .init(customColumnPages: "#pages")])
            )
            replies["/dshelper/1/configuration/\(library.key)"] = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        }
        let log = MockURLProtocol.answer(replies)
        let manager = container.serverManager
        let old = CalibreServerDSReaderHelper(port: 8080, configurationData: Data(global.utf8))
        try container.serverRepository.saveServer(server)
        try container.serverRepository.saveDSReaderHelper(old, for: server.id)
        manager.calibreServers[server.id] = server
        for library in available + [failed] {
            container.libraryManager.calibreLibraries[library.id] = library
        }

        let load = try XCTUnwrap(manager.requestServerHelperConfigSync(serverId: server.id))
        do {
            _ = try await load.task.value
            XCTFail("A partial aggregate must fail")
        } catch let error as CalibreAPIError {
            XCTAssertEqual(error, .unsupportedPayload)
        }
        XCTAssertEqual(manager.queryServerDSReaderHelper(server: server), old)
        XCTAssertTrue(log.unexpected.isEmpty)

        let entries = await helperActivities(since: since)
        XCTAssertEqual(entries.count, 6)
        let failedEntry = entries.first { $0.libraryId == failed.id }
        XCTAssertEqual(failedEntry?.state, .finished(.failed))
        XCTAssertEqual(failedEntry?.result.errorCategory, .decoding)
        XCTAssertEqual(failedEntry?.result.httpStatusCode, 200)
        XCTAssertTrue(entries.filter { $0.libraryId != failed.id }.allSatisfy {
            $0.state == .finished(.succeeded) && $0.result.httpStatusCode == 200
        })
    }

    func testConfigurationLibraryMalformedJSONKeepsHTTPStatusAndScope() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/dshelper/1/configuration/lib1")
            return try Self.reply(request, code: 200, data: Data("invalid JSON".utf8))
        }
        let since = Date()
        let request = makeRequest(libraries: [library])
        let scope = try XCTUnwrap(request.libraries.first)
        let connector = DSReaderHelperConnector(calibreServerService: service, server: server,
                                                dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: nil)
        do {
            _ = try await connector.fetchLibraryConfiguration(baseURL: request.baseURL, library: scope)
            XCTFail("Invalid configuration")
        } catch let error as CalibreAPIError {
            guard case .decoding = error else { return XCTFail("Unexpected error: \(error)") }
        }
        let entries = await helperActivities(since: since)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.libraryId, library.id)
        XCTAssertEqual(entries.first?.state, .finished(.failed))
        XCTAssertEqual(entries.first?.result.httpStatusCode, 200)
        XCTAssertEqual(entries.first?.result.errorCategory, .decoding)
    }

    func testConfigurationThrowsForInvalidEndpoint() async throws {
        let since = Date()
        await assertHelperDownloadFails(makeRequest(baseURL: URL(fileURLWithPath: "/")))
        let entries = await helperActivities(since: since)
        XCTAssertTrue(entries.isEmpty)
    }

    private nonisolated static func reply(
        _ request: URLRequest, code: Int, data: Data = Data(), contentType: String = "application/json"
    ) throws -> (HTTPURLResponse, Data) {
        let url = try XCTUnwrap(request.url)
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: code, httpVersion: nil,
                                                     headerFields: ["Content-Type": contentType]))
        return (response, data)
    }

    private func makeRequest(
        libraries: [CalibreLibrary] = [], baseURL: URL = URL(string: "http://localhost")!,
        saved: CalibreServerDSReaderHelper? = nil
    ) -> DSReaderHelperConfigurationRequest {
        DSReaderHelperConfigurationRequest(
            server: server, baseURL: baseURL, port: 8080,
            libraries: libraries.map { .init(id: $0.id, key: $0.key, name: $0.name, hidden: $0.hidden) },
            stored: .init(connection: .init(server), helper: saved)
        )
    }

    private func helperActivities(since: Date) async -> [ActivityLogSnapshot] {
        await service.logger.flushPendingActivitiesForTesting()
        return container.activityLogRepository.fetchTestSnapshots(libraryId: nil, bookId: nil, since: since)
            .filter { $0.kind == .helper }
    }

    private func assertHelperDownloadFails(_ request: DSReaderHelperConfigurationRequest, line: UInt = #line) async {
        do {
            _ = try await DSReaderHelperConfigurationLoader.load(service: service, request: request)
            XCTFail("Expected configuration download to fail", line: line)
        } catch {}
    }
}
