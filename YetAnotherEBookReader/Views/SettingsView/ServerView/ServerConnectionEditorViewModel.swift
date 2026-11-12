import Foundation
import SwiftUI

@MainActor
final class ServerConnectionEditorViewModel: ObservableObject {
    enum Mode {
        case add
        case edit(serverID: String)

        var serverID: String? {
            if case .edit(let serverID) = self { return serverID }
            return nil
        }
    }

    struct Draft {
        var name = ""
        var internalAddress = ""
        var publicAddress = ""
        var usePublicAddress = false
        var requiresAuthentication = false
        var username = ""
        var password = ""

        init(server: CalibreServer?) {
            guard let server else { return }
            name = server.name
            internalAddress = server.baseUrl
            publicAddress = server.publicUrl
            usePublicAddress = server.hasPublicUrl
            requiresAuthentication = server.hasAuth
            username = server.username
            password = server.password
        }
    }

    enum Confirmation {
        case added(libraryToBrowse: CalibreLibrary?)
        case edited(original: CalibreServer, updated: CalibreServer)
    }

    struct Reachability: Equatable {
        var probing = false
        var privateAddress: Bool?
        var publicAddress: Bool?
    }

    let mode: Mode
    private let container: AppContainer
    private let probeServer: (CalibreProbeServerRequest) async -> CalibreServerInfo?
    private let probeLibrary: (CalibreProbeLibraryRequest) async -> CalibreLibraryProbeTask

    @Published var draft = Draft(server: nil)
    @Published var passwordVisible = false
    @Published var resultPresented = false
    @Published var alertItem: AlertItem?
    @Published var browseLibraryID: String?
    @Published private(set) var originalServer: CalibreServer?
    @Published private(set) var serverInfo: CalibreServerInfo?
    @Published private(set) var isProbing = false
    @Published private(set) var editTargetAvailable = true
    @Published private(set) var reachability = Reachability()
    @Published private(set) var knownLibraryNames: [String] = []

    @Published private var libraryResults: [String: String] = [:]
    @Published private var connectionChanged = false
    private var isEditing = false
    private var serverObservation: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var probeID: UUID?
    private var savedConnectionAtProbe: DSReaderHelperConnection?

    init(
        container: AppContainer,
        mode: Mode,
        probeServer: ((CalibreProbeServerRequest) async -> CalibreServerInfo?)? = nil,
        probeLibrary: ((CalibreProbeLibraryRequest) async -> CalibreLibraryProbeTask)? = nil
    ) {
        self.container = container
        self.mode = mode
        self.probeServer = probeServer ?? { await container.serverManager.probeServer(request: $0) }
        self.probeLibrary = probeLibrary ?? { await container.libraryManager.probeLibrary(request: $0) }
    }

    deinit {
        serverObservation?.cancel()
        probeTask?.cancel()
    }

    var isAdding: Bool { mode.serverID == nil }
    var isBusy: Bool { isProbing || reachability.probing }

    private var currentEditTarget: CalibreServer? {
        guard let serverID = mode.serverID,
              let server = container.serverManager.calibreServers[serverID], !server.removed else { return nil }
        return server
    }

    func startEditing() {
        guard !isEditing else { return }
        isEditing = true
        resetDraft()
        guard !isAdding else { return }
        let changes = container.serverManager.stateChanges()
        serverObservation = Task { @MainActor [weak self] in
            for await _ in changes {
                guard let self, !Task.isCancelled else { return }
                self.refreshEditTarget()
            }
        }
    }

    func endEditing() {
        isEditing = false
        serverObservation?.cancel()
        serverObservation = nil
        dismissResult()
        passwordVisible = false
    }

    func resetDraft() {
        dismissResult()
        alertItem = nil
        let original = currentEditTarget
        originalServer = original
        draft = Draft(server: original)
        passwordVisible = false
        if let original {
            knownLibraryNames = container.libraryManager.calibreLibraries.values
                .filter { $0.server.id == original.id && !$0.hidden }
                .map(\.name).sorted()
        } else {
            knownLibraryNames = []
        }
        refreshEditTarget()
    }

    private func refreshEditTarget() {
        let current = currentEditTarget
        let available = isAdding || current != nil
        if editTargetAvailable != available { editTargetAvailable = available }
        if let savedConnectionAtProbe, current.map(DSReaderHelperConnection.init) != savedConnectionAtProbe {
            cancelProbe()
            connectionChanged = true
        }

        var value = Reachability()
        if let current {
            let connection = DSReaderHelperConnection(current)
            for info in container.serverManager.calibreServerInfoStaging.values
            where DSReaderHelperConnection(info.request.server) == connection {
                value.probing = value.probing || info.probing
                if info.isPublic { value.publicAddress = info.reachable }
                else { value.privateAddress = info.reachable }
            }
        }
        if reachability != value { reachability = value }
    }

