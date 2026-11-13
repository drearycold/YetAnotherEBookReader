//
//  CalibreLibraryManager.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/13.
//

import Foundation
import OSLog

class CalibreLibraryManager {
    enum StartupScan {
        case notRequired
        case pending
        case complete
        case incomplete

        var isPending: Bool {
            if case .pending = self { return true }
            return false
        }

        var fileAccessNotice: AlertItem? {
            switch self {
            case .pending:
                return AlertItem(id: "Checking Local Library", msg: "Try again after the file check finishes.")
            case .incomplete:
                return AlertItem(id: "Local Library Check Incomplete", msg: "Reopen the app to check the library files again.")
            case .notRequired, .complete:
                return nil
            }
        }
    }

    @MainActor private(set) var startupScan: StartupScan = .notRequired
    @MainActor private var verifiedStartupFiles = [URL: Int32]()
    @MainActor private var unverifiedStartupFiles = Set<URL>()
    private let startupScanBroadcaster = ManagerAsyncBroadcaster<Bool>()

    @MainActor
    func beginStartupScan() {
        verifiedStartupFiles = [:]
        unverifiedStartupFiles = []
        startupScan = .pending
        startupScanBroadcaster.send(true)
    }

    @MainActor
    func finishStartupScan(_ result: LocalBookImportCoordinator.ScanResult?) {
        startupScan = result == nil ? .incomplete : .complete
        verifiedStartupFiles = result?.verifiedFiles ?? [:]
        unverifiedStartupFiles = result?.unverifiedFiles ?? []
        startupScanBroadcaster.send(false)
    }

    @MainActor
    func startupScanChanges() -> AsyncStream<Bool> {
        startupScanBroadcaster.stream(initialValue: startupScan.isPending, bufferingPolicy: .bufferingNewest(1))
    }

    @MainActor
    func canRestoreLocalFile(book: CalibreBook, url: URL) -> Bool {
        switch startupScan {
        case .notRequired: return true
        case .pending, .incomplete: return false
        case .complete: return verifiedStartupFiles[url.standardizedFileURL] == book.id
        }
    }

    @MainActor
    func finishRestoringStartupReaders() { verifiedStartupFiles = [:] }

    @MainActor
    func localFileAccessNotice(for book: CalibreBook, format: Format? = nil) -> AlertItem? {
        guard book.library.server.isLocal else { return nil }
        if let notice = startupScan.fileAccessNotice { return notice }
        let formats = format.map { [$0] } ?? Format.allCases
        if formats.contains(where: { format in
            getSavedUrl(book: book, format: format).map { unverifiedStartupFiles.contains($0.standardizedFileURL) } == true
        }) {
            return AlertItem(id: "Local Book File Could Not Be Checked",
                             msg: "Reopen the app to check this file again.")
        }
        return nil
    }

    private let logger = Logger(subsystem: "YetAnotherEBookReader", category: "CalibreLibraryManager")

    weak var container: AppContainerProtocol?
    let databaseService: DatabaseService
    private let libraryRepository: LibraryRepositoryProtocol

    private let stateChangeBroadcaster = ManagerAsyncBroadcaster<Void>()
    private let libraryBroadcaster = ManagerAsyncBroadcaster<[String: CalibreLibrary]>()
    private let libraryInfoStagingBroadcaster = ManagerAsyncBroadcaster<[String: CalibreLibraryInfo]>()
    private let librarySyncStatusBroadcaster = ManagerAsyncBroadcaster<[String: CalibreSyncStatus]>()

    var calibreLibraries = [String: CalibreLibrary]() {
        didSet {
            container?.calibreServerService.updateCalibreLibraries(calibreLibraries)
            libraryBroadcaster.send(calibreLibraries)
            publishStateChange()
        }
    }
    var calibreLibraryInfoStaging = [String: CalibreLibraryInfo]() {
        didSet {
            libraryInfoStagingBroadcaster.send(calibreLibraryInfoStaging)
            publishStateChange()
        }
    }
    var librarySyncStatus = [String: CalibreSyncStatus]() {
        didSet {
            librarySyncStatusBroadcaster.send(librarySyncStatus)
            publishStateChange()
        }
    }
    @MainActor private var librarySyncIDs: [String: UUID] = [:]
    var localLibrary: CalibreLibrary?

