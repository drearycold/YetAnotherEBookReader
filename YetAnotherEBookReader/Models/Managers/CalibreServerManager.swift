//
//  CalibreServerManager.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/13.
//

import Foundation
import OSLog

class CalibreServerManager {
    private let logger = Logger(subsystem: "YetAnotherEBookReader", category: "CalibreServerManager")

    weak var container: AppContainerProtocol?
    let databaseService: DatabaseService
    private let serverRepository: ServerRepositoryProtocol

    private let stateChangeBroadcaster = ManagerAsyncBroadcaster<Void>()
    private let serverBroadcaster = ManagerAsyncBroadcaster<[String: CalibreServer]>()
    private let serverInfoStagingBroadcaster = ManagerAsyncBroadcaster<[String: CalibreServerInfo]>()
    private let helperConfigRequestBroadcaster = ManagerAsyncBroadcaster<String>()
    private var syncServerHelperConfigTask: Task<Void, Never>?

    var calibreServers = [String: CalibreServer]() {
        didSet {
            serverBroadcaster.send(calibreServers)
            publishStateChange()
        }
    }
    var calibreServerInfoStaging = [String: CalibreServerInfo]() {
        didSet {
            container?.calibreServerService.updateServerInfoStaging(calibreServerInfoStaging)
            serverInfoStagingBroadcaster.send(calibreServerInfoStaging)
            publishStateChange()
        }
    }
    var documentServer: CalibreServer?

    init(container: AppContainerProtocol, databaseService: DatabaseService, serverRepository: ServerRepositoryProtocol) {
        self.container = container
        self.databaseService = databaseService
        self.serverRepository = serverRepository
        registerSyncServerHelperConfigTask()
    }

    deinit {
        syncServerHelperConfigTask?.cancel()
    }

    func stateChanges() -> AsyncStream<Void> {
        stateChangeBroadcaster.stream()
    }

    func serverSnapshots() -> AsyncStream<[String: CalibreServer]> {
        serverBroadcaster.stream(initialValue: calibreServers)
    }

    func serverInfoStagingSnapshots() -> AsyncStream<[String: CalibreServerInfo]> {
        serverInfoStagingBroadcaster.stream(initialValue: calibreServerInfoStaging)
    }

    func requestServerHelperConfigSync(serverId: String) {
        helperConfigRequestBroadcaster.send(serverId)
    }

    private func publishStateChange() {
        stateChangeBroadcaster.send(())
    }
    
    // MARK: - Migrated Methods
    
    private func configureCredentials(for urlString: String, server: CalibreServer) {
        guard let url = URL(string: urlString), let host = url.host, let port = url.port else { return }
        var authMethod = NSURLAuthenticationMethodDefault
        if url.scheme == "http" {
            authMethod = NSURLAuthenticationMethodHTTPDigest
        }
        if url.scheme == "https" {
            authMethod = NSURLAuthenticationMethodHTTPBasic
        }
        let protectionSpace = URLProtectionSpace(host: host,
                                                 port: port,
                                                 protocol: url.scheme,
                                                 realm: "calibre",
                                                 authenticationMethod: authMethod)
        let userCredential = URLCredential(user: server.username,
                                           password: server.password,
                                           persistence: .permanent)
        URLCredentialStorage.shared.set(userCredential, for: protectionSpace)
    }

    func populateServers() {
        let servers = serverRepository.getAllServers().sorted(by: {
            if $0.username == $1.username {
                return $0.baseUrl < $1.baseUrl
            }
            return $0.username < $1.username
        })
        var tempServers = [String: CalibreServer]()
        servers.forEach { calibreServer in
            guard calibreServer.removed == false,
                  calibreServer.baseUrl.isEmpty == false
            else { return }
            
            tempServers[calibreServer.id] = calibreServer
            
            if calibreServer.username.isEmpty == false && calibreServer.password.isEmpty == false {
                configureCredentials(for: calibreServer.baseUrl, server: calibreServer)
                configureCredentials(for: calibreServer.publicUrl, server: calibreServer)
            }
        }
        calibreServers = tempServers
    }
    
