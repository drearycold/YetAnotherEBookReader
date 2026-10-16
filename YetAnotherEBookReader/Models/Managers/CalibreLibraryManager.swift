//
//  CalibreLibraryManager.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/13.
//

import Foundation
import OSLog

class CalibreLibraryManager {
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
    var localLibrary: CalibreLibrary?

    init(container: AppContainerProtocol, databaseService: DatabaseService, libraryRepository: LibraryRepositoryProtocol) {
        self.container = container
        self.databaseService = databaseService
        self.libraryRepository = libraryRepository
    }

    func stateChanges() -> AsyncStream<Void> {
        stateChangeBroadcaster.stream()
    }

    func librarySnapshots() -> AsyncStream<[String: CalibreLibrary]> {
        libraryBroadcaster.stream(initialValue: calibreLibraries)
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

    func populateLocalLibraryBooks(completion: (() -> Void)? = nil) {
        let finish = {
            if Thread.isMainThread {
                completion?()
            } else {
                DispatchQueue.main.async {
                    completion?()
                }
            }
        }

        guard let documentDirectoryURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            finish()
            return
        }

        let tmpServer = CalibreServer(uuid: CalibreServer.LocalServerUUID, name: "Document Folder", baseUrl: ".", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        guard let container = self.container else {
            finish()
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

        let tmpLibrary = CalibreLibrary(
            server: container.serverManager.documentServer!,
            key: localLibraryURL.lastPathComponent,
            name: localLibraryURL.lastPathComponent)
        localLibrary = calibreLibraries[tmpLibrary.id]
        if localLibrary == nil {
            calibreLibraries[tmpLibrary.id] = tmpLibrary
            localLibrary = calibreLibraries[tmpLibrary.id]
            do {
                try libraryRepository.saveLibrary(localLibrary!)
            } catch {
                logger.error("Failed to update local library realm: \(error.localizedDescription)")
            }
        }

        let booksInShelfSnapshot = container.bookManager.booksInShelf

        // Offload file scanning and metadata loading to the background thread
        let work = { [weak self] in
            guard let self = self,
                  let localLibrary = self.localLibrary,
                  let documentServer = container.serverManager.documentServer
            else {
                finish()
                return
            }

            guard let dirEnum = FileManager.default.enumerator(atPath: localLibraryURL.path) else {
                finish()
                return
            }

            dirEnum.forEach {
                guard let fileName = $0 as? String else {
                    return
                }
                if fileName.hasSuffix(".db") { return }
                if fileName.hasSuffix(".db.lock") { return }
                if fileName.hasSuffix(".db.note") { return }
                if fileName.hasSuffix(".db.management") { return }
                if fileName.hasSuffix(".cv") { return }
                if fileName.hasSuffix(".mx") { return }

                self.logger.debug("populateLocalLibraryBooks \(fileName)")
                if let localBaseUrl = documentServer.localBaseUrl {
                    let fileURL = localBaseUrl.appendingPathComponent(localLibrary.key, isDirectory: true).appendingPathComponent(fileName, isDirectory: false)
                    container.bookManager.loadLocalLibraryBookMetadata(fileURL: fileURL, in: localLibrary, on: documentServer)
                }
            }

            let booksInShelfValues = booksInShelfSnapshot.map { $0.value }
            let removedBooks: [CalibreBook] = booksInShelfValues.compactMap { (book: CalibreBook) -> CalibreBook? in
                guard book.library.server.isLocal else { return nil }
                let existingFormats: [String] = book.formats.compactMap {
                    guard let format = Format(rawValue: $0.key),
                          let bookFileUrl = getSavedUrl(book: book, format: format) else { return nil }

                    var isDirectory : ObjCBool = false
                    guard FileManager.default.fileExists(atPath: bookFileUrl.path, isDirectory: &isDirectory) else {
                        return nil
                    }
                    guard isDirectory.boolValue == false else {
                        return nil
                    }

                    return $0.key
                }

                guard existingFormats.isEmpty else {
                    return nil
                }

                return book
            }

            let publish = {
                removedBooks.forEach {
                    container.bookManager.removeFromShelf(inShelfId: $0.inShelfId)
                    self.logger.debug("populateLocalLibraryBooks removeFromShelf \($0.inShelfId)")
                }
                finish()
            }

            if Thread.isMainThread {
                publish()
            } else {
                DispatchQueue.main.async(execute: publish)
            }
        }

        if NSClassFromString("XCTestCase") != nil {
            work()
        } else {
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        }
    }

    func saveLibrary(library: CalibreLibrary) throws {
        try libraryRepository.saveLibrary(library)
    }

    func hideLibrary(libraryId: String) {
        calibreLibraries[libraryId]?.hidden = true
        if let library = calibreLibraries[libraryId] {
            try? libraryRepository.saveLibrary(library)
        }
    }

    func restoreLibrary(libraryId: String) {
        calibreLibraries[libraryId]?.hidden = false
        calibreLibraries[libraryId]?.lastModified = Date(timeIntervalSince1970: 0)
        if let library = calibreLibraries[libraryId] {
            try? libraryRepository.saveLibrary(library)
        }
    }

    func queryLibraryBookRealmCount(library: CalibreLibrary, realm: Any? = nil) -> Int {
        return libraryRepository.countBooks(for: library)
    }

    func updateServerLibraryInfo(serverInfo: CalibreServerInfo) {
        guard let server = container?.calibreServers[serverInfo.server.id] else { return }

        serverInfo.libraryMap.forEach { key, name in
            let newLibrary = CalibreLibrary(server: serverInfo.server, key: key, name: name)
            let libraryId = newLibrary.id

            if calibreLibraries[libraryId] != nil {
                calibreLibraries[libraryId]!.key = newLibrary.key
            } else {
                let library = CalibreLibrary(server: server, key: newLibrary.key, name: newLibrary.name)
                calibreLibraries[libraryId] = library
            }
            do {
                try libraryRepository.saveLibrary(calibreLibraries[libraryId]!)
            } catch {
                logger.error("Failed to update library realm in updateServerLibraryInfo: \(error.localizedDescription)")
            }
        }

        // If the server's defaultLibrary changed, persist it on the server.
        if let serverManager = container?.serverManager,
           var mutableServer = serverManager.calibreServers[serverInfo.server.id],
           mutableServer.defaultLibrary != serverInfo.defaultLibrary {
            mutableServer.defaultLibrary = serverInfo.defaultLibrary
            serverManager.calibreServers[serverInfo.server.id] = mutableServer
            do {
                try serverManager.saveServer(server: mutableServer)
            } catch {
                logger.error("Failed to update server realm defaultLibrary: \(error.localizedDescription)")
            }
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

    @MainActor
    func removeLibrary(library: CalibreLibrary) async {
        guard let container = self.container else { return }
        if librarySyncStatus[library.id] != nil {
            librarySyncStatus[library.id]?.isSync = true
        } else {
            librarySyncStatus[library.id] = .init(library: library, isSync: true)
        }

        //remove cached book files
        let libraryBooksInShelf = container.bookManager.booksInShelf.filter {
            $0.value.library.id == library.id
        }
        libraryBooksInShelf.forEach {
            container.bookManager.clearCache(inShelfId: $0.key)
            container.bookManager.removeFromShelf(inShelfId: $0.key)     //just in case
        }

        let serverUUIDString = library.server.uuid.uuidString
        let libraryName = library.name
        try? libraryRepository.deleteLibrary(serverUUID: serverUUIDString, name: libraryName)

        self.calibreLibraries.removeValue(forKey: library.id)
        self.librarySyncStatus[library.id]?.isSync = false
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
    func syncLibrary(request: CalibreSyncLibraryRequest) async {
        guard let container = self.container else { return }
        let libraryId = request.library.id
        guard (self.librarySyncStatus[libraryId]?.isSync ?? false) == false else {
            return
        }

        guard request.library.hidden == false else {
            return
        }

        if var status = self.librarySyncStatus[libraryId] {
            status.isSync = true
            status.isError = false
            status.msg = ""
            self.librarySyncStatus[libraryId] = status
        } else {
            self.librarySyncStatus[libraryId] = .init(library: request.library, isSync: true)
        }

        let calibreServerService = container.calibreServerService
        var library = calibreLibraries[libraryId] ?? request.library
        var summaryError: String?

        do {
            let summary = try await calibreServerService.getLibrarySummary(library: library)
            let previousBookCount = self.librarySyncStatus[libraryId]?.cnt
            let (updatedLibrary, changed) = applySummary(summary, previousBookCount: previousBookCount, to: library)
            library = updatedLibrary
            self.librarySyncStatus[libraryId]?.cnt = summary.bookCount
            if changed {
                container.publishCalibreUpdate(.library(library))
            }
        } catch {
            logger.error("Failed to read the summary of \(library.name): \(error.localizedDescription)")
            summaryError = error.localizedDescription
        }

        self.librarySyncStatus[libraryId]?.isSync = false
        self.librarySyncStatus[libraryId]?.isError = summaryError != nil
        self.librarySyncStatus[libraryId]?.msg = summaryError ?? "Success"

        // A library removed meanwhile stays removed: no categories are cached for it.
        guard calibreLibraries[libraryId] != nil else { return }

        var categoryError: String?
        do {
            let categories = try await calibreServerService.getLibraryCategories(library: library)
            library = applyCategoryFields(of: categories, to: library)
            categoryError = await refreshCategoryCaches(
                container: container,
                library: library,
                categories: categories
            )
        } catch {
            logger.error("Failed to read the categories of \(library.name): \(error.localizedDescription)")
            categoryError = error.localizedDescription
        }

        // Unless a newer sync has started, or the summary already failed.
        if let categoryError,
           let status = self.librarySyncStatus[libraryId],
           status.isSync == false,
           status.isError == false {
            self.librarySyncStatus[libraryId]?.isError = true
            self.librarySyncStatus[libraryId]?.msg = categoryError
        }
    }

    /// Keeps the field calibre searches each category by (`CalibreLibrary.categoryFields`): a
    /// category's name is in the server's language, and isn't one.
    @MainActor
    private func applyCategoryFields(of categories: [CalibreLibraryCategory], to library: CalibreLibrary) -> CalibreLibrary {
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
        calibreLibraries[library.id] = updated
        do {
            try libraryRepository.saveLibrary(updated)
        } catch {
            logger.error("Failed to save the category fields of \(updated.name): \(error.localizedDescription)")
        }
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
    ) -> (CalibreLibrary, Bool) {
        var updated = calibreLibraries[library.id] ?? library
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

        calibreLibraries[library.id] = updated
        do {
            try libraryRepository.saveLibrary(updated)
        } catch {
            logger.error("Failed to save the summary of \(updated.name): \(error.localizedDescription)")
        }
        return (updated, true)
    }

    /// Returns the first error of a category that couldn't be refreshed, so the sync reports it.
    @MainActor
    private func refreshCategoryCaches(
        container: AppContainerProtocol,
        library: CalibreLibrary,
        categories: [CalibreLibraryCategory]
    ) async -> String? {
        let activeCategories = categories.filter { $0.is_category }
        let activeCategoryNames = Set(activeCategories.map(\.name))

        do {
            try container.categoryCacheRepository.removeLibraryCategoryResultsNotIn(
                libraryId: library.id,
                activeCategoryNames: activeCategoryNames
            )
        } catch {
            logger.error("Failed to prune stale categories for \(library.name): \(error.localizedDescription)")
        }

        var firstError: String?
        for category in activeCategories {
            do {
                _ = try await container.libraryCategoryService.fetchAndCacheCategory(
                    library: library,
                    category: category
                )
            } catch {
                logger.error("Failed to fetch and cache category \(category.name) for \(library.name): \(error.localizedDescription)")
                firstError = firstError ?? "\(category.name): \(error.localizedDescription)"
            }
        }
        return firstError
    }
}
