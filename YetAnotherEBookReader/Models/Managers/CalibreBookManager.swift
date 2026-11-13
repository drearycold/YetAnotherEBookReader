//
//  CalibreBookManager.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/13.
//

import Foundation
import Darwin
import OSLog
import CryptoSwift

#if canImport(R2Shared)
import R2Shared
import R2Streamer
#endif

class CalibreBookManager {
    struct FileOperations {
        var copy: (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) }
        var move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
        var replace: (URL, URL) throws -> Void = { staged, destination in
            // The staging directory is on the destination volume. POSIX rename either
            // installs the staged file or leaves the existing destination in place.
            guard rename(staged.path, destination.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        var remove: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }

        static func live() -> FileOperations {
            #if FI1_UI_TEST_FIXTURE
            var files = FileOperations()
            if ProcessInfo.processInfo.environment["YABR_FI1_FAIL_OVERWRITE"] == "1",
               UITestingConfiguration.skipsConsentPrompts() {
                let replace = files.replace
                var failOnce = true
                files.replace = { source, destination in
                    if failOnce, source.lastPathComponent == "incoming" {
                        failOnce = false
                        throw CocoaError(.fileWriteNoPermission)
                    }
                    try replace(source, destination)
                }
            }
            return files
            #else
            return FileOperations()
            #endif
        }
    }

    private let files: FileOperations
    private let localDirectory: URL?
    private let fileCommitLock = NSRecursiveLock()
    private let logger = Logger(subsystem: "YetAnotherEBookReader", category: "CalibreBookManager")

    weak var container: AppContainerProtocol?
    let databaseService: DatabaseService

    private let stateChangeBroadcaster = ManagerAsyncBroadcaster<Void>()
    private let booksInShelfBroadcaster = ManagerAsyncBroadcaster<[String: CalibreBook]>()
    private let booksAnnotationBroadcaster = ManagerAsyncBroadcaster<[String: CalibreBook]>()
    private let isShelfLoadedBroadcaster = ManagerAsyncBroadcaster<Bool>()
    private let selectedBookIdBroadcaster = ManagerAsyncBroadcaster<String?>()

    var booksInShelf = [String: CalibreBook]() {
        didSet {
            booksInShelfBroadcaster.send(booksInShelf)
            publishStateChange()
        }
    }
    var booksAnnotation = [String: CalibreBook]() {
        didSet {
            booksAnnotationBroadcaster.send(booksAnnotation)
            publishStateChange()
        }
    }
    var isShelfLoaded = false {
        didSet {
            isShelfLoadedBroadcaster.send(isShelfLoaded)
            publishStateChange()
        }
    }

    var selectedBookId: String? = nil {
        didSet {
            selectedBookIdBroadcaster.send(selectedBookId)
            publishStateChange()
            if let selectedBookId = selectedBookId,
               readingBookInShelfId != selectedBookId {
                readingBookInShelfId = selectedBookId
            }
        }
    }

    var currentBookId: String = "" {
        didSet {
            self.selectedBookId = currentBookId
        }
    }

    var readingBookInShelfId: String? {
        get { container?.sessionManager.readingBookInShelfId }
        set { container?.sessionManager.readingBookInShelfId = newValue }
    }

    var readingBook: CalibreBook? {
        get { container?.sessionManager.readingBook }
        set { container?.sessionManager.readingBook = newValue }
    }

    var presentingEBookReaderFromShelf: Bool {
        get { container?.sessionManager.presentingEBookReaderFromShelf ?? false }
        set { container?.sessionManager.presentingEBookReaderFromShelf = newValue }
    }

    let bookRepository: BookRepositoryProtocol
    let readingPositionRepository: ReadingPositionRepositoryProtocol
    let annotationRepository: AnnotationRepositoryProtocol
    private let metadataSyncWorker: BookMetadataSyncWorker

    init(
        container: AppContainerProtocol? = nil,
        databaseService: DatabaseService = .shared,
        bookRepository: BookRepositoryProtocol? = nil,
        readingPositionRepository: ReadingPositionRepositoryProtocol? = nil,
        annotationRepository: AnnotationRepositoryProtocol? = nil,
        files: FileOperations = .live(),
        localDirectory: URL? = nil
    ) {
        self.container = container
        self.databaseService = databaseService
        self.files = files
        self.localDirectory = localDirectory

        if let repo = bookRepository {
            self.bookRepository = repo
        } else {
            guard let resolver = container else {
                fatalError("LibraryResolver must be available if no repository is provided")
            }
            self.bookRepository = RealmBookRepository(databaseService: databaseService, libraryResolver: resolver)
        }

        if let repo = readingPositionRepository {
            self.readingPositionRepository = repo
        } else {
            self.readingPositionRepository = RealmReadingPositionRepository(
                databaseService: databaseService,
                realmConfigurationProvider: container?.serverScopedRealmProvider
                    ?? DefaultServerScopedRealmConfigurationProvider()
            )
        }

        if let repo = annotationRepository {
            self.annotationRepository = repo
        } else {
            self.annotationRepository = RealmAnnotationRepository(databaseService: databaseService)
        }

        self.metadataSyncWorker = BookMetadataSyncWorker(
            readingPositionRepository: self.readingPositionRepository,
            annotationRepository: self.annotationRepository
        )
    }

