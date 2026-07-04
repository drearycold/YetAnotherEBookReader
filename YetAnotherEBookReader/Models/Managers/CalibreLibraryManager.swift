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
    private var probeLibraryLastModifiedTask: Task<Void, Never>?

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

    deinit {
        probeLibraryLastModifiedTask?.cancel()
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
        calibreLibraries[libraryId]?.autoUpdate = false
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

    func startProbeLibraryLastModifiedTask() {
        let dateFormatter = ISO8601DateFormatter()
        let dateFormatter2 = ISO8601DateFormatter()
        dateFormatter2.formatOptions.formUnion(.withFractionalSeconds)

        guard let container = self.container else { return }
        let requests = container.probeLibraryLastModifiedRequests()
        probeLibraryLastModifiedTask?.cancel()
        probeLibraryLastModifiedTask = Task { [weak self] in
            for await request in requests {
                guard !Task.isCancelled,
                      let self,
                      let calibreServerService = self.container?.calibreServerService else { return }

                do {
                    let syncResult = try await calibreServerService.syncLegacyLibraryResult(
                        resultPrev: .init(request: request, result: [:]),
                        order: "",
                        filter: "",
                        limit: 1
                    )

                    await MainActor.run {
                        guard var library = self.calibreLibraries[syncResult.request.library.id],
                              let lastModifiedStr = syncResult.list.data.last_modified.first?.value.v,
                              let lastModified = dateFormatter.date(from: lastModifiedStr) ?? dateFormatter2.date(from: lastModifiedStr)
                        else {
                            return
                        }
                        if lastModified > library.lastModified {
                            library.lastModified = lastModified
                            self.calibreLibraries[syncResult.request.library.id] = library
                            try? self.libraryRepository.saveLibrary(library)
                        }

                        self.container?.publishCalibreUpdate(.library(library))
                    }
                } catch {
                    self.logger.error("Failed to probe library last modified: \(error.localizedDescription)")
                }
            }
        }
    }

    @MainActor
    func syncLibrary(request: CalibreSyncLibraryRequest) async {
        guard let container = self.container else { return }
        let calibreServerService = container.calibreServerService
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
            status.cnt = nil
            self.librarySyncStatus[libraryId] = status
        } else {
            self.librarySyncStatus[libraryId] = .init(library: request.library, isSync: true)
        }

        var result = await calibreServerService.getCustomColumns(request: request)
        result = await calibreServerService.getLibraryCategories(resultPrev: result)

        let shouldSyncBooks = request.autoUpdateOnly == false || request.library.autoUpdate

        if shouldSyncBooks {
            var filter = ""
            if request.incremental,
               let cachedLib = calibreLibraries[result.request.library.id] {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions.formUnion(.withColonSeparatorInTimeZone)
                formatter.timeZone = .current
                let lastModifiedStr = formatter.string(from: cachedLib.lastModified)
                filter = "last_modified:\">=\(lastModifiedStr)\""
            }

            result = await calibreServerService.syncLibrary(resultPrev: result, filter: filter)

            self.librarySyncStatus[libraryId]?.isError = result.isError

            if result.isError == false {
                let library = result.request.library

                await withCheckedContinuation { continuation in
                    DatabaseService.metadataWriteQueue.async { [weak self] in
                        guard let self = self else {
                            continuation.resume()
                            return
                        }
                        try? self.libraryRepository.saveLibrary(library)
                        continuation.resume()
                    }
                }

                result.categories.filter { $0.is_category }.forEach { category in
                    Task {
                        do {
                            _ = try await container.libraryCategoryService.fetchAndCacheCategory(library: library, category: category)
                        } catch {
                            logger.error("Failed to fetch and cache category \(category.name) for \(library.name): \(error.localizedDescription)")
                        }
                    }
                }

                let dateFormatter = ISO8601DateFormatter()
                let dateFormatter2 = ISO8601DateFormatter()
                dateFormatter2.formatOptions.formUnion(.withFractionalSeconds)

                var progress = 0
                let total = result.list.book_ids.count
                for chunk in result.list.book_ids.chunks(size: 1024) {
                    let preMsg = "\(progress) / \(total)"
                    let list = chunk.compactMap { id -> BookMetadataSyncRecord? in
                        let idStr = id.description
                        guard let lastModifiedStr = result.list.data.last_modified[idStr]?.v,
                              let lastModified = dateFormatter.date(from: lastModifiedStr) ?? dateFormatter2.date(from: lastModifiedStr) else { return nil }
                        return BookMetadataSyncRecord(id: id, lastModified: lastModified)
                    }
                    progress += chunk.count
                    let postMsg = "\(progress) / \(total)"
                    await saveBookMetadata(metadata: .init(library: library, action: .save(list), preMsg: preMsg, postMsg: postMsg))

                    if let lastMod = list.last?.lastModified {
                        result.lastModified = lastMod
                    }
                }

                if result.request.incremental == false {
                    await saveBookMetadata(metadata: .init(library: library, action: .updateDeleted(result.list.data.last_modified), preMsg: "", postMsg: ""))
                }

                await saveBookMetadata(metadata: .init(library: library, action: .complete(result.lastModified, result.result["result"] ?? [:]), preMsg: "", postMsg: "Success"))

                if container.serverManager.isServerReachable(server: library.server) {
                    await container.publishCalibreUpdate(.server(library.server))
                    container.publishProbeLibraryLastModifiedRequest(.init(library: library, autoUpdateOnly: false, incremental: false))
                }
            }
        } else {
            let isError = !result.errmsg.isEmpty
            self.librarySyncStatus[libraryId]?.isError = isError
            self.librarySyncStatus[libraryId]?.isSync = false

            if !isError {
                let library = result.request.library

                result.categories.filter { $0.is_category }.forEach { category in
                    Task {
                        do {
                            _ = try await container.libraryCategoryService.fetchAndCacheCategory(library: library, category: category)
                        } catch {
                            logger.error("Failed to fetch and cache category \(category.name) for \(library.name): \(error.localizedDescription)")
                        }
                    }
                }

                self.librarySyncStatus[libraryId]?.msg = "Success (Categories)"

                if container.serverManager.isServerReachable(server: library.server) {
                    await container.publishCalibreUpdate(.server(library.server))
                }
            } else {
                self.librarySyncStatus[libraryId]?.msg = result.errmsg
            }
        }
    }

    @MainActor
    func saveBookMetadata(metadata: CalibreSyncLibraryBooksMetadata) async {
        guard let container = self.container else { return }
        self.librarySyncStatus[metadata.library.id]?.msg = metadata.preMsg

        var metadataResult = metadata

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DatabaseService.metadataWriteQueue.async { [weak self] in
                guard let self = self, let bookRepository = self.container?.bookRepository else {
                    continuation.resume()
                    return
                }

                switch metadataResult.action {
                case let .save(list):
                    bookRepository.saveBookSyncRecords(list, library: metadataResult.library)
                case let .updateDeleted(last_modified):
                    metadataResult.bookDeleted = bookRepository.findDeletedBookIds(
                        library: metadataResult.library,
                        activeIds: last_modified
                    )
                case .complete:
                    if metadataResult.library.autoUpdate {
                        let syncInfo = bookRepository.countAndNeedUpdateBooks(library: metadataResult.library)
                        metadataResult.bookCount = syncInfo.count
                        metadataResult.bookToUpdate = syncInfo.needUpdateIds
                    }
                }
                continuation.resume()
            }
        }

        let library = metadata.library
        var libraryUpdated: CalibreLibrary? = nil

        switch metadataResult.action {
        case let .complete(lastModified, columnInfos):
            if columnInfos.isEmpty == false,
               library.customColumnInfos != columnInfos {
                if libraryUpdated == nil {
                    libraryUpdated = library
                }
                libraryUpdated!.customColumnInfos = columnInfos
            }
            if let lastModified = lastModified,
               library.lastModified != lastModified {
                if libraryUpdated == nil {
                    libraryUpdated = library
                }
                libraryUpdated!.lastModified = lastModified
            }

            if let libraryUpdated = libraryUpdated {
                self.calibreLibraries[library.id] = libraryUpdated
                await withCheckedContinuation { continuation in
                    DatabaseService.metadataWriteQueue.async { [weak self] in
                        guard let self = self else {
                            continuation.resume()
                            return
                        }
                        try? self.libraryRepository.saveLibrary(libraryUpdated)
                        continuation.resume()
                    }
                }
            }

            self.librarySyncStatus[library.id]?.isSync = false
            self.librarySyncStatus[library.id]?.cnt = metadataResult.bookCount

            let bookToUpdate = metadataResult.bookToUpdate.filter {
                self.librarySyncStatus[library.id]?.upd.contains($0) == false
            }
            self.librarySyncStatus[library.id]?.upd.formUnion(bookToUpdate)

            bookToUpdate.chunks(size: 256).forEach { chunk in
                Task {
                    await container.bookManager.getBooksMetadata(request: .init(library: metadata.library, books: chunk, getAnnotations: false))
                }
            }
        case .updateDeleted:
            self.librarySyncStatus[library.id]?.del.formUnion(metadataResult.bookDeleted)
        case let .save(list):
            let bookIds = list.map(\.id)
            bookIds.chunks(size: 256).forEach { chunk in
                Task {
                    await container.bookManager.getBooksMetadata(request: .init(library: library, books: chunk, getAnnotations: false))
                }
            }
        }

        self.librarySyncStatus[library.id]?.msg = metadata.postMsg
    }
}
