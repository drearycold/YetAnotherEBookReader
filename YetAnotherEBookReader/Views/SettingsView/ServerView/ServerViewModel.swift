//
//  ServerViewModel.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/12.
//

import Foundation
import Combine
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
    
    // Server Detail properties (ServerDetailView)
    @Published var libraryList: [String] = []
    @Published var selectedLibrary: String? = nil
    @Published var syncingLibrary: Bool = false
    @Published var libraryRestoreListActive: Bool = false
    @Published var libraryRestoreListSelection: Set<String> = []
    
    // DSReader Helper properties (ServerOptionsDSReaderHelper)
    @Published var dsreaderHelperServer = CalibreServerDSReaderHelper(port: 0)
    @Published var portStr: String = ""
    @Published var configurationData: Data? = nil
    @Published var configuration: CalibreDSReaderHelperConfiguration? = nil
    @Published var helperStatus: String? = nil
    @Published var configAlertItem: AlertItem? = nil
    @Published var dsreaderHelperInstructionPresenting: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private var refreshCancellable: AnyCancellable?
    
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
    
    func setupBindings() {
        // Observe calibreLibraries to keep libraryList updated
        container.libraryManager.$calibreLibraries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateLibraryList()
            }
            .store(in: &cancellables)
            
        // Map portStr changes back to dsreaderHelperServer.port
        $portStr
            .sink { [weak self] newValue in
                guard let self = self else { return }
                let filtered = newValue.filter { "0123456789".contains($0) }
                if let num = Int(filtered), num != self.dsreaderHelperServer.port {
                    if num > 65535 {
                        self.dsreaderHelperServer.port = 65535
                    } else if num < 1024 {
                        self.dsreaderHelperServer.port = 1024
                    } else {
                        self.dsreaderHelperServer.port = num
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Add / Modify Server Actions (AddModServerView)
    
    func resetStates(server: CalibreServer?) {
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
        if server == nil {
            dataAction = "Add"
            processUrlInputs(server: server)
            addServerConfirmButtonAction(completion: completion)
        } else {
            dataAction = "Mod"
            processUrlInputs(server: server)
            modServerConfirmButtonAction(completion: completion)
        }
        self.serverCalibreInfoPresenting = true
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
    
    func addServerConfirmed(serverBinding: Binding<CalibreServer?>, isActiveBinding: Binding<Bool>) {
        guard let serverInfo = calibreServerInfo else { return }

        var newServer = serverInfo.server
        newServer.defaultLibrary = serverInfo.defaultLibrary

        let libraries: [CalibreLibrary] = serverInfo.libraryMap
            .sorted { $0.key < $1.key }
            .map {
                .init(
                    server: serverInfo.server,
                    key: $0,
                    name: $1,
                    autoUpdate: false,
                    discoverable: true
                )
            }

        container.serverManager.addServer(server: newServer, libraries: libraries)
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
        guard let serverInfo = calibreServerInfo else {
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
        Task {
            let serverInfo = await container.serverManager.probeServer(request: .init(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: true, incremental: true))

            self.calibreServerInfo = serverInfo
            if let serverInfo = serverInfo {
                for (key, name) in serverInfo.libraryMap {
                    await container.libraryManager.probeLibrary(request: .init(library: .init(server: serverInfo.request.server, key: key, name: name)))
                }
            }
            self.isProbing = false
            completion()
        }
    }
    
    func disableProbeServerCancellable() {
        self.calibreServerInfo = nil
        self.isProbing = false
    }
    
    // MARK: - Server Details actions (ServerDetailView)

    func updateLibraryList() {
        guard let serverId = serverId else { return }
        libraryList = container.libraryManager.calibreLibraries.values.filter { library in
            library.server.id == serverId && library.hidden == false
        }
        .sorted { $0.name < $1.name }
        .map { $0.id }
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

    func removeDeleteBooksFromServer(server: CalibreServer) {
        container.bookManager.removeDeleteBooksFromServer(server: server)
    }

    func probeReachability(server: CalibreServer) {
        container.serverManager.probeServersReachability(with: [server.id], updateLibrary: true, autoUpdateOnly: true, incremental: false)
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
        refreshCancellable?.cancel()
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
                        let activeLibraries = container.libraryManager.calibreLibraries.filter {
                            $0.value.server.uuid == server.uuid && !$0.value.hidden
                        }.map { $0.value.key }

                        for libraryKey in activeLibraries {
                            group.addTask {
                                return (libraryKey, try await connector.refreshConfiguration(libraryKey).0)
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
                // Fallback to Combine
                refreshCancellable = connector.refreshConfiguration()?
                    .receive(on: DispatchQueue.main)
                    .sink(receiveCompletion: { [weak self] complete in
                        guard let self = self else { return }
                        switch complete {
                        case .finished:
                            break
                        default:
                            self.helperStatus = "Failed to Connect"
                            self.configAlertItem = AlertItem(id: "failedConnectConfigAlert")
                        }
                    }, receiveValue: { [weak self] data in
                        guard let self = self else { return }
                        let decoder = JSONDecoder()
                        if let config = try? decoder.decode(CalibreDSReaderHelperConfiguration.self, from: data.data), config.dsreader_helper_prefs != nil {
                            self.configuration = config
                            self.configurationData = data.data
                            self.helperStatus = "Connected"
                            self.configAlertItem = AlertItem(id: "updateConfigAlert")
                        } else {
                            self.helperStatus = "Failed"
                            self.configAlertItem = AlertItem(id: "failedParseConfigAlert")
                        }
                    })
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