    func stateChanges() -> AsyncStream<Void> {
        stateChangeBroadcaster.stream()
    }

    func booksInShelfSnapshots(
        bufferingPolicy: AsyncStream<[String: CalibreBook]>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<[String: CalibreBook]> {
        booksInShelfBroadcaster.stream(initialValue: booksInShelf, bufferingPolicy: bufferingPolicy)
    }

    func booksAnnotationSnapshots() -> AsyncStream<[String: CalibreBook]> {
        booksAnnotationBroadcaster.stream(initialValue: booksAnnotation)
    }

    func isShelfLoadedSnapshots() -> AsyncStream<Bool> {
        isShelfLoadedBroadcaster.stream(initialValue: isShelfLoaded)
    }

    func selectedBookIdSnapshots() -> AsyncStream<String?> {
        selectedBookIdBroadcaster.stream(initialValue: selectedBookId)
    }

    private func publishStateChange() {
        stateChangeBroadcaster.send(())
    }

    // MARK: - Initialization & Realm Sync

    func populateBookShelf(sendShelfUpdate: Bool = true, completion: (() -> Void)? = nil) {
        let finish = {
            if Thread.isMainThread {
                completion?()
            } else {
                DispatchQueue.main.async {
                    completion?()
                }
            }
        }

        let work = { [weak self] in
            guard let self = self else {
                finish()
                return
            }
            let books = self.bookRepository.getAllBooksInShelf()
            var tempBooks = [String: CalibreBook]()
            var changedBooks = [CalibreBook]()

            for book in books {
                var updatedBook = book
                var needsSave = false

                for (formatRaw, formatInfo) in updatedBook.formats {
                    guard let format = Format(rawValue: formatRaw) else {
                        continue
                    }
                    var formatInfoNew = formatInfo
                    if let cacheInfo = self.getCacheInfo(book: updatedBook, format: format),
                       let modified = cacheInfo.1 {
                        formatInfoNew.cached = true
                        formatInfoNew.cacheSize = cacheInfo.0
                        formatInfoNew.cacheMTime = modified
                    } else {
                        formatInfoNew.cached = false
                        formatInfoNew.cacheSize = 0
                        formatInfoNew.cacheMTime = Date.distantPast
                    }

                    if formatInfoNew.cached != formatInfo.cached {
                        updatedBook.formats[formatRaw] = formatInfoNew
                        needsSave = true
                    }
                }

                if needsSave {
                    self.bookRepository.saveBook(updatedBook)
                    changedBooks.append(updatedBook)
                }

                tempBooks[updatedBook.inShelfId] = updatedBook
            }

            let publish = {
                self.booksInShelf = tempBooks
                for updatedBook in changedBooks {
                    if self.readingBook?.inShelfId == updatedBook.inShelfId {
                        self.readingBook = updatedBook
                    }
                }
                self.isShelfLoaded = true
                if sendShelfUpdate {
                    Task { @MainActor in
                        self.container?.publishCalibreUpdate(.shelf)
                    }
                }
                finish()
            }

            if Thread.isMainThread {
                publish()
            } else {
                DispatchQueue.main.async(execute: publish)
            }
        }

        let isUITestingMockLibrary = ProcessInfo.processInfo.arguments.contains("--ui-testing-mock-library")
        if NSClassFromString("XCTestCase") != nil || isUITestingMockLibrary {
            work()
        } else {
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        }
    }

    // MARK: - Realm CRUD

    func updateBook(book: CalibreBook) {
        bookRepository.saveBook(book)
        publishSavedBook(book)
    }

    private func publishSavedBook(_ book: CalibreBook) {
        let publish = { [weak self] in
            guard let self = self else { return }
            if self.readingBook?.inShelfId == book.inShelfId {
                self.readingBook = book
            }
            if book.inShelf {
                self.booksInShelf[book.inShelfId] = book
            }
        }

        if Thread.isMainThread {
            publish()
        } else {
            DispatchQueue.main.async(execute: publish)
        }
    }

    func deleteBook(book: CalibreBook) {
        deleteBook(forPrimaryKey: bookRepository.primaryKey(for: book))
    }

    func deleteBook(forPrimaryKey primaryKey: String) {
        bookRepository.deleteBook(id: primaryKey)
    }

    // MARK: - Shelf Management

    func shouldAutoUpdateGoodreads(library: CalibreLibrary) -> (CalibreServerDSReaderHelper, CalibreDSReaderHelperPrefs.Options, CalibreGoodreadsSyncPrefs.PluginPrefs)? {
        guard let serverManager = container?.serverManager else { return nil }

        // must have dsreader helper info and enabled by server
        guard let dsreaderHelperServer = serverManager.queryServerDSReaderHelper(server: library.server), dsreaderHelperServer.port > 0 else { return nil }
        guard let configuration = dsreaderHelperServer.configuration, let dsreader_helper_prefs = configuration.dsreader_helper_prefs, dsreader_helper_prefs.plugin_prefs.Options.goodreadsSyncEnabled else { return nil }

        // check if user disabled auto update
        let dsreaderHelperLibrary = library.pluginDSReaderHelperOptions(configuration: configuration)
        guard dsreaderHelperLibrary.isEnabled else { return nil }

        // check if profile name exists
        let goodreadsSync = library.pluginGoodreadsSyncPreferences(configuration: configuration)
        guard goodreadsSync.isEnabled else { return nil }
        guard let goodreads_sync_prefs = configuration.goodreads_sync_prefs, goodreads_sync_prefs.plugin_prefs.Users.contains(where: { $0.key == goodreadsSync.profileName }) else { return nil }

        return (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync)
    }

    func addToShelf(book: CalibreBook, formats: [Format]) {
        var book = book
        book.inShelf = true
        formats.forEach {
            book.formats[$0.rawValue]?.selected = true
        }
        updateBook(book: book)

        if let calibreServerService = container?.calibreServerService,
           let library = container?.calibreLibraries[book.library.id],
           let goodreadsId = book.identifiers["goodreads"],
           let (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync) = shouldAutoUpdateGoodreads(library: library),
           dsreaderHelperLibrary.autoUpdateGoodreadsBookShelf {
            let connector = DSReaderHelperConnector(calibreServerService: calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: goodreadsSync)
            Task {
                do {
                    try await connector.addToShelf(goodreads_id: goodreadsId, shelfName: "currently-reading", book: book)
                } catch {
                    logger.error("Failed to add book \(book.title) to Goodreads currently-reading shelf: \(error.localizedDescription)")
                }
            }
        }

        Task { @MainActor in
            container?.publishCalibreUpdate(.book(book))
        }
    }

    func removeFromShelf(inShelfId: String) {
        if readingBook?.inShelfId == inShelfId {
            readingBook?.inShelf = false
        }

        guard var book = booksInShelf[inShelfId] else { return }
        book.inShelf = false

        updateBook(book: book)

        booksInShelf.removeValue(forKey: inShelfId)

        if readingPositionRepository.getPositions(for: book).first?.id == container?.deviceName,
           let calibreServerService = container?.calibreServerService,
           let library = container?.calibreLibraries[book.library.id],
           let goodreadsId = book.identifiers["goodreads"],
           let (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync) = shouldAutoUpdateGoodreads(library: library),
           dsreaderHelperLibrary.autoUpdateGoodreadsBookShelf {
            let connector = DSReaderHelperConnector(calibreServerService: calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: goodreadsSync)
            Task {
                do {
                    try await connector.removeFromShelf(goodreads_id: goodreadsId, shelfName: "currently-reading", book: book)
                } catch {
                    logger.error("Failed to remove book \(book.title) from Goodreads currently-reading shelf: \(error.localizedDescription)")
                }

                if let position = readingPositionRepository.getPosition(for: book, policy: .latestForDevice(container?.deviceName ?? "")), position.lastProgress > 99 {
                    do {
                        try await connector.addToShelf(goodreads_id: goodreadsId, shelfName: "read", book: book)
                    } catch {
                        logger.error("Failed to add book \(book.title) to Goodreads read shelf: \(error.localizedDescription)")
                    }
                }
            }
        }

        Task { @MainActor in
            container?.publishCalibreUpdate(.deleted(book.inShelfId))
        }
    }

    // MARK: - Cache Management

    @discardableResult
    func clearCache(inShelfId: String) -> BookFileRemovalResult {
        guard let book = booksInShelf[inShelfId] else {
            return .committed()
        }

        let cachedFormats = book.formats.filter { $1.cached }
        var outcome = BookFileRemovalResult.committed()
        for (key, _) in cachedFormats {
            guard let format = Format(rawValue: key) else { continue }
            guard let currentBook = booksInShelf[inShelfId] else { continue }
            let result = clearCache(book: currentBook, format: format)
            if !result.succeeded { return result }
            if result.cleanupPending { outcome = result }
        }
        return outcome
    }

    func addedCache(book: CalibreBook, format: Format) {
        guard var formatInfo = book.formats[format.rawValue] else { return }
        var newBook = book

        if let cacheInfo = getCacheInfo(book: newBook, format: format),
           let cacheMTime = cacheInfo.1 {
            logger.debug("cacheInfo: \(cacheInfo.0) \(cacheMTime) vs \(formatInfo.serverSize) \(formatInfo.serverMTime)")
            formatInfo.cached = true
            formatInfo.cacheSize = cacheInfo.0
            formatInfo.cacheMTime = cacheMTime
        } else {
            formatInfo.cached = false
            formatInfo.cacheSize = 0
            formatInfo.cacheMTime = .distantPast
        }

        newBook.formats[format.rawValue] = formatInfo
        newBook.lastUpdated = .init()

        updateBook(book: newBook)

        if format == Format.EPUB {
            removeFolioCache(book: newBook, format: format)
        }

        refreshShelfMetadataV2(with: [book.library.server.id], for: [book.inShelfId], serverReachableChanged: true)
    }

    @discardableResult
    func clearCache(book: CalibreBook, format: Format) -> BookFileRemovalResult {
        fileCommitLock.withLock {
            let current = bookRepository.getBook(id: book.inShelfId) ?? book
            guard let url = savedFileURL(book: current, format: format) else { return .fileFailed }
            if current.library.server.isLocal { return removeLocalFile(url, book: current, format: format) }

            guard removeCachedFile(book: current, format: format) else { return .fileFailed }
            let updated = clearingFormat(format, from: current)
            updateBook(book: updated)
            if updated.inShelf, !updated.formats.values.contains(where: \.cached) {
                removeFromShelf(inShelfId: updated.inShelfId)
            }
            return .committed()
        }
    }

    private func clearingFormat(_ format: Format, from book: CalibreBook) -> CalibreBook {
        var updated = book
        updated.formats[format.rawValue]?.cacheMTime = .distantPast
        updated.formats[format.rawValue]?.cacheSize = 0
        updated.formats[format.rawValue]?.cached = false
        updated.formats[format.rawValue]?.selected = nil
        updated.lastUpdated = Date()
        return updated
    }

    private func removeLocalFile(_ url: URL, book: CalibreBook, format: Format) -> BookFileRemovalResult {
        var workspace: URL?
        var backup: URL?
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let folder = try makeFileWorkspace(near: url)
                workspace = folder
                let saved = folder.appendingPathComponent("previous")
                try files.copy(url, saved)
                backup = saved
                try files.remove(url)
            }
        } catch {
            if !FileManager.default.fileExists(atPath: url.path), let backup,
               !restoreBackup(backup, to: url) {
                return .recoveryRequired(workspace?.lastPathComponent)
            }
            _ = cleanFileWorkspace(workspace)
            logger.error("Could not remove the local book file: \(error.localizedDescription)")
            return .fileFailed
        }

