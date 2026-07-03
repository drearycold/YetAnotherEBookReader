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
    private let refreshDatabaseAction: () -> Void
    private let populateBookShelfAction: () -> Void
    private let probeServersReachabilityAction: (Set<String>) -> Void
    
    @Published var serverList = [CalibreServer]()
    @Published var serverListDelete: CalibreServer? = nil {
        didSet {
            updateServerList()
        }
    }
    @Published var selectedServer: String? = nil
    @Published var addServerActive = false
    @Published var alertItem: AlertItem?
    @Published private(set) var serverInfoStaging = [String: CalibreServerInfo]()
    
    init(
        container: AppContainer,
        refreshDatabaseAction: (() -> Void)? = nil,
        populateBookShelfAction: (() -> Void)? = nil,
        probeServersReachabilityAction: ((Set<String>) -> Void)? = nil
    ) {
        self.container = container
        self.refreshDatabaseAction = refreshDatabaseAction ?? { container.refreshDatabase() }
        self.populateBookShelfAction = populateBookShelfAction ?? { container.bookManager.populateBookShelf() }
        self.probeServersReachabilityAction = probeServersReachabilityAction ?? { serverIds in
            container.serverManager.probeServersReachability(with: serverIds)
        }
        self.serverInfoStaging = container.serverManager.calibreServerInfoStaging
        setupSubscriptions()
    }

    deinit {
        serverObservationTask?.cancel()
        serverInfoObservationTask?.cancel()
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
    }

    var isRefreshing: Bool {
        serverInfoStaging.allSatisfy { $1.probing == false } == false
    }

    func updateServerList() {
        serverList = container.serverManager.calibreServers
            .filter { $1.isLocal == false && $1.id != serverListDelete?.id && $1.removed == false }
            .map { $0.value }
        sortServerList()
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

        container.serverManager.calibreServers[server.id]?.removed = true
        if let updatedServer = container.serverManager.calibreServers[server.id] {
            try? container.serverManager.saveServer(server: updatedServer)
        }
        Task {
            await self.container.serverManager.removeServer(server: server)
        }
        serverListDelete = nil
    }

    func updateServer(oldServer: CalibreServer, newServer: CalibreServer) {
        if oldServer.id == newServer.id {
            container.serverManager.calibreServers[newServer.id] = newServer
            try? container.serverManager.saveServer(server: newServer)
            if let index = serverList.firstIndex(where: { $0.id == newServer.id }) {
                serverList[index] = newServer
            }
            for libraryId in container.libraryManager.calibreLibraries.filter({ $0.value.server.id == newServer.id }).map({ $0.key }) {
                container.libraryManager.calibreLibraries[libraryId]?.server = newServer
            }
            return
        }

        serverListDelete = oldServer

        let newServerLibraries = container.libraryManager.calibreLibraries.filter { $1.server.id == oldServer.id }.map { id, library -> CalibreLibrary in
            var newLibrary = library
            newLibrary.server = newServer
            if var syncStat = container.libraryManager.librarySyncStatus[library.id] {
                syncStat.library = newLibrary
                container.libraryManager.librarySyncStatus[newLibrary.id] = syncStat
            }
            return newLibrary
        }

        container.serverManager.addServer(server: newServer, libraries: newServerLibraries)
        selectedServer = nil

        DispatchQueue(label: "data").async { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.refreshDatabaseAction()
                self.container.bookManager.booksInShelf.removeAll(keepingCapacity: true)
                self.populateBookShelfAction()
                self.serverListDelete = nil
                self.probeServersReachabilityAction([newServer.id])
            }
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
            if serverInfo.reachable {
                serverInfoText = "Server has \(serverInfo.libraryMap.count) libraries"
            } else {
                serverInfoText = serverInfo.errorMsg
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
