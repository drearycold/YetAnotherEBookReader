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

        let request = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: true, incremental: true)
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
