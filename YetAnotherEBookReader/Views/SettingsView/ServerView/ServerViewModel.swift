//
//  ServerViewModel.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/12.
//

import Foundation
import SwiftUI

@MainActor
class ServerViewModel: ObservableObject {
    let container: AppContainer
    private var serverId: String? // nil if adding a new server
    
    // Binding fields for server editing (AddModServerView)
    @Published var calibreServerUUID: UUID
    @Published var calibreServerName: String = ""
    @Published var calibreServerUrl: String = ""
    @Published var calibreServerUrlWelformed: String = ""
    @Published var calibreServerUrlPublic: String = ""
    @Published var calibreServerSetPublicAddress: Bool = false
    @Published var calibreServerNeedAuth: Bool = false
    @Published var calibreUsername: String = ""
    @Published var calibrePassword: String = ""
    @Published var calibrePasswordVisible: Bool = false
    @Published var dataAction: String? = nil
    @Published var isProbing: Bool = false
    @Published var calibreServerInfo: CalibreServerInfo? = nil
    @Published var serverCalibreInfoPresenting: Bool = false
    @Published var alertItem: AlertItem? = nil
    @Published var browseLibraryID: String?
    
    // Server Detail properties (ServerDetailView)
    @Published var libraryList: [String] = []
    @Published var hiddenLibraryList: [CalibreLibrary] = []
    @Published var librarySyncStatus: [String: CalibreSyncStatus] = [:]
    @Published var selectedLibrary: String? = nil
    @Published var syncingLibrary: Bool = false
    @Published var libraryRestoreListActive: Bool = false
    @Published var libraryRestoreListSelection: Set<String> = []
    
    // DSReader Helper properties (ServerOptionsDSReaderHelper)
    @Published var dsreaderHelperServer = CalibreServerDSReaderHelper(port: 0)
    @Published var portStr: String = "" {
        didSet {
            updateDSReaderHelperPort(from: portStr)
        }
    }
    @Published var configurationData: Data? = nil
    @Published var configuration: CalibreDSReaderHelperConfiguration? = nil
    @Published var helperStatus: String? = nil
    @Published var configAlertItem: AlertItem? = nil
    @Published var dsreaderHelperInstructionPresenting: Bool = false
    
    private var libraryObservationTask: Task<Void, Never>?
    private var librarySyncStatusObservationTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var probeID: UUID?
    
    init(container: AppContainer, server: CalibreServer?) {
        self.container = container
        
        if let server = server {
            self.serverId = server.id
            self.calibreServerUUID = server.uuid
            
            // Populate basic fields
            self.calibreServerName = server.name
            self.calibreServerUrl = server.baseUrl
            self.calibreServerUrlPublic = server.publicUrl
            self.calibreServerSetPublicAddress = server.hasPublicUrl
            self.calibreServerNeedAuth = server.hasAuth
            self.calibreUsername = server.username
            self.calibrePassword = server.password
        } else {
            self.serverId = nil
            self.calibreServerUUID = UUID()
        }
        
        setupBindings()
    }

    deinit {
        libraryObservationTask?.cancel()
        librarySyncStatusObservationTask?.cancel()
        probeTask?.cancel()
    }
    
    func setupBindings() {
        libraryObservationTask?.cancel()
        libraryObservationTask = Task { @MainActor [weak self, container] in
            for await _ in container.libraryManager.librarySnapshots() {
                guard !Task.isCancelled else { return }
                self?.updateLibraryList()
            }
        }
        librarySyncStatusObservationTask?.cancel()
        librarySyncStatusObservationTask = Task { @MainActor [weak self, container] in
            for await statusMap in container.libraryManager.librarySyncStatusSnapshots() {
                guard !Task.isCancelled else { return }
                self?.librarySyncStatus = statusMap
            }
        }
    }

    private func updateDSReaderHelperPort(from newValue: String) {
        let filtered = newValue.filter { "0123456789".contains($0) }
        if let num = Int(filtered), num != dsreaderHelperServer.port {
            if num > 65535 {
                dsreaderHelperServer.port = 65535
            } else if num < 1024 {
                dsreaderHelperServer.port = 1024
            } else {
                dsreaderHelperServer.port = num
            }
        }
    }
    
