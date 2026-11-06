//
//  SettingsViewModelTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by opencode on 2026/6/18.
//

import XCTest
import SwiftUI
import Combine
@testable import YetAnotherEBookReader

@MainActor class SettingsViewModelTests: XCTestCase {
    var viewModel: SettingsViewModel!
    var mockAppContainer: AppContainer!
    var cancellables: Set<AnyCancellable>!
    var orderedEvents: [String]!
    
    override func setUpWithError() throws {
        mockAppContainer = MockAppContainerFactory.makeContainer(testName: "SettingsViewModelTests")
        mockAppContainer.calibreServers.removeAll()
        mockAppContainer.calibreLibraries.removeAll()
        mockAppContainer.booksInShelf.removeAll()
        orderedEvents = []
        viewModel = SettingsViewModel(container: mockAppContainer)
        cancellables = []
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        mockAppContainer = nil
        cancellables = nil
        orderedEvents = nil
    }
    
    func testInitialization() throws {
        XCTAssertEqual(viewModel.serverList.count, 0)
        XCTAssertNil(viewModel.serverListDelete)
        XCTAssertNil(viewModel.selectedServer)
        XCTAssertFalse(viewModel.addServerActive)
        XCTAssertNil(viewModel.alertItem)
    }
    
    func testUpdateServerList() throws {
        let server = CalibreServer(uuid: UUID(), name: "Test Server", baseUrl: "http://localhost", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        mockAppContainer.calibreServers[server.id] = server
        
        viewModel.updateServerList()
        
        XCTAssertEqual(viewModel.serverList.count, 1)
        XCTAssertEqual(viewModel.serverList.first?.id, server.id)
    }
    
    func testStageServerDeletion() throws {
        let server = CalibreServer(uuid: UUID(), name: "Test Server", baseUrl: "http://localhost", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        mockAppContainer.calibreServers[server.id] = server
        viewModel.updateServerList()
        
        viewModel.stageServerDeletion(at: 0)
        
        XCTAssertEqual(viewModel.serverListDelete?.id, server.id)
        XCTAssertEqual(viewModel.alertItem?.id, "DelServer")
    }
    
    func testCancelServerDeletion() throws {
        let server = CalibreServer(uuid: UUID(), name: "Test Server", baseUrl: "http://localhost", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        viewModel.serverListDelete = server
        
        viewModel.cancelServerDeletion()
        
        XCTAssertNil(viewModel.serverListDelete)
    }

    func testUpdateServerTriggersRefreshPopulateAndProbeInOrder() throws {
        let oldServer = CalibreServer(uuid: UUID(), name: "Old Server", baseUrl: "http://localhost/old", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let newServer = CalibreServer(uuid: UUID(), name: "New Server", baseUrl: "http://localhost/new", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        mockAppContainer.calibreServers[oldServer.id] = oldServer
        mockAppContainer.booksInShelf["stale"] = TestFixtures.makeBook()
        var staleRemovedBeforePopulate = false

        let expectation = expectation(description: "refresh pipeline")
        viewModel = SettingsViewModel(
            container: mockAppContainer,
            refreshDatabaseAction: { [weak self] in
                self?.orderedEvents.append("refresh")
                self?.mockAppContainer.refreshDatabase()
            },
            populateBookShelfAction: { [weak self] in
                self?.orderedEvents.append("populate")
                staleRemovedBeforePopulate = self?.mockAppContainer.booksInShelf["stale"] == nil
                self?.mockAppContainer.bookManager.populateBookShelf()
            },
            probeServersReachabilityAction: { [weak self] serverIds in
                self?.orderedEvents.append("probe")
                self?.mockAppContainer.serverManager.probeServersReachability(with: serverIds)
                expectation.fulfill()
            }
        )

        viewModel.updateServer(oldServer: oldServer, newServer: newServer)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(orderedEvents, ["refresh", "populate", "probe"])
        XCTAssertTrue(staleRemovedBeforePopulate)
    }

    func testServerInfoSnapshotsUpdateRefreshingAndRowState() async throws {
        let server = CalibreServer(uuid: UUID(), name: "Status Server", baseUrl: "http://localhost/status", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        mockAppContainer.serverManager.calibreServers[server.id] = server
        viewModel.updateServerList()
        let initialServerList = viewModel.serverList

        let request = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: true)
        let probingInfo = CalibreServerInfo(
            server: server,
            isPublic: false,
            url: URL(string: server.baseUrl)!,
            probing: true,
            errorMsg: "Connecting",
            defaultLibrary: "",
            libraryMap: [:],
            request: request
        )
        mockAppContainer.serverManager.calibreServerInfoStaging[request.id] = probingInfo

        let receivedProbingSnapshot = await waitUntil { self.viewModel.isRefreshing }
        XCTAssertTrue(receivedProbingSnapshot)
        XCTAssertEqual(viewModel.serverList, initialServerList)

        let reachableInfo = CalibreServerInfo(
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
        mockAppContainer.serverManager.calibreServerInfoStaging[request.id] = reachableInfo

        let receivedReachableSnapshot = await waitUntil { self.viewModel.isRefreshing == false }
        XCTAssertTrue(receivedReachableSnapshot)
        let state = viewModel.rowState(for: server)
        XCTAssertEqual(state.isLocalReachable, true)
        XCTAssertEqual(state.serverInfoText, "Server has 1 libraries")
        XCTAssertFalse(state.isServerError)
        XCTAssertEqual(viewModel.serverList, initialServerList)
    }

    func testServerViewModelProcessInputNormalizesURLAndAllowsBlankPublicURL() {
        let viewModel = ServerViewModel(container: mockAppContainer, server: nil)
        viewModel.calibreServerUrl = "example.com"
        viewModel.calibreServerUrlPublic = ""

        viewModel.processInputAction(server: nil) {}

        XCTAssertEqual(viewModel.calibreServerUrl, "http://example.com/")
        XCTAssertEqual(viewModel.calibreServerUrlPublic, "")
        XCTAssertTrue(viewModel.serverCalibreInfoPresenting)
    }

    func testFailedProbeCannotBeConfirmedAsANewServer() throws {
        let server = TestFixtures.makeServer()
        let connection = ServerViewModel(container: mockAppContainer, server: nil)
        connection.dataAction = "Add"
        connection.serverCalibreInfoPresenting = true
        connection.calibreServerInfo = CalibreServerInfo(
            server: server, isPublic: false, url: try XCTUnwrap(URL(string: server.baseUrl)),
            reachable: false, probing: false, errorMsg: "Connection failed",
            defaultLibrary: "library", libraryMap: ["library": "Library"],
            request: .init(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: true)
        )
        var savedServer: CalibreServer?
        var active = true

        connection.addServerConfirmed(
            serverBinding: Binding(get: { savedServer }, set: { savedServer = $0 }),
            isActiveBinding: Binding(get: { active }, set: { active = $0 })
        )

        XCTAssertTrue(mockAppContainer.calibreServers.isEmpty)
        XCTAssertTrue(mockAppContainer.calibreLibraries.isEmpty)
        XCTAssertNil(savedServer)
        XCTAssertTrue(active)
    }

    func testSingleConnectedLibrarySavesAndBrowsesThatLibrary() throws {
        let connection = try stagedConnection(libraries: ["only": "Only Library"])
        let expected = try XCTUnwrap(connection.librariesToAdd.first)
        XCTAssertEqual(connection.libraryToBrowse?.id, expected.id)
        var browsedLibrary: CalibreLibrary?
        var active = true
        connection.addServerConfirmed(serverBinding: .constant(nil),
            isActiveBinding: Binding(get: { active }, set: { active = $0 }),
            browseLibrary: { browsedLibrary = $0 })

        XCTAssertFalse(active)
        XCTAssertEqual(browsedLibrary?.id, expected.id)
        XCTAssertEqual(mockAppContainer.libraryRepository.getAllLibraries().first { $0.id == expected.id }?.name, "Only Library")
        XCTAssertNotNil(mockAppContainer.serverRepository.getAllServers().first { $0.id == expected.server.id })
    }

    func testMultipleLibrariesRequireAnExplicitChoiceAndSaveAllLibraries() throws {
        let connection = try stagedConnection(libraries: ["a": "First Library", "b": "Second Library"])
        XCTAssertNil(connection.libraryToBrowse)
        var browsedLibrary: CalibreLibrary?
        var active = true
        let binding = Binding(get: { active }, set: { active = $0 })
        connection.addServerConfirmed(serverBinding: .constant(nil), isActiveBinding: binding,
                                      browseLibrary: { browsedLibrary = $0 })
        XCTAssertTrue(active)
        XCTAssertNil(browsedLibrary)
        XCTAssertTrue(mockAppContainer.calibreServers.isEmpty)

        let second = try XCTUnwrap(connection.librariesToAdd.first { $0.key == "b" })
        connection.browseLibraryID = second.id
        connection.addServerConfirmed(serverBinding: .constant(nil), isActiveBinding: binding,
                                      browseLibrary: { browsedLibrary = $0 })
        XCTAssertFalse(active)
        XCTAssertEqual(browsedLibrary?.id, second.id)
        XCTAssertEqual(Set(mockAppContainer.calibreLibraries.values.map(\.key)), ["a", "b"])
        XCTAssertEqual(mockAppContainer.libraryRepository.getAllLibraries().filter { $0.server.id == second.server.id }.count, 2)
    }

    func testSettingsAddDoesNotRequireChoosingABrowseLibrary() throws {
        let connection = try stagedConnection(libraries: ["a": "First", "b": "Second"])
        var active = true
        connection.addServerConfirmed(serverBinding: .constant(nil),
            isActiveBinding: Binding(get: { active }, set: { active = $0 }))
        XCTAssertFalse(active)
        XCTAssertEqual(mockAppContainer.calibreLibraries.count, 2)
    }

    func testCancelledOrStillProbingConnectionCannotSaveOrBrowse() throws {
        for cancelled in [false, true] {
            let connection = try stagedConnection(libraries: ["a": "Library"])
            if cancelled {
                connection.disableProbeServerCancellable()
            } else {
                connection.isProbing = true
            }
            var active = true
            var didBrowse = false
            connection.addServerConfirmed(serverBinding: .constant(nil),
                isActiveBinding: Binding(get: { active }, set: { active = $0 }),
                browseLibrary: { _ in didBrowse = true })
            XCTAssertTrue(active)
            XCTAssertFalse(didBrowse)
            XCTAssertTrue(mockAppContainer.calibreServers.isEmpty)
            XCTAssertTrue(mockAppContainer.calibreLibraries.isEmpty)
        }
    }

    func testCancellingAnInFlightProbeDiscardsItsLateAnswer() async throws {
        let connection = ServerViewModel(container: mockAppContainer, server: nil)
        connection.calibreServerUrl = "http://127.0.0.1:1"
        var didComplete = false
        connection.processInputAction(server: nil) { didComplete = true }
        connection.disableProbeServerCancellable()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(connection.calibreServerInfo)
        XCTAssertFalse(connection.isProbing)
        XCTAssertFalse(didComplete)
        XCTAssertTrue(mockAppContainer.calibreServers.isEmpty)
    }

    func testReopeningConnectionClearsPreviousResultAndLibraryChoice() throws {
        let connection = try stagedConnection(libraries: ["a": "First", "b": "Second"])
        connection.browseLibraryID = connection.librariesToAdd.last?.id
        connection.resetStates(server: nil)
        XCTAssertFalse(connection.serverCalibreInfoPresenting)
        XCTAssertNil(connection.calibreServerInfo)
        XCTAssertNil(connection.libraryToBrowse)
        XCTAssertNil(connection.browseLibraryID)
        XCTAssertNil(connection.dataAction)
        XCTAssertTrue(connection.calibreServerUrl.isEmpty)
    }

    func testConnectionFailurePresentationNeverIncludesServerBodiesAndRetainsHTTPStatus() throws {
        let connection = try stagedConnection(libraries: [:])
        let body = Data(("<html><style>" + String(repeating: "CSS server error", count: 10000)).utf8)
        for status in [400, 401, 403, 404, 429, 500, 503] {
            var info = try XCTUnwrap(connection.calibreServerInfo)
            info.reachable = false
            info.errorMsg = String(decoding: body, as: UTF8.self)
            info.error = status == 401 || status == 403 ? .authFailed : .httpStatus(status, body)
            info.httpStatusCode = status
            let display = ServerConnectionStatus(info: info)
            XCTAssertTrue(display.title.contains("HTTP \(status)"))
            XCTAssertLessThan((display.message ?? "").count, 180)
            XCTAssertFalse((display.title + (display.message ?? "")).contains("<html>"))
            XCTAssertEqual(info.error?.localizedDescription,
                           status == 401 || status == 403 ? "Authentication Failed" : status == 404 ? "Deleted" : info.errorMsg)
        }
    }

    func testConnectionMessagesDistinguishKnownCausesWithoutGuessingAuthentication() throws {
        let connection = try stagedConnection(libraries: [:])
        var info = try XCTUnwrap(connection.calibreServerInfo)
        info.reachable = false
        let cases: [(CalibreAPIError, String)] = [
            (.transport(URLError(.cannotConnectToHost)), "address, port and network"),
            (.transport(URLError(.timedOut)), "did not respond in time"),
            (.transport(URLError(.notConnectedToInternet)), "network connection"),
            (.transport(URLError(.serverCertificateUntrusted)), "server certificate"),
            (.transport(URLError(.cancelled)), "If the server requires authentication"),
            (.authFailed, "username, password"),
            (.unsupportedPayload, "library list"),
            (.unknown(NSError(domain: "<html>", code: 0)), "address, port and network")
        ]
        for (error, expected) in cases {
            info.error = error
            XCTAssertTrue(ServerConnectionStatus(info: info).message?.contains(expected) == true, "\(error)")
        }
        info.httpStatusCode = 200
        info.error = .unsupportedPayload
        XCTAssertTrue(ServerConnectionStatus(info: info).message?.contains("library list") == true)
        info.errorMsg = "Server has no library"
        XCTAssertTrue(ServerConnectionStatus(info: info).message?.contains("no available libraries") == true)
        info.httpStatusCode = 401
        info.error = .transport(URLError(.cancelled))
        XCTAssertTrue(ServerConnectionStatus(info: info).title.contains("HTTP 401"))
        XCTAssertFalse(ServerConnectionStatus(info: info).message?.contains("cancelled") == true)
    }

    func testEditConnectionPreservesAllInputAndCannotSaveAnOldSuccess() throws {
        let connection = try stagedConnection(libraries: ["a": "Library"])
        connection.calibreServerName = "My Calibre"
        connection.calibreServerUrl = "http://localhost:8080/"
        connection.calibreServerUrlPublic = "https://example.com/"
        connection.calibreServerSetPublicAddress = true
        connection.calibreServerNeedAuth = true
        connection.calibreUsername = "user"
        connection.calibrePassword = "password"
        connection.editConnection()
        XCTAssertEqual(connection.calibreServerName, "My Calibre")
        XCTAssertEqual(connection.calibreServerUrl, "http://localhost:8080/")
        XCTAssertEqual(connection.calibreServerUrlPublic, "https://example.com/")
        XCTAssertTrue(connection.calibreServerSetPublicAddress)
        XCTAssertTrue(connection.calibreServerNeedAuth)
        XCTAssertEqual(connection.calibreUsername, "user")
        XCTAssertEqual(connection.calibrePassword, "password")
        XCTAssertFalse(connection.serverCalibreInfoPresenting)
        XCTAssertNil(connection.calibreServerInfo)
        XCTAssertNil(connection.dataAction)
        XCTAssertFalse(connection.canConfirmServer)
    }

    private func stagedConnection(libraries: [String: String]) throws -> ServerViewModel {
        let server = TestFixtures.makeServer(baseUrl: "http://127.0.0.1:1")
        let connection = ServerViewModel(container: mockAppContainer, server: nil)
        connection.dataAction = "Add"
        connection.serverCalibreInfoPresenting = true
        connection.calibreServerInfo = CalibreServerInfo(
            server: server, isPublic: false, url: try XCTUnwrap(URL(string: server.baseUrl)),
            reachable: true, probing: false, errorMsg: "Success", defaultLibrary: "a", libraryMap: libraries,
            request: .init(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: true)
        )
        return connection
    }

    private func waitUntil(
        timeout: TimeInterval = 1.0,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

}
