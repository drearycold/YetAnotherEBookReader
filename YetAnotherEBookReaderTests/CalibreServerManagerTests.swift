//
//  CalibreServerManagerTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-23.
//

import XCTest
import RealmSwift
import Combine
@testable import YetAnotherEBookReader

@MainActor
final class CalibreServerManagerTests: XCTestCase {
    private var container: AppContainer!
    private var serverManager: CalibreServerManager!
    private var databaseService: DatabaseService!
    private var serverRepository: ServerRepositoryProtocol!
    private var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        // Isolated in-memory Realm configuration
        container = MockAppContainerFactory.makeContainer(testName: "CalibreServerManagerTests")
        
        serverManager = container.serverManager
        databaseService = container.databaseService
        serverRepository = container.serverRepository
        cancellables = []
    }

    override func tearDownWithError() throws {
        container = nil
        serverManager = nil
        databaseService = nil
        serverRepository = nil
        cancellables = nil
        AppContainer.shared = nil
    }

    func testProbePreservesStructuredFailureAndUsesCurrentConfigurationOnRetry() async throws {
        var server = TestFixtures.makeServer(baseUrl: "http://localhost/recovery")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        func installSession() {
            container.calibreServerService.metadataSessions[
                CalibreServerURLSessionKey(server: server, timeout: 10, qos: .default)
            ] = session
        }
        let body = Data(("<html><style>body { color: red; }</style>" + String(repeating: "error", count: 8000) + "</html>").utf8)
        MockURLProtocol.requestHandler = { request in
            (try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 503,
                                          httpVersion: nil, headerFields: nil)), body)
        }
        installSession()
        let failed = await serverManager.probeServer(request: .init(server: server, isPublic: false,
                                                                    updateLibrary: false, autoUpdateOnly: true))
        XCTAssertEqual(failed?.error, .httpStatus(503, body))
        XCTAssertFalse(failed?.reachable ?? true)
        XCTAssertFalse(serverRepository.getAllServers().contains { $0.id == server.id })

        server.name = "Edited server"
        server.password = "corrected password"
        MockURLProtocol.requestHandler = { request in
            (try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200,
                                          httpVersion: nil, headerFields: nil)),
             Data(#"{"default_library":"lib","library_map":{"lib":"Library"}}"#.utf8))
        }
        installSession()
        let recovered = await serverManager.probeServer(request: .init(server: server, isPublic: false,
                                                                       updateLibrary: false, autoUpdateOnly: true))
        XCTAssertEqual(recovered?.server.name, server.name)
        XCTAssertEqual(recovered?.server.password, server.password)
        XCTAssertTrue(recovered?.reachable ?? false)
        XCTAssertNil(recovered?.error)
    }

    func testBackgroundProbeKeepsKnownReachabilityUntilItsAnswer() async throws {
        let server = TestFixtures.makeServer(baseUrl: "http://localhost/background")
        let request = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: true)
        let url = try XCTUnwrap(URL(string: server.baseUrl))
        serverManager.calibreServerInfoStaging[request.id] = .init(
            server: server, isPublic: false, url: url, reachable: true, defaultLibrary: "lib",
            libraryMap: ["lib": "Library"], request: request)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        container.calibreServerService.metadataSessions[
            CalibreServerURLSessionKey(server: server, timeout: 10, qos: .default)
        ] = URLSession(configuration: config)
        MockURLProtocol.requestHandler = { _ in
            Thread.sleep(forTimeInterval: 0.2)
            throw URLError(.cannotConnectToHost)
        }
        let task = Task { await serverManager.probeServer(request: request) }
        for _ in 0..<50 {
            if serverManager.isServerProbing(server: server) { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(serverManager.isServerProbing(server: server))
        XCTAssertEqual(container.calibreServerService.getServerUrlByReachability(server: server), url)
        let result = await task.value
        XCTAssertFalse(result?.reachable ?? true)
        XCTAssertEqual(result?.error, .transport(URLError(.cannotConnectToHost)))
        XCTAssertTrue(result?.libraryMap.isEmpty == true)
    }

    func testOlderProbeCannotReplaceStagingForTheSameServerID() async throws {
        let original = TestFixtures.makeServer(baseUrl: "http://first-probe.test")
        var updated = original
        updated.baseUrl = "http://second-probe.test"
        let requestStarted = expectation(description: "Original probe reached transport")
        let lock = NSLock()
        var originalResponse: DeferredProbeURLProtocol?

        for server in [original, updated] {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DeferredProbeURLProtocol.self]
            let key = CalibreServerURLSessionKey(server: server, timeout: 10, qos: .default)
            container.calibreServerService.metadataSessions[key] = URLSession(configuration: configuration)
        }
        DeferredProbeURLProtocol.onStart = { response in
            if response.request.url?.host == "first-probe.test" {
                lock.lock()
                originalResponse = response
                lock.unlock()
                requestStarted.fulfill()
            } else {
                response.finish(defaultLibrary: "new")
            }
        }
        defer { DeferredProbeURLProtocol.onStart = nil }
        let first = CalibreProbeServerRequest(server: original, isPublic: false, updateLibrary: false, autoUpdateOnly: true)
        let second = CalibreProbeServerRequest(server: updated, isPublic: false, updateLibrary: false, autoUpdateOnly: true)
        let olderProbe = Task { await serverManager.probeServer(request: first) }
        await fulfillment(of: [requestStarted], timeout: 3)
        let heldResponse = try XCTUnwrap(lock.withLock { originalResponse })
        let newerResult = await serverManager.probeServer(request: second)
        XCTAssertEqual(newerResult?.defaultLibrary, "new")
        heldResponse.finish(defaultLibrary: "old")
        let olderResult = await olderProbe.value
        XCTAssertNil(olderResult)
        XCTAssertEqual(serverManager.calibreServerInfoStaging[first.id]?.server.baseUrl, updated.baseUrl)
        XCTAssertEqual(serverManager.calibreServerInfoStaging[first.id]?.defaultLibrary, "new")
    }

    func testPopulateServers() throws {
        // Create custom mock servers and save to repository
        let server1 = CalibreServer(uuid: UUID(), name: "A Server", baseUrl: "http://localhost/a", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "userA", password: "")
        let server2 = CalibreServer(uuid: UUID(), name: "B Server", baseUrl: "http://localhost/b", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "userB", password: "")
        
        try serverRepository.saveServer(server1)
        try serverRepository.saveServer(server2)
        
        // Clear in-memory dictionary
        serverManager.calibreServers.removeAll()
        
        // Populate
        serverManager.populateServers()
        
        // Assert populated
        XCTAssertNotNil(serverManager.calibreServers[server1.id])
        XCTAssertNotNil(serverManager.calibreServers[server2.id])
    }

    func testAddServer() throws {
        let newServer = CalibreServer(uuid: UUID(), name: "New Add Server", baseUrl: "http://localhost/add", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let newLib = CalibreLibrary(server: newServer, key: "add_lib", name: "Add Library")
        
        // Add server via manager
        serverManager.addServer(server: newServer, libraries: [newLib])
        
        // Verify in manager dictionary
        XCTAssertNotNil(serverManager.calibreServers[newServer.id])
        
        // Verify in repository
        let allServers = serverRepository.getAllServers()
        XCTAssertTrue(allServers.contains(where: { $0.id == newServer.id }))
        
        // Verify library was added
        XCTAssertNotNil(container.libraryManager.calibreLibraries[newLib.id])
        let allLibs = container.libraryRepository.getAllLibraries()
        XCTAssertTrue(allLibs.contains(where: { $0.id == newLib.id }))
    }

    func testUpdateServerRealm() throws {
        let server = CalibreServer(uuid: UUID(), name: "Server X", baseUrl: "http://localhost/x", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        try serverManager.saveServer(server: server)
        
        let allServers = serverRepository.getAllServers()
        XCTAssertTrue(allServers.contains(where: { $0.id == server.id }))
    }

    func testRemoveServer() async throws {
        let server = CalibreServer(uuid: UUID(), name: "Delete Server", baseUrl: "http://localhost/del", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        container.serverManager.calibreServers[server.id] = server
        try serverRepository.saveServer(server)
        
        let library = CalibreLibrary(server: server, key: "del_lib", name: "Delete Library")
        container.libraryManager.calibreLibraries[library.id] = library
        try container.libraryRepository.saveLibrary(library)
        
        // Verify library exists in repository before deletion
        XCTAssertNotNil(container.libraryRepository.getAllLibraries().first { $0.id == library.id })
        _ = container.calibreServerService.urlSession(server: server)

        // Remove server
        await serverManager.removeServer(server: server)

        // Verify libraries associated with server are deleted from repository
        XCTAssertNil(container.libraryRepository.getAllLibraries().first { $0.id == library.id })
        XCTAssertNil(container.libraryManager.calibreLibraries[library.id])
        // Its cached sessions are retired
        XCTAssertFalse(container.calibreServerService.metadataSessions.keys.contains { $0.server == server })
    }

    func testDSReaderHelperOperations() throws {
        let server = CalibreServer(uuid: UUID(), name: "Server DSR", baseUrl: "http://localhost/dsr", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        container.serverManager.calibreServers[server.id] = server
        try serverRepository.saveServer(server)
        
        let helperConfig = CalibreServerDSReaderHelper(port: 9090)
        serverManager.updateServerDSReaderHelper(serverId: server.id, dsreaderHelper: helperConfig)
        
        let retrieved = serverManager.queryServerDSReaderHelper(server: server)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.port, 9090)
    }

    func testReachabilityHelpers() throws {
        let server = CalibreServer(uuid: UUID(), name: "Reach Server", baseUrl: "http://localhost/reach", hasPublicUrl: true, publicUrl: "http://public/reach", hasAuth: false, username: "", password: "")
        
        // 1. Probing state
        let infoProbing = CalibreServerInfo(
            server: server,
            isPublic: false,
            url: URL(string: server.baseUrl)!,
            probing: true,
            errorMsg: "",
            defaultLibrary: "",
            libraryMap: [:],
            request: .init(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false)
        )
        serverManager.calibreServerInfoStaging[infoProbing.id] = infoProbing
        
        XCTAssertTrue(serverManager.isServerProbing(server: server))
        XCTAssertFalse(serverManager.isServerReachable(server: server))
        XCTAssertEqual(serverManager.isServerReachable(server: server, isPublic: false), false)
        
        // 2. Reachable state
        let infoReachable = CalibreServerInfo(
            server: server,
            isPublic: false,
            url: URL(string: server.baseUrl)!,
            reachable: true,
            probing: false,
            errorMsg: "",
            defaultLibrary: "",
            libraryMap: [:],
            request: .init(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false)
        )
        serverManager.calibreServerInfoStaging[infoReachable.id] = infoReachable
        
        XCTAssertFalse(serverManager.isServerProbing(server: server))
        XCTAssertTrue(serverManager.isServerReachable(server: server))
        XCTAssertTrue(serverManager.isServerReachable(server: server, isPublic: false) ?? false)
        
        // 3. Get server info
        let info = serverManager.getServerInfo(server: server)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.id, infoReachable.id)
    }

    func testManagerAsyncBroadcasterStreamsInitialAndSubsequentValues() async {
        let broadcaster = ManagerAsyncBroadcaster<Int>()
        let stream = broadcaster.stream(initialValue: 1)
        var iterator = stream.makeAsyncIterator()

        let initial = await iterator.next()
        broadcaster.send(2)
        let updated = await iterator.next()

        XCTAssertEqual(initial, 1)
        XCTAssertEqual(updated, 2)
    }

    func testProbeServerSuccess() async throws {
        let server = CalibreServer(uuid: UUID(), name: "Probe Server Success", baseUrl: "http://localhost/probe_success", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        container.serverManager.calibreServers[server.id] = server
        
        // Mock session mapping for CalibreServerService
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        for timeout in [10.0, 600.0] {
            for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
                let key = CalibreServerURLSessionKey(server: server, timeout: timeout, qos: qos)
                container.calibreServerService.metadataSessions[key] = mockSession
            }
        }
        
        // library-info keeps the server URL's path; makeEndpointURL's relative paths drop it.
        let emptyLibrarySearch = """
        {"total_num": 0, "sort_order": "desc", "num_books_without_search": 0, "offset": 0, "num": 0,
         "sort": "last_modified", "base_url": "", "query": null, "library_id": "", "book_ids": [], "vl": ""}
        """
        let answers = [
            "/probe_success/ajax/library-info": """
            {
                "default_library": "lib_default",
                "library_map": {
                    "lib_default": "Default Library",
                    "lib_other": "Other Library"
                }
            }
            """,
            "/ajax/search/lib_default": emptyLibrarySearch,
            "/ajax/search/lib_other": emptyLibrarySearch,
            "/ajax/categories/lib_default": "[]",
            "/ajax/categories/lib_other": "[]"
        ]
        let requests = MockURLProtocol.answer(answers)
        
        // Call probeServer (updateLibrary: true)
        let request = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: true, autoUpdateOnly: true)
        let infoResult = await serverManager.probeServer(request: request)
        
        XCTAssertNotNil(infoResult)
        XCTAssertTrue(infoResult?.reachable ?? false)
        XCTAssertEqual(infoResult?.defaultLibrary, "lib_default")
        XCTAssertEqual(infoResult?.libraryMap["lib_other"], "Other Library")
        
        // Verify staging info is stored
        let staged = serverManager.calibreServerInfoStaging[request.id]
        XCTAssertNotNil(staged)
        XCTAssertTrue(staged?.reachable ?? false)
        XCTAssertEqual(staged?.errorMsg, "Success")
        
        // Verify library was auto-created in container.libraryManager.calibreLibraries and saved to repository
        let autoLibId = CalibreLibrary(server: server, key: "lib_other", name: "Other Library").id
        XCTAssertNotNil(container.libraryManager.calibreLibraries[autoLibId])
        XCTAssertNotNil(container.libraryRepository.getAllLibraries().first { $0.id == autoLibId })

        // Each library is synced: its summary and categories, nothing else.
        let libraryIds = ["lib_default": "Default Library", "lib_other": "Other Library"].map {
            CalibreLibrary(server: server, key: $0.key, name: $0.value).id
        }
        // The categories are read after the status says "Success".
        let categoryPaths: Set = ["/ajax/categories/lib_default", "/ajax/categories/lib_other"]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline,
              !libraryIds.allSatisfy({ container.libraryManager.librarySyncStatus[$0]?.msg == "Success" })
                || !categoryPaths.isSubset(of: requests.answered) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(categoryPaths.isSubset(of: requests.answered), "\(requests.answered)")
        for libraryId in libraryIds {
            XCTAssertEqual(container.libraryManager.librarySyncStatus[libraryId]?.msg, "Success", libraryId)
            XCTAssertEqual(container.libraryManager.librarySyncStatus[libraryId]?.cnt, 0, libraryId)
        }
        XCTAssertEqual(requests.unexpected, [])
    }

    func testProbeServerFailure() async throws {
        let server = CalibreServer(uuid: UUID(), name: "Probe Server Failure", baseUrl: "http://localhost/probe_failure", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        container.serverManager.calibreServers[server.id] = server
        
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
        
        let request = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: true)
        let infoResult = await serverManager.probeServer(request: request)
        
        XCTAssertNotNil(infoResult)
        XCTAssertFalse(infoResult?.reachable ?? true)
        XCTAssertEqual(infoResult?.errorMsg, "HTTP 500")
        
        let staged = serverManager.calibreServerInfoStaging[request.id]
        XCTAssertNotNil(staged)
        XCTAssertFalse(staged?.reachable ?? true)
    }

    func testProbeServersReachability() async throws {
        let server1 = CalibreServer(uuid: UUID(), name: "Server 1", baseUrl: "http://localhost/s1", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let server2 = CalibreServer(uuid: UUID(), name: "Server 2", baseUrl: "http://localhost/s2", hasPublicUrl: true, publicUrl: "http://public/s2", hasAuth: false, username: "", password: "")
        
        serverManager.calibreServers[server1.id] = server1
        serverManager.calibreServers[server2.id] = server2
        
        // We will call probeServersReachability with empty set (probing all)
        serverManager.probeServersReachability(with: [])
        
        // Yield to allow async Tasks to schedule and run
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        
        let req1 = CalibreProbeServerRequest(server: server1, isPublic: false, updateLibrary: false, autoUpdateOnly: false)
        let req2 = CalibreProbeServerRequest(server: server2, isPublic: false, updateLibrary: false, autoUpdateOnly: false)
        let req2Pub = CalibreProbeServerRequest(server: server2, isPublic: true, updateLibrary: false, autoUpdateOnly: false)
        
        XCTAssertNotNil(serverManager.calibreServerInfoStaging[req1.id])
        XCTAssertNotNil(serverManager.calibreServerInfoStaging[req2.id])
        XCTAssertNotNil(serverManager.calibreServerInfoStaging[req2Pub.id])
    }

    func testManualHelperDownloadsFinishingOutOfOrderKeepNewestCandidate() async throws {
        let loader = installControlledHelperLoader()
        let server = TestFixtures.makeServer(baseUrl: "http://helper-order")
        try installServerForHelperSync(server)
        let saved = try makeDSReaderHelperConfigurationData(servicePort: 7777)
        try serverRepository.saveDSReaderHelper(.init(port: 8080, configurationData: saved), for: server.id)

        let model = DSReaderHelperConfigurationViewModel(container: container, serverID: server.id)
        model.resume()
        let first = try XCTUnwrap(model.connectDSReader())
        let firstRequest = try await loader.nextRequest()
        model.setPortDraft("8081")
        let second = try XCTUnwrap(model.connectDSReader())
        let secondRequest = try await loader.nextRequest()
        XCTAssertEqual(firstRequest.port, 8080)
        XCTAssertEqual(secondRequest.port, 8081)

        try secondRequest.succeed(servicePort: 8082)
        await second.value
        let ticket = try XCTUnwrap(model.helperConfirmation)
        guard case .awaitingConfirmation(let candidate) = model.helperState else { return XCTFail("Missing candidate") }
        XCTAssertEqual(candidate.payload.configuration.dsreader_helper_prefs?.plugin_prefs.Options.servicePort, 8082)
        XCTAssertEqual(try JSONDecoder().decode(CalibreDSReaderHelperConfiguration.self, from: candidate.payload.data),
                       candidate.payload.configuration)
        XCTAssertEqual(model.savedHelper?.configurationData, saved)
        XCTAssertEqual(serverRepository.getDSReaderHelper(for: server.id)?.configurationData, saved)

        // This fixture deliberately completes even after Task.cancel().
        try firstRequest.succeed(servicePort: 8080)
        await first.value
        XCTAssertEqual(model.helperConfirmation, ticket)
        model.applyHelperConfiguration(ticket)
        XCTAssertEqual(model.savedHelper?.port, 8081)
        XCTAssertEqual(serverRepository.getDSReaderHelper(for: server.id)?.configurationData, candidate.payload.data)
        XCTAssertNil(model.helperConfirmation)
    }

    func testManualHelperPortValidationAndFailureKeepSavedConfigurationAndAllowRetry() async throws {
        let loader = installControlledHelperLoader()
        let server = TestFixtures.makeServer(baseUrl: "http://helper-retry")
        try installServerForHelperSync(server)
        let saved = try makeDSReaderHelperConfigurationData(servicePort: 8080)
        try serverRepository.saveDSReaderHelper(.init(port: 8080, configurationData: saved), for: server.id)
        let model = DSReaderHelperConfigurationViewModel(container: container, serverID: server.id)
        model.resume()

        for invalid in ["", "8x080", " 8080", "１０２４", "1023", "65536", "99999999999999999999999"] {
            model.setPortDraft(invalid)
            XCTAssertNil(model.helperPort)
            XCTAssertNil(model.connectDSReader())
        }
        XCTAssertEqual(loader.requestCount, 0)
        XCTAssertEqual(CalibreServerDSReaderHelper.parsePort("1024"), 1024)
        XCTAssertEqual(CalibreServerDSReaderHelper.parsePort("65535"), 65535)

        model.setPortDraft("8081")
        let failed = try XCTUnwrap(model.connectDSReader())
        let failedRequest = try await loader.nextRequest()
        failedRequest.fail(URLError(.timedOut))
        await failed.value
        guard case .failure(.timeout) = model.helperState else { return XCTFail("Expected timeout") }
        XCTAssertNil(model.helperConfirmation)
        XCTAssertEqual(model.savedHelper?.configurationData, saved)

        model.setPortDraft("8082")
        let retry = try XCTUnwrap(model.connectDSReader())
        let retryRequest = try await loader.nextRequest()
        try retryRequest.succeed(servicePort: 8182)
        await retry.value
        let ticket = try XCTUnwrap(model.helperConfirmation)
        model.discardHelperConfiguration(ticket)
        model.applyHelperConfiguration(ticket)
        XCTAssertNil(model.helperConfirmation)
        XCTAssertEqual(serverRepository.getDSReaderHelper(for: server.id)?.configurationData, saved)
    }

    func testManualHelperCancelAndReopenRejectLateResultsAndOldConfirmations() async throws {
        let loader = installControlledHelperLoader()
        let server = TestFixtures.makeServer(baseUrl: "http://helper-reopen")
        let otherServer = TestFixtures.makeServer(baseUrl: "http://helper-other")
        try installServerForHelperSync(server)
        try installServerForHelperSync(otherServer)
        let model = DSReaderHelperConfigurationViewModel(container: container, serverID: server.id)
        model.resume()

        let cancelled = try XCTUnwrap(model.connectDSReader())
        let cancelledRequest = try await loader.nextRequest()
        model.stopHelperConfiguration()
        try cancelledRequest.succeed(servicePort: 8001)
        await cancelled.value
        guard case .cancelled = model.helperState else { return XCTFail("Expected cancelled state") }
        XCTAssertNil(model.helperConfirmation)

        let leaving = try XCTUnwrap(model.connectDSReader())
        let leavingRequest = try await loader.nextRequest()
        model.closeRoute()
        model.resume()
        try leavingRequest.succeed(servicePort: 8002)
        await leaving.value
        XCTAssertNil(model.helperConfirmation)

        let load = try XCTUnwrap(model.connectDSReader())
        let request = try await loader.nextRequest()
        try request.succeed(servicePort: 8003)
        await load.value
        let oldTicket = try XCTUnwrap(model.helperConfirmation)
        model.closeRoute()
        let otherModel = DSReaderHelperConfigurationViewModel(container: container, serverID: otherServer.id)
        otherModel.resume()
        let otherLoad = try XCTUnwrap(otherModel.connectDSReader())
        let otherRequest = try await loader.nextRequest()
        try otherRequest.succeed(servicePort: 8004)
        await otherLoad.value
        let otherTicket = try XCTUnwrap(otherModel.helperConfirmation)
        otherModel.applyHelperConfiguration(oldTicket)
        otherModel.discardHelperConfiguration(oldTicket)
        XCTAssertEqual(otherModel.helperConfirmation, otherTicket)
        otherModel.applyHelperConfiguration(otherTicket)
        XCTAssertNil(serverRepository.getDSReaderHelper(for: server.id)?.configurationData)
        XCTAssertEqual(serverRepository.getDSReaderHelper(for: otherServer.id)?.configuration?.dsreader_helper_prefs?.plugin_prefs.Options.servicePort, 8004)
    }

    func testStoppingParentDetailDoesNotCancelChildHelperAndSuspensionDropsCandidate() async throws {
        let loader = installControlledHelperLoader()
        let server = TestFixtures.makeServer(baseUrl: "http://helper-child")
        try installServerForHelperSync(server)
        let detail = ServerDetailViewModel(container: container, serverID: server.id)
        let helper = DSReaderHelperConfigurationViewModel(container: container, serverID: server.id)
        detail.startObserving(.detail)
        helper.resume()
        helper.setPortDraft("9090")
        let download = try XCTUnwrap(helper.connectDSReader())
        let request = try await loader.nextRequest()
        detail.stopObserving(.detail)
        try request.succeed(servicePort: 9191)
        await download.value
        let ticket = try XCTUnwrap(helper.helperConfirmation)

        helper.suspend()
        helper.resume()
        XCTAssertEqual(helper.portStr, "9090")
        XCTAssertNil(helper.helperConfirmation)
        helper.applyHelperConfiguration(ticket)
        XCTAssertEqual(serverRepository.getDSReaderHelper(for: server.id)?.port, 8080)
    }

    func testVisibleHelperDismissesCandidateWhenItsLibraryScopeChanges() async throws {
        let loader = installControlledHelperLoader()
        let server = TestFixtures.makeServer(baseUrl: "http://helper-library-scope")
        try installServerForHelperSync(server)
        let library = CalibreLibrary(server: server, key: "visible", name: "Visible")
        container.libraryManager.calibreLibraries[library.id] = library
        let helper = DSReaderHelperConfigurationViewModel(container: container, serverID: server.id)
        helper.resume()
        let download = try XCTUnwrap(helper.connectDSReader())
        let request = try await loader.nextRequest()
        try request.succeed(servicePort: 8080)
        await download.value
        let ticket = try XCTUnwrap(helper.helperConfirmation)

        let dismissed = expectation(description: "The stale confirmation was dismissed")
        let observation = helper.$helperConfirmation.dropFirst().first { $0 == nil }.sink { _ in dismissed.fulfill() }
        defer { observation.cancel() }
        container.libraryManager.hideLibrary(libraryId: library.id)
        await fulfillment(of: [dismissed], timeout: 3)
        helper.applyHelperConfiguration(ticket)
        XCTAssertNil(serverRepository.getDSReaderHelper(for: server.id)?.configurationData)
        guard case .failure(.stale) = helper.helperState else { return XCTFail("Expected a stale configuration") }
    }

    func testOpeningHelperInstructionsCancelsTheDownloadAndPreservesTheDraft() async throws {
        let loader = installControlledHelperLoader()
        let server = TestFixtures.makeServer(baseUrl: "http://helper-instructions")
        try installServerForHelperSync(server)
        let helper = DSReaderHelperConfigurationViewModel(container: container, serverID: server.id)
        helper.resume()
        helper.setPortDraft("9090")
        let download = try XCTUnwrap(helper.connectDSReader())
        let request = try await loader.nextRequest()

        // A sheet can be presented without the underlying form receiving onDisappear.
        helper.instructionPresented = true
        try request.succeed(servicePort: 9191)
        await download.value
        XCTAssertNil(helper.helperConfirmation)
        helper.instructionPresented = false
        XCTAssertEqual(helper.portStr, "9090")
        XCTAssertNil(helper.helperConfirmation)
        XCTAssertEqual(serverRepository.getDSReaderHelper(for: server.id)?.port, 8080)
    }

    func testHelperCredentialsPortAndDeletionInvalidateTheRequestOrCandidate() async throws {
        let loader = installControlledHelperLoader()
        var server = TestFixtures.makeServer(baseUrl: "http://helper-changes")
        server.hasAuth = true
        server.username = "account"
        server.password = "old"
        try installServerForHelperSync(server)

        let staleCredentials = try serverManager.requestManualHelperConfiguration(serverID: server.id, port: 8080)
        let first = try await loader.nextRequest()
        server.password = "new"
        try serverRepository.saveServer(server)
        serverManager.calibreServers[server.id] = server
        XCTAssertEqual(serverRepository.getDSReaderHelper(for: server.id)?.port, 8080)
        try first.succeed(servicePort: 8180)
        await assertHelperLoadFailed(staleCredentials)

        let stalePort = try serverManager.requestManualHelperConfiguration(serverID: server.id, port: 8080)
        let second = try await loader.nextRequest()
        XCTAssertEqual(second.server.password, "new")
        try second.succeed(servicePort: 8181)
        let portCandidate = try await stalePort.task.value
        let current = CalibreServerDSReaderHelper(port: 9090, configurationData: try makeDSReaderHelperConfigurationData(servicePort: 9191))
        try serverRepository.saveDSReaderHelper(current, for: server.id)
        XCTAssertThrowsError(try serverManager.applyHelperConfiguration(portCandidate))
        XCTAssertEqual(serverRepository.getDSReaderHelper(for: server.id), current)

        let removed = try serverManager.requestManualHelperConfiguration(serverID: server.id, port: 9090)
        let third = try await loader.nextRequest()
        try third.succeed(servicePort: 9192)
        let deletedCandidate = try await removed.task.value
        // Remove the Realm row while the manager still holds its in-memory server snapshot.
        try serverRepository.deleteServer(id: server.id)
        XCTAssertThrowsError(try serverManager.applyHelperConfiguration(deletedCandidate))
        XCTAssertNil(serverRepository.getDSReaderHelper(for: server.id))
    }

    func testManualHelperConfirmationRejectsChangedLibraryScope() async throws {
        let loader = installControlledHelperLoader()
        let server = TestFixtures.makeServer(baseUrl: "http://helper-library-change")
        try installServerForHelperSync(server)
        let library = CalibreLibrary(server: server, key: "visible", name: "Visible")
        container.libraryManager.calibreLibraries[library.id] = library

        let load = try serverManager.requestManualHelperConfiguration(serverID: server.id, port: 8080)
        let request = try await loader.nextRequest()
        XCTAssertEqual(request.libraries.map(\.id), [library.id])
        try request.succeed(servicePort: 8080)
        let candidate = try await load.task.value
        container.libraryManager.calibreLibraries[library.id]?.hidden = true
        XCTAssertThrowsError(try serverManager.applyHelperConfiguration(candidate))
        XCTAssertNil(serverRepository.getDSReaderHelper(for: server.id)?.configurationData)
    }

    func testBackgroundHelperLatestRequestWinsIndependentlyPerServer() async throws {
        let loader = installControlledHelperLoader()
        let server = TestFixtures.makeServer(baseUrl: "http://helper-bg-a")
        let other = TestFixtures.makeServer(baseUrl: "http://helper-bg-b")
        try installServerForHelperSync(server)
        try installServerForHelperSync(other)
        let first = try XCTUnwrap(serverManager.requestServerHelperConfigSync(serverId: server.id))
        let firstRequest = try await loader.nextRequest()
        let independent = try XCTUnwrap(serverManager.requestServerHelperConfigSync(serverId: other.id))
        let independentRequest = try await loader.nextRequest()
        let latest = try XCTUnwrap(serverManager.requestServerHelperConfigSync(serverId: server.id))
        let latestRequest = try await loader.nextRequest()

        try latestRequest.succeed(servicePort: 8002)
        _ = try await latest.task.value
        try firstRequest.succeed(servicePort: 8001)
        await assertHelperLoadFailed(first)
        try independentRequest.succeed(servicePort: 8101)
        _ = try await independent.task.value
        XCTAssertEqual(serverRepository.getDSReaderHelper(for: server.id)?.configuration?.dsreader_helper_prefs?.plugin_prefs.Options.servicePort, 8002)
        XCTAssertEqual(serverRepository.getDSReaderHelper(for: other.id)?.configuration?.dsreader_helper_prefs?.plugin_prefs.Options.servicePort, 8101)
    }

    func testBackgroundHelperCannotOverwriteManualConfirmationOrApply() async throws {
        let loader = installControlledHelperLoader()
        let server = TestFixtures.makeServer(baseUrl: "http://helper-manual-wins")
        try installServerForHelperSync(server)
        let background = try XCTUnwrap(serverManager.requestServerHelperConfigSync(serverId: server.id))
        let backgroundRequest = try await loader.nextRequest()
        let manual = try serverManager.requestManualHelperConfiguration(serverID: server.id, port: 9090)
        let manualRequest = try await loader.nextRequest()
        XCTAssertNil(serverManager.requestServerHelperConfigSync(serverId: server.id))

        try manualRequest.succeed(servicePort: 9191)
        let candidate = try await manual.task.value
        XCTAssertNil(serverManager.requestServerHelperConfigSync(serverId: server.id))
        XCTAssertEqual(serverRepository.getDSReaderHelper(for: server.id)?.port, 8080)
        let saved = try serverManager.applyHelperConfiguration(candidate)
        try backgroundRequest.succeed(servicePort: 8888)
        await assertHelperLoadFailed(background)
        XCTAssertEqual(serverRepository.getDSReaderHelper(for: server.id), saved)
        XCTAssertEqual(saved.port, 9090)
    }

    func testBackgroundHelperDiscardsAResponseAfterSavedPortChangesOrServerDeletion() async throws {
        let loader = installControlledHelperLoader()
        let server = TestFixtures.makeServer(baseUrl: "http://helper-bg-edit")
        try installServerForHelperSync(server)
        let first = try XCTUnwrap(serverManager.requestServerHelperConfigSync(serverId: server.id))
        let firstRequest = try await loader.nextRequest()
        let current = CalibreServerDSReaderHelper(port: 9090, configurationData: try makeDSReaderHelperConfigurationData(servicePort: 9090))
        try serverRepository.saveDSReaderHelper(current, for: server.id)
        try firstRequest.succeed(servicePort: 8080)
        await assertHelperLoadFailed(first)
        XCTAssertEqual(serverRepository.getDSReaderHelper(for: server.id), current)

        let second = try XCTUnwrap(serverManager.requestServerHelperConfigSync(serverId: server.id))
        let secondRequest = try await loader.nextRequest()
        XCTAssertEqual(secondRequest.port, 9090)
        try serverRepository.deleteServer(id: server.id)
        try secondRequest.succeed(servicePort: 9191)
        await assertHelperLoadFailed(second)
        XCTAssertNil(serverRepository.getDSReaderHelper(for: server.id))
    }

    private func assertHelperLoadFailed(_ load: DSReaderHelperConfigurationLoad, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await load.task.value
            XCTFail("A superseded configuration request returned a candidate", file: file, line: line)
        } catch {}
    }

    private func installControlledHelperLoader() -> ControlledHelperLoader {
        let loader = ControlledHelperLoader()
        serverManager = CalibreServerManager(container: container, databaseService: databaseService,
                                             serverRepository: serverRepository, loadHelperConfiguration: loader.load)
        container.serverManager = serverManager
        return loader
    }

    func testSyncServerHelperConfigUpdatesConfiguration() async throws {
        let server = CalibreServer(uuid: UUID(), name: "Helper Server", baseUrl: "http://helper-one", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        try installServerForHelperSync(server)

        let payload = try makeDSReaderHelperConfigurationData(servicePort: 7777)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, payload)
        }

        let load = try XCTUnwrap(serverManager.requestServerHelperConfigSync(serverId: server.id))
        _ = try await load.task.value
        let helper = serverManager.queryServerDSReaderHelper(server: server)
        XCTAssertEqual(helper?.port, 8080)
        XCTAssertEqual(helper?.configurationData, payload)
        XCTAssertEqual(helper?.configuration?.dsreader_helper_prefs?.plugin_prefs.Options.servicePort, 7777)
    }

    func testSyncServerHelperConfigIgnoresRequestFailure() async throws {
        let server = CalibreServer(uuid: UUID(), name: "Failing Helper Server", baseUrl: "http://helper-fail", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        try installServerForHelperSync(server)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("failure".utf8))
        }

        let load = try XCTUnwrap(serverManager.requestServerHelperConfigSync(serverId: server.id))
        await assertHelperLoadFailed(load)

        let helper = serverManager.queryServerDSReaderHelper(server: server)
        XCTAssertNotNil(helper)
        XCTAssertNil(helper?.configurationData)
    }

    func testSyncServerHelperConfigIgnoresConfigurationWithoutDSReaderPrefs() async throws {
        let server = CalibreServer(uuid: UUID(), name: "Invalid Helper Server", baseUrl: "http://helper-invalid", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        try installServerForHelperSync(server)

        let config = CalibreDSReaderHelperConfiguration(
            dsreader_helper_prefs: nil,
            count_pages_prefs: CalibreCountPagesPrefs(library_config: [:]),
            goodreads_sync_prefs: nil
        )
        let payload = try JSONEncoder().encode(config)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, payload)
        }

        let load = try XCTUnwrap(serverManager.requestServerHelperConfigSync(serverId: server.id))
        await assertHelperLoadFailed(load)

        let helper = serverManager.queryServerDSReaderHelper(server: server)
        XCTAssertNotNil(helper)
        XCTAssertNil(helper?.configurationData)
    }

    func testSyncServerHelperConfigTracksMultipleServersIndependently() async throws {
        let serverOne = CalibreServer(uuid: UUID(), name: "Helper One", baseUrl: "http://helper-one", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let serverTwo = CalibreServer(uuid: UUID(), name: "Helper Two", baseUrl: "http://helper-two", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        try installServerForHelperSync(serverOne)
        try installServerForHelperSync(serverTwo)

        let payloadOne = try makeDSReaderHelperConfigurationData(servicePort: 7101)
        let payloadTwo = try makeDSReaderHelperConfigurationData(servicePort: 7202)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = request.url?.host == "helper-two" ? payloadTwo : payloadOne
            return (response, data)
        }

        let one = try XCTUnwrap(serverManager.requestServerHelperConfigSync(serverId: serverOne.id))
        let two = try XCTUnwrap(serverManager.requestServerHelperConfigSync(serverId: serverTwo.id))
        _ = try await one.task.value
        _ = try await two.task.value
        let helperOne = serverManager.queryServerDSReaderHelper(server: serverOne)
        let helperTwo = serverManager.queryServerDSReaderHelper(server: serverTwo)
        XCTAssertEqual(helperOne?.configuration?.dsreader_helper_prefs?.plugin_prefs.Options.servicePort, 7101)
        XCTAssertEqual(helperTwo?.configuration?.dsreader_helper_prefs?.plugin_prefs.Options.servicePort, 7202)
    }

    private func installServerForHelperSync(_ server: CalibreServer) throws {
        container.serverManager.calibreServers[server.id] = server
        try serverRepository.saveServer(server)
        serverManager.updateServerDSReaderHelper(serverId: server.id, dsreaderHelper: CalibreServerDSReaderHelper(port: 8080))

        let request = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false)
        let info = CalibreServerInfo(
            server: server,
            isPublic: false,
            url: URL(string: server.baseUrl)!,
            reachable: true,
            probing: false,
            errorMsg: "Success",
            defaultLibrary: "lib",
            libraryMap: ["lib": "Library"],
            request: request
        )
        serverManager.calibreServerInfoStaging[request.id] = info

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

    private func makeDSReaderHelperConfigurationData(servicePort: Int) throws -> Data {
        let options = CalibreDSReaderHelperPrefs.Options(servicePort: servicePort)
        let config = CalibreDSReaderHelperConfiguration(
            dsreader_helper_prefs: CalibreDSReaderHelperPrefs(plugin_prefs: .init(Options: options)),
            count_pages_prefs: nil,
            goodreads_sync_prefs: nil
        )
        return try JSONEncoder().encode(config)
    }

}

