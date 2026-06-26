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
    var modelData: ModelData!
    var service: CalibreServerService!
    var server: CalibreServer!
    var library: CalibreLibrary!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()

        let config = Realm.Configuration(inMemoryIdentifier: "CalibreServerServiceTests-\(UUID().uuidString)")
        DatabaseService.shared.setup(conf: config)

        modelData = ModelData(mock: true)
        modelData.realmConf = config
        service = modelData.calibreServerService
        cancellables = []

        server = CalibreServer(uuid: UUID(), name: "Server", baseUrl: "http://localhost", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        library = CalibreLibrary(server: server, key: "lib1", name: "Library 1")

        let probeRequest = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: false, incremental: false)
        let info = CalibreServerInfo(server: server, isPublic: false, url: URL(string: "http://localhost")!, reachable: true, probing: false, errorMsg: "Success", defaultLibrary: library.id, libraryMap: [library.id: library.name], request: probeRequest)
        modelData.calibreServerInfoStaging = [server.uuid.uuidString: info]

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
        modelData = nil
        ModelData.shared = nil
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
}