    // MARK: - Add / Modify Server Actions (AddModServerView)
    
    func resetStates(server: CalibreServer?) {
        disableProbeServerCancellable()
        serverCalibreInfoPresenting = false
        dataAction = nil
        alertItem = nil
        self.calibreServerName = server?.name ?? ""
        self.calibreServerUrl = server?.baseUrl ?? ""
        self.calibreUsername = server?.username ?? ""
        self.calibrePassword = server?.password ?? ""
        self.calibreServerUrlPublic = server?.publicUrl ?? ""
        self.calibreServerSetPublicAddress = server?.hasPublicUrl ?? false
        self.calibreServerNeedAuth = server?.hasAuth ?? false
        self.updateLibraryList()
    }
    
    func processInputAction(server: CalibreServer?, completion: @escaping () -> Void) {
        disableProbeServerCancellable()
        if server == nil {
            dataAction = "Add"
            processUrlInputs(server: server)
            addServerConfirmButtonAction(completion: completion)
        } else {
            dataAction = "Mod"
            processUrlInputs(server: server)
            modServerConfirmButtonAction(completion: completion)
        }
        self.serverCalibreInfoPresenting = alertItem == nil
    }
    
    private func processUrlInputs(server: CalibreServer?) {
        if calibreServerUrl != server?.baseUrl {
            calibreServerUrl = normalizedServerURLString(calibreServerUrl)
        }
        if calibreServerUrlPublic != server?.publicUrl {
            calibreServerUrlPublic = normalizedServerURLString(calibreServerUrlPublic)
        }
    }

