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
    
    override func setUpWithError() throws {
        mockAppContainer = MockAppContainerFactory.makeContainer(testName: "SettingsViewModelTests")
        mockAppContainer.calibreServers.removeAll()
        mockAppContainer.calibreLibraries.removeAll()
        mockAppContainer.booksInShelf.removeAll()
        viewModel = SettingsViewModel(container: mockAppContainer)
        cancellables = []
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        mockAppContainer = nil
        cancellables = nil
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

    func testFailedConnectionSaveKeepsCurrentManagerSnapshot() {
        let server = TestFixtures.makeServer(baseUrl: "http://saved:8080")
        let repository = MockServerRepository()
        repository.saveServerError = CocoaError(.fileWriteNoPermission)
        let manager = CalibreServerManager(container: mockAppContainer, databaseService: mockAppContainer.databaseService,
                                           serverRepository: repository)
        mockAppContainer.serverManager = manager
        manager.calibreServers[server.id] = server
        var draft = server
        draft.baseUrl = "http://unsaved:8080"
        let request = CalibreProbeServerRequest(server: draft, isPublic: false, updateLibrary: false, autoUpdateOnly: true)
        let validation = makeProbeInfo(request, libraries: ["a": "Library"])
        XCTAssertNotNil(validation)
        XCTAssertThrowsError(try manager.updateConnection(draft, ifCurrent: server, validation: validation))
        XCTAssertEqual(manager.calibreServers[server.id]?.baseUrl, server.baseUrl)
        XCTAssertTrue(manager.calibreServerInfoStaging.isEmpty)
    }

    func testFailedServerRemovalKeepsServerListed() {
        let server = TestFixtures.makeServer(baseUrl: "http://saved:8080")
        let repository = MockServerRepository()
        repository.saveServerError = CocoaError(.fileWriteNoPermission)
        let manager = CalibreServerManager(container: mockAppContainer, databaseService: mockAppContainer.databaseService,
                                           serverRepository: repository)
        mockAppContainer.serverManager = manager
        viewModel = SettingsViewModel(container: mockAppContainer)
        manager.calibreServers[server.id] = server
        viewModel.updateServerList()
        viewModel.stageServerDeletion(at: 0)
        XCTAssertEqual(viewModel.serverList.map(\.id), [server.id])
        viewModel.confirmDeleteServer()
        XCTAssertEqual(viewModel.serverList.map(\.id), [server.id])
        XCTAssertEqual(manager.calibreServers[server.id]?.removed, false)
        XCTAssertNotNil(viewModel.alertItem)
    }

    func testAddSaveFailureRetainsResultAndRetryCommitsTheSameIDOnce() async throws {
        let repository = MockServerRepository()
        repository.saveServerError = CocoaError(.fileWriteNoPermission)
        let manager = CalibreServerManager(container: mockAppContainer, databaseService: mockAppContainer.databaseService,
                                           serverRepository: repository)
        mockAppContainer.serverManager = manager
        let editor = try await stagedConnection(libraries: ["one": "One"])
        let id = try XCTUnwrap(editor.serverInfo?.server.id)
        XCTAssertNil(editor.confirm(browseAfterAdding: true))
        XCTAssertEqual(editor.saveFailure, .failed)
        XCTAssertTrue(editor.resultPresented)
        XCTAssertTrue(editor.canConfirmServer)
        XCTAssertTrue(manager.calibreServers.isEmpty)
        XCTAssertTrue(mockAppContainer.calibreLibraries.isEmpty)
        XCTAssertTrue(manager.calibreServerInfoStaging.isEmpty)

        repository.saveServerError = nil
        guard case .added(let library?) = editor.confirm(browseAfterAdding: true) else {
            return XCTFail("Retry did not commit the validated connection")
        }
        XCTAssertEqual(library.server.id, id)
        XCTAssertEqual(manager.calibreServers.keys.sorted(), [id])
        XCTAssertEqual(manager.getServerInfo(server: library.server)?.reachable, true)
        XCTAssertNil(editor.confirm(browseAfterAdding: true))
        editor.endEditing()
        XCTAssertNotNil(manager.calibreServers[id])
    }

    func testRestoreRetainsOnlyFailedSelectionsAndDoesNotChangeTheirFlags() throws {
        let server = TestFixtures.makeServer()
        let first = CalibreLibrary(server: server, key: "one", name: "One", hidden: true)
        let second = CalibreLibrary(server: server, key: "two", name: "Two", hidden: true)
        let repository = MockLibraryRepository()
        repository.visibilityErrors[second.id] = CocoaError(.fileWriteNoPermission)
        let manager = CalibreLibraryManager(container: mockAppContainer, databaseService: mockAppContainer.databaseService,
                                            libraryRepository: repository)
        mockAppContainer.libraryManager = manager
        mockAppContainer.calibreServers[server.id] = server
        manager.calibreLibraries = [first.id: first, second.id: second]
        let detail = ServerDetailViewModel(container: mockAppContainer, serverID: server.id)
        detail.beginRestoringLibraries()
        detail.restoreSelection = [first.id, second.id]

        XCTAssertFalse(detail.restoreLibraries(detail.restoreSelection))
        XCTAssertEqual(detail.restoreSelection, [second.id])
        XCTAssertEqual(detail.snapshot.visible.map(\.id), [first.id])
        XCTAssertEqual(detail.snapshot.hidden.map(\.id), [second.id])
        XCTAssertEqual(detail.librarySaveFailure, .failed)

        repository.visibilityErrors = [:]
        XCTAssertTrue(detail.restoreLibraries(detail.restoreSelection))
        XCTAssertTrue(detail.restoreSelection.isEmpty)
        XCTAssertTrue(detail.snapshot.hidden.isEmpty)
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

    func testConnectionEditorNormalizesURLAndAllowsBlankPublicURL() async throws {
        let editor = makeEditor(libraries: [:])
        editor.startEditing()
        editor.draft.internalAddress = "example.com"

        let probe = try XCTUnwrap(editor.connect())
        XCTAssertEqual(editor.draft.internalAddress, "http://example.com/")
        XCTAssertEqual(editor.draft.publicAddress, "")
        XCTAssertTrue(editor.resultPresented)
        await probe.value
    }

    func testFailedProbeCannotBeConfirmedAsANewServer() async throws {
        let editor = try await stagedConnection(libraries: ["library": "Library"], reachable: false)
        XCTAssertNil(editor.confirm())
        XCTAssertTrue(mockAppContainer.calibreServers.isEmpty)
        XCTAssertTrue(mockAppContainer.calibreLibraries.isEmpty)
        XCTAssertTrue(editor.resultPresented)
    }

    func testSingleConnectedLibrarySavesAndBrowsesThatLibrary() async throws {
        let editor = try await stagedConnection(libraries: ["only": "Only Library"])
        let expected = try XCTUnwrap(editor.librariesFromProbe.first)
        XCTAssertEqual(editor.libraryToBrowse?.id, expected.id)
        guard case .added(let browsed)? = editor.confirm(browseAfterAdding: true) else {
            return XCTFail("Expected a saved server")
        }
        XCTAssertEqual(browsed?.id, expected.id)
        XCTAssertEqual(mockAppContainer.libraryRepository.getAllLibraries().first { $0.id == expected.id }?.name, "Only Library")
        XCTAssertNotNil(mockAppContainer.serverRepository.getAllServers().first { $0.id == expected.server.id })
    }

    func testMultipleLibrariesRequireAnExplicitChoiceAndSaveAllLibraries() async throws {
        let editor = try await stagedConnection(libraries: ["a": "First Library", "b": "Second Library"])
        XCTAssertNil(editor.libraryToBrowse)
        XCTAssertNil(editor.confirm(browseAfterAdding: true))
        XCTAssertTrue(mockAppContainer.calibreServers.isEmpty)

        let second = try XCTUnwrap(editor.librariesFromProbe.first { $0.key == "b" })
        editor.browseLibraryID = second.id
        guard case .added(let browsed)? = editor.confirm(browseAfterAdding: true) else {
            return XCTFail("Expected a saved server")
        }
        XCTAssertEqual(browsed?.id, second.id)
        XCTAssertEqual(Set(mockAppContainer.calibreLibraries.values.map(\.key)), ["a", "b"])
        XCTAssertEqual(mockAppContainer.libraryRepository.getAllLibraries().filter { $0.server.id == second.server.id }.count, 2)
    }

    func testSettingsAddDoesNotRequireChoosingABrowseLibrary() async throws {
        let editor = try await stagedConnection(libraries: ["a": "First", "b": "Second"])
        guard case .added(nil)? = editor.confirm() else { return XCTFail("Expected a save with no Browse route") }
        XCTAssertEqual(mockAppContainer.calibreLibraries.count, 2)
    }

    func testCancellingAnInFlightProbeDiscardsItsLateAnswer() async throws {
        let started = expectation(description: "Probe suspended")
        var result: CheckedContinuation<CalibreServerInfo?, Never>?
        var request: CalibreProbeServerRequest?
        let editor = ServerConnectionEditorViewModel(container: mockAppContainer, mode: .add, probeServer: { pending in
            await withCheckedContinuation {
                request = pending
                result = $0
                started.fulfill()
            }
        })
        editor.startEditing()
        editor.draft.internalAddress = "http://127.0.0.1:1"
        let probe = try XCTUnwrap(editor.connect())
        await fulfillment(of: [started], timeout: 3)
        XCTAssertNil(editor.confirm(browseAfterAdding: true))

        editor.endEditing()
        editor.startEditing()
        result?.resume(returning: makeProbeInfo(try XCTUnwrap(request), libraries: ["a": "Library"]))
        await probe.value

        XCTAssertNil(editor.serverInfo)
        XCTAssertFalse(editor.isProbing)
        XCTAssertNil(editor.confirm(browseAfterAdding: true))
        XCTAssertTrue(mockAppContainer.calibreServers.isEmpty)
    }

    func testReopeningConnectionClearsPreviousResultAndLibraryChoice() async throws {
        let editor = try await stagedConnection(libraries: ["a": "First", "b": "Second"])
        editor.browseLibraryID = editor.librariesFromProbe.last?.id
        editor.endEditing()
        editor.startEditing()
        XCTAssertFalse(editor.resultPresented)
        XCTAssertNil(editor.serverInfo)
        XCTAssertNil(editor.libraryToBrowse)
        XCTAssertNil(editor.browseLibraryID)
        XCTAssertTrue(editor.draft.internalAddress.isEmpty)
    }

    func testConnectionEntrypointsKeepIndependentDraftsAndIgnoreUnrelatedUpdates() async throws {
        let welcome = makeEditor(libraries: [:])
        let settings = makeEditor(libraries: [:])
        XCTAssertNil(welcome.connect())
        welcome.startEditing()
        settings.startEditing()
        welcome.draft.name = "Welcome draft"
        settings.draft.name = "Settings draft"
        let unrelated = TestFixtures.makeServer()
        mockAppContainer.calibreServers[unrelated.id] = unrelated
        welcome.startEditing()
        XCTAssertEqual(welcome.draft.name, "Welcome draft")
        XCTAssertEqual(settings.draft.name, "Settings draft")
        welcome.endEditing()
        welcome.startEditing()
        XCTAssertTrue(welcome.draft.name.isEmpty)
        XCTAssertEqual(settings.draft.name, "Settings draft")
    }

    func testEditRouteRejectsAnOldProbeWhenTheSavedCredentialsChange() async throws {
        var server = TestFixtures.makeServer(baseUrl: "http://server-one:8080")
        server.password = "initial"
        try mockAppContainer.serverRepository.saveServer(server)
        mockAppContainer.calibreServers[server.id] = server
        let editor = makeEditor(libraries: ["a": "Library"], mode: .edit(serverID: server.id))
        editor.startEditing()
        editor.draft.password = "draft"
        let probe = try XCTUnwrap(editor.connect())
        await probe.value
        let other = TestFixtures.makeServer(baseUrl: "http://server-two:8080")
        mockAppContainer.calibreServers[other.id] = other
        XCTAssertTrue(editor.canConfirmServer)
        server.password = "external change"
        mockAppContainer.calibreServers[server.id] = server
        XCTAssertNil(editor.confirm())
        let receivedChange = await waitUntil { editor.connectionStatus.title == "Server Configuration Changed" }
        XCTAssertTrue(receivedChange)
        XCTAssertEqual(editor.draft.password, "draft")

        mockAppContainer.calibreServers.removeValue(forKey: server.id)
        let removed = await waitUntil { !editor.editTargetAvailable }
        XCTAssertTrue(removed)
        XCTAssertNil(editor.connect())
        XCTAssertNil(editor.confirm())
    }

    func testSavingUnchangedConnectionPublishesSuccessfulValidation() async throws {
        try await assertEditPublishesValidation(rename: false)
    }

    func testRenamingServerPublishesSuccessfulValidationForTheSameConnection() async throws {
        try await assertEditPublishesValidation(rename: true)
    }

    private func assertEditPublishesValidation(rename: Bool) async throws {
        let (server, editor) = try await prepareUnreachableServerForEdit()
        defer { MockURLProtocol.requestHandler = nil }
        if rename { editor.draft.name = "Renamed Server" }
        let validation = try XCTUnwrap(editor.connect())
        await validation.value
        let manager = mockAppContainer.serverManager
        let service = mockAppContainer.calibreServerService
        XCTAssertTrue(editor.canConfirmServer)
        XCTAssertEqual(manager.getServerInfo(server: server)?.reachable, false)
        XCTAssertNil(service.getServerUrlByReachability(server: server))

        guard case .edited(let saved)? = editor.confirm() else { return XCTFail("Expected committed edit") }
        XCTAssertEqual(saved.id, server.id)
        XCTAssertEqual(DSReaderHelperConnection(saved), DSReaderHelperConnection(server))
        XCTAssertEqual(mockAppContainer.serverRepository.getAllServers().first { $0.id == saved.id }?.name, editor.draft.name)

        // No actor suspension or refresh response can supply reachability before these checks.
        XCTAssertEqual(manager.getServerInfo(server: saved)?.reachable, true)
        XCTAssertEqual(service.getServerUrlByReachability(server: saved), URL(string: server.baseUrl))
        XCTAssertNoThrow(try {
            let load = try manager.requestManualHelperConfiguration(serverID: saved.id, port: 8081)
            manager.cancelHelperConfiguration(load.ticket)
        }())

        var snapshots = manager.serverInfoStagingSnapshots().makeAsyncIterator()
        let request = CalibreProbeServerRequest(server: saved, isPublic: false, updateLibrary: true, autoUpdateOnly: true)
        let snapshot = await snapshots.next()
        XCTAssertEqual(snapshot?[request.id]?.reachable, true)
        if snapshot?[request.id]?.reachable == true {
            let refreshed = await waitUntil {
                manager.calibreServerInfoStaging[request.id]?.request.updateLibrary == true
                    && manager.calibreServerInfoStaging[request.id]?.probing == false
            }
            XCTAssertTrue(refreshed)
        }
    }

    func testDeletedServerCannotPublishSuccessfulEditValidation() async throws {
        let (server, editor) = try await prepareUnreachableServerForEdit()
        defer { MockURLProtocol.requestHandler = nil }
        let validation = try XCTUnwrap(editor.connect())
        await validation.value
        XCTAssertTrue(editor.canConfirmServer)
        // Drop the persisted target while the editor still sees the previous manager snapshot.
        try mockAppContainer.serverRepository.deleteServer(id: server.id)
        XCTAssertNil(editor.confirm())
        XCTAssertEqual(editor.saveFailure, .stale)
        let manager = mockAppContainer.serverManager
        XCTAssertEqual(manager.getServerInfo(server: server)?.httpStatusCode, 503)
        XCTAssertEqual(manager.getServerInfo(server: server)?.reachable, false)
        XCTAssertNil(mockAppContainer.calibreServerService.getServerUrlByReachability(server: server))
    }

    func testOlderEditValidationDoesNotReplaceNewerReachabilityResult() async throws {
        let (server, editor) = try await prepareUnreachableServerForEdit()
        defer { MockURLProtocol.requestHandler = nil }
        let validation = try XCTUnwrap(editor.connect())
        await validation.value
        XCTAssertTrue(editor.canConfirmServer)
        let validatedStart = try XCTUnwrap(editor.serverInfo?.probeStartedAt)

        answerUnreachableServer()
        let manager = mockAppContainer.serverManager
        let latest = await manager.probeServer(request: .init(server: server, isPublic: false,
                                                               updateLibrary: true, autoUpdateOnly: true))
        let latestStart = try XCTUnwrap(latest?.probeStartedAt)
        XCTAssertGreaterThan(latestStart, validatedStart)
        guard case .edited(let saved)? = editor.confirm() else { return XCTFail("Expected committed edit") }
        XCTAssertEqual(manager.getServerInfo(server: saved)?.probeStartedAt, latestStart)
        XCTAssertEqual(manager.getServerInfo(server: saved)?.reachable, false)
        XCTAssertNil(mockAppContainer.calibreServerService.getServerUrlByReachability(server: saved))
    }

    private func prepareUnreachableServerForEdit() async throws -> (CalibreServer, ServerConnectionEditorViewModel) {
        let server = TestFixtures.makeServer(baseUrl: "http://\(UUID().uuidString).test:8080")
        let library = CalibreLibrary(server: server, key: "a", name: "Library", hidden: true)
        let manager = mockAppContainer.serverManager
        try manager.addServer(server: server, libraries: [library])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        for timeout in [10.0, 600.0] {
            let key = CalibreServerURLSessionKey(server: server, timeout: timeout, qos: .default)
            mockAppContainer.calibreServerService.metadataSessions[key] = session
        }
        answerUnreachableServer()
        let offline = await manager.probeServer(request: .init(server: server, isPublic: false,
                                                               updateLibrary: true, autoUpdateOnly: true))
        XCTAssertEqual(offline?.reachable, false)
        _ = MockURLProtocol.answer([
            "/ajax/library-info": #"{"default_library":"a","library_map":{"a":"Library"}}"#,
            "/ajax/search/a": #"{"total_num":0,"sort_order":"asc","num_books_without_search":0,"offset":0,"num":0,"sort":"title","base_url":"","library_id":"a","book_ids":[],"vl":""}"#
        ])
        let editor = ServerConnectionEditorViewModel(container: mockAppContainer, mode: .edit(serverID: server.id))
        editor.startEditing()
        return (server, editor)
    }

    private func answerUnreachableServer() {
        MockURLProtocol.requestHandler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 503,
                                                        httpVersion: nil, headerFields: nil))
            return (response, Data())
        }
    }

    func testServerDetailObservesOnlyItsServerAndTheVisibleOwner() async throws {
        var server = TestFixtures.makeServer(name: "First server")
        let other = TestFixtures.makeServer(name: "Other server")
        let library = CalibreLibrary(server: server, key: "same-key", name: "Library")
        let otherLibrary = CalibreLibrary(server: other, key: "same-key", name: "Library")
        mockAppContainer.calibreServers = [server.id: server, other.id: other]
        mockAppContainer.calibreLibraries = [library.id: library, otherLibrary.id: otherLibrary]
        try mockAppContainer.libraryRepository.saveLibrary(library)
        let manager = mockAppContainer.libraryManager
        let detail = ServerDetailViewModel(container: mockAppContainer, serverID: server.id)
        XCTAssertNil(detail.snapshot.name)

        detail.startObserving(.detail)
        detail.startObserving(.detail)
        XCTAssertEqual(detail.snapshot.visible.map(\.id), [library.id])
        XCTAssertNil(detail.library(for: otherLibrary.id))
        var snapshots = [ServerDetailViewModel.Snapshot]()
        let subscription = detail.$snapshot.dropFirst().sink { snapshots.append($0) }
        defer { subscription.cancel() }
        manager.librarySyncStatus[otherLibrary.id] = .init(library: otherLibrary, isSync: true)
        manager.calibreLibraries[library.id]?.discoverable = false
        let rowUpdated = await waitUntil { detail.snapshot.visible.first?.discoverable == false }
        XCTAssertTrue(rowUpdated)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertFalse(detail.snapshot.syncing)

        detail.startObserving(.hiddenLibraries)
        detail.stopObserving(.detail)
        try manager.hideLibrary(libraryId: library.id, serverID: server.id)
        let hiddenObserved = await waitUntil { detail.snapshot.hidden.first?.id == library.id }
        XCTAssertTrue(hiddenObserved)
        detail.restoreLibraries([otherLibrary.id, library.id])
        XCTAssertEqual(detail.snapshot.visible.map(\.id), [library.id])
        XCTAssertTrue(detail.snapshot.hidden.isEmpty)

        detail.stopObserving(.hiddenLibraries)
        server.name = "Renamed while stopped"
        mockAppContainer.calibreServers[server.id] = server
        XCTAssertEqual(detail.snapshot.name, "First server")
        detail.startObserving(.detail)
        XCTAssertEqual(detail.snapshot.name, "Renamed while stopped")
        mockAppContainer.calibreServers.removeValue(forKey: server.id)
        let deletedObserved = await waitUntil { detail.snapshot.name == nil }
        XCTAssertTrue(deletedObserved)
        XCTAssertTrue(detail.snapshot.visible.isEmpty)
        XCTAssertTrue(detail.snapshot.hidden.isEmpty)
    }

    func testSettingsKeepsTheSelectedServerIDThroughAnEditAndDismissesOnRemoval() {
        var server = TestFixtures.makeServer(baseUrl: "http://original:8080")
        mockAppContainer.calibreServers[server.id] = server
        viewModel.updateServerList()
        viewModel.openServerDetail(server.id)
        XCTAssertEqual(viewModel.selectedServer, server.id)
        XCTAssertEqual(viewModel.displayedServerID, server.id)

        server.baseUrl = "http://edited:8080"
        server.name = "Edited"
        mockAppContainer.calibreServers[server.id] = server
        viewModel.updateServerList()
        XCTAssertEqual(viewModel.selectedServer, server.id)
        XCTAssertEqual(viewModel.displayedServerID, server.id)

        mockAppContainer.calibreServers.removeValue(forKey: server.id)
        viewModel.updateServerList()
        XCTAssertNil(viewModel.selectedServer)
        XCTAssertEqual(viewModel.displayedServerID, server.id)
    }

    func testObserversReleaseWithTheirModels() {
        let server = TestFixtures.makeServer()
        mockAppContainer.calibreServers[server.id] = server
        weak var detailReference: ServerDetailViewModel?
        weak var helperReference: DSReaderHelperConfigurationViewModel?
        weak var editorReference: ServerConnectionEditorViewModel?
        do {
            let detail = ServerDetailViewModel(container: mockAppContainer, serverID: server.id)
            let helper = DSReaderHelperConfigurationViewModel(container: mockAppContainer, serverID: server.id)
            let editor = makeEditor(libraries: [:], mode: .edit(serverID: server.id))
            detailReference = detail
            helperReference = helper
            editorReference = editor
            detail.startObserving(.detail)
            helper.resume()
            editor.startEditing()
        }
        XCTAssertNil(detailReference)
        XCTAssertNil(helperReference)
        XCTAssertNil(editorReference)
    }

    func testHelperKeepsDirtyDraftThroughChildPagesAndSavedUpdates() async throws {
        let server = TestFixtures.makeServer(baseUrl: "http://helper-draft:8080")
        let other = TestFixtures.makeServer(baseUrl: "http://other-helper:8080")
        let manager = mockAppContainer.serverManager
        try mockAppContainer.serverRepository.saveServer(server)
        try mockAppContainer.serverRepository.saveServer(other)
        mockAppContainer.calibreServers = [server.id: server, other.id: other]
        manager.updateServerDSReaderHelper(serverId: server.id, dsreaderHelper: .init(port: 8081))
        let helper = DSReaderHelperConfigurationViewModel(container: mockAppContainer, serverID: server.id)
        XCTAssertNil(helper.savedHelper)
        XCTAssertNil(helper.connectDSReader())
        helper.resume()
        helper.setPortDraft("9000")
        helper.resume()
        XCTAssertEqual(helper.portStr, "9000")

        manager.updateServerDSReaderHelper(serverId: other.id, dsreaderHelper: .init(port: 9080))
        manager.updateServerDSReaderHelper(serverId: server.id, dsreaderHelper: .init(port: 8082))
        let changed = await waitUntil { helper.savedHelper?.port == 8082 }
        XCTAssertTrue(changed)
        XCTAssertEqual(helper.portStr, "9000")

        helper.suspend()
        manager.updateServerDSReaderHelper(serverId: server.id, dsreaderHelper: .init(port: 8083))
        XCTAssertEqual(helper.savedHelper?.port, 8082)
        helper.resume()
        XCTAssertEqual(helper.savedHelper?.port, 8083)
        XCTAssertEqual(helper.portStr, "9000")
        helper.closeRoute()
        helper.resume()
        XCTAssertEqual(helper.portStr, "8083")

        mockAppContainer.calibreServers[server.id]?.removed = true
        let removed = await waitUntil { !helper.serverAvailable }
        XCTAssertTrue(removed)
        XCTAssertFalse(helper.canDownload)
        XCTAssertNil(helper.savedHelper)
    }

    func testConnectionFailurePresentationNeverIncludesServerBodiesAndRetainsHTTPStatus() throws {
        let request = CalibreProbeServerRequest(server: TestFixtures.makeServer(), isPublic: false,
                                               updateLibrary: false, autoUpdateOnly: true)
        let body = Data(("<html><style>" + String(repeating: "CSS server error", count: 10000)).utf8)
        for status in [400, 401, 403, 404, 429, 500, 503] {
            var info = try XCTUnwrap(makeProbeInfo(request, libraries: [:]))
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
        let request = CalibreProbeServerRequest(server: TestFixtures.makeServer(), isPublic: false,
                                               updateLibrary: false, autoUpdateOnly: true)
        var info = try XCTUnwrap(makeProbeInfo(request, libraries: [:]))
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

    func testEditConnectionPreservesAllInputAndCannotSaveAnOldSuccess() async throws {
        let editor = try await stagedConnection(libraries: ["a": "Library"])
        editor.draft.name = "My Calibre"
        editor.draft.internalAddress = "http://localhost:8080/"
        editor.draft.publicAddress = "https://example.com/"
        editor.draft.usePublicAddress = true
        editor.draft.requiresAuthentication = true
        editor.draft.username = "user"
        editor.draft.password = "password"
        editor.dismissResult()
        XCTAssertEqual(editor.draft.name, "My Calibre")
        XCTAssertEqual(editor.draft.internalAddress, "http://localhost:8080/")
        XCTAssertEqual(editor.draft.publicAddress, "https://example.com/")
        XCTAssertTrue(editor.draft.usePublicAddress)
        XCTAssertTrue(editor.draft.requiresAuthentication)
        XCTAssertEqual(editor.draft.username, "user")
        XCTAssertEqual(editor.draft.password, "password")
        XCTAssertFalse(editor.resultPresented)
        XCTAssertNil(editor.serverInfo)
        XCTAssertFalse(editor.canConfirmServer)
    }

    private func stagedConnection(
        libraries: [String: String], reachable: Bool = true
    ) async throws -> ServerConnectionEditorViewModel {
        let editor = makeEditor(libraries: libraries, reachable: reachable)
        editor.startEditing()
        editor.draft.internalAddress = "http://127.0.0.1:1/\(UUID().uuidString)"
        let task = try XCTUnwrap(editor.connect())
        await task.value
        return editor
    }

    private func makeEditor(
        libraries: [String: String], reachable: Bool = true,
        mode: ServerConnectionEditorViewModel.Mode = .add
    ) -> ServerConnectionEditorViewModel {
        ServerConnectionEditorViewModel(
            container: mockAppContainer,
            mode: mode,
            probeServer: { [weak self] in self?.makeProbeInfo($0, libraries: libraries, reachable: reachable) },
            probeLibrary: { .init(library: $0.library, probeUrl: URL(fileURLWithPath: "/")) }
        )
    }

    private func makeProbeInfo(
        _ request: CalibreProbeServerRequest, libraries: [String: String], reachable: Bool = true
    ) -> CalibreServerInfo? {
        guard let url = URL(string: request.server.baseUrl) else { return nil }
        return CalibreServerInfo(
            server: request.server, isPublic: false, url: url, reachable: reachable,
            probing: false, errorMsg: reachable ? "Success" : "Connection failed",
            defaultLibrary: "a", libraryMap: libraries, request: request
        )
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
