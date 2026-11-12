import Foundation
import SwiftUI

@MainActor
final class DSReaderHelperConfigurationViewModel: ObservableObject {
    let serverID: String
    private let serverManager: CalibreServerManager
    private let libraryManager: CalibreLibraryManager
    private let serverService: CalibreServerService

    @Published private(set) var savedHelper: CalibreServerDSReaderHelper?
    @Published private(set) var portStr = ""
    @Published private(set) var helperState: HelperConfigurationState = .idle
    @Published private(set) var serverAvailable = false
    @Published var helperConfirmation: DSReaderHelperConfigurationTicket?
    @Published var instructionPresented = false {
        didSet {
            guard instructionPresented != oldValue else { return }
            if instructionPresented {
                pauseObserving()
            } else {
                observeFormIfVisible()
            }
        }
    }

    var helperPort: Int? { CalibreServerDSReaderHelper.parsePort(portStr) }
    var canDownload: Bool { serverAvailable && helperPort != nil }

    private var routeInitialized = false
    private var formVisible = false
    private var defaultPortDraft = ""
    private var observations: [Task<Void, Never>] = []
    private var helperTicket: DSReaderHelperConfigurationTicket?
    private var helperTask: Task<Void, Never>?

    init(container: AppContainer, serverID: String) {
        self.serverID = serverID
        self.serverManager = container.serverManager
        self.libraryManager = container.libraryManager
        self.serverService = container.calibreServerService
    }

    deinit {
        observations.forEach { $0.cancel() }
        helperTask?.cancel()
        if let ticket = helperTicket {
            Task { @MainActor [serverManager] in serverManager.cancelHelperConfiguration(ticket) }
        }
    }

    func resume() {
        formVisible = true
        observeFormIfVisible()
    }

    private func observeFormIfVisible() {
        guard formVisible, !instructionPresented, observations.isEmpty else { return }

        let servers = serverManager.serverSnapshots()
        let savedConfigurations = serverManager.helperConfigurationUpdates()
        let libraries = libraryManager.librarySnapshots(bufferingPolicy: .bufferingNewest(1))
        observations = [
            Task { @MainActor [weak self] in
                for await _ in servers {
                    guard let self, !Task.isCancelled else { return }
                    self.refreshSavedConfiguration()
                }
            },
            Task { @MainActor [weak self, serverID] in
                for await changedServerID in savedConfigurations where changedServerID == serverID {
                    guard let self, !Task.isCancelled else { return }
                    self.refreshSavedConfiguration()
                }
            },
            Task { @MainActor [weak self] in
                for await _ in libraries {
                    guard let self, !Task.isCancelled else { return }
                    self.invalidateStaleRequest()
                }
            }
        ]
        refreshSavedConfiguration()
    }

    /// A pushed plugin page can cover this form while its route and draft stay active.
    func suspend() {
        formVisible = false
        pauseObserving()
    }

    private func pauseObserving() {
        observations.forEach { $0.cancel() }
        observations = []
        if helperTicket != nil {
            clearHelperRequest()
            helperState = .idle
        }
    }

    func closeRoute() {
        suspend()
        routeInitialized = false
        helperState = .idle
        instructionPresented = false
    }

    func setPortDraft(_ value: String) {
        guard portStr != value else { return }
        clearHelperRequest()
        portStr = value
        helperState = serverAvailable ? .idle : .failure(.stale)
    }

    private func refreshSavedConfiguration() {
        let wasAvailable = serverAvailable
        let wasInitialized = routeInitialized
        let current = serverManager.calibreServers[serverID]
        let server = current.flatMap { $0.removed ? nil : $0 }
        let available = server != nil && server?.isLocal == false
        if serverAvailable != available { serverAvailable = available }

        let stored = server.flatMap { serverManager.queryServerDSReaderHelper(server: $0) }
        if savedHelper != stored { savedHelper = stored }
        invalidateStaleRequest()

        let oldDefault = defaultPortDraft
        let ports = CalibreServerDSReaderHelper.validPorts
        let url = server.flatMap {
            serverService.getServerUrlByReachability(server: $0) ?? URL(string: $0.serverUrl)
        }
        let suggested = url?.port.flatMap { $0 < ports.upperBound ? $0 + 1 : nil }
        let port = stored?.port ?? suggested
        defaultPortDraft = port.flatMap { ports.contains($0) ? String($0) : nil } ?? ""
        if (!routeInitialized || portStr == oldDefault), portStr != defaultPortDraft {
            portStr = defaultPortDraft
        }
        routeInitialized = true
        if !available && (wasAvailable || !wasInitialized) {
            helperState = .failure(.stale)
        } else if available && !wasAvailable && wasInitialized {
            helperState = .idle
        }
    }

