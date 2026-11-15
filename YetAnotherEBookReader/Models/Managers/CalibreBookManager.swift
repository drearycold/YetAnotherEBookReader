//
//  CalibreBookManager.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/13.
//

import Foundation
import OSLog

class CalibreBookManager {
    private let files: LocalBookFileOperations
    private let localDirectory: URL?
    private let localImports: LocalBookImportCoordinator
    private let localCoverCache: BookCoverCaching?
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
    @MainActor private lazy var refreshCoordinator = BookRefreshCoordinator(database: databaseService) { [weak self] library, id in
        self?.booksInShelf[CalibreBook.identity(library: library, bookId: id)] != nil
    } updateBusy: { [weak self] id, busy in
        guard let container = self?.container, let library = container.calibreLibraries[id] else { return }
        var status = container.librarySyncStatus[id] ?? .init(library: library)
        guard status.isUpd != busy else { return }
        status.isUpd = busy
        container.librarySyncStatus[id] = status
    }

    init(
        container: AppContainerProtocol? = nil,
        databaseService: DatabaseService = .shared,
        bookRepository: BookRepositoryProtocol? = nil,
        readingPositionRepository: ReadingPositionRepositoryProtocol? = nil,
        annotationRepository: AnnotationRepositoryProtocol? = nil,
        files: LocalBookFileOperations = .live(),
        localDirectory: URL? = nil,
        localImports: LocalBookImportCoordinator? = nil,
        localCoverCache: BookCoverCaching? = nil
    ) {
        self.container = container
        self.databaseService = databaseService
        self.files = files
        self.localDirectory = localDirectory
        self.localCoverCache = localCoverCache ?? container?.coverCache

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

        self.localImports = localImports ?? LocalBookImportCoordinator(repository: self.bookRepository, files: files,
                                                       loadMetadata: LocalPublicationMetadata.load)
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
    @MainActor
    func clearCache(inShelfId: String) async -> BookFileRemovalResult {
        guard let book = booksInShelf[inShelfId] else { return .committed() }
        if book.library.server.isLocal {
            guard container?.libraryManager.localFileAccessNotice(for: book) == nil else { return .storageFailed }
            guard let scope = localImportScope(), scope.library.id == book.library.id else { return .storageFailed }
            return await localImports.remove(bookID: inShelfId, scope: scope, publish: localFilePublisher,
                                             coverCache: localCoverCache)
        }

        var outcome = BookFileRemovalResult.committed()
        for (key, info) in book.formats where info.cached {
            guard let format = Format(rawValue: key), let currentBook = booksInShelf[inShelfId] else { continue }
            let result = clearCache(book: currentBook, format: format)
            if !result.succeeded { return result }
            if result.cleanupPending { outcome = result }
        }
        return outcome
    }

    @MainActor
    func addedCache(book: CalibreBook, format: Format) {
        var newBook = bookRepository.getBook(id: book.inShelfId) ?? book
        guard var formatInfo = newBook.formats[format.rawValue] else { return }

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
        let current = bookRepository.getBook(id: book.inShelfId) ?? book
        guard !current.library.server.isLocal, removeCachedFile(book: current, format: format) else {
            return .fileFailed
        }
        let updated = current.clearingCachedFormat(format)
        updateBook(book: updated)
        if updated.inShelf, !updated.formats.values.contains(where: \.cached) {
            removeFromShelf(inShelfId: updated.inShelfId)
        }
        return .committed()
    }

    @MainActor
    private var localFilePublisher: LocalBookImportCoordinator.Publish {
        { [weak self] changes in self?.publishLocalFileChanges(changes) }
    }

    @MainActor
    private func publishLocalFileChanges(_ changes: LocalBookImportCoordinator.Changes) {
        guard !changes.removedIDs.isEmpty || !changes.savedBooks.isEmpty else { return }
        databaseService.refreshMainRealm()
        for id in changes.removedIDs {
            guard bookRepository.getBook(id: id)?.inShelf != true else { continue }
            if let url = booksInShelf[id]?.coverURL { localCoverCache?.removeCover(for: url) }
            if readingBook?.inShelfId == id { readingBook?.inShelf = false }
            booksInShelf.removeValue(forKey: id)
            container?.publishCalibreUpdate(.deleted(id))
        }
        for snapshot in changes.savedBooks {
            guard let book = bookRepository.getBook(id: snapshot.inShelfId) else { continue }
            publishSavedBook(book)
            container?.publishCalibreUpdate(.book(book))
        }
    }

    /// The repository has already deleted these books. Cache cleanup must not save them again.
    @MainActor
    func discardShelfBooks(in libraryIDs: Set<String>) {
        let books = booksInShelf.values.filter { libraryIDs.contains($0.library.id) }
        booksAnnotation = booksAnnotation.filter { !libraryIDs.contains($0.value.library.id) }
        var localPaths = Set<URL>()
        for book in books {
            if book.library.server.isLocal, let cover = book.coverURL { localCoverCache?.removeCover(for: cover) }
            for (key, info) in book.formats where info.cached {
                guard let format = Format(rawValue: key) else { continue }
                if book.library.server.isLocal {
                    if let url = savedFileURL(book: book, format: format) { localPaths.insert(url) }
                } else if !removeCachedFile(book: book, format: format) {
                    logger.error("File cleanup is pending after a committed library removal")
                }
            }
            if readingBook?.inShelfId == book.inShelfId { readingBook?.inShelf = false }
            booksInShelf.removeValue(forKey: book.inShelfId)
            container?.publishCalibreUpdate(.deleted(book.inShelfId))
        }
        localImports.cleanupRemovedLibraryFiles(localPaths)
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

    // MARK: - Local Files

    @MainActor
    func importBook(_ request: LocalBookImportRequest) async -> BookImportInfo {
        var result = BookImportInfo(request: request)
        guard request.url.isFileURL else { return result.with(error: .protocolUnsupported) }
        guard !request.overwrite || !request.asNew else { return result.with(error: .invalidArg) }
        // An external Files URL can arrive before the startup worker has established the library.
        let accessed = request.url.startAccessingSecurityScopedResource()
        defer { if accessed { request.url.stopAccessingSecurityScopedResource() } }
        if let libraryManager = container?.libraryManager, libraryManager.startupScan.isPending {
            for await pending in libraryManager.startupScanChanges() where !pending { break }
            guard !Task.isCancelled else { return result.with(error: .cancelled) }
        }
        guard let scope = localImportScope() else { return result.with(error: .libraryAbsent) }
        return await localImports.run(request, scope: scope, publish: localFilePublisher,
                                      coverCache: localCoverCache)
    }

    @discardableResult
    @MainActor
    func scanLocalBooks() async -> LocalBookImportCoordinator.ScanResult? {
        guard let scope = localImportScope() else { return nil }
        return await localImports.scan(scope: scope, publish: localFilePublisher, coverCache: localCoverCache)
    }

    @MainActor
    func removeLocalFile(book: CalibreBook, format: Format) async -> BookFileRemovalResult {
        guard let scope = localImportScope(), scope.library.id == book.library.id else { return .storageFailed }
        return await localImports.remove(bookID: book.inShelfId, format: format, scope: scope, publish: localFilePublisher,
                                         coverCache: localCoverCache)
    }

    @MainActor
    func isCurrentImportResult(_ info: BookImportInfo) -> Bool {
        guard let databaseID = info.databaseID else { return true }
        guard let scope = localImportScope() else { return false }
        return scope.databaseID == databaseID && scope.library.id == info.libraryID
    }

    @MainActor
    func importedBook(for info: BookImportInfo) -> CalibreBook? {
        databaseService.refreshMainRealm()
        guard info.error == nil, let id = info.bookId, let scope = localImportScope(),
              scope.databaseID == info.databaseID, scope.library.id == info.libraryID,
              let format = Format(rawValue: info.url.pathExtension.uppercased()),
              let book = bookRepository.getBook(library: scope.library, bookId: id), book.inShelf,
              book.formats[format.rawValue]?.cached == true,
              let file = savedFileURL(book: book, format: format),
              FileManager.default.isReadableFile(atPath: file.path)
        else { return nil }
        return book
    }

    @MainActor
    private func localImportScope() -> LocalBookImportCoordinator.Scope? {
        guard let container, let library = container.libraryManager.localLibrary,
              let current = container.libraryManager.calibreLibraries[library.id],
              !current.hidden, current.server.isLocal,
              let server = container.serverManager.documentServer, server.id == current.server.id, !server.removed,
              container.serverManager.calibreServers[server.id]?.removed == false,
              let base = server.localBaseUrl, let database = databaseService.cacheConfigurationSnapshot,
              let lifetime = try? container.calibreServerService.cacheLifetime(for: current)
        else { return nil }

        let directory = localDirectory ?? base.appendingPathComponent(current.key, isDirectory: true)
        let storage = LocalBookStorageScope(library: current, database: database, lifetime: lifetime)
        return LocalBookImportCoordinator.Scope(storage: storage, directory: directory,
                                               databaseChanges: { [databaseService] in databaseService.cacheConfigurationChanges() },
                                               libraryChanges: { [weak container] in
            container?.libraryManager.librarySnapshots(bufferingPolicy: .bufferingNewest(1)) ?? AsyncStream { $0.finish() }
        }, serverChanges: { [weak container] in
            container?.serverManager.serverSnapshots() ?? AsyncStream { $0.finish() }
        }, isCurrent: { [weak container, weak databaseService] in
            guard let container, databaseService?.cacheConfigurationSnapshot?.id == database.id,
                  (try? lifetime.checkCurrent()) != nil,
                  container.libraryManager.localLibrary?.id == current.id,
                  let server = container.serverManager.documentServer, server.id == current.server.id, !server.removed,
                  container.serverManager.calibreServers[server.id]?.removed == false else { return false }
            return true
        })
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

    @MainActor
    func bookRefreshUpdates() -> AsyncStream<BookRefreshCoordinator.State> {
        refreshCoordinator.updates()
    }

    @MainActor
    func cancelBookRefreshes() {
        refreshCoordinator.cancelAll()
    }

    @discardableResult
    @MainActor
    func getBooksMetadata(request: CalibreBooksMetadataRequest) async -> [Int32: BookMetadataRefreshResult] {
        var seen = Set<Int32>()
        let ids = request.books.filter { seen.insert($0).inserted }
        guard !ids.isEmpty else { return [:] }
        if Task.isCancelled { return metadataResults(ids, .cancelled) }

        do {
            let (scope, work) = try prepareBookRefresh(request, ids: ids)
            guard let task = refreshCoordinator.start(scope: scope, ids: ids, work: work) else {
                return metadataResults(ids, .failed("Book sync is busy. Please try again."))
            }
            return await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
        } catch {
            return metadataResults(ids, metadataFailure(error))
        }
    }

    @MainActor
    private func prepareBookRefresh(_ request: CalibreBooksMetadataRequest, ids: [Int32])
        throws -> (BookMetadataRefreshScope, BookRefreshCoordinator.Refresh) {
        guard let container else { throw CalibreAPIError.serverUnreachable }
        guard let library = container.calibreLibraries[request.library.id], !library.server.isLocal else {
            throw CacheContextError.superseded
        }
        let service = container.calibreServerService
        guard let lifetime = try service.cacheLifetime(for: library) else { throw CacheContextError.superseded }
        guard let source = service.getServerUrlByReachability(server: library.server), source.isHTTP else {
            throw CalibreAPIError.serverUnreachable
        }
        let scope = try bookRepository.prepareMetadataRefresh(
            library: library, source: source, bookIDs: ids, lifetime: lifetime)
        refreshCoordinator.observe(libraries: container.libraryManager.librarySnapshots(bufferingPolicy: .bufferingNewest(1)))
        let getAnnotations = request.getAnnotations
        return (scope, { [weak self] id, scope, ids in
            guard let self else { return [:] }
            return await self.runBookRefresh(ids, operation: id, scope: scope, service: service,
                                             getAnnotations: getAnnotations)
        })
    }

    @MainActor
    private func runBookRefresh(_ ids: [Int32], operation: UUID, scope: BookMetadataRefreshScope,
                                service: CalibreServerService, getAnnotations: Bool) async -> [Int32: BookMetadataRefreshResult] {
        var results: [Int32: BookMetadataRefreshResult] = [:]
        for batch in ids.chunks(size: CalibreServerService.booksMetadataBatchSize) {
            let batchResults = await refreshMetadataBatch(batch, operation: operation, scope: scope, service: service,
                                                          getAnnotations: getAnnotations)
            results.merge(batchResults) { _, new in new }
        }
        return results
    }

    @MainActor
    private func refreshMetadataBatch(_ ids: [Int32], operation: UUID, scope: BookMetadataRefreshScope, service: CalibreServerService,
                                      getAnnotations: Bool) async -> [Int32: BookMetadataRefreshResult] {
        if (try? scope.checkCurrent(in: databaseService)) == nil { return metadataResults(ids, .superseded) }
        if Task.isCancelled { return metadataResults(ids, .cancelled) }
        let library = scope.library
        let requestedBooks: [Int32: CalibreBook]
        do {
            requestedBooks = try bookRepository.metadataRefreshBooks(scope, bookIDs: ids)
        } catch {
            return metadataResults(ids, metadataFailure(error))
        }

        let books = ids.compactMap { requestedBooks[$0] }
        var results = metadataResults(ids, .localBookMissing)
        guard !books.isEmpty else { return results }
        let bookIDs = books.map(\.id)
        guard let request = service.buildBooksMetadataTask(
            library: library, books: books, getAnnotations: getAnnotations, serverURL: scope.source)
        else { return results.merging(metadataResults(bookIDs, .failed("Invalid book refresh URL."))) { _, new in new } }

        let fetch = AppPerformanceSignpost.begin("MetadataHTTPFetch", "Library: \(library.id), Books: \(books.count)")
        let repository = bookRepository
        let task = await fetchMetadata(for: request, operation: operation, scope: scope, service: service)
        AppPerformanceSignpost.end("MetadataHTTPFetch", fetch, "Library: \(library.id), Books: \(books.count)")
        do {
            try bookRepository.checkMetadataRefresh(scope, bookID: nil)
        } catch {
            return metadataResults(ids, metadataFailure(error))
        }
        if Task.isCancelled { return metadataResults(ids, .cancelled) }
        let payload = task.metadataAnswers
        // A queued transaction is independent of caller cancellation. Its
        // committed values still have to reach the shelf and observers.
        if Task.isCancelled { return metadataResults(ids, .cancelled) }
        do {
            let persisted = try await withCheckedThrowingContinuation { continuation in
                DatabaseService.metadataWriteQueue.async {
                    let save = AppPerformanceSignpost.begin("MetadataRealmSave", "Library: \(library.id), Books: \(bookIDs.count)")
                    defer { AppPerformanceSignpost.end("MetadataRealmSave", save, "Library: \(library.id), Books: \(bookIDs.count)") }
                    continuation.resume(with: Result {
                        try repository.persistMetadataEntries(scope: scope, bookIDs: bookIDs, answers: payload)
                    })
                }
            }
            let current = try bookRepository.metadataRefreshBooks(scope, bookIDs: bookIDs)
            try scope.checkCurrent(in: databaseService)
            let syncIDs = reconcileMetadataRefresh(library: library, ids: bookIDs, persisted: persisted,
                current: current, fetchError: task.error, includeAnnotations: getAnnotations, results: &results)

            if !Task.isCancelled, getAnnotations, !syncIDs.isEmpty {
                await syncRefreshedBookAnnotations(syncIDs, operation: operation, scope: scope, service: service)
            }
        } catch {
            let failure = metadataFailure(error)
            if failure == .superseded { return metadataResults(ids, failure) }
            results.merge(metadataResults(bookIDs, failure)) { _, new in new }
        }
        if Task.isCancelled, (try? scope.checkCurrent(in: databaseService)) != nil {
            return metadataResults(ids, .cancelled)
        }
        return results
    }

    @MainActor
    private func reconcileMetadataRefresh(
        library: CalibreLibrary, ids: [Int32], persisted: [Int32: BookMetadataPersistenceResult],
        current: [Int32: CalibreBook], fetchError: CalibreAPIError?, includeAnnotations: Bool,
        results: inout [Int32: BookMetadataRefreshResult]
    ) -> [Int32] {
        var present = Set<Int32>()
        var missing = Set<Int32>()
        var failed = Set<Int32>()
        var updated = [CalibreBook]()
        var retainedShelfChanged = false
        var syncIDs = [Int32]()

        for id in ids {
            guard let book = current[id] else {
                results[id] = .localBookMissing
                continue
            }
            switch persisted[id] {
            case .updated(let committed):
                results[id] = .updated
                if book.lastUpdated == committed.lastUpdated && book.lastModified == committed.lastModified {
                    present.insert(id)
                }
                updated.append(book)
                syncIDs.append(id)
            case .unchanged(let confirmed):
                results[id] = .unchanged
                if let confirmed, book.lastUpdated == confirmed.lastUpdated, book.lastModified == confirmed.lastModified {
                    present.insert(id)
                }
                retainedShelfChanged = retainedShelfChanged || shelfSnapshotChanged(for: book)
                syncIDs.append(id)
            case .unavailable(let committed):
                if book.lastUpdated == committed.lastUpdated && book.lastModified == committed.lastModified {
                    missing.insert(id)
                    results[id] = .unavailable
                } else {
                    results[id] = .superseded
                }
            case .unanswered:
                failed.insert(id)
                results[id] = fetchError.map { metadataFailure($0) } ?? .failed("The server did not return this book's details.")
                continue
            case .invalid:
                failed.insert(id)
                results[id] = .failed("The server returned invalid details for this book.")
                continue
            case .localBookMissing:
                results[id] = .localBookMissing
                continue
            case .superseded, nil:
                results[id] = .superseded
                continue
            }

            if readingBook?.inShelfId == book.inShelfId { readingBook = book }
            if book.inShelf {
                booksInShelf[book.inShelfId] = book
                if booksAnnotation[book.inShelfId] != nil { booksAnnotation.removeValue(forKey: book.inShelfId) }
            } else {
                booksInShelf.removeValue(forKey: book.inShelfId)
                if includeAnnotations || booksAnnotation[book.inShelfId] != nil {
                    booksAnnotation[book.inShelfId] = book
                }
            }
        }

        recordMetadataAnswers(library: library, missing: missing, failed: failed, present: present)
        if ids.count == 1, let book = updated.first {
            container?.publishCalibreUpdate(.book(book))
        } else if retainedShelfChanged || updated.contains(where: \.inShelf) {
            container?.publishCalibreUpdate(.shelf)
        }
        return syncIDs
    }

    @MainActor
    private func shelfSnapshotChanged(for book: CalibreBook) -> Bool {
        guard let previous = booksInShelf[book.inShelfId] else { return book.inShelf }
        let previousAuthors = previous.authors.isEmpty ? ["Unknown"] : previous.authors
        let authors = book.authors.isEmpty ? ["Unknown"] : book.authors
        return !book.inShelf || previous.title != book.title || previousAuthors.prefix(3) != authors.prefix(3)
            || previous.lastModified != book.lastModified || previous.lastUpdated != book.lastUpdated
            || previous.coverURL != book.coverURL || previous.formats != book.formats
    }

    @MainActor
    private func syncRefreshedBookAnnotations(_ ids: [Int32], operation: UUID, scope: BookMetadataRefreshScope,
                                              service: CalibreServerService) async {
        guard let latest = try? bookRepository.metadataRefreshBooks(scope, bookIDs: ids),
              !latest.isEmpty,
              let task = service.buildBooksMetadataTask(library: scope.library, books: Array(latest.values),
                                                        getAnnotations: true, serverURL: scope.source) else { return }
        let repository = bookRepository
        let readSequence = refreshCoordinator.beginAnnotationRead()
        let response = await service.getAnnotations(task: task, timeout: CalibreServerService.bookRefreshTimeout, checkCurrent: {
            try repository.checkMetadataRefresh(scope, bookID: nil)
        })
        guard !Task.isCancelled, (try? repository.checkMetadataRefresh(scope, bookID: nil)) != nil else { return }
        refreshCoordinator.record(operation) {
            if response.annotationsError == nil { $0.annotationReads += 1 }
            else { $0.annotationFailures += 1 }
        }
        guard let entries = response.booksAnnotationsEntry, !entries.isEmpty else { return }

        let jobs = latest.values.flatMap { book in
            book.formats.keys.compactMap { key -> BookMetadataSyncWorker.SyncJob? in
                guard let format = Format(rawValue: key),
                      let entry = entries["\(book.id):\(key)"] ?? entries["\(book.id):\(key.lowercased())"] else { return nil }
                return .init(book: book, format: format, entry: entry, needUpload: book.inShelf)
            }
        }
        let outcome = await metadataSyncWorker.executeSync(jobs: jobs, refresh: (scope, repository))
        let changedIDs = latest.values.filter { outcome.changedPositionShelfIDs.contains($0.inShelfId) }.map(\.id)
        if !changedIDs.isEmpty,
           let current = try? repository.metadataRefreshBooks(scope, bookIDs: changedIDs),
           current.values.contains(where: \.inShelf) {
            container?.publishCalibreUpdate(.shelf)
        }
        refreshCoordinator.record(operation) {
            $0.localMerges += outcome.mergedJobs
            $0.localMergeFailures += outcome.failedJobs
            $0.localMergeSkips += outcome.skippedJobs
        }
        guard !Task.isCancelled else { return }
        enqueueRefreshUploads(outcome, operation: operation, scope: scope, service: service, readSequence: readSequence)
    }

    @MainActor
    private func fetchMetadata(for request: CalibreBooksTask, operation: UUID, scope: BookMetadataRefreshScope,
                               service: CalibreServerService) async -> CalibreBooksTask {
        let repository = bookRepository
        let checkCurrent = { try repository.checkMetadataRefresh(scope, bookID: nil) }
        let initial = await service.getBooksMetadata(task: request, timeout: CalibreServerService.bookRefreshTimeout,
                                                     checkCurrent: checkCurrent)
        guard initial.error?.allowsBookRefreshRetry == true, !Task.isCancelled else { return initial }
        refreshCoordinator.record(operation) { $0.waitingToRetry = true }
        defer { refreshCoordinator.record(operation) { $0.waitingToRetry = false } }
        do {
            // One retry for a transient failure of this read-only GET.
            try await Task.sleep(nanoseconds: 300_000_000)
            try Task.checkCancellation()
            let remaining = try repository.metadataRefreshBooks(scope, bookIDs: request.books)
            guard remaining.count == request.books.count else { return initial }
        } catch {
            return initial
        }
        refreshCoordinator.record(operation) {
            $0.waitingToRetry = false
            $0.retries += 1
        }
        return await service.getBooksMetadata(task: request, timeout: CalibreServerService.bookRefreshTimeout,
                                             checkCurrent: checkCurrent)
    }

    @MainActor
    private func enqueueRefreshUploads(_ outcome: BookMetadataSyncWorker.SyncOutcome, operation: UUID,
                                       scope: BookMetadataRefreshScope, service: CalibreServerService, readSequence: UInt64) {
        var uploadsByBook: [Int32: [RefreshUpload]] = [:]
        for upload in outcome.positionsToUpload {
            let entries = upload.entries.filter {
                let reader = BookDeviceReadingPosition(entry: $0).flatMap { ReaderType(rawValue: $0.readerName) }
                return reader == nil || reader == .UNSUPPORTED || reader?.format == upload.format
            }
            let grouped = Dictionary(grouping: entries, by: \.device)
            for device in grouped.keys.sorted() {
                if let newest = grouped[device]?.max(by: { $0.epoch < $1.epoch }) {
                    uploadsByBook[upload.book.id, default: []].append(
                        .position(upload.book, upload.format, newest))
                }
            }
        }
        for upload in outcome.annotationsToUpload {
            uploadsByBook[upload.book.id, default: []].append(.annotations(upload))
        }

        let repository = bookRepository
        let positions = readingPositionRepository
        refreshCoordinator.enqueue(uploadsByBook.map { bookID, uploads in
            .init(lane: .init(serverID: scope.library.server.id, libraryKey: scope.library.key, bookID: bookID),
                  count: uploads.count, readSequence: readSequence) { lifetime in
                var results: [BookRefreshCoordinator.Delivery] = []
                for (index, upload) in uploads.enumerated() {
                    let delivery = await Self.deliverRefreshUpload(upload, scope: scope, service: service,
                                                                   repository: repository, positions: positions,
                                                                   lifetime: lifetime)
                    results.append(delivery)
                    if case .uncertainTransport = delivery {
                        results += Array(repeating: .discarded, count: uploads.count - index - 1)
                        break
                    }
                }
                return results
            }
        }, for: operation)
    }

    private enum RefreshUpload {
        case position(CalibreBook, Format, CalibreBookLastReadPositionEntry)
        case annotations(BookMetadataSyncWorker.SyncOutcome.UploadAnnotations)

        var target: (CalibreBook, Format) {
            switch self {
            case .position(let book, let format, _): return (book, format)
            case .annotations(let upload): return (upload.book, upload.format)
            }
        }
    }

    @MainActor
    private static func deliverRefreshUpload(_ upload: RefreshUpload, scope: BookMetadataRefreshScope,
                                              service: CalibreServerService, repository: BookRepositoryProtocol,
                                              positions: ReadingPositionRepositoryProtocol,
                                              lifetime: CacheLibraryLifetime) async -> BookRefreshCoordinator.Delivery {
        let (book, format) = upload.target
        let checkCurrent = {
            try Task.checkCancellation()
            try lifetime.checkCurrent()
            guard let current = try repository.metadataRefreshBooks(scope, bookIDs: [book.id])[book.id],
                  current.inShelf, current.formats[format.rawValue]?.cached == true else {
                throw CacheContextError.superseded
            }
            if case .position(_, _, let candidate) = upload {
                // Compare our original reading epochs and snapshot, not Calibre's
                // transport-generated epoch. The request may have waited behind a POST.
                let latest = positions.getPositions(for: current).filter {
                    guard $0.id == candidate.device else { return false }
                    let reader = ReaderType(rawValue: $0.readerName)
                    return reader == nil || reader == .UNSUPPORTED || reader?.format == format
                }
                    .max { $0.epoch < $1.epoch }?.toEntry()
                guard latest?.epoch == candidate.epoch, latest?.cfi == candidate.cfi,
                      latest?.pos_frac == candidate.pos_frac else { throw CacheContextError.superseded }
            }
        }
        do {
            try checkCurrent()
            let error: CalibreAPIError?
            switch upload {
            case .position(_, let format, let entry):
                let task = try service.buildSetLastReadPositionTask(library: scope.library, bookId: book.id,
                    format: format, entry: entry, serverURL: scope.source)
                error = await service.setLastReadPositionByTask(task: task, timeout: CalibreServerService.bookRefreshTimeout,
                                                               checkCurrent: checkCurrent).error
            case .annotations(let upload):
                let task = try service.buildUpdateAnnotationsTask(library: scope.library, bookId: book.id,
                    format: format, highlights: upload.highlights, bookmarks: upload.bookmarks, serverURL: scope.source)
                error = await service.updateAnnotationByTask(task: task, timeout: CalibreServerService.bookRefreshTimeout,
                                                            checkCurrent: checkCurrent).error
            }
            return Self.deliveryResult(error)
        } catch CacheContextError.superseded {
            return .discarded
        } catch is CancellationError {
            return .discarded
        } catch {
            return .rejected
        }
    }

    private static func deliveryResult(_ error: CalibreAPIError?) -> BookRefreshCoordinator.Delivery {
        switch error {
        case nil: return .uploaded
        case .authFailed, .serverRejected: return .rejected
        case .httpStatus(let status, _) where (400..<500).contains(status): return .rejected
        case .unknown(let underlying) where underlying is CacheContextError || underlying is CancellationError:
            return .discarded
        case .transport: return .uncertainTransport
        default:
            // A timed-out or interrupted POST may already have changed Calibre.
            // Another explicit sync reads the server before deciding what to send.
            return .uncertain
        }
    }

    private func metadataResults(_ ids: [Int32], _ result: BookMetadataRefreshResult) -> [Int32: BookMetadataRefreshResult] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, result) })
    }

    private func metadataFailure(_ error: Error) -> BookMetadataRefreshResult {
        switch error {
        case CacheContextError.superseded:
            return .superseded
        case BookMetadataStorageError.unavailable:
            return .failed("Book storage is unavailable. Please try again.")
        case let error as CalibreAPIError:
            if case .httpStatus(let status, _) = error {
                return .failed("The server could not refresh book details (HTTP \(status)). Please try again.")
            }
            return .failed(error.localizedDescription)
        default:
            logger.error("Metadata persistence failed: \(error.localizedDescription)")
            return .failed("Could not save book details. Please try again.")
        }
    }

    func getBook(for primaryKey: String) -> CalibreBook? {
        return bookRepository.getBook(id: primaryKey)
    }

    func bookExists(forPrimaryKey: String) -> Bool {
        return bookRepository.bookExists(id: forPrimaryKey)
    }

    /// Records what an `ajax/books` answer said about each book, for Settings to list:
    /// - `missing`: its entry came back null, as calibre
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
        status.err.subtract(present.union(missing))
        status.err.formUnion(failed)
        guard (status.del, status.err) != previous else { return }
        container.librarySyncStatus[library.id] = status
    }

    // MARK: - Shelf Refresh

    /// Group the current shelf by library, filter by the given server / book
    /// ids, then fetch fresh metadata for each non-empty group. If the
    /// `serverReachableChanged` flag is set and no groups remain, send an
    /// empty `.shelf` update so observers re-render.
    @MainActor
    func refreshShelfMetadataV2(with serverIds: Set<String> = [], for bookInShelfIds: Set<String> = [], serverReachableChanged: Bool) {
        let libraryBooks = booksInShelf.map { $0.value }
            .filter { serverIds.isEmpty || serverIds.contains($0.library.server.id) }
            .filter { bookInShelfIds.isEmpty || bookInShelfIds.contains($0.inShelfId) }
            .reduce(into: [CalibreLibrary: [CalibreBook]]()) { partialResult, book in
                guard let library = container?.calibreLibraries[book.library.id], !library.hidden else { return }
                partialResult[library, default: []].append(book)
            }

        if serverReachableChanged && libraryBooks.isEmpty {
            container?.publishCalibreUpdate(.shelf)
            return
        }

        for (library, books) in libraryBooks.sorted(by: { $0.key.id < $1.key.id }) {
            let ids = books.map(\.id).sorted()
            if let (scope, work) = try? prepareBookRefresh(.init(library: library, books: ids, getAnnotations: true), ids: ids) {
                refreshCoordinator.scheduleShelf(scope: scope, work: work)
            }
        }
    }
}
