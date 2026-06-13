//
//  CalibreServerManager.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/13.
//

import Foundation
import Combine
import RealmSwift
import SwiftUI
import OSLog

class CalibreServerManager: ObservableObject {
    private let logger = Logger(subsystem: "YetAnotherEBookReader", category: "CalibreServerManager")
    
    weak var modelData: ModelData?
    let databaseService: DatabaseService
    
    @Published var calibreServers = [String: CalibreServer]()
    @Published var calibreServerInfoStaging = [String: CalibreServerInfo]() {
        didSet {
            modelData?.calibreServerService.updateServerInfoStaging(calibreServerInfoStaging)
        }
    }
    var documentServer: CalibreServer?
    
    init(modelData: ModelData, databaseService: DatabaseService) {
        self.modelData = modelData
        self.databaseService = databaseService
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
        guard let realm = databaseService.realm else { return }
        let serversCached = realm.objects(CalibreServerRealm.self).sorted(by: [SortDescriptor(keyPath: "username"), SortDescriptor(keyPath: "baseUrl")])
        serversCached.forEach { serverRealm in
            guard serverRealm.removed == false,
                  serverRealm.baseUrl != nil
            else { return }
            
            guard let uuidString = serverRealm.primaryKey,
                  let uuid = UUID(uuidString: uuidString)
            else { return }
            
            let calibreServer = CalibreServer(
                uuid: uuid,
                name: serverRealm.name ?? serverRealm.baseUrl!,
                baseUrl: serverRealm.baseUrl!,
                hasPublicUrl: serverRealm.hasPublicUrl,
                publicUrl: serverRealm.publicUrl ?? "",
                hasAuth: serverRealm.hasAuth,
                username: serverRealm.username ?? "",
                password: serverRealm.password ?? "",
                defaultLibrary: serverRealm.defaultLibrary ?? "",
                removed: serverRealm.removed
            )
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
                if let realm = databaseService.realm {
                    try modelData?.updateLibraryRealm(library: $0, realm: realm)
                }
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
        guard let realm = databaseService.realm else { return }
        let serverRealm = CalibreServerRealm()
        serverRealm.primaryKey = server.uuid.uuidString
        serverRealm.name = server.name
        serverRealm.baseUrl = server.baseUrl
        serverRealm.hasPublicUrl = server.hasPublicUrl
        serverRealm.publicUrl = server.publicUrl
        serverRealm.hasAuth = server.hasAuth
        serverRealm.username = server.username
        serverRealm.password = server.password
        serverRealm.defaultLibrary = server.defaultLibrary
        serverRealm.removed = server.removed
        try realm.write {
            realm.add(serverRealm, update: .modified)
        }
    }
    
    @MainActor
    func removeServer(server: CalibreServer) async {
        guard let modelData = self.modelData else { return }
        let librariesToRemove = modelData.calibreLibraries.filter { $0.value.server.id == server.id }
        for (_, library) in librariesToRemove {
            modelData.hideLibrary(libraryId: library.id)
            await modelData.removeLibrary(library: library)
        }
        
        modelData.calibreUpdatedSubject.send(.shelf)
    }
    
    func queryServerDSReaderHelper(server: CalibreServer) -> CalibreServerDSReaderHelper? {
        guard let realm = Thread.isMainThread ? databaseService.realm : try? Realm(configuration: databaseService.realmConf) else { return nil }
        
        guard let serverRealm = realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: server.id),
              let helper = serverRealm.dsreaderHelper else { return nil }
        
        let unmanaged = CalibreServerDSReaderHelper(port: helper.port)
        unmanaged.configurationData = helper.configurationData
        return unmanaged
    }
    
    func updateServerDSReaderHelper(serverId: String, dsreaderHelper: CalibreServerDSReaderHelper, realm: Realm) {
        guard let serverRealm = realm.object(ofType: CalibreServerRealm.self, forPrimaryKey: serverId) else { return }
        try? realm.write {
            if let existing = serverRealm.dsreaderHelper {
                existing.update(from: dsreaderHelper)
            } else {
                serverRealm.dsreaderHelper = CalibreServerDSReaderHelper(value: dsreaderHelper)
            }
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
                    if let realm = databaseService.realm {
                        try? modelData?.updateLibraryRealm(library: newLibrary, realm: realm)
                    }
                }
            }
            
            if serverInfo.request.autoUpdateOnly == false {
                modelData?.syncServerHelperConfigSubject.send(serverInfo.server.id)
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
}
