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
    typealias HelperConfigurationLoader = (CalibreServerService, DSReaderHelperConfigurationRequest) async throws
        -> DSReaderHelperConfigurationPayload
    private let loadHelperConfiguration: HelperConfigurationLoader

    private struct HelperOperation {
        let ticket: DSReaderHelperConfigurationTicket
        let request: DSReaderHelperConfigurationRequest
        let manual: Bool
        var task: Task<DSReaderHelperConfigurationCandidate, Error>?
    }

    @MainActor private var helperOperations: [String: HelperOperation] = [:]

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

    init(
        container: AppContainerProtocol,
        databaseService: DatabaseService,
        serverRepository: ServerRepositoryProtocol,
        loadHelperConfiguration: @escaping HelperConfigurationLoader = DSReaderHelperConfigurationLoader.load
    ) {
        self.container = container
        self.databaseService = databaseService
        self.serverRepository = serverRepository
        self.loadHelperConfiguration = loadHelperConfiguration
    }

    deinit {
        for operation in helperOperations.values {
            operation.task?.cancel()
        }
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
        cancelHelperConfiguration(serverID: server.id)
        guard let container = self.container else { return }
        let librariesToRemove = container.libraryManager.calibreLibraries.filter { $0.value.server.id == server.id }
        for (_, library) in librariesToRemove {
            container.libraryManager.hideLibrary(libraryId: library.id)
            await container.libraryManager.removeLibrary(library: library)
        }
        container.calibreServerService.retireSessions(for: server)

        container.publishCalibreUpdate(.shelf)
    }
    
    func queryServerDSReaderHelper(server: CalibreServer) -> CalibreServerDSReaderHelper? {
        return serverRepository.getDSReaderHelper(for: server.id)
    }
    
    @MainActor
    func updateServerDSReaderHelper(serverId: String, dsreaderHelper: CalibreServerDSReaderHelper) {
        cancelHelperConfiguration(serverID: serverId)
        do {
            try serverRepository.saveDSReaderHelper(dsreaderHelper, for: serverId)
        } catch {
            logger.error("Failed to save DSReaderHelper: \(error.localizedDescription)")
        }
    }
    
    func probeServersReachability(with serverIds: Set<String>, updateLibrary: Bool = false, autoUpdateOnly: Bool = true) {
        calibreServers.filter {
            $0.value.isLocal == false
            && (serverIds.isEmpty || serverIds.contains($0.value.id))
        }.forEach { serverId, server in
            Task {
                await self.probeServer(request: .init(server: server, isPublic: false, updateLibrary: updateLibrary, autoUpdateOnly: autoUpdateOnly))
            }
            if server.hasPublicUrl {
                Task {
                    await self.probeServer(request: .init(server: server, isPublic: true,  updateLibrary: updateLibrary, autoUpdateOnly: autoUpdateOnly))
                }
            }
        }
    }
    
    @discardableResult
    @MainActor
    func probeServer(request: CalibreProbeServerRequest) async -> CalibreServerInfo? {
        // A retry must use this request's credentials and address, even for the same server ID.
        let previousInfo = calibreServerInfoStaging[request.id]
        let sameConnection = previousInfo?.server == request.server
            && previousInfo?.server.password == request.server.password
            && previousInfo?.url.absoluteString == (request.isPublic ? request.server.publicUrl : request.server.baseUrl)
        let pendingInfo = CalibreServerInfo(
            server: request.server,
            isPublic: request.isPublic,
            url: URL(string: request.isPublic ? request.server.publicUrl : request.server.baseUrl) ?? URL(fileURLWithPath: "/"),
            reachable: sameConnection && previousInfo?.reachable == true,
            probing: true,
            errorMsg: "Connecting",
            defaultLibrary: request.server.defaultLibrary,
            libraryMap: sameConnection ? previousInfo?.libraryMap ?? [:] : [:],
            request: request
        )
        self.calibreServerInfoStaging[request.id] = pendingInfo

        guard let info = self.calibreServerInfoStaging[request.id] else { return nil }
        
        guard let calibreServerService = container?.calibreServerService else { return nil }
        let newServerInfo = await calibreServerService.probeServerReachability(serverInfo: info)
        
        guard var serverInfo = self.calibreServerInfoStaging[newServerInfo.id] else { return nil }
        serverInfo.probing = false
        serverInfo.errorMsg = newServerInfo.errorMsg
        serverInfo.error = newServerInfo.error
        serverInfo.httpStatusCode = newServerInfo.httpStatusCode

        if newServerInfo.libraryMap.isEmpty {
            serverInfo.reachable = false
            serverInfo.libraryMap = [:]
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
            
            container?.calibreLibraries.filter {
                $0.value.server.id == serverInfo.server.id
            }.forEach { id, library in
                Task {
                    await container?.libraryManager.syncLibrary(request: .init(library: library))
                }
            }
            
            if serverInfo.reachable {
                Task { @MainActor in
                    container?.publishCalibreUpdate(.server(serverInfo.server))
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

    // MARK: - DSReader Helper Configuration

    @MainActor
    @discardableResult
    func requestServerHelperConfigSync(serverId: String) -> DSReaderHelperConfigurationLoad? {
        // A manual request owns this server until its candidate is applied or dismissed.
        guard helperOperations[serverId]?.manual != true,
              let port = serverRepository.getDSReaderHelperStoredConfiguration(for: serverId)?.helper?.port else { return nil }
        return try? startHelperConfiguration(serverID: serverId, port: port, manual: false)
    }

    @MainActor
    func requestManualHelperConfiguration(serverID: String, port: Int) throws -> DSReaderHelperConfigurationLoad {
        try startHelperConfiguration(serverID: serverID, port: port, manual: true)
    }

    @MainActor
    func cancelHelperConfiguration(serverID: String) {
        helperOperations.removeValue(forKey: serverID)?.task?.cancel()
    }

    @MainActor
    func cancelHelperConfiguration(_ ticket: DSReaderHelperConfigurationTicket) {
        guard helperOperations[ticket.serverID]?.ticket == ticket else { return }
        cancelHelperConfiguration(serverID: ticket.serverID)
    }

    @MainActor
    func validateHelperConfigurationCandidate(_ ticket: DSReaderHelperConfigurationTicket) throws {
        _ = try pendingManualHelperOperation(for: ticket)
    }

    @MainActor
    func applyHelperConfiguration(_ candidate: DSReaderHelperConfigurationCandidate) throws -> CalibreServerDSReaderHelper {
        let ticket = candidate.ticket
        defer { cancelHelperConfiguration(ticket) }
        let operation = try pendingManualHelperOperation(for: ticket)
        return try persistHelperConfiguration(candidate, for: operation.request)
    }

    @MainActor
    private func pendingManualHelperOperation(for ticket: DSReaderHelperConfigurationTicket) throws -> HelperOperation {
        let operation = try currentHelperOperation(for: ticket)
        guard operation.manual, operation.task == nil else { throw DSReaderHelperConfigurationError.stale }
        return operation
    }

    @MainActor
    private func startHelperConfiguration(serverID: String, port: Int, manual: Bool) throws -> DSReaderHelperConfigurationLoad {
        cancelHelperConfiguration(serverID: serverID)
        guard CalibreServerDSReaderHelper.validPorts.contains(port) else {
            throw DSReaderHelperConfigurationError.invalidPort
        }
        guard let container, let server = calibreServers[serverID], !server.removed, !server.isLocal,
              let stored = serverRepository.getDSReaderHelperStoredConfiguration(for: serverID),
              stored.connection == DSReaderHelperConnection(server) else { throw DSReaderHelperConfigurationError.stale }
        let service = container.calibreServerService
        guard let baseURL = service.getServerUrlByReachability(server: server) else {
            throw CalibreAPIError.serverUnreachable
        }

        let request = DSReaderHelperConfigurationRequest(
            server: server, baseURL: baseURL, port: port, libraries: helperLibraries(for: serverID), stored: stored
        )
        let ticket = DSReaderHelperConfigurationTicket(serverID: serverID)
        let task = Task { @MainActor [weak self, loadHelperConfiguration] in
            do {
                try Task.checkCancellation()
                let payload = try await loadHelperConfiguration(service, request)
                try Task.checkCancellation()
                guard let self else { throw CancellationError() }
                _ = try self.currentHelperOperation(for: ticket)
                let candidate = DSReaderHelperConfigurationCandidate(ticket: ticket, payload: payload)
                if manual {
                    // Keep the ticket while the user reviews the result, and release the finished task.
                    self.helperOperations[serverID]?.task = nil
                } else {
                    _ = try self.persistHelperConfiguration(candidate, for: request)
                    self.helperOperations.removeValue(forKey: serverID)
                }
                return candidate
            } catch {
                self?.cancelHelperConfiguration(ticket)
                throw error
            }
        }
        helperOperations[serverID] = HelperOperation(ticket: ticket, request: request, manual: manual, task: task)
        return DSReaderHelperConfigurationLoad(ticket: ticket, task: task)
    }

    @MainActor
    private func currentHelperOperation(for ticket: DSReaderHelperConfigurationTicket) throws -> HelperOperation {
        let serverID = ticket.serverID
        guard let operation = helperOperations[serverID], operation.ticket == ticket,
              let server = calibreServers[serverID],
              DSReaderHelperConnection(server) == operation.request.stored.connection,
              serverRepository.getDSReaderHelperStoredConfiguration(for: serverID) == operation.request.stored,
              helperLibraries(for: serverID) == operation.request.libraries else {
            throw DSReaderHelperConfigurationError.stale
        }
        return operation
    }

    @MainActor
    private func helperLibraries(for serverID: String) -> [DSReaderHelperConfigurationRequest.Library] {
        guard let container else { return [] }
        return container.libraryManager.calibreLibraries.values
            .filter { $0.server.id == serverID }
            .map { .init(id: $0.id, key: $0.key, name: $0.name, hidden: $0.hidden) }
            .sorted { $0.id < $1.id }
    }

    @MainActor
    private func persistHelperConfiguration(
        _ candidate: DSReaderHelperConfigurationCandidate,
        for request: DSReaderHelperConfigurationRequest
    ) throws -> CalibreServerDSReaderHelper {
        let helper = CalibreServerDSReaderHelper(port: request.port, configurationData: candidate.payload.data)
        let saved: Bool
        do {
            saved = try serverRepository.replaceDSReaderHelper(helper, ifCurrent: request.stored)
        } catch {
            throw DSReaderHelperConfigurationError.couldNotSave
        }
        guard saved else { throw DSReaderHelperConfigurationError.stale }
        return helper
    }
}

struct DSReaderHelperConfigurationTicket: Hashable, Identifiable {
    let serverID: String
    let id = UUID()
}

struct DSReaderHelperConfigurationCandidate {
    let ticket: DSReaderHelperConfigurationTicket
    let payload: DSReaderHelperConfigurationPayload
}

struct DSReaderHelperConfigurationLoad {
    let ticket: DSReaderHelperConfigurationTicket
    let task: Task<DSReaderHelperConfigurationCandidate, Error>
}

enum DSReaderHelperConfigurationError: Error {
    case invalidPort
    case stale
    case couldNotSave
}
