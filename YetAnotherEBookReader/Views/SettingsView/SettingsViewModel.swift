//
//  SettingsViewModel.swift
//  YetAnotherEBookReader
//
//  Created by opencode on 2026-06-18.
//

import SwiftUI

@MainActor @available(macCatalyst 14.0, *)
final class SettingsViewModel: ObservableObject {
    let container: AppContainer
    private var serverObservationTask: Task<Void, Never>?
    private var serverInfoObservationTask: Task<Void, Never>?
    private var helperObservationTask: Task<Void, Never>?

    @Published var serverList = [CalibreServer]()
    @Published var serverListDelete: CalibreServer?
    @Published private(set) var selectedServer: String?
    @Published private(set) var displayedServerID: String?
    @Published var addServerActive = false
    @Published var alertItem: AlertItem?
    @Published private(set) var serverInfoStaging = [String: CalibreServerInfo]()
    
    init(container: AppContainer) {
        self.container = container
        self.serverInfoStaging = container.serverManager.calibreServerInfoStaging
        setupSubscriptions()
    }

    deinit {
        serverObservationTask?.cancel()
        serverInfoObservationTask?.cancel()
        helperObservationTask?.cancel()
    }
    
    private func setupSubscriptions() {
        serverObservationTask?.cancel()
        serverObservationTask = Task { @MainActor [weak self, container] in
            for await _ in container.serverManager.serverSnapshots() {
                guard !Task.isCancelled else { return }
                self?.updateServerList()
            }
        }

        serverInfoObservationTask?.cancel()
        serverInfoObservationTask = Task { @MainActor [weak self, container] in
            for await snapshot in container.serverManager.serverInfoStagingSnapshots() {
                guard !Task.isCancelled else { return }
                self?.serverInfoStaging = snapshot
            }
        }
        let helperUpdates = container.serverManager.helperConfigurationUpdates()
        helperObservationTask = Task { @MainActor [weak self] in
            for await _ in helperUpdates {
                guard !Task.isCancelled else { return }
                self?.updateServerList()
            }
        }
    }

    var isRefreshing: Bool {
        serverInfoStaging.allSatisfy { $1.probing == false } == false
    }

    func updateServerList() {
        let includeUITestLocalServer = ProcessInfo.processInfo.arguments.contains("--ui-testing-mock-library")
        serverList = container.serverManager.calibreServers
            .filter {
                ($1.isLocal == false || (includeUITestLocalServer && $1.name == "UI Test Server"))
                    && $1.removed == false
            }
            .map { $0.value }
        sortServerList()
        if let selectedServer, !serverList.contains(where: { $0.id == selectedServer }) {
            dismissServerDetail()
        }
    }

    func openServerDetail(_ serverID: String) {
        guard serverList.contains(where: { $0.id == serverID }) else { return }
        displayedServerID = serverID
        selectedServer = serverID
    }

    func dismissServerDetail() {
        selectedServer = nil
    }
    
    private func sortServerList() {
        serverList.sort {
            if $0.isLocal { return false }
            if $1.isLocal { return true }
            if $0.name != $1.name { return $0.name < $1.name }
            if $0.baseUrl != $1.baseUrl { return $0.baseUrl < $1.baseUrl }
            return $0.username < $1.username
        }
    }
    
    func refreshServers() {
        container.serverManager.probeServersReachability(with: [], updateLibrary: true)
    }

    func stageServerDeletion(at index: Int) {
        guard index < serverList.count else { return }
        serverListDelete = serverList[index]
        alertItem = AlertItem(id: "DelServer")
    }

    func cancelServerDeletion() {
        serverListDelete = nil
    }

    func confirmDeleteServer() {
        guard let server = serverListDelete else { return }
        serverListDelete = nil
        do {
            try container.serverManager.removeServer(server: server)
            updateServerList()
        } catch is CancellationError {
            return
        } catch {
            let failure = error as? ServerSettingsSaveError ?? .failed
            alertItem = AlertItem(id: "Error", msg: failure.message)
        }
    }

    // Derived display state for rows
    struct ServerRowState {
        let hasDSReaderHelper: Bool
        let isLocalReachable: Bool?
        let isPublicReachable: Bool?
        let libraryCount: Int
        let locationString: String
        let processingCount: Int
        let serverInfoText: String?
        let isServerError: Bool
    }
    
    func rowState(for server: CalibreServer) -> ServerRowState {
        let hasHelper = (container.serverManager.queryServerDSReaderHelper(server: server)?.configuration?.dsreader_helper_prefs?.plugin_prefs.Options.servicePort ?? 0) > 0
        let isLocalReachable = isServerReachable(server: server, isPublic: false)
        let isPublicReachable = isServerReachable(server: server, isPublic: true)

        let libraryCount = container.libraryManager.calibreLibraries.filter { $0.value.server.id == server.id }.count

        let locationString: String
        if server.isLocal {
            locationString = "On Device"
        } else if server.username.isEmpty {
            locationString = server.baseUrl
        } else {
            locationString = "\(server.username) @ \(server.baseUrl)"
        }

        let processingCount = container.libraryManager.librarySyncStatus.filter { $0.value.isSync && container.libraryManager.calibreLibraries[$0.key]?.server.id == server.id }.count

        var serverInfoText: String? = nil
        var isServerError = false
        if let serverInfo = serverInfo(for: server) {
            if serverInfo.libraryRefreshFailed {
                serverInfoText = "Library refresh failed"
                isServerError = true
            } else if serverInfo.reachable {
                serverInfoText = "Server has \(serverInfo.libraryMap.count) libraries"
            } else {
                serverInfoText = serverInfo.probing ? "Connecting" : "Server refresh failed"
                isServerError = true
            }
        }
        
        return ServerRowState(
            hasDSReaderHelper: hasHelper,
            isLocalReachable: isLocalReachable,
            isPublicReachable: isPublicReachable,
            libraryCount: libraryCount,
            locationString: locationString,
            processingCount: processingCount,
            serverInfoText: serverInfoText,
            isServerError: isServerError
        )
    }

    private func isServerReachable(server: CalibreServer, isPublic: Bool) -> Bool? {
        serverInfoStaging.first {
            $1.server.id == server.id && $1.isPublic == isPublic
        }?.value.reachable
    }

    private func serverInfo(for server: CalibreServer) -> CalibreServerInfo? {
        let serverInfos = serverInfoStaging.filter { $1.server.id == server.id }
        if serverInfos.count == 2 {
            if let active = serverInfos.first(where: { !$0.value.isPublic && $0.value.reachable }) {
                return active.value
            }
            if let active = serverInfos.first(where: { $0.value.isPublic && $0.value.reachable }) {
                return active.value
            }
        }
        return serverInfos.first?.value
    }
}