        var updated = clearingFormat(format, from: book)
        let deleted = !updated.formats.values.contains(where: \.cached)
        if deleted { updated.inShelf = false }
        do {
            try bookRepository.commitBookFiles(saving: deleted ? [] : [updated],
                                               deleting: deleted ? [book.inShelfId] : [])
        } catch {
            if let backup, !restoreBackup(backup, to: url) { return .recoveryRequired(workspace?.lastPathComponent) }
            _ = cleanFileWorkspace(workspace)
            return .storageFailed
        }
        if deleted { publishRemovedLocalBook(book) }
        else { publishSavedBook(updated) }
        return .committed(cleanupPending: !cleanFileWorkspace(workspace))
    }

    private func publishRemovedLocalBook(_ book: CalibreBook) {
        if readingBook?.inShelfId == book.inShelfId { readingBook?.inShelf = false }
        booksInShelf.removeValue(forKey: book.inShelfId)
        Task { @MainActor in container?.publishCalibreUpdate(.deleted(book.inShelfId)) }
    }

    /// The repository has already deleted these books. Cache cleanup must not save them again.
    @MainActor
    func discardShelfBooks(in libraryIDs: Set<String>) {
        let books = booksInShelf.values.filter { libraryIDs.contains($0.library.id) }
        for book in books {
            for (key, info) in book.formats where info.cached {
                if let format = Format(rawValue: key), !removeCachedFile(book: book, format: format) {
                    logger.error("File cleanup is pending after a committed library removal")
                }
            }
            if readingBook?.inShelfId == book.inShelfId { readingBook?.inShelf = false }
            booksInShelf.removeValue(forKey: book.inShelfId)
            container?.publishCalibreUpdate(.deleted(book.inShelfId))
        }
    }

    private func removeCachedFile(book: CalibreBook, format: Format) -> Bool {
        guard let url = savedFileURL(book: book, format: format) else { return false }
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try files.remove(url)
            } catch {
                logger.error("Failed to remove cached book file: \(error.localizedDescription)")
                return false
            }
        }
        return true
    }

    private func savedFileURL(book: CalibreBook, format: Format) -> URL? {
        if let localDirectory, book.library.server.isLocal {
            return book.formats[format.rawValue]?.filename.map { localDirectory.appendingPathComponent($0) }
        }
        return getSavedUrl(book: book, format: format)
    }

    func getCacheInfo(book: CalibreBook, format: Format) -> (UInt64, Date?)? {
        var resultStorage: ObjCBool = false
        guard let bookFileURL = getSavedUrl(book: book, format: format) else {
            return nil
        }

        if FileManager.default.fileExists(atPath: bookFileURL.path, isDirectory: &resultStorage),
           resultStorage.boolValue == false,
           let attribs = try? FileManager.default.attributesOfItem(atPath: bookFileURL.path) as NSDictionary {
            return (attribs.fileSize(), attribs.fileModificationDate())
        }

        return nil
    }

    // MARK: - Local File Imports

    func onOpenURL(url: URL, doMove: Bool, doOverwrite: Bool, asNew: Bool) -> BookImportInfo {
        fileCommitLock.withLock {
            importLocalFile(url, doMove: doMove, overwrite: doOverwrite, asNew: asNew)
        }
    }

    private func importLocalFile(_ source: URL, doMove: Bool, overwrite: Bool, asNew: Bool) -> BookImportInfo {
        var result = BookImportInfo(url: source, overwrite: overwrite, asNew: asNew)
        guard source.isFileURL else { return result.with(error: .protocolUnsupported) }
        guard !overwrite || !asNew else { return result.with(error: .invalidArg) }
        guard let library = container?.libraryManager.localLibrary,
              let base = container?.serverManager.documentServer?.localBaseUrl else {
            return result.with(error: .libraryAbsent)
        }
        guard let format = Format(rawValue: source.pathExtension.uppercased()), format != .UNKNOWN else {
            return result.with(error: .formatUnsupported)
        }

        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }

        let directory = localDirectory ?? base.appendingPathComponent(library.key, isDirectory: true)
        let name = source.deletingPathExtension().lastPathComponent
        var destination = directory.appendingPathComponent(name).appendingPathExtension(format.ext)
        let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL
        let destinationPath = destination.resolvingSymlinksInPath().standardizedFileURL
        let sourceIdentity = try? source.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        let destinationIdentity = try? destination.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        let sameFile = sourcePath == destinationPath || sourceIdentity?.isEqual(destinationIdentity) == true
        if sameFile, sourcePath.deletingLastPathComponent() == destinationPath.deletingLastPathComponent() {
            destination = source
        }
        guard let sourceId = calcLocalFileBookId(for: source) else { return result.with(error: .idCalcFail) }
        result.bookId = sourceId
        if let book = bookRepository.getBook(library: library, bookId: sourceId),
           book.inShelf, book.formats[format.rawValue]?.cached == true,
           let existing = savedFileURL(book: book, format: format),
           FileManager.default.fileExists(atPath: existing.path) {
            return result
        }

        if !sameFile, FileManager.default.fileExists(atPath: destination.path) {
            if asNew {
                guard let available = (1..<100).lazy.map({
                    directory.appendingPathComponent("\(name) (\($0))").appendingPathExtension(format.ext)
                }).first(where: { !FileManager.default.fileExists(atPath: $0.path) }) else {
                    return result.with(error: .tooManyFiles)
                }
                destination = available
            } else if !overwrite {
                return result.with(error: .destConflict)
            }
        }

        var workspace: URL?
        var keepBackup = false
        var backup: URL?
        var installed = false
        do {
            let input: URL
            if sameFile {
                input = source
            } else {
                let folder = try makeFileWorkspace(near: destination)
                workspace = folder
                let stage = folder.appendingPathComponent("incoming")
                // Keep the original available until both the destination and Realm have committed.
                try files.copy(source, stage)
                input = stage
            }

            guard let bookId = calcLocalFileBookId(for: input) else { throw ImportError.idCalcFail }
            result.bookId = bookId
            let preparedBook = try localBook(file: input, destination: destination, format: format,
                                             library: library, bookId: bookId)
            let previous = try bookRepository.localBooks(library: library, filename: destination.lastPathComponent,
                                                          format: format).filter { $0.id != bookId }
            if let workspace {
                if FileManager.default.fileExists(atPath: destination.path) {
                    guard overwrite else { throw ImportError.destConflict }
                    let saved = workspace.appendingPathComponent("previous")
                    try files.copy(destination, saved)
                    backup = saved
                    try files.replace(input, destination)
                } else {
                    try files.move(input, destination)
                }
                installed = true
            }

            let cleared = previous.map { clearingFormat(format, from: $0) }
            let removed = cleared.filter { !$0.formats.values.contains(where: \.cached) }
            let retained = cleared.filter { $0.formats.values.contains(where: \.cached) }
            do {
                try bookRepository.commitBookFiles(saving: [preparedBook] + retained,
                                                   deleting: Set(removed.map(\.inShelfId)))
            } catch {
                if installed {
                    if let backup {
                        keepBackup = !restoreBackup(backup, to: destination)
                    } else {
                        do {
                            guard let workspace else { throw ImportError.recoveryRequired }
                            try files.move(destination, workspace.appendingPathComponent("uncommitted"))
                        }
                        catch { keepBackup = true }
                    }
                }
                throw keepBackup ? ImportError.recoveryRequired : ImportError.loadMetaFail
            }

            for book in removed { publishRemovedLocalBook(book) }
            for book in retained { publishSavedBook(book) }
            publishSavedBook(preparedBook)
            if doMove && !sameFile {
                do { try files.remove(source) }
                catch {
                    logger.error("Imported the book, but could not remove its original: \(error.localizedDescription)")
                    result.cleanupPending = true
                }
            }
            let cleaned = cleanFileWorkspace(workspace)
            result.cleanupPending = result.cleanupPending || !cleaned
            enrichLocalBook(preparedBook, at: destination)
            return result
        } catch {
            logger.error("Could not commit the local import: \(error.localizedDescription)")
            if keepBackup {
                result.recoveryFolder = backup == nil ? nil : workspace?.lastPathComponent
            } else {
                result.cleanupPending = !cleanFileWorkspace(workspace)
            }
            if (error as? ImportError) != .destConflict { result.bookId = nil }
            return result.with(error: error as? ImportError ?? .fileOpFail)
        }
    }

    private func makeFileWorkspace(near destination: URL) throws -> URL {
        let folder = destination.deletingLastPathComponent()
            .appendingPathComponent(".dsreader-file-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func restoreBackup(_ backup: URL, to destination: URL) -> Bool {
        do {
            try files.replace(backup, destination)
            return true
        } catch {
            logger.error("Could not restore local book file. Recovery copy: \(backup.lastPathComponent, privacy: .public) in \(backup.deletingLastPathComponent().lastPathComponent, privacy: .public)")
            return false
        }
    }

    private func cleanFileWorkspace(_ workspace: URL?) -> Bool {
        guard let workspace else { return true }
        do {
            try files.remove(workspace)
            return true
        } catch {
            logger.error("Could not clean local file workspace: \(workspace.lastPathComponent, privacy: .public)")
            return false
        }
    }

    func calcLocalFileBookId(for fileURL: URL) -> Int32? {
        guard let digest = sha256new(for: fileURL) else { return nil }

        let bookId = Int32(bigEndian: digest.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        return bookId
    }

    func loadLocalLibraryBookMetadata(fileURL: URL, in library: CalibreLibrary, on server: CalibreServer, knownBookId: Int32? = nil) -> Int32? {
        fileCommitLock.withLock {
            guard let format = Format(rawValue: fileURL.pathExtension.uppercased()), format != .UNKNOWN,
                  let bookId = knownBookId ?? calcLocalFileBookId(for: fileURL) else { return nil }
            do {
                let book = try localBook(file: fileURL, destination: fileURL, format: format, library: library, bookId: bookId)
                try bookRepository.commitBookFiles(saving: [book], deleting: [])
                publishSavedBook(book)
                enrichLocalBook(book, at: fileURL)
                return bookId
            } catch {
                logger.error("Could not save local book metadata: \(error.localizedDescription)")
                return nil
            }
        }
    }

    private func localBook(file: URL, destination: URL, format: Format, library: CalibreLibrary, bookId: Int32) throws -> CalibreBook {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.uint64Value, size > 0,
              let modified = attributes[.modificationDate] as? Date else { throw ImportError.loadMetaFail }
        var book = bookRepository.getBook(library: library, bookId: bookId) ?? CalibreBook(id: bookId, library: library)
        book.title = destination.deletingPathExtension().lastPathComponent
        book.lastModified = Date()
        book.lastSynced = book.lastModified
        book.timestamp = max(book.timestamp, modified)
        book.formats[format.rawValue] = FormatInfo(filename: destination.lastPathComponent,
                                                  serverSize: size, serverMTime: modified, cached: true,
                                                  cacheSize: size, cacheMTime: modified)
        book.inShelf = true
        return book
    }

    private func enrichLocalBook(_ book: CalibreBook, at fileURL: URL) {
        #if canImport(R2Shared)
        let streamer = Streamer()
        streamer.open(asset: FileAsset(url: fileURL), allowUserInteraction: false) { [weak self] result in
            guard let self, let publication = try? result.get() else { return }
            let title = publication.metadata.title
            let cover = publication.cover?.pngData()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.fileCommitLock.withLock {
                    guard FileManager.default.fileExists(atPath: fileURL.path),
                          var current = self.bookRepository.getBook(id: book.inShelfId),
                          current.lastSynced == book.lastSynced else { return }
                    current.title = title
                    do {
                        try self.bookRepository.commitBookFiles(saving: [current], deleting: [])
                        self.publishSavedBook(current)
                        if let cover, let url = current.coverURL {
                            self.container?.coverCache.storeCoverData(cover, for: url)
                        }
                    } catch {
                        self.logger.error("Could not save publication enrichment: \(error.localizedDescription)")
                    }
                }
            }
        }
        #endif
    }

    // MARK: - Reading Prep & Navigation

    func prepareBookReading(book: CalibreBook) -> ReaderInfo {
        guard let sessionManager = container?.sessionManager else {
            fatalError("sessionManager is missing")
        }
        return sessionManager.prepareBookReading(book: book)
    }

    func goToPreviousBook() {
        // MARK: FIXME
    }

    func goToNextBook() {
        // MARK: FIXME
    }

    // MARK: - Remote Data & Sync

    @discardableResult
    @MainActor
    func getBooksMetadata(request: CalibreBooksMetadataRequest) async -> [Int32: BookMetadataRefreshResult] {
        // A long list, such as a large shelf's, goes in batches: calibre refuses a long request line.
        if request.books.count > CalibreServerService.booksMetadataBatchSize {
            var results = [Int32: BookMetadataRefreshResult]()
            for batch in request.books.chunks(size: CalibreServerService.booksMetadataBatchSize) {
                let batchResults = await getBooksMetadata(request: .init(library: request.library, books: batch, getAnnotations: request.getAnnotations))
                results.merge(batchResults) { _, new in new }
            }
            return results
        }

        container?.librarySyncStatus[request.library.id]?.isUpd = true
        defer { container?.librarySyncStatus[request.library.id]?.isUpd = false }
        let cancelled = Dictionary(uniqueKeysWithValues: Set(request.books).map { ($0, BookMetadataRefreshResult.cancelled) })
        guard !Task.isCancelled else { return cancelled }

        let books = request.books.map { bookId -> CalibreBook in
            let book = CalibreBook(id: bookId, library: request.library)
            if let book = self.booksInShelf[book.inShelfId] {
                return book
            }
            if let book = self.booksAnnotation[book.inShelfId] {
                return book
            }
            if request.getAnnotations,
               let book = self.getBook(for: book.inShelfId) {
                return book
            }
            return book
        }

        guard let calibreServerService = container?.calibreServerService else {
            return Dictionary(uniqueKeysWithValues: Set(request.books).map { ($0, .failed("Server unavailable")) })
        }

        var task = calibreServerService.buildBooksMetadataTask(library: request.library, books: books, getAnnotations: request.getAnnotations) ?? CalibreBooksTask(request: request)

        let fetchSignpost = AppPerformanceSignpost.begin("MetadataHTTPFetch", "Library: \(request.library.id), Books: \(books.count)")
        task = await calibreServerService.getBooksMetadata(task: task)

        if !Task.isCancelled, task.request.getAnnotations {
            task = await calibreServerService.getAnnotations(task: task)
        }

        var annotationCount = 0
        if let annotationsResult = task.booksAnnotationsEntry {
            for (_, entry) in annotationsResult {
                annotationCount += (entry.annotations_map.bookmark?.count ?? 0)
                annotationCount += (entry.annotations_map.highlight?.count ?? 0)
            }
        }
        AppPerformanceSignpost.end("MetadataHTTPFetch", fetchSignpost, "Library: \(request.library.id), Books: \(books.count), Annotations: \(annotationCount)")
        guard !Task.isCancelled else { return cancelled }

        let metadataPersistenceResult = await withCheckedContinuation { (continuation: CheckedContinuation<BookMetadataPersistenceResult, Never>) in
            DatabaseService.metadataWriteQueue.async {
                guard let entries = task.booksMetadataEntry,
                      let json = task.booksMetadataJSON else {
                    continuation.resume(returning: BookMetadataPersistenceResult())
                    return
                }

                let saveSignpost = AppPerformanceSignpost.begin("MetadataRealmSave", "Library: \(task.library.id), Books: \(task.books.count)")
                let result = self.bookRepository.persistMetadataEntries(
                    library: task.library,
                    bookIds: task.books,
                    entries: entries,
                    json: json,
                    includeAnnotationBooks: task.annotationsData != nil
                )
                AppPerformanceSignpost.end("MetadataRealmSave", saveSignpost, "Library: \(task.library.id), Books: \(task.books.count)")
                continuation.resume(returning: result)
            }
        }
        // Once queued, the GCD write completes even if its caller cancels. Reconcile its
        // committed values and publish the result before reporting cancellation, otherwise
        // a later shelf mutation can save an old snapshot over the refreshed metadata.
        task.booksUpdated.formUnion(metadataPersistenceResult.booksUpdated)
        task.booksDeleted.formUnion(metadataPersistenceResult.booksDeleted)
        task.booksInShelf.append(contentsOf: metadataPersistenceResult.booksInShelf)
        task.booksAnnotation.append(contentsOf: metadataPersistenceResult.booksAnnotation)

        task.booksInShelf.forEach { newBook in
            self.booksInShelf[newBook.inShelfId] = newBook
        }
        task.booksAnnotation.forEach { newBook in
            self.booksAnnotation[newBook.inShelfId] = newBook
        }

        if !Task.isCancelled, task.request.getAnnotations, let annotationsResult = task.booksAnnotationsEntry {
            var jobs = [BookMetadataSyncWorker.SyncJob]()

            for book in task.booksInShelf {
                for (formatKey, _) in book.formats {
                    guard let format = Format(rawValue: formatKey),
                          let entry = annotationsResult["\(book.id):\(formatKey)"]
                    else { continue }
                    jobs.append(
                        BookMetadataSyncWorker.SyncJob(
                            book: book,
                            format: format,
                            entry: entry,
                            needUpload: true
                        )
                    )
                }
            }

            for book in task.booksAnnotation {
                for (formatKey, _) in book.formats {
                    guard let format = Format(rawValue: formatKey),
                          let entry = annotationsResult["\(book.id):\(formatKey)"]
                    else { continue }
                    jobs.append(
                        BookMetadataSyncWorker.SyncJob(
                            book: book,
                            format: format,
                            entry: entry,
                            needUpload: false
                        )
                    )
                }
            }

            let outcome = await metadataSyncWorker.executeSync(jobs: jobs)
            if !Task.isCancelled {
                // Trigger uploads for positions
                for posUpload in outcome.positionsToUpload {
                    for pos in posUpload.entries {
                        do {
                            let setTask = try calibreServerService.buildSetLastReadPositionTask(
                                library: task.library,
                                bookId: posUpload.book.id,
                                format: posUpload.format,
                                entry: pos
                            )
                            Task {
                                await calibreServerService.setLastReadPositionByTask(task: setTask)
                            }
                        } catch {
                            logger.error("Failed to build set last read position task: \(error.localizedDescription)")
                        }
                    }
                }

                // Trigger uploads for annotations
                for annUpload in outcome.annotationsToUpload {
                    do {
                        let updateTask = try calibreServerService.buildUpdateAnnotationsTask(
                            library: task.library,
                            bookId: annUpload.book.id,
                            format: annUpload.format,
                            highlights: annUpload.highlights,
                            bookmarks: annUpload.bookmarks
                        )
                        Task {
                            await calibreServerService.updateAnnotationByTask(task: updateTask)
                        }
                    } catch {
                        logger.error("Failed to build update annotations task: \(error.localizedDescription)")
                    }
                }
            }
        }

        let booksHandled = task.booksUpdated.union(task.booksError).union(task.booksDeleted)

        recordMetadataAnswers(library: task.library, missing: task.booksDeleted, failed: task.booksError, present: task.booksUpdated)

        if !Task.isCancelled, task.booksError.isEmpty == false {
            let booksRetry = task.books.filter { booksHandled.contains($0) == false }

            if booksRetry.isEmpty == false {
                booksRetry.chunks(size: max(booksRetry.count / 16, 1)).forEach { chunk in
                    Task {
                        await self.getBooksMetadata(request: .init(library: task.library, books: chunk, getAnnotations: task.request.getAnnotations))
                    }
                }
            }
        }

        container?.librarySyncStatus[task.library.id]?.isUpd = false

        if request.books.count == 1, let bookId = request.books.first {
            // The main Realm may not have advanced to the background commit yet.
            // Publish the committed value already used to reconcile the shelf when available.
            let committedBook = task.booksInShelf.first { $0.id == bookId }
                ?? task.booksAnnotation.first { $0.id == bookId }
            if let book = committedBook ?? self.getBook(
                for: bookRepository.primaryKey(library: task.library, bookId: bookId)
            ) {
                await container?.publishCalibreUpdate(.book(book))
            }
        } else if !task.booksInShelf.isEmpty {
            await container?.publishCalibreUpdate(.shelf)
        }

        return Dictionary(uniqueKeysWithValues: Set(request.books).map { id in
            let result: BookMetadataRefreshResult
            if Task.isCancelled {
                result = .cancelled
            } else if task.booksDeleted.contains(id) {
                result = .unavailable
            } else if let error = task.error {
                if case .httpStatus(let status, _) = error {
                    result = .failed("The server could not refresh book details (HTTP \(status)). Please try again.")
                } else {
                    result = .failed(error.localizedDescription)
                }
            } else if task.booksUpdated.contains(id), !task.booksError.contains(id) {
                result = .updated
            } else {
                result = .failed("The server did not return this book's details.")
            }
            return (id, result)
        })
    }

    func getBook(for primaryKey: String) -> CalibreBook? {
        return bookRepository.getBook(id: primaryKey)
    }

    func bookExists(forPrimaryKey: String) -> Bool {
        return bookRepository.bookExists(id: forPrimaryKey)
    }

    /// Records what an `ajax/books` answer said about each book, for Settings to list:
    /// - `missing`: its entry came back null (`BookRepository.persistMetadataEntries`), as calibre
    ///   answers for a book it doesn't have and for one out of a restricted user's reach. Nothing
    ///   is deleted locally, as a shelf book's files and positions are still the user's.
    /// - `failed`: its entry couldn't be read.
    /// - `present`: its entry was read, which clears both.
    ///
    /// Browsing reports its answers here too (`LibrarySearchService`).
    @MainActor
    func recordMetadataAnswers(library: CalibreLibrary, missing: Set<Int32>, failed: Set<Int32> = [], present: Set<Int32>) {
        guard let container else { return }
        var status = container.librarySyncStatus[library.id] ?? .init(library: library)
        let previous = (status.del, status.err)
        status.del.subtract(present)
        status.del.formUnion(missing)
        status.err.subtract(present)
        status.err.formUnion(failed)
        guard (status.del, status.err) != previous else { return }
        container.librarySyncStatus[library.id] = status
    }

    // MARK: - Shelf Refresh

    /// Group the current shelf by library, filter by the given server / book
    /// ids, then fetch fresh metadata for each non-empty group. If the
    /// `serverReachableChanged` flag is set and no groups remain, send an
    /// empty `.shelf` update so observers re-render.
    func refreshShelfMetadataV2(with serverIds: Set<String> = [], for bookInShelfIds: Set<String> = [], serverReachableChanged: Bool) {
        let libraryBooks = booksInShelf.map { $0.value }
            .filter { serverIds.isEmpty || serverIds.contains($0.library.server.id) }
            .filter { bookInShelfIds.isEmpty || bookInShelfIds.contains($0.inShelfId) }
            .reduce(into: [CalibreLibrary: [CalibreBook]]()) { partialResult, book in
                guard let library = container?.calibreLibraries[book.library.id], !library.hidden else { return }
                partialResult[library, default: []].append(book)
            }

        if serverReachableChanged && libraryBooks.isEmpty {
            Task { @MainActor in
                container?.publishCalibreUpdate(.shelf)
            }
            return
        }

        libraryBooks.forEach { library, books in
            Task {
                await self.getBooksMetadata(
                    request: .init(library: library, books: books.map { $0.id }, getAnnotations: true)
                )
            }
        }
    }
}