    func addServer(server: CalibreServer, libraries: [CalibreLibrary]) {
        libraries.forEach {
            do {
                try container?.libraryRepository.saveLibrary($0)
                container?.calibreLibraries[$0.id] = $0
            } catch {
                logger.error("Failed to update library realm: \(error.localizedDescription)")
            }
        }
        
        do {
            try saveServer(server: server)
            calibreServers[server.id] = server
        } catch {
            logger.error("Failed to update server realm: \(error.localizedDescription)")
        }
    }
    
    func saveServer(server: CalibreServer) throws {
        try serverRepository.saveServer(server)
    }
    
    @MainActor
    func removeServer(server: CalibreServer) async {
        guard let container = self.container else { return }
        let librariesToRemove = container.libraryManager.calibreLibraries.filter { $0.value.server.id == server.id }
        for (_, library) in librariesToRemove {
            container.libraryManager.hideLibrary(libraryId: library.id)
            await container.libraryManager.removeLibrary(library: library)
        }
        
        container.publishCalibreUpdate(.shelf)
    }
    
    func queryServerDSReaderHelper(server: CalibreServer) -> CalibreServerDSReaderHelper? {
        return serverRepository.getDSReaderHelper(for: server.id)
    }
    
    func updateServerDSReaderHelper(serverId: String, dsreaderHelper: CalibreServerDSReaderHelper) {
        do {
            try serverRepository.saveDSReaderHelper(dsreaderHelper, for: serverId)
        } catch {
            logger.error("Failed to save DSReaderHelper: \(error.localizedDescription)")
        }
    }
    
    func probeServersReachability(with serverIds: Set<String>, updateLibrary: Bool = false, autoUpdateOnly: Bool = true, incremental: Bool = true) {
        calibreServers.filter {
            $0.value.isLocal == false
            && (serverIds.isEmpty || serverIds.contains($0.value.id))
        }.forEach { serverId, server in
            Task {
                await self.probeServer(request: .init(server: server, isPublic: false, updateLibrary: updateLibrary, autoUpdateOnly: autoUpdateOnly, incremental: incremental))
            }
            if server.hasPublicUrl {
                Task {
                    await self.probeServer(request: .init(server: server, isPublic: true,  updateLibrary: updateLibrary, autoUpdateOnly: autoUpdateOnly, incremental: incremental))
                }
            }
        }
    }
    
    @discardableResult
    @MainActor
    func probeServer(request: CalibreProbeServerRequest) async -> CalibreServerInfo? {
        if var info = self.calibreServerInfoStaging[request.id] {
            info.probing = true
            info.errorMsg = "Connecting"
            info.request = request
            info.url = URL(string: request.isPublic ? request.server.publicUrl : request.server.baseUrl) ?? URL(fileURLWithPath: "/")
            self.calibreServerInfoStaging[request.id] = info
        } else {
            let info = CalibreServerInfo(
                server: request.server,
                isPublic: request.isPublic,
                url: URL(string: request.isPublic ? request.server.publicUrl : request.server.baseUrl) ?? URL(fileURLWithPath: "/"),
                probing: true,
                errorMsg: "Connecting",
                defaultLibrary: request.server.defaultLibrary,
                request: request
            )
            self.calibreServerInfoStaging[request.id] = info
        }
        
        guard let info = self.calibreServerInfoStaging[request.id] else { return nil }
        
        guard let calibreServerService = container?.calibreServerService else { return nil }
        let newServerInfo = await calibreServerService.probeServerReachability(serverInfo: info)
        
        guard var serverInfo = self.calibreServerInfoStaging[newServerInfo.id] else { return nil }
        serverInfo.probing = false
        serverInfo.errorMsg = newServerInfo.errorMsg

        if newServerInfo.libraryMap.isEmpty {
            serverInfo.reachable = false
            if serverInfo.errorMsg.isEmpty {
                serverInfo.errorMsg = "Empty Server"
            }
        } else {
            serverInfo.reachable = newServerInfo.reachable
            serverInfo.libraryMap = newServerInfo.libraryMap
            serverInfo.defaultLibrary = newServerInfo.defaultLibrary
        }
        self.calibreServerInfoStaging[newServerInfo.id] = serverInfo
        
        if serverInfo.server.isLocal == false && serverInfo.request.updateLibrary {
            serverInfo.libraryMap.forEach { key, name in
                let newLibrary = CalibreLibrary(server: serverInfo.server, key: key, name: name)
                if container?.calibreLibraries[newLibrary.id] == nil {
                    container?.calibreLibraries[newLibrary.id] = newLibrary
                    try? container?.libraryRepository.saveLibrary(newLibrary)
                }
            }
            
            if serverInfo.request.autoUpdateOnly == false {
                requestServerHelperConfigSync(serverId: serverInfo.server.id)
            }
            
            // TODO: replace sync library with library search
            container?.calibreLibraries.filter {
                $0.value.server.id == serverInfo.server.id
            }.forEach { id, library in
                Task {
                    await container?.libraryManager.syncLibrary(
                        request: .init(
                            library: library,
                            autoUpdateOnly: serverInfo.request.autoUpdateOnly,
                            incremental: serverInfo.request.incremental
                        )
                    )
                }
            }
            
            if serverInfo.reachable {
                Task { @MainActor in
                    container?.publishCalibreUpdate(.server(serverInfo.server))
                }
                
                container?.calibreLibraries.filter {
                    $0.value.server.id == serverInfo.server.id
                }.forEach { id, library in
                    container?.publishProbeLibraryLastModifiedRequest(.init(library: library, autoUpdateOnly: false, incremental: false))
                }
            }
        }
        
        return serverInfo
    }
    