    private func normalizedServerURLString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }

        let prefixed = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard var components = URLComponents(string: prefixed) else {
            return prefixed
        }

        if components.scheme == nil {
            components.scheme = "http"
        }
        if components.path.isEmpty {
            components.path = "/"
        }

        return components.string ?? prefixed
    }
    
    private func addServerConfirmButtonAction(completion: @escaping () -> Void) {
        if calibreServerName.isEmpty {
            if let url = URL(string: calibreServerUrl), let host = url.host {
                calibreServerName = host
            } else {
                calibreServerName = "Unnamed"
            }
        }

        if let existingServer = container.serverManager.calibreServers.values.first(where: { server in
            server.baseUrl == calibreServerUrl
            && server.username == calibreUsername
            && server.removed == false
        }) {
            alertItem = AlertItem(id: "Exist", msg: "Conflict with \"\(existingServer.name)\"\nA server with the same address and username already exists")
            return
        }

        calibreServerUUID = .init()
        let calibreServer = CalibreServer(
            uuid: calibreServerUUID,
            name: calibreServerName,
            baseUrl: calibreServerUrl,
            hasPublicUrl: calibreServerSetPublicAddress,
            publicUrl: calibreServerUrlPublic,
            hasAuth: calibreServerNeedAuth,
            username: calibreUsername,
            password: calibrePassword
        )
        
        performProbeServer(server: calibreServer, isAdd: true, completion: completion)
    }
    
    var connectionStatus: ServerConnectionStatus {
        if isProbing { return .init(title: "Connecting…", message: nil) }
        guard let info = calibreServerInfo else {
            return .init(title: "Connection Failed", message: "Check the server address and try again.")
        }
        return ServerConnectionStatus(info: info)
    }

    func editConnection() {
        disableProbeServerCancellable()
        serverCalibreInfoPresenting = false
        dataAction = nil
        // Preserve all form fields, including credentials, for correction and a fresh probe.
    }

    var canConfirmServer: Bool {
        serverCalibreInfoPresenting && !isProbing && calibreServerInfo?.reachable == true
            && calibreServerInfo?.errorMsg == "Success"
    }

    var librariesToAdd: [CalibreLibrary] {
        guard let info = calibreServerInfo, info.reachable, info.errorMsg == "Success" else { return [] }
        return info.libraryMap.map {
            CalibreLibrary(server: info.server, key: $0.key, name: $0.value, discoverable: true)
        }.sorted { $0.name == $1.name ? $0.key < $1.key : $0.name < $1.name }
    }

    var libraryToBrowse: CalibreLibrary? {
        let libraries = librariesToAdd
        return libraries.count == 1 ? libraries.first : libraries.first { $0.id == browseLibraryID }
    }

    func addServerConfirmed(serverBinding: Binding<CalibreServer?>, isActiveBinding: Binding<Bool>,
                            browseLibrary: ((CalibreLibrary) -> Void)? = nil) {
        guard canConfirmServer, dataAction == "Add", let serverInfo = calibreServerInfo else { return }
        let selectedLibrary = libraryToBrowse
        guard browseLibrary == nil || selectedLibrary != nil else { return }

        var newServer = serverInfo.server
        newServer.defaultLibrary = serverInfo.defaultLibrary

        let libraries = librariesToAdd

        container.serverManager.addServer(server: newServer, libraries: libraries)
        guard container.serverManager.calibreServers[newServer.id] != nil,
              libraries.allSatisfy({ container.libraryManager.calibreLibraries[$0.id] != nil }) else {
            alertItem = AlertItem(id: "Error", msg: "Could not save the server. Please try again.")
            return
        }
        if let url = URL(string: newServer.baseUrl) {
            container.serverManager.updateServerDSReaderHelper(
                serverId: newServer.id,
                dsreaderHelper: CalibreServerDSReaderHelper(
                    port: (url.port ?? -1) + 1
                )
            )
        }

        container.serverManager.probeServersReachability(with: [newServer.id], updateLibrary: true, autoUpdateOnly: true)

        serverBinding.wrappedValue = newServer
        if let selectedLibrary { browseLibrary?(selectedLibrary) }
        isActiveBinding.wrappedValue = false
    }

    private func modServerConfirmButtonAction(completion: @escaping () -> Void) {
        guard let serverId = serverId, let server = container.serverManager.calibreServers[serverId] else { return }
        calibreServerUUID = server.uuid
        let newServer = CalibreServer(
            uuid: calibreServerUUID,
            name: calibreServerName,
            baseUrl: calibreServerUrl,
            hasPublicUrl: calibreServerSetPublicAddress,
            publicUrl: calibreServerUrlPublic,
            hasAuth: calibreServerNeedAuth,
            username: calibreUsername,
            password: calibrePassword
        )

        if let existingServer = container.serverManager.calibreServers.values.first(where: { s in
            s.uuid != newServer.uuid
            && s.baseUrl == newServer.baseUrl
            && s.username == newServer.username
            && s.removed == false
        }) {
            alertItem = AlertItem(id: "Exist", msg: "Conflict with \"\(existingServer.name)\"\nA server with the same address and username already exists")
            return
        }

        performProbeServer(server: newServer, isAdd: false, completion: completion)
    }
    
    func modServerConfirmed(serverBinding: Binding<CalibreServer?>, isActiveBinding: Binding<Bool>) {
        guard canConfirmServer, dataAction == "Mod", let serverInfo = calibreServerInfo else {
            alertItem = AlertItem(id: "Error", msg: "Unexpected Error")
            return
        }
        
        var newServer = serverInfo.request.server
        newServer.defaultLibrary = serverInfo.defaultLibrary
        newServer.removed = serverBinding.wrappedValue?.removed ?? false
        
        serverBinding.wrappedValue = newServer
        isActiveBinding.wrappedValue = false
    }
    
    private func performProbeServer(server: CalibreServer, isAdd: Bool, completion: @escaping () -> Void) {
        isProbing = true
        let probeID = UUID()
        self.probeID = probeID
        probeTask = Task { [weak self, container] in
            let serverInfo = await container.serverManager.probeServer(request: .init(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: true))
            guard let self, !Task.isCancelled, self.probeID == probeID else { return }
            self.calibreServerInfo = serverInfo
            if let serverInfo = serverInfo {
                for (key, name) in serverInfo.libraryMap {
                    await container.libraryManager.probeLibrary(request: .init(library: .init(server: serverInfo.request.server, key: key, name: name)))
                    guard !Task.isCancelled, self.probeID == probeID else { return }
                }
            }
            self.isProbing = false
            completion()
        }
    }
    
    func disableProbeServerCancellable() {
        probeTask?.cancel()
        probeTask = nil
        probeID = nil
        browseLibraryID = nil
        self.calibreServerInfo = nil
        self.isProbing = false
    }
    
    // MARK: - Server Details actions (ServerDetailView)

    func updateLibraryList() {
        guard let serverId = serverId else { return }
        let serverLibraries = container.libraryManager.calibreLibraries.values.filter { library in
            library.server.id == serverId && library.hidden == false
        }
        libraryList = serverLibraries
            .sorted { $0.name < $1.name }
            .map { $0.id }
        hiddenLibraryList = container.libraryManager.calibreLibraries.values
            .filter { $0.server.id == serverId && $0.hidden }
            .sorted { $0.id < $1.id }
    }

    func deleteLibrary(at offsets: IndexSet) {
        let deletedLibraryIds = offsets.map { libraryList[$0] }
        deletedLibraryIds.forEach { libraryId in
            self.container.libraryManager.hideLibrary(libraryId: libraryId)

            guard self.container.libraryManager.librarySyncStatus[libraryId]?.isSync != true else { return }

            guard let library = self.container.libraryManager.calibreLibraries[libraryId] else { return }

            self.container.publishCalibreUpdate(.library(library))

            Task {
                await self.container.libraryManager.removeLibrary(library: library)
            }
        }
        updateLibraryList()
    }

    func restoreSelectedLibraries(updater: Binding<Int>) {
        libraryRestoreListSelection.forEach { libId in
            container.libraryManager.restoreLibrary(libraryId: libId)
            if let library = self.container.libraryManager.calibreLibraries[libId], library.discoverable {
                self.container.publishCalibreUpdate(.library(library))
            }
        }
        updater.wrappedValue += 1
        libraryRestoreListActive.toggle()
    }

    func probeReachability(server: CalibreServer) {
        container.serverManager.probeServersReachability(with: [server.id], updateLibrary: true, autoUpdateOnly: true)
    }

    // MARK: - DSReader Helper actions (ServerOptionsDSReaderHelper)

    func setDSReaderStates(server: CalibreServer) {
        let dsHelper = container.serverManager.queryServerDSReaderHelper(server: server) ?? {
            var dsreaderHelper = CalibreServerDSReaderHelper(port: 0)
            if let url = container.calibreServerService.getServerUrlByReachability(server: server) ?? URL(string: server.baseUrl) ?? URL(string: server.publicUrl) {
                dsreaderHelper.port = (url.port ?? -1) + 1
            }
            return dsreaderHelper
        }()

        configurationData = dsHelper.configurationData
        configuration = dsHelper.configuration
        self.dsreaderHelperServer = dsHelper
        portStr = dsHelper.port.description
    }

    func connectDSReader(server: CalibreServer) {
        configurationData = nil
        configuration = nil
        helperStatus = "Connecting..."

        let connector = DSReaderHelperConnector(calibreServerService: container.calibreServerService, server: server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: nil)

        Task {
            do {
                let (config, data) = try await connector.refreshConfiguration("_")
                guard config.dsreader_helper_prefs != nil else {
                    throw URLError(.badServerResponse)
                }
                var updatedConfig = config
                var updatedData = data

                if config.count_pages_prefs != nil {
                    self.helperStatus = "Pulling Library-Specific Configurations..."
                    var libraryConfigs: [String: CalibreCountPagesPrefs.LibraryConfig] = [:]

                    try await withThrowingTaskGroup(of: (String, CalibreDSReaderHelperConfiguration).self) { group in
                        let activeLibraries = container.libraryManager.calibreLibraries.values.filter {
                            $0.server.uuid == server.uuid && !$0.hidden
                        }

                        for library in activeLibraries {
                            group.addTask {
                                let config = try await connector.refreshConfiguration(library.key, libraryId: library.id).0
                                return (library.key, config)
                            }
                        }

                        for try await (libraryKey, libConfig) in group {
                            if let libraryConfig = libConfig.count_pages_prefs?.library_config?[libraryKey] {
                                libraryConfigs[libraryKey] = libraryConfig
                            }
                        }
                    }
                    updatedConfig.count_pages_prefs?.library_config = libraryConfigs
                    updatedData = try JSONEncoder().encode(updatedConfig)
                }

                self.configuration = updatedConfig
                self.configurationData = updatedData
                self.helperStatus = "Connected"
                self.configAlertItem = AlertItem(id: "updateConfigAlert")
            } catch {
                do {
                    let data = try await connector.refreshConfiguration()
                    let decoder = JSONDecoder()
                    if let config = try? decoder.decode(CalibreDSReaderHelperConfiguration.self, from: data.data),
                       config.dsreader_helper_prefs != nil {
                        self.configuration = config
                        self.configurationData = data.data
                        self.helperStatus = "Connected"
                        self.configAlertItem = AlertItem(id: "updateConfigAlert")
                    } else {
                        self.helperStatus = "Failed"
                        self.configAlertItem = AlertItem(id: "failedParseConfigAlert")
                    }
                } catch {
                    self.helperStatus = "Failed to Connect"
                    self.configAlertItem = AlertItem(id: "failedConnectConfigAlert")
                }
            }
        }
    }

    func updateDSReaderHelperConfig(server: CalibreServer) {
        guard let configuration = configuration else { return }
        dsreaderHelperServer.configuration = configuration
        dsreaderHelperServer.configurationData = configurationData

        container.serverManager.updateServerDSReaderHelper(serverId: server.id, dsreaderHelper: dsreaderHelperServer)
        helperStatus = nil
    }
}

