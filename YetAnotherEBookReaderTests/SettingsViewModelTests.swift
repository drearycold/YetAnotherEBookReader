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
        mockAppContainer = AppContainer(mock: true)
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

    func testServerViewModelProcessInputNormalizesURLAndAllowsBlankPublicURL() {
        let viewModel = ServerViewModel(container: mockAppContainer, server: nil)
        viewModel.calibreServerUrl = "example.com"
        viewModel.calibreServerUrlPublic = ""

        viewModel.processInputAction(server: nil) {}

        XCTAssertEqual(viewModel.calibreServerUrl, "http://example.com/")
        XCTAssertEqual(viewModel.calibreServerUrlPublic, "")
        XCTAssertTrue(viewModel.serverCalibreInfoPresenting)
    }

}