@MainActor
private final class ControlledHelperLoader {
    struct Pending {
        let request: DSReaderHelperConfigurationRequest
        let result: CheckedContinuation<DSReaderHelperConfigurationPayload, Error>

        var port: Int { request.port }
        var server: CalibreServer { request.server }
        var libraries: [DSReaderHelperConfigurationRequest.Library] { request.libraries }

        func succeed(servicePort: Int) throws {
            let configuration = CalibreDSReaderHelperConfiguration(
                dsreader_helper_prefs: .init(plugin_prefs: .init(Options: .init(servicePort: servicePort)))
            )
            result.resume(returning: try .init(configuration: configuration))
        }

        func fail(_ error: Error) {
            result.resume(throwing: error)
        }
    }

    private(set) var requestCount = 0
    private var requests: [Pending] = []
    private var receivedRequest: XCTestExpectation?

    func load(_ service: CalibreServerService, _ request: DSReaderHelperConfigurationRequest) async throws -> DSReaderHelperConfigurationPayload {
        try await withCheckedThrowingContinuation { result in
            requestCount += 1
            requests.append(Pending(request: request, result: result))
            receivedRequest?.fulfill()
            receivedRequest = nil
        }
    }

    func nextRequest() async throws -> Pending {
        if requests.isEmpty {
            let received = XCTestExpectation(description: "Helper load started")
            receivedRequest = received
            _ = await XCTWaiter.fulfillment(of: [received], timeout: 3)
            receivedRequest = nil
        }
        return try XCTUnwrap(requests.isEmpty ? nil : requests.removeFirst())
    }
}


private final class DeferredProbeURLProtocol: URLProtocol, @unchecked Sendable {
    static var onStart: ((DeferredProbeURLProtocol) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.onStart?(self) }
    override func stopLoading() {}

    func finish(defaultLibrary: String) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                             headerFields: ["Content-Type": "application/json"]) else { return }
        let data = Data(#"{"default_library":"\#(defaultLibrary)","library_map":{"\#(defaultLibrary)":"Library"}}"#.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
