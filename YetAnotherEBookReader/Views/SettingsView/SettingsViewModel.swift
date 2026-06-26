//
//  SettingsViewModel.swift
//  YetAnotherEBookReader
//
//  Created by opencode on 2026-06-18.
//

import SwiftUI
import Combine

@MainActor @available(macCatalyst 14.0, *)
final class SettingsViewModel: ObservableObject {
    let modelData: ModelData
    private var cancellables = Set<AnyCancellable>()
    private let refreshDatabaseAction: () -> Void
    private let populateBookShelfAction: () -> Void
    private let probeServersReachabilityAction: (Set<String>) -> Void
    
    @Published var serverList = [CalibreServer]()
    @Published var serverListDelete: CalibreServer? = nil
    @Published var selectedServer: String? = nil
    @Published var addServerActive = false
    @Published var alertItem: AlertItem?
    
    init(
        modelData: ModelData,
        refreshDatabaseAction: (() -> Void)? = nil,
        populateBookShelfAction: (() -> Void)? = nil,
        probeServersReachabilityAction: ((Set<String>) -> Void)? = nil
    ) {
        self.modelData = modelData
        self.refreshDatabaseAction = refreshDatabaseAction ?? { modelData.refreshDatabase() }
        self.populateBookShelfAction = populateBookShelfAction ?? { modelData.populateBookShelf() }
        self.probeServersReachabilityAction = probeServersReachabilityAction ?? { serverIds in
            modelData.probeServersReachability(with: serverIds)
        }
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        // Observe changes to serverManager's calibreServers to keep our list updated and sorted
        modelData.serverManager.$calibreServers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateServerList()
            }
            .store(in: &cancellables)
            
        // Also observe deletions
        $serverListDelete
            .sink { [weak self] _ in
                self?.updateServerList()
            }
            .store(in: &cancellables)
    }
    
    var isRefreshing: Bool {
        modelData.calibreServerInfoStaging.allSatisfy { $1.probing == false } == false
    }
    
    func updateServerList() {
        serverList = modelData.calibreServers
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
        modelData.probeServersReachability(with: [], updateLibrary: true)
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
        
        modelData.calibreServers[server.id]?.removed = true
        if let updatedServer = modelData.calibreServers[server.id] {
            try? modelData.updateServerRealm(server: updatedServer)
        }
        Task {
            await self.modelData.removeServer(server: server)
        }
        serverListDelete = nil
    }
    
    func updateServer(oldServer: CalibreServer, newServer: CalibreServer) {
        if oldServer.id == newServer.id {
            modelData.calibreServers[newServer.id] = newServer
            try? modelData.updateServerRealm(server: newServer)
            if let index = serverList.firstIndex(where: { $0.id == newServer.id }) {
                serverList[index] = newServer
            }
            for libraryId in modelData.calibreLibraries.filter({ $0.value.server.id == newServer.id }).map({ $0.key }) {
                modelData.calibreLibraries[libraryId]?.server = newServer
            }
            return
        }
        
        serverListDelete = oldServer
        
        let newServerLibraries = modelData.calibreLibraries.filter { $1.server.id == oldServer.id }.map { id, library -> CalibreLibrary in
            var newLibrary = library
            newLibrary.server = newServer
            if var syncStat = modelData.librarySyncStatus[library.id] {
                syncStat.library = newLibrary
                modelData.librarySyncStatus[newLibrary.id] = syncStat
            }
            return newLibrary
        }
        
        modelData.addServer(server: newServer, libraries: newServerLibraries)
        selectedServer = nil
        
        DispatchQueue(label: "data").async { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.refreshDatabaseAction()
                self.modelData.booksInShelf.removeAll(keepingCapacity: true)
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
        let hasHelper = (modelData.queryServerDSReaderHelper(server: server)?.configuration?.dsreader_helper_prefs?.plugin_prefs.Options.servicePort ?? 0) > 0
        let isLocalReachable = modelData.isServerReachable(server: server, isPublic: false)
        let isPublicReachable = modelData.isServerReachable(server: server, isPublic: true)
        
        let libraryCount = modelData.calibreLibraries.filter { $0.value.server.id == server.id }.count
        
        let locationString: String
        if server.isLocal {
            locationString = "On Device"
        } else if server.username.isEmpty {
            locationString = server.baseUrl
        } else {
            locationString = "\(server.username) @ \(server.baseUrl)"
        }
        
        let processingCount = modelData.librarySyncStatus.filter { $0.value.isSync && modelData.calibreLibraries[$0.key]?.server.id == server.id }.count
        
        var serverInfoText: String? = nil
        var isServerError = false
        if let serverInfo = modelData.getServerInfo(server: server) {
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
}