    @discardableResult
    func connect() -> Task<Void, Never>? {
        guard isEditing else { return nil }
        cancelProbe()
        connectionChanged = false
        alertItem = nil
        let current = currentEditTarget
        guard isAdding || current != nil else {
            connectionChanged = true
            resultPresented = true
            return nil
        }
        if draft.internalAddress != current?.baseUrl {
            draft.internalAddress = normalizedURL(draft.internalAddress)
        }
        if draft.publicAddress != current?.publicUrl {
            draft.publicAddress = normalizedURL(draft.publicAddress)
        }
        if isAdding && draft.name.isEmpty {
            draft.name = URL(string: draft.internalAddress)?.host ?? "Unnamed"
        }
        if let conflict = container.serverManager.calibreServers.values.first(where: {
            !$0.removed && $0.id != mode.serverID && $0.baseUrl == draft.internalAddress && $0.username == draft.username
        }) {
            resultPresented = false
            alertItem = AlertItem(id: "Exist", msg: "Conflict with \"\(conflict.name)\"\nA server with the same address and username already exists")
            return nil
        }

        let server = CalibreServer(
            uuid: current?.uuid ?? UUID(),
            name: draft.name,
            baseUrl: draft.internalAddress,
            hasPublicUrl: draft.usePublicAddress,
            publicUrl: draft.publicAddress,
            hasAuth: draft.requiresAuthentication,
            username: draft.username,
            password: draft.password
        )
        savedConnectionAtProbe = current.map(DSReaderHelperConnection.init)
        let request = CalibreProbeServerRequest(server: server, isPublic: false, updateLibrary: false, autoUpdateOnly: true)
        let id = UUID()
        probeID = id
        isProbing = true
        resultPresented = true
        let task = Task { @MainActor [weak self, probeServer, probeLibrary] in
            let info = await probeServer(request)
            guard !Task.isCancelled, self?.probeID == id else { return }
            self?.serverInfo = info
            for library in self?.librariesFromProbe ?? [] {
                let result = await probeLibrary(.init(library: library))
                guard !Task.isCancelled, self?.probeID == id else { return }
                self?.libraryResults[library.id] = result.probeResult.map { "\($0.total_num) books" } ?? "Failed"
            }
            self?.isProbing = false
            self?.probeTask = nil
        }
        probeTask = task
        return task
    }

    private func normalizedURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let prefixed = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard var components = URLComponents(string: prefixed) else { return prefixed }
        if components.scheme == nil { components.scheme = "http" }
        if components.path.isEmpty { components.path = "/" }
        return components.string ?? prefixed
    }

    var connectionStatus: ServerConnectionStatus {
        if connectionChanged {
            return .init(title: "Server Configuration Changed", message: "Check the current settings and connect again.")
        }
        if isProbing { return .init(title: "Connecting…", message: nil) }
        guard let serverInfo else {
            return .init(title: "Connection Failed", message: "Check the server address and try again.")
        }
        return ServerConnectionStatus(info: serverInfo)
    }

    var canConfirmServer: Bool {
        resultPresented && !isProbing && !connectionChanged && serverInfo?.reachable == true
            && serverInfo?.errorMsg == "Success"
            && (isAdding || currentEditTarget.map(DSReaderHelperConnection.init) == savedConnectionAtProbe)
    }

    var librariesFromProbe: [CalibreLibrary] {
        guard let serverInfo, serverInfo.reachable, serverInfo.errorMsg == "Success" else { return [] }
        return serverInfo.libraryMap.map {
            CalibreLibrary(server: serverInfo.server, key: $0.key, name: $0.value, discoverable: true)
        }.sorted { $0.name == $1.name ? $0.key < $1.key : $0.name < $1.name }
    }

    func libraryProbeStatus(for libraryID: String) -> String {
        libraryResults[libraryID] ?? "Probing"
    }

    var libraryToBrowse: CalibreLibrary? {
        let libraries = librariesFromProbe
        return libraries.count == 1 ? libraries.first : libraries.first { $0.id == browseLibraryID }
    }

    func confirm(browseAfterAdding: Bool = false) -> Confirmation? {
        guard canConfirmServer, let serverInfo else { return nil }
        var updated = serverInfo.request.server
        updated.defaultLibrary = serverInfo.defaultLibrary

        if !isAdding {
            guard let original = currentEditTarget, original.id == updated.id else { return nil }
            updated.removed = original.removed
            return .edited(original: original, updated: updated)
        }

        let selectedLibrary = libraryToBrowse
        guard !browseAfterAdding || selectedLibrary != nil else { return nil }
        let libraries = librariesFromProbe
        let manager = container.serverManager
        manager.addServer(server: updated, libraries: libraries)
        guard manager.calibreServers[updated.id] != nil,
              libraries.allSatisfy({ container.libraryManager.calibreLibraries[$0.id] != nil }) else {
            alertItem = AlertItem(id: "Error", msg: "Could not save the server. Please try again.")
            return nil
        }
        if let port = URL(string: updated.baseUrl)?.port, port < Int.max {
            manager.updateServerDSReaderHelper(serverId: updated.id, dsreaderHelper: .init(port: port + 1))
        } else if URL(string: updated.baseUrl) != nil {
            manager.updateServerDSReaderHelper(serverId: updated.id, dsreaderHelper: .init(port: 0))
        }
        manager.probeServersReachability(with: [updated.id], updateLibrary: true, autoUpdateOnly: true)
        return .added(libraryToBrowse: browseAfterAdding ? selectedLibrary : nil)
    }

    func dismissResult() {
        resultPresented = false
        connectionChanged = false
        cancelProbe()
    }

    private func cancelProbe() {
        probeTask?.cancel()
        probeTask = nil
        probeID = nil
        savedConnectionAtProbe = nil
        browseLibraryID = nil
        serverInfo = nil
        libraryResults = [:]
        isProbing = false
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