    init(container: AppContainerProtocol, databaseService: DatabaseService, libraryRepository: LibraryRepositoryProtocol) {
        self.container = container
        self.databaseService = databaseService
        self.libraryRepository = libraryRepository
    }

    func stateChanges() -> AsyncStream<Void> {
        stateChangeBroadcaster.stream()
    }

    func librarySnapshots(
        bufferingPolicy: AsyncStream<[String: CalibreLibrary]>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<[String: CalibreLibrary]> {
        libraryBroadcaster.stream(initialValue: calibreLibraries, bufferingPolicy: bufferingPolicy)
    }

    func libraryInfoStagingSnapshots() -> AsyncStream<[String: CalibreLibraryInfo]> {
        libraryInfoStagingBroadcaster.stream(initialValue: calibreLibraryInfoStaging)
    }

    func librarySyncStatusSnapshots() -> AsyncStream<[String: CalibreSyncStatus]> {
        librarySyncStatusBroadcaster.stream(initialValue: librarySyncStatus)
    }

    private func publishStateChange() {
        stateChangeBroadcaster.send(())
    }

    // MARK: - Migrated Methods

    func populateLibraries() {
        let libraries = libraryRepository.getAllLibraries()
        var tempLibraries = [String: CalibreLibrary]()
        libraries.forEach { calibreLibrary in
            tempLibraries[calibreLibrary.id] = calibreLibrary
        }
        calibreLibraries = tempLibraries
    }

    @MainActor
    func populateLocalLibraryBooks(scan: Bool = true,
                                   completion: ((LocalBookImportCoordinator.ScanResult?) -> Void)? = nil) {
        guard let documentDirectoryURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            completion?(nil)
            return
        }

        let tmpServer = CalibreServer(uuid: CalibreServer.LocalServerUUID, name: "Document Folder", baseUrl: ".", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        guard let container = self.container else {
            completion?(nil)
            return
        }

        container.serverManager.documentServer = container.serverManager.calibreServers[tmpServer.id]
        if container.serverManager.documentServer == nil || container.serverManager.documentServer?.name != tmpServer.name {
            container.serverManager.calibreServers[tmpServer.id] = tmpServer
            container.serverManager.documentServer = container.serverManager.calibreServers[tmpServer.id]
            do {
                try container.serverManager.saveServer(server: container.serverManager.documentServer!)
            } catch {
                logger.error("Failed to update server realm for document folder: \(error.localizedDescription)")
            }
        }

        let localLibraryURL = documentDirectoryURL.appendingPathComponent("Local Library", isDirectory: true)

        if FileManager.default.fileExists(atPath: localLibraryURL.path) == false {
            do {
                try FileManager.default.createDirectory(atPath: localLibraryURL.path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                logger.error("Failed to create local library directory: \(error.localizedDescription)")
            }
        }

        guard let documentServer = container.serverManager.documentServer else {
            completion?(nil)
            return
        }
        let tmpLibrary = CalibreLibrary(
            server: documentServer,
            key: localLibraryURL.lastPathComponent,
            name: localLibraryURL.lastPathComponent)
        localLibrary = calibreLibraries[tmpLibrary.id]
        if localLibrary == nil {
            calibreLibraries[tmpLibrary.id] = tmpLibrary
            localLibrary = tmpLibrary
            do {
                try libraryRepository.saveLibrary(tmpLibrary)
            } catch {
                logger.error("Failed to update local library realm: \(error.localizedDescription)")
            }
        }

        guard scan else {
            completion?(nil)
            return
        }
        Task { @MainActor [weak container] in
            let result = await container?.bookManager.scanLocalBooks()
            completion?(result)
        }
    }

    func saveLibrary(library: CalibreLibrary) throws {
        try libraryRepository.saveLibrary(library)
    }

    @MainActor
    func setDiscoverable(_ value: Bool, libraryID: String, serverID: String) throws {
        var library = try currentLibrary(id: libraryID, serverID: serverID)
        guard !library.hidden else { throw ServerSettingsSaveError.stale }
        guard value != library.discoverable else { return }
        try Task.checkCancellation()
        try libraryRepository.updateLibraryFlags(id: libraryID, discoverable: value)
        library.discoverable = value
        calibreLibraries[libraryID] = library
        container?.publishCalibreUpdate(.library(library))
    }

    @MainActor
    func hideLibrary(libraryId: String, serverID: String) throws {
        try setHidden(true, libraryID: libraryId, serverID: serverID)
    }

    @MainActor
    func restoreLibrary(libraryId: String, serverID: String) throws {
        try setHidden(false, libraryID: libraryId, serverID: serverID)
    }

    @MainActor
    private func setHidden(_ hidden: Bool, libraryID: String, serverID: String) throws {
        var library = try currentLibrary(id: libraryID, serverID: serverID)
        guard hidden != library.hidden else { throw ServerSettingsSaveError.stale }
        try Task.checkCancellation()
        try libraryRepository.setLibraryHidden(id: libraryID, serverID: serverID, hidden: hidden)
        library.hidden = hidden
        if !hidden { library.lastModified = Date(timeIntervalSince1970: 0) }
        calibreLibraries[libraryID] = library
        container?.publishCalibreUpdate(.library(library))
    }

    @MainActor
    private func currentLibrary(id: String, serverID: String) throws -> CalibreLibrary {
        guard let library = calibreLibraries[id], library.server.id == serverID,
              let server = container?.calibreServers[serverID], !server.removed else {
            throw ServerSettingsSaveError.stale
        }
        return library
    }

    func queryLibraryBookRealmCount(library: CalibreLibrary, realm: Any? = nil) -> Int {
        return libraryRepository.countBooks(for: library)
    }

    @MainActor
    func registerLibraries(from info: CalibreServerInfo) -> Bool {
        guard let server = container?.calibreServers[info.server.id], !server.removed,
              DSReaderHelperConnection(server) == DSReaderHelperConnection(info.server) else { return false }
        var allSaved = true
        for (key, name) in info.libraryMap {
            let newLibrary = CalibreLibrary(server: server, key: key, name: name)
            var library = calibreLibraries[newLibrary.id] ?? newLibrary
            if calibreLibraries[newLibrary.id] != nil, library.key == key { continue }
            library.key = key
            do {
                try libraryRepository.saveLibrary(library)
                calibreLibraries[library.id] = library
            } catch {
                allSaved = false
                logger.error("Could not save a library during server refresh")
            }
        }
        return allSaved
    }

    @MainActor
    func updateServerSnapshot(_ server: CalibreServer, connectionChanged: Bool) {
        let ids = calibreLibraries.values.filter { $0.server.id == server.id }.map(\.id)
        for id in ids {
            calibreLibraries[id]?.server = server
            if var status = librarySyncStatus[id] {
                status.library.server = server
                if connectionChanged {
                    status.isSync = false
                    status.isError = false
                    status.msg = nil
                }
                librarySyncStatus[id] = status
            }
            if connectionChanged { librarySyncIDs.removeValue(forKey: id) }
        }
    }

    @discardableResult
    @MainActor
    func probeLibrary(request: CalibreProbeLibraryRequest) async -> CalibreLibraryProbeTask {
        guard let calibreServerService = container?.calibreServerService else {
            fatalError("calibreServerService not found")
        }
        let task = await calibreServerService.probeLibrary(library: request.library)

        if let probeResult = task.probeResult {
            self.calibreLibraryInfoStaging[task.library.id] = .init(library: task.library, totalNumber: probeResult.total_num, errorMessage: "Success")
        } else {
            self.calibreLibraryInfoStaging[task.library.id] = .init(library: task.library, totalNumber: 0, errorMessage: "Failed")
        }

        return task
    }

    /// A library whose summary is syncing is hidden and remains available to Restore.
    @MainActor
    func removeOrHideLibrary(libraryID: String, serverID: String) throws {
        let library = try currentLibrary(id: libraryID, serverID: serverID)
        guard !library.hidden else { throw ServerSettingsSaveError.stale }
        if librarySyncStatus[libraryID]?.isSync == true {
            try hideLibrary(libraryId: libraryID, serverID: serverID)
        } else {
            try removeLibrary(library: library)
        }
    }

    @MainActor
    func removeLibrary(library: CalibreLibrary) throws {
        let current = try currentLibrary(id: library.id, serverID: library.server.id)
        try Task.checkCancellation()
        try libraryRepository.deleteLibrary(serverUUID: current.server.id, name: current.name)
        discardLibraries([current.id])
        container?.publishCalibreUpdate(.library(current))
    }

    @MainActor
    func discardRemovedServer(serverID: String) {
        discardLibraries(Set(calibreLibraries.values.filter { $0.server.id == serverID }.map(\.id)))
    }

    @MainActor
    private func discardLibraries(_ ids: Set<String>) {
        if let localLibrary, ids.contains(localLibrary.id) { self.localLibrary = nil }
        for id in ids {
            librarySyncIDs.removeValue(forKey: id)
            calibreLibraries.removeValue(forKey: id)
            calibreLibraryInfoStaging.removeValue(forKey: id)
            librarySyncStatus.removeValue(forKey: id)
        }
        container?.bookManager.discardShelfBooks(in: ids)
    }

    /// Refreshes what the app keeps about a library besides its books, which calibre is asked for
    /// as they're browsed or shelved:
    /// - its summary (`CalibreServerService.getLibrarySummary`): the book count Settings shows, the
    ///   custom columns that turn category filters into searches (`buildLibrarySearchTasks`), and
    ///   the newest change, which is the search and category caches' generation;
    /// - its categories and their cached items.
    ///
    /// `isSync` covers the summary only. The categories can take long to refresh, and a category
    /// the user refreshes meanwhile (`UnifiedCategoryViewModel`) syncs again rather than waiting.
    @MainActor
    func syncLibrary(request: CalibreSyncLibraryRequest, cache suppliedCache: CategoryCacheRepository? = nil) async {
        guard let container,
              var library = try? currentLibrary(id: request.library.id, serverID: request.library.server.id),
              !library.hidden, librarySyncStatus[library.id]?.isSync != true else { return }
        let libraryID = library.id
        let cache: CategoryCacheRepository
        do {
            cache = try (suppliedCache ?? container.categoryCacheRepository.snapshot())
            try cache.checkCurrent()
        } catch {
            var status = librarySyncStatus[libraryID] ?? .init(library: library)
            status.isError = true
            status.msg = "Library refresh failed. Try refreshing again."
            librarySyncStatus[libraryID] = status
            return
        }
        let syncID = UUID()
        let connection = DSReaderHelperConnection(library.server)
        let key = library.key
        librarySyncIDs[libraryID] = syncID
        var status = librarySyncStatus[libraryID] ?? .init(library: library)
        status.isSync = true
        status.isError = false
        status.msg = ""
        librarySyncStatus[libraryID] = status

        func isCurrent() -> Bool {
            librarySyncIDs[libraryID] == syncID && calibreLibraries[libraryID]?.key == key
                && container.calibreServers[connection.serverID].map(DSReaderHelperConnection.init) == connection
                && (try? cache.checkCurrent()) != nil
        }
        defer {
            if librarySyncIDs[libraryID] == syncID {
                librarySyncIDs.removeValue(forKey: libraryID)
                if librarySyncStatus[libraryID]?.isSync == true { librarySyncStatus[libraryID]?.isSync = false }
            }
        }

        let service = container.calibreServerService
        var summaryError: String?
        do {
            let summary = try await service.getLibrarySummary(library: library)
            guard isCurrent(), !Task.isCancelled else { return }
            let previousBookCount = librarySyncStatus[libraryID]?.cnt
            let (updatedLibrary, changed) = try applySummary(summary, previousBookCount: previousBookCount, to: library)
            library = updatedLibrary
            librarySyncStatus[libraryID]?.cnt = summary.bookCount
            if changed { container.publishCalibreUpdate(.library(library)) }
        } catch {
            guard isCurrent(), !Task.isCancelled else { return }
            logger.error("Could not refresh the library summary")
            summaryError = "Library refresh failed. Try refreshing again."
        }

        librarySyncStatus[libraryID]?.isSync = false
        librarySyncStatus[libraryID]?.isError = summaryError != nil
        librarySyncStatus[libraryID]?.msg = summaryError ?? "Success"

        var categoryError: String?
        do {
            let categories = try await service.getLibraryCategories(library: library)
            guard isCurrent(), !Task.isCancelled else { return }
            library = try applyCategoryFields(of: categories, to: library)
            categoryError = await refreshCategoryCaches(
                container: container, library: library, categories: categories, cache: cache, isCurrent: isCurrent
            )
        } catch {
            logger.error("Could not refresh the library categories")
            categoryError = "Category refresh failed. Try refreshing again."
        }

        if isCurrent(), !Task.isCancelled, let categoryError, summaryError == nil {
            librarySyncStatus[libraryID]?.isError = true
            librarySyncStatus[libraryID]?.msg = categoryError
        }
    }

    /// Keeps the field calibre searches each category by (`CalibreLibrary.categoryFields`): a
    /// category's name is in the server's language, and isn't one.
    @MainActor
    private func applyCategoryFields(of categories: [CalibreLibraryCategory], to library: CalibreLibrary) throws -> CalibreLibrary {
        let categoryFields = categories
            .filter(\.is_category)
            .reduce(into: [String: String]()) { fields, category in
                fields[category.name] = category.field
            }
        // A library removed meanwhile stays removed.
        guard var updated = calibreLibraries[library.id],
              updated.categoryFields != categoryFields else {
            return library
        }

        updated.categoryFields = categoryFields
        try libraryRepository.saveLibrary(updated)
        calibreLibraries[library.id] = updated
        return updated
    }

    /// The field calibre searches a category by, from any library calibre named it for, for a
    /// filter that spans libraries (`CalibreLibrary.searchField(forCategory:)`).
    func searchField(forCategory name: String) -> String {
        calibreLibraries.values.lazy.compactMap { $0.categoryFields[name] }.first ?? name.lowercased()
    }

    /// Keeps the newer `lastModified` and the custom columns, when the library has a book to
    /// describe them.
    ///
    /// A deleted book changes no other book, so calibre's newest change stays put, or goes back
    /// when it was the newest. A book count that changed since the last summary moves the
    /// generation just past the date it had, so the search and category caches are fetched again.
    @MainActor
    private func applySummary(
        _ summary: CalibreLibrarySummary,
        previousBookCount: Int?,
        to library: CalibreLibrary
    ) throws -> (CalibreLibrary, Bool) {
        guard var updated = calibreLibraries[library.id] else { throw ServerSettingsSaveError.stale }
        var changed = false
        if let lastModified = summary.lastModified, lastModified > updated.lastModified {
            updated.lastModified = lastModified
            changed = true
        } else if let previousBookCount, previousBookCount != summary.bookCount {
            updated.lastModified = updated.lastModified.addingTimeInterval(0.001)
            changed = true
        }
        if let customColumnInfos = summary.customColumnInfos, customColumnInfos != updated.customColumnInfos {
            updated.customColumnInfos = customColumnInfos
            changed = true
        }
        // A library removed meanwhile stays removed.
        guard changed, calibreLibraries[library.id] != nil else {
            return (updated, false)
        }

        try libraryRepository.saveLibrary(updated)
        calibreLibraries[library.id] = updated
        return (updated, true)
    }

    /// Returns the first error of a category that couldn't be refreshed, so the sync reports it.
    @MainActor
    private func refreshCategoryCaches(
        container: AppContainerProtocol,
        library: CalibreLibrary,
        categories: [CalibreLibraryCategory],
        cache: CategoryCacheRepository,
        isCurrent: () -> Bool
    ) async -> String? {
        let activeCategories = categories.filter { $0.is_category }
        let activeCategoryNames = Set(activeCategories.map(\.name))

        do {
            let lifetime = try container.calibreServerService.cacheLifetime(for: library)
            let scoped = try cache.scoped(to: library, lifetime: lifetime)
            try scoped.removeLibraryCategoryResultsNotIn(
                libraryId: library.id,
                activeCategoryNames: activeCategoryNames
            )
        } catch CacheContextError.superseded {
            return nil
        } catch {
            logger.error("Could not prune stale library categories")
            return "Category refresh failed. Try refreshing again."
        }

        var firstError: String?
        for category in activeCategories {
            guard isCurrent(), !Task.isCancelled else { return nil }
            do {
                _ = try await container.libraryCategoryService.fetchAndCacheCategory(
                    library: library,
                    category: category,
                    cache: cache
                )
            } catch CacheContextError.superseded {
                return nil
            } catch is CancellationError {
                return nil
            } catch {
                logger.error("Could not refresh a library category")
                firstError = "Category refresh failed. Try refreshing again."
            }
        }
        return firstError
    }
}
