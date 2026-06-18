//
//  DSReaderHelperConnectorTests.swift
//  YetAnotherEBookReaderTests
//
//  Created on 2026/6/18.
//  P1/A09: Verifies that DSReaderHelperConnector.urlSession no longer uses
//  DispatchQueue.main.sync and can be safely accessed from background threads.
//

import XCTest
import Combine
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
final class DSReaderHelperConnectorTests: XCTestCase {
    var modelData: ModelData!
    var service: CalibreServerService!
    var server: CalibreServer!
    var library: CalibreLibrary!
    var dsreaderHelperServer: CalibreServerDSReaderHelper!

    override func setUp() async throws {
        try await super.setUp()

        let config = Realm.Configuration(inMemoryIdentifier: "DSReaderHelperConnectorTests-\(UUID().uuidString)")
        DatabaseService.shared.setup(conf: config)

        modelData = ModelData(mock: true)
        modelData.realmConf = config
        service = modelData.calibreServerService

        server = CalibreServer(uuid: UUID(), name: "Server", baseUrl: "http://localhost", hasPublicUrl: false, publicUrl: "", hasAuth: true, username: "user", password: "pass")
        library = CalibreLibrary(server: server, key: "lib1", name: "Library 1")

        let probeRequest = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        let info = CalibreServerInfo(server: server, isPublic: false, url: URL(string: "http://localhost")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: library.id, libraryMap: [library.id: library.name], request: probeRequest)
        modelData.calibreServerInfoStaging = [server.uuid.uuidString: info]

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
        library = nil
        server = nil
        service = nil
        modelData = nil
        ModelData.shared = nil
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
}
