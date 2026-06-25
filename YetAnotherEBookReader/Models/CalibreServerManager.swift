//
//  CalibreServerManager.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/13.
//

import Foundation
import Combine
import SwiftUI
import OSLog

class CalibreServerManager: ObservableObject {
    private let logger = Logger(subsystem: "YetAnotherEBookReader", category: "CalibreServerManager")

    weak var modelData: ModelData?
    let databaseService: DatabaseService
    private let serverRepository: ServerRepositoryProtocol

    /// Internal subject emitted whenever a new full server probe completes.
    /// Consumed by `registerSyncServerHelperConfigCancellable()` to refresh
    /// each server's DSReader Helper configuration.
    let syncServerHelperConfigSubject = PassthroughSubject<String, Never>()

    private var syncServerHelperConfigCancellable: AnyCancellable?

    @Published var calibreServers = [String: CalibreServer]()
    @Published var calibreServerInfoStaging = [String: CalibreServerInfo]() {
        didSet {
            modelData?.calibreServerService.updateServerInfoStaging(calibreServerInfoStaging)
        }
    }
    var documentServer: CalibreServer?

    init(modelData: ModelData, databaseService: DatabaseService, serverRepository: ServerRepositoryProtocol) {
        self.modelData = modelData
        self.databaseService = databaseService
        self.serverRepository = serverRepository
        registerSyncServerHelperConfigCancellable()
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
        servers.forEach { calibreServer in
            guard calibreServer.removed == false,
                  calibreServer.baseUrl.isEmpty == false
            else { return }
            
            calibreServers[calibreServer.id] = calibreServer
            
            if calibreServer.username.isEmpty == false && calibreServer.password.isEmpty == false {
                configureCredentials(for: calibreServer.baseUrl, server: calibreServer)
                configureCredentials(for: calibreServer.publicUrl, server: calibreServer)
            }
        }
    }
    
    func addServer(server: CalibreServer, libraries: [CalibreLibrary]) {
        libraries.forEach {
            do {
                try modelData?.libraryRepository.saveLibrary($0)
                modelData?.calibreLibraries[$0.id] = $0
            } catch {
                logger.error("Failed to update library realm: \(error.localizedDescription)")
            }
        }
        
        do {
            try updateServerRealm(server: server)
            calibreServers[server.id] = server
        } catch {
            logger.error("Failed to update server realm: \(error.localizedDescription)")
        }
    }
    
    func updateServerRealm(server: CalibreServer) throws {
        try serverRepository.saveServer(server)
    }
    
    @MainActor
    func removeServer(server: CalibreServer) async {
        guard let modelData = self.modelData else { return }
        let librariesToRemove = modelData.libraryManager.calibreLibraries.filter { $0.value.server.id == server.id }
        for (_, library) in librariesToRemove {
            modelData.libraryManager.hideLibrary(libraryId: library.id)
            await modelData.libraryManager.removeLibrary(library: library)
        }
        
        modelData.calibreUpdatedSubject.send(.shelf)
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
        
        guard let calibreServerService = modelData?.calibreServerService else { return nil }
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
                if modelData?.calibreLibraries[newLibrary.id] == nil {
                    modelData?.calibreLibraries[newLibrary.id] = newLibrary
                    try? modelData?.libraryRepository.saveLibrary(newLibrary)
                }
            }
            
            if serverInfo.request.autoUpdateOnly == false {
                syncServerHelperConfigSubject.send(serverInfo.server.id)
            }
            
            // TODO: replace sync library with library search
            modelData?.calibreLibraries.filter {
                $0.value.server.id == serverInfo.server.id
            }.forEach { id, library in
                Task {
                    await modelData?.syncLibrary(
                        request: .init(
                            library: library,
                            autoUpdateOnly: serverInfo.request.autoUpdateOnly,
                            incremental: serverInfo.request.incremental
                        )
                    )
                }
            }
            
            if serverInfo.reachable {
                modelData?.calibreUpdatedSubject.send(.server(serverInfo.server))
                
                modelData?.calibreLibraries.filter {
                    $0.value.server.id == serverInfo.server.id
                }.forEach { id, library in
                    modelData?.probeLibraryLastModifiedSubject.send(.init(library: library, autoUpdateOnly: false, incremental: false))
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

    /// Subscribe to `syncServerHelperConfigSubject` and, for every server id
    /// emitted, fetch the latest DSReader Helper configuration from the helper
    /// endpoint and persist it back into the server Realm.
    private func registerSyncServerHelperConfigCancellable() {
        let queue = DispatchQueue(label: "sync-server-helper", qos: .userInitiated)
        syncServerHelperConfigCancellable = syncServerHelperConfigSubject
            .receive(on: queue)
            .flatMap { [weak self] serverId -> AnyPublisher<Result<(id: String, port: Int, data: Data), URLError>, Never> in
                guard let self = self,
                      let modelData = self.modelData,
                      let server = self.calibreServers[serverId],
                      let dsreaderHelperServer = self.queryServerDSReaderHelper(server: server),
                      let publisher = DSReaderHelperConnector(
                        calibreServerService: modelData.calibreServerService,
                        server: server,
                        dsreaderHelperServer: dsreaderHelperServer,
                        goodreadsSync: nil
                      ).refreshConfiguration()
                else {
                    return Just(Result.failure(URLError(.unknown))).eraseToAnyPublisher()
                }
                return publisher
                    .map { Result.success($0) }
                    .catch { Just(Result.failure($0)) }
                    .eraseToAnyPublisher()
            }
            .map { result -> (id: String, port: Int, data: Data, config: CalibreDSReaderHelperConfiguration?, error: URLError?) in
                switch result {
                case .success(let task):
                    return (
                        id: task.id,
                        port: task.port,
                        data: task.data,
                        config: try? JSONDecoder().decode(CalibreDSReaderHelperConfiguration.self, from: task.data),
                        error: nil
                    )
                case .failure(let error):
                    return (id: "", port: 0, data: Data(), config: nil, error: error)
                }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] task in
                if let error = task.error {
                    self?.logger.error("Failed to sync server helper configuration: \(error.localizedDescription)")
                    return
                }
                if let config = task.config, config.dsreader_helper_prefs != nil {
                    let dsreaderHelper = CalibreServerDSReaderHelper(port: task.port)
                    dsreaderHelper.configurationData = task.data
                    self?.updateServerDSReaderHelper(serverId: task.id, dsreaderHelper: dsreaderHelper)
                }
            }
    }
}