/// Presentation for connection setup only. Never render a server's untrusted error body here.
struct ServerConnectionStatus {
    let title: String
    let message: String?

    init(title: String, message: String?) {
        self.title = title
        self.message = message
    }

    init(info: CalibreServerInfo) {
        if info.reachable && info.errorMsg == "Success" {
            self.init(title: "Connected", message: nil)
            return
        }
        var status = info.httpStatusCode
        if case .httpStatus(let code, _) = info.error { status = code }
        status = status.flatMap { (400...599).contains($0) ? $0 : nil }
        let title = status.map { "Connection Failed (HTTP \($0))" } ?? "Connection Failed"
        let message: String
        if let status, status == 401 || status == 403 {
            message = "Check Require, username, password and server access permissions, then retry."
        } else if let status {
            switch status {
            case 404:
                message = "Check the Calibre content server address and port, then retry."
            case 500...599:
                message = "The server or proxy could not complete the request. Check that the Calibre content server is running, then retry."
            default:
                message = "The server refused this request. Check the server address and access settings, then retry."
            }
        } else {
            switch info.error {
            case .authFailed:
                message = "Check Require, username, password and server access permissions, then retry."
            case .transport(let error):
                switch error.code {
                case .cancelled:
                    message = "The connection was cancelled. If the server requires authentication, check Require, username and password, then retry."
                case .userAuthenticationRequired, .userCancelledAuthentication:
                    message = "Check Require, username and password, then retry."
                case .timedOut:
                    message = "The server did not respond in time. Check your network and that the Calibre content server is running, then retry."
                case .notConnectedToInternet, .networkConnectionLost:
                    message = "Check your network connection, then retry."
                case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
                     .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                    message = "A secure connection could not be established. Check the HTTPS address and server certificate, then retry."
                default:
                    message = "Cannot reach the server. Check the address, port and network, and that the Calibre content server is running."
                }
            case .decoding, .unsupportedPayload, .emptyResponse:
                message = info.errorMsg == "Server has no library"
                    ? "The server has no available libraries. Check libraries and access permissions in Calibre, then retry."
                    : "This address did not return a Calibre library list. Check the Calibre content server address and port."
            default:
                message = "Check the Calibre content server address, port and network, then retry."
            }
        }
        self.init(title: title, message: message)
    }
}
