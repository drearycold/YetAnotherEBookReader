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
    private var modelData: ModelData!
    private var serverManager: CalibreServerManager!
    private var databaseService: DatabaseService!
    private var serverRepository: ServerRepositoryProtocol!
    private var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        // Isolated in-memory Realm configuration
        let config = Realm.Configuration(inMemoryIdentifier: "CalibreServerManagerTests-\(UUID().uuidString)")
        DatabaseService.shared.setup(conf: config)
        
        modelData = ModelData(mock: true)
        modelData.realmConf = config
        
        serverManager = modelData.serverManager
        databaseService = modelData.databaseService
        serverRepository = modelData.serverRepository
        cancellables = []
    }

    override func tearDownWithError() throws {
        modelData = nil
        serverManager = nil
        databaseService = nil
        serverRepository = nil
        cancellables = nil
        ModelData.shared = nil
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
        XCTAssertNotNil(modelData.calibreLibraries[newLib.id])
        let allLibs = modelData.libraryRepository.getAllLibraries()
        XCTAssertTrue(allLibs.contains(where: { $0.id == newLib.id }))
    }

    func testUpdateServerRealm() throws {
        let server = CalibreServer(uuid: UUID(), name: "Server X", baseUrl: "http://localhost/x", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        try serverManager.updateServerRealm(server: server)
        
        let allServers = serverRepository.getAllServers()
        XCTAssertTrue(allServers.contains(where: { $0.id == server.id }))
    }

    func testRemoveServer() async throws {
        let server = CalibreServer(uuid: UUID(), name: "Delete Server", baseUrl: "http://localhost/del", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        modelData.calibreServers[server.id] = server
        try serverRepository.saveServer(server)
        
        let library = CalibreLibrary(server: server, key: "del_lib", name: "Delete Library")
        modelData.calibreLibraries[library.id] = library
        try modelData.libraryRepository.saveLibrary(library)
        
        // Verify library exists in repository before deletion
        XCTAssertNotNil(modelData.libraryRepository.getAllLibraries().first { $0.id == library.id })
        
        // Remove server
        await serverManager.removeServer(server: server)
        
        // Verify libraries associated with server are deleted from repository
        XCTAssertNil(modelData.libraryRepository.getAllLibraries().first { $0.id == library.id })
        XCTAssertNil(modelData.calibreLibraries[library.id])
    }

    func testDSReaderHelperOperations() throws {
        let server = CalibreServer(uuid: UUID(), name: "Server DSR", baseUrl: "http://localhost/dsr", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        modelData.calibreServers[server.id] = server
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
            request: .init(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
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
            request: .init(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
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

    func testProbeServerSuccess() async throws {
        let server = CalibreServer(uuid: UUID(), name: "Probe Server Success", baseUrl: "http://localhost/probe_success", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        modelData.calibreServers[server.id] = server
        
        // Mock session mapping for CalibreServerService
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        for timeout in [10.0, 600.0] {
            for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
                let key = CalibreServerURLSessionKey(server: server, timeout: timeout, qos: qos)
                modelData.calibreServerService.metadataSessions[key] = mockSession
            }
        }
        
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            let statusCode: Int
            let jsonString: String
            
            if path.contains("library-info") {
                statusCode = 200
                jsonString = """
                {
                    "default_library": "lib_default",
                    "library_map": {
                        "lib_default": "Default Library",
                        "lib_other": "Other Library"
                    }
                }
                """
            } else if path.contains("custom_columns") {
                statusCode = 200
                jsonString = "{}"
            } else if path.contains("categories") {
                statusCode = 200
                jsonString = "[]"
            } else if path.contains("list") {
                statusCode = 200
                jsonString = """
                {
                    "book_ids": [],
                    "data": {
                        "last_modified": [:]
                    }
                }
                """
            } else {
                statusCode = 404
                jsonString = ""
            }
            
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            return (response, jsonString.data(using: .utf8)!)
        }
        
        // Call probeServer (updateLibrary: true)
        let request = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: true, autoUpdateOnly: true, incremental: true)
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
        
        // Verify library was auto-created in modelData.calibreLibraries and saved to repository
        let autoLibId = CalibreLibrary(server: server, key: "lib_other", name: "Other Library").id
        XCTAssertNotNil(modelData.calibreLibraries[autoLibId])
        XCTAssertNotNil(modelData.libraryRepository.getAllLibraries().first { $0.id == autoLibId })
    }

    func testProbeServerFailure() async throws {
        let server = CalibreServer(uuid: UUID(), name: "Probe Server Failure", baseUrl: "http://localhost/probe_failure", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        modelData.calibreServers[server.id] = server
        
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        for timeout in [10.0, 600.0] {
            for qos in [DispatchQoS.QoSClass.default, .background, .utility, .userInitiated, .userInteractive, .unspecified] {
                let key = CalibreServerURLSessionKey(server: server, timeout: timeout, qos: qos)
                modelData.calibreServerService.metadataSessions[key] = mockSession
            }
        }
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        
        let request = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: true, incremental: true)
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
        
        let req1 = CalibreProbeServerRequest(server: server1, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        let req2 = CalibreProbeServerRequest(server: server2, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        let req2Pub = CalibreProbeServerRequest(server: server2, isPublic: true, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        
        XCTAssertNotNil(serverManager.calibreServerInfoStaging[req1.id])
        XCTAssertNotNil(serverManager.calibreServerInfoStaging[req2.id])
        XCTAssertNotNil(serverManager.calibreServerInfoStaging[req2Pub.id])
    }
}
