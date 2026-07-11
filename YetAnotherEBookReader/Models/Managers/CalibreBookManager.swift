//
//  CalibreBookManager.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/13.
//

import Foundation
import OSLog
import CryptoSwift

#if canImport(R2Shared)
import R2Shared
import R2Streamer
#endif

class CalibreBookManager {
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
        annotationRepository: AnnotationRepositoryProtocol? = nil
    ) {
        self.container = container
        self.databaseService = databaseService

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

    func booksInShelfSnapshots() -> AsyncStream<[String: CalibreBook]> {
        booksInShelfBroadcaster.stream(initialValue: booksInShelf)
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
                    try await connector.addToShelf(goodreads_id: goodreadsId, shelfName: "currently-reading")
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
                    try await connector.removeFromShelf(goodreads_id: goodreadsId, shelfName: "currently-reading")
                } catch {
                    logger.error("Failed to remove book \(book.title) from Goodreads currently-reading shelf: \(error.localizedDescription)")
                }

                if let position = readingPositionRepository.getPosition(for: book, policy: .latestForDevice(container?.deviceName ?? "")), position.lastProgress > 99 {
                    do {
                        try await connector.addToShelf(goodreads_id: goodreadsId, shelfName: "read")
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

    func clearCache(inShelfId: String) {
        guard let book = booksInShelf[inShelfId] else {
            return
        }

        let cachedFormats = book.formats.filter { $1.cached }
        for (key, _) in cachedFormats {
            guard let format = Format(rawValue: key) else { continue }
            guard let currentBook = booksInShelf[inShelfId] else { continue }
            clearCache(book: currentBook, format: format)
        }
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

    func clearCache(book: CalibreBook, format: Format) {
        guard let bookFileURL = getSavedUrl(book: book, format: format) else { return }

        if FileManager.default.fileExists(atPath: bookFileURL.path) {
            do {
                try FileManager.default.removeItem(at: bookFileURL)
            } catch {
                logger.error("clearCache \(error.localizedDescription)")
            }
        }
        var newBook = book

        newBook.formats[format.rawValue]?.cacheMTime = .distantPast
        newBook.formats[format.rawValue]?.cacheSize = 0
        newBook.formats[format.rawValue]?.cached = false
        newBook.formats[format.rawValue]?.selected = nil
        newBook.lastUpdated = .init()

        updateBook(book: newBook)

        if newBook.inShelf, newBook.formats.filter({ $1.cached }).isEmpty {
            removeFromShelf(inShelfId: newBook.inShelfId)
        }
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

    func onOpenURL(url: URL, doMove: Bool, doOverwrite: Bool, asNew: Bool, knownBookId: Int32? = nil) -> BookImportInfo {
        var bookImportInfo = BookImportInfo(url: url, bookId: nil, error: nil)

        guard let documentServer = container?.serverManager.documentServer,
              let localLibrary = container?.libraryManager.localLibrary,
              let localBaseUrl = documentServer.localBaseUrl else {
            return bookImportInfo.with(error: .libraryAbsent)
        }

        guard let format = Format(rawValue: url.pathExtension.uppercased()) else {
            return bookImportInfo.with(error: .formatUnsupported)
        }

        if url.isFileURL {
            let _ = url.startAccessingSecurityScopedResource()
            defer {
                url.stopAccessingSecurityScopedResource()
            }

            do {
                guard let bookId = knownBookId ?? calcLocalFileBookId(for: url) else { return bookImportInfo.with(error: .idCalcFail) }
                logger.debug("onOpenURL \(bookId)")
                bookImportInfo.bookId = bookId

                // check for identical file
                let bookForQuery = CalibreBook(id: bookId, library: localLibrary)
                if let book = booksInShelf[bookForQuery.inShelfId] {
                    let readerInfo = prepareBookReading(book: book)
                    if readerInfo.url.pathExtension.lowercased() == url.pathExtension.lowercased() {
                        return bookImportInfo
                    }
                }

                // check for dest file
                let basename = url.deletingPathExtension().lastPathComponent
                var dest = localBaseUrl.appendingPathComponent("Local Library", isDirectory: true).appendingPathComponent(basename, isDirectory: false).appendingPathExtension(format.ext)
                if FileManager.default.fileExists(atPath: dest.path) {
                    if !doOverwrite && !asNew {
                        return bookImportInfo.with(error: .destConflict)
                    }
                    if doOverwrite && asNew {
                        return bookImportInfo.with(error: .invalidArg)
                    }
                    if doOverwrite {
                        if let book = booksInShelf.filter (
                            {
                                guard $1.library.server.isLocal, let formatInfo = $1.formats[format.rawValue] else { return false }
                                return formatInfo.cached && formatInfo.filename == dest.lastPathComponent
                            }).first {
                            self.clearCache(book: book.value, format: format)   //should remove it from shelf
                        }
                    }
                    if asNew {
                        var found = false
                        for i in (1..<100) {
                            dest = localBaseUrl.appendingPathComponent("Local Library", isDirectory: true).appendingPathComponent("\(basename) (\(i))", isDirectory: false).appendingPathExtension(url.pathExtension.lowercased())
                            if FileManager.default.fileExists(atPath: dest.path) == false {
                                found = true
                                break
                            }
                        }
                        if !found {
                            return bookImportInfo.with(error: .tooManyFiles)
                        }
                    }
                }

                if doMove {
                    try FileManager.default.moveItem(at: url, to: dest)
                } else {
                    try FileManager.default.copyItem(at: url, to: dest)
                }

                if bookId == loadLocalLibraryBookMetadata(fileURL: dest, in: localLibrary, on: documentServer, knownBookId: bookId) {
                    return bookImportInfo
                } else {
                    return bookImportInfo.with(error: .loadMetaFail)
                }

            } catch {
                logger.error("onOpenURL \(error.localizedDescription)")
                return bookImportInfo.with(error: .fileOpFail)
            }
        }

        return bookImportInfo.with(error: .protocolUnsupported)
    }

    func calcLocalFileBookId(for fileURL: URL) -> Int32? {
        guard let digest = sha256new(for: fileURL) else { return nil }

        let bookId = Int32(bigEndian: digest.prefix(4).withUnsafeBytes{$0.load(as: Int32.self)})
        return bookId
    }

    func loadLocalLibraryBookMetadata(fileURL: URL, in library: CalibreLibrary, on server: CalibreServer, knownBookId: Int32? = nil) -> Int32? {
        guard let format = Format(rawValue: fileURL.pathExtension.uppercased()) else { return nil }

        guard let bookId = knownBookId ?? calcLocalFileBookId(for: fileURL) else { return nil }

        var book = CalibreBook(
            id: bookId,
            library: library
        )

        if let existingBook = bookRepository.getBook(library: library, bookId: book.id) {
            book = existingBook
        }

        book.title = fileURL.deletingPathExtension().lastPathComponent
        book.lastModified = Date()
        book.lastSynced = book.lastModified

        var formatInfo = FormatInfo(serverSize: 0, serverMTime: .distantPast, cached: true, cacheSize: 0, cacheMTime: .distantPast)
        formatInfo.filename = fileURL.lastPathComponent
        if let fileAttribs = try? FileManager.default.attributesOfItem(atPath: fileURL.path) {
            if let fileSize = fileAttribs[.size] as? NSNumber {
                formatInfo.serverSize = fileSize.uint64Value
                formatInfo.cacheSize = fileSize.uint64Value
            }
            if let fileTS = fileAttribs[.modificationDate] as? Date {
                formatInfo.serverMTime = fileTS
                formatInfo.cacheMTime = fileTS
                if book.timestamp < fileTS {
                    book.timestamp = fileTS
                }
            }
        }

        book.formats[format.rawValue] = formatInfo
        book.inShelf = true

        self.updateBook(book: book)

        #if canImport(R2Shared)
        let streamer = Streamer()
        streamer.open(asset: FileAsset(url: fileURL), allowUserInteraction: false) { result in
            guard let publication = try? result.get() else {
                self.logger.error("Failed to open local publication with streamer: \(fileURL.absoluteString)")
                return
            }

            book.title = publication.metadata.title
            if let cover = publication.cover, let coverData = cover.pngData(), let coverUrl = book.coverURL {
                container?.coverCache.storeCoverData(coverData, for: coverUrl)
            }

            self.updateBook(book: book)
        }
        #endif
        return bookId
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
    func getBooksMetadata(request: CalibreBooksMetadataRequest) async {
        container?.librarySyncStatus[request.library.id]?.isUpd = true

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

        guard let calibreServerService = container?.calibreServerService else { return }

        var task = calibreServerService.buildBooksMetadataTask(library: request.library, books: books, getAnnotations: request.getAnnotations) ?? CalibreBooksTask(request: request)

        let fetchSignpost = AppPerformanceSignpost.begin("MetadataHTTPFetch", "Library: \(request.library.id), Books: \(books.count)")
        task = await calibreServerService.getBooksMetadata(task: task)

        if task.request.getAnnotations {
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

        if task.request.getAnnotations, let annotationsResult = task.booksAnnotationsEntry {
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

        let booksHandled = task.booksUpdated.union(task.booksError).union(task.booksDeleted)

        container?.librarySyncStatus[task.library.id]?.upd.subtract(booksHandled)

        if task.booksError.isEmpty == false {
            container?.librarySyncStatus[task.library.id]?.err.formUnion(task.booksError)
            container?.librarySyncStatus[task.library.id]?.del.formUnion(task.booksDeleted)
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

        if request.books.count == 1 {
            if let book = self.getBook(
                for: bookRepository.primaryKey(library: task.library, bookId: task.request.books.first!)
               ) {
                await container?.publishCalibreUpdate(.book(book))
            }
        } else if !task.booksInShelf.isEmpty {
            await container?.publishCalibreUpdate(.shelf)
        }
    }

    func getBook(for primaryKey: String) -> CalibreBook? {
        return bookRepository.getBook(id: primaryKey)
    }

    func bookExists(forPrimaryKey: String) -> Bool {
        return bookRepository.bookExists(id: forPrimaryKey)
    }

    func removeDeleteBooksFromServer(server: CalibreServer) {
        guard let librarySyncStatus = container?.librarySyncStatus else { return }

        librarySyncStatus.filter {
             $0.value.library.server.id == server.id && $0.value.del.count > 0
        }.forEach { lss in
            container?.librarySyncStatus[lss.key]?.isSync = true
            var progress = 0
            let total = lss.value.del.count
            DispatchQueue.global(qos: .userInitiated).async {
                Array(lss.value.del).chunks(size: 100).forEach { chunk in
                    self.bookRepository.deleteBooks(library: lss.value.library, ids: chunk)
                    progress += chunk.count
                    DispatchQueue.main.async {
                        self.container?.librarySyncStatus[lss.key]?.msg = "Removing deleted \(progress) / \(total)"
                    }
                }

                DispatchQueue.main.async {
                    self.container?.librarySyncStatus[lss.key]?.del.removeAll()
                    self.container?.librarySyncStatus[lss.key]?.isSync = false
                    self.container?.librarySyncStatus[lss.key]?.msg = nil
                    self.container?.serverManager.probeServersReachability(with: [server.id], updateLibrary: false, autoUpdateOnly: true, incremental: false)
                }
            }
        }
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
                if partialResult[book.library] == nil {
                    partialResult[book.library] = []
                }
                partialResult[book.library]?.append(book)
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
