import Foundation
import SwiftUI

@MainActor
final class ServerDetailViewModel: ObservableObject {
    enum Surface: Hashable {
        case detail
        case hiddenLibraries
    }

    struct LibraryRow: Identifiable, Equatable {
        let id: String
        let name: String
        let discoverable: Bool
        let status: Status?

        struct Status: Equatable {
            let syncing: Bool
            let failed: Bool
            let message: String?
            let count: Int?
            let unavailableCount: Int

            init(_ value: CalibreSyncStatus) {
                syncing = value.isSync
                failed = value.isError
                message = value.msg
                count = value.cnt
                unavailableCount = value.del.count
            }
        }

        init(_ library: CalibreLibrary, status: CalibreSyncStatus? = nil) {
            id = library.id
            name = library.name
            discoverable = library.discoverable
            self.status = status.map(Status.init)
        }
    }

    struct Snapshot: Equatable {
        var name: String?
        var probing = false
        var syncing = false
        var refreshFailed = false
        var visible: [LibraryRow] = []
        var hidden: [LibraryRow] = []
    }

    let serverID: String
    private let container: AppContainer
    @Published private(set) var snapshot = Snapshot()
    @Published var restoreSelection: Set<String> = []
    @Published private(set) var librarySaveFailure: ServerSettingsSaveError?
    private var surfaces: Set<Surface> = []
    private var observations: [Task<Void, Never>] = []

    init(container: AppContainer, serverID: String) {
        self.container = container
        self.serverID = serverID
    }

    deinit {
        observations.forEach { $0.cancel() }
    }

    private var server: CalibreServer? {
        guard let server = container.serverManager.calibreServers[serverID], !server.removed else { return nil }
        return server
    }

    func startObserving(_ surface: Surface) {
        guard surfaces.insert(surface).inserted, observations.isEmpty else { return }
        let servers = container.serverManager.stateChanges()
        let libraries = container.libraryManager.stateChanges()
        observations = [servers, libraries].map { changes in
            Task { @MainActor [weak self] in
                for await _ in changes {
                    guard let self, !Task.isCancelled else { return }
                    self.refresh()
                }
            }
        }
        refresh()
    }

    func stopObserving(_ surface: Surface) {
        guard surfaces.remove(surface) != nil, surfaces.isEmpty else { return }
        observations.forEach { $0.cancel() }
        observations = []
    }

    private func refresh() {
        var current = Snapshot()
        if let server {
            let manager = container.libraryManager
            let libraries = manager.calibreLibraries.values.filter { $0.server.id == serverID }
            current.name = server.name
            current.probing = container.serverManager.isServerProbing(server: server)
            if let info = container.serverManager.getServerInfo(server: server) {
                current.refreshFailed = !current.probing && (!info.reachable || info.libraryRefreshFailed)
            }
            current.visible = libraries.filter { !$0.hidden }
                .sorted { $0.name < $1.name }
                .map { LibraryRow($0, status: manager.librarySyncStatus[$0.id]) }
            current.hidden = libraries.filter(\.hidden)
                .sorted { $0.id < $1.id }
                .map { LibraryRow($0) }
            current.syncing = libraries.contains { manager.librarySyncStatus[$0.id]?.isSync == true }
        }
        if snapshot != current { snapshot = current }
    }

    func library(for id: String) -> CalibreLibrary? {
        guard server != nil, let library = container.libraryManager.calibreLibraries[id],
              library.server.id == serverID, !library.hidden else { return nil }
        return library
    }

    func removeLibraries(at offsets: IndexSet) {
        let ids = offsets.compactMap { snapshot.visible.indices.contains($0) ? snapshot.visible[$0].id : nil }
        librarySaveFailure = nil
        for id in ids {
            do {
                try container.libraryManager.removeOrHideLibrary(libraryID: id, serverID: serverID)
            } catch is CancellationError {
                break
            } catch {
                librarySaveFailure = error as? ServerSettingsSaveError ?? .failed
            }
        }
        refresh()
    }

    @discardableResult
    func restoreLibraries(_ ids: Set<String>) -> Bool {
        librarySaveFailure = nil
        var pending = ids
        for id in ids.sorted() {
            do {
                try container.libraryManager.restoreLibrary(libraryId: id, serverID: serverID)
                pending.remove(id)
            } catch is CancellationError {
                break
            } catch {
                librarySaveFailure = error as? ServerSettingsSaveError ?? .failed
            }
        }
        restoreSelection = pending
        refresh()
        return pending.isEmpty
    }

    func beginRestoringLibraries() {
        restoreSelection = []
        librarySaveFailure = nil
        startObserving(.hiddenLibraries)
    }

    func probeReachability() {
        guard let server else { return }
        container.serverManager.probeServersReachability(with: [server.id], updateLibrary: true, autoUpdateOnly: true)
    }
}