    private func invalidateStaleRequest() {
        guard let helperTicket else { return }
        do {
            try serverManager.validateHelperConfigurationRequest(helperTicket)
        } catch {
            clearHelperRequest()
            helperState = .failure(.stale)
        }
    }

    func stopHelperConfiguration() {
        clearHelperRequest()
        helperState = .cancelled
    }

    @discardableResult
    func connectDSReader() -> Task<Void, Never>? {
        guard !observations.isEmpty, serverAvailable else { return nil }
        clearHelperRequest()
        guard let helperPort else {
            helperState = .failure(.invalidPort)
            return nil
        }
        do {
            let load = try serverManager.requestManualHelperConfiguration(serverID: serverID, port: helperPort)
            helperTicket = load.ticket
            helperState = .loading
            let task = Task { @MainActor [weak self] in
                do {
                    let candidate = try await load.task.value
                    guard let self, !Task.isCancelled, self.helperTicket == load.ticket else { return }
                    try self.serverManager.validateHelperConfigurationCandidate(load.ticket)
                    self.helperState = .awaitingConfirmation(candidate)
                    self.helperConfirmation = candidate.ticket
                    self.helperTask = nil
                } catch {
                    guard let self, !Task.isCancelled, self.helperTicket == load.ticket else { return }
                    self.clearHelperRequest()
                    self.helperState = HelperConfigurationFailure.isCancellation(error)
                        ? .cancelled : .failure(.init(error))
                }
            }
            helperTask = task
            return task
        } catch {
            helperState = .failure(.init(error))
            return nil
        }
    }

    func applyHelperConfiguration(_ ticket: DSReaderHelperConfigurationTicket) {
        guard helperTicket == ticket, case .awaitingConfirmation(let candidate) = helperState else { return }
        defer { clearHelperRequest() }
        do {
            let saved = try serverManager.applyHelperConfiguration(candidate)
            savedHelper = saved
            defaultPortDraft = String(saved.port)
            portStr = defaultPortDraft
            helperState = .idle
        } catch {
            helperState = .failure(.init(error))
        }
    }

    func discardHelperConfiguration(_ ticket: DSReaderHelperConfigurationTicket) {
        guard helperTicket == ticket else { return }
        clearHelperRequest()
        helperState = .idle
    }

    private func clearHelperRequest() {
        if let helperTicket {
            serverManager.cancelHelperConfiguration(helperTicket)
        }
        helperTicket = nil
        helperTask?.cancel()
        helperTask = nil
        helperConfirmation = nil
    }
}

enum HelperConfigurationState {
    case idle
    case loading
    case awaitingConfirmation(DSReaderHelperConfigurationCandidate)
    case failure(HelperConfigurationFailure)
    case cancelled
}

enum HelperConfigurationFailure {
    case invalidPort
    case stale
    case couldNotSave
    case authentication
    case invalidResponse
    case timeout
    case unavailable

    init(_ error: Error) {
        if let failure = error as? DSReaderHelperConfigurationError {
            switch failure {
            case .invalidPort: self = .invalidPort
            case .stale: self = .stale
            case .couldNotSave: self = .couldNotSave
            }
            return
        }

        switch CalibreAPIError(error: error) {
        case .authFailed:
            self = .authentication
        case .transport(let urlError) where urlError.code == .userAuthenticationRequired:
            self = .authentication
        case .decoding, .unsupportedPayload, .emptyResponse:
            self = .invalidResponse
        case .transport(let urlError) where urlError.code == .timedOut:
            self = .timeout
        default:
            self = .unavailable
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if case .transport(let error) = CalibreAPIError(error: error) { return error.code == .cancelled }
        return false
    }

    var message: LocalizedStringKey {
        switch self {
        case .invalidPort: return "Enter a plugin service port between 1024 and 65535."
        case .stale: return "The server or saved configuration changed. Download the configuration again."
        case .couldNotSave: return "Could not save the configuration. Download it again and retry."
        case .authentication: return "DSReader Helper denied access. Check the server credentials and permissions."
        case .invalidResponse: return "DSReader Helper returned an incomplete or unreadable configuration."
        case .timeout: return "DSReader Helper did not respond in time. Check the service and retry."
        case .unavailable: return "Could not connect to DSReader Helper. Check the service port and that the plugin is running."
        }
    }
}