    // MARK: - Helpers
    
    func isServerReachable(server: CalibreServer) -> Bool {
        return calibreServerInfoStaging.filter {
            $1.reachable && $1.server.id == server.id
        }.isEmpty == false
    }
    
    func isServerReachable(server: CalibreServer, isPublic: Bool) -> Bool? {
        return calibreServerInfoStaging.filter {
            $1.server.id == server.id && $1.isPublic == isPublic
        }.first?.value.reachable
    }
    
    func isServerProbing(server: CalibreServer) -> Bool {
        return calibreServerInfoStaging.filter {
            $1.server.id == server.id && $1.probing == true
        }.isEmpty == false
    }
    
    func getServerInfo(server: CalibreServer) -> CalibreServerInfo? {
        let serverInfos = calibreServerInfoStaging.filter { $1.server.id == server.id }
        if serverInfos.count == 2 {
            if let active = serverInfos.filter({ !$0.value.isPublic && $0.value.reachable }).first {
                return active.value
            }
            if let active = serverInfos.filter({ $0.value.isPublic && $0.value.reachable }).first {
                return active.value
            }
        }
        return serverInfos.first?.value
    }

    // MARK: - DSReader Helper Config Sync

    /// For every requested server id, fetch the latest DSReader Helper
    /// configuration from the helper endpoint and persist it through the repository.
    private func registerSyncServerHelperConfigTask() {
        let serverIds = helperConfigRequestBroadcaster.stream()
        syncServerHelperConfigTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                for await serverId in serverIds {
                    guard !Task.isCancelled else { return }
                    group.addTask { [weak self] in
                        await self?.syncServerHelperConfiguration(serverId: serverId)
                    }
                }
            }
        }
    }

    @MainActor
    private func syncServerHelperConfiguration(serverId: String) async {
        guard let container,
              let server = calibreServers[serverId],
              let dsreaderHelperServer = queryServerDSReaderHelper(server: server) else {
            logger.error("Failed to sync server helper configuration: missing server or helper configuration")
            return
        }

        let connector = DSReaderHelperConnector(
            calibreServerService: container.calibreServerService,
            server: server,
            dsreaderHelperServer: dsreaderHelperServer,
            goodreadsSync: nil
        )

        do {
            let task = try await connector.refreshConfiguration()
            guard let config = try? JSONDecoder().decode(CalibreDSReaderHelperConfiguration.self, from: task.data),
                  config.dsreader_helper_prefs != nil else {
                return
            }
            var dsreaderHelper = CalibreServerDSReaderHelper(port: task.port)
            dsreaderHelper.configurationData = task.data
            updateServerDSReaderHelper(serverId: task.id, dsreaderHelper: dsreaderHelper)
        } catch {
            logger.error("Failed to sync server helper configuration: \(error.localizedDescription)")
        }
    }
}
