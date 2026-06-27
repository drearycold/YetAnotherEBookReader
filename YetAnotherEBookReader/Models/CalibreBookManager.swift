//
//  CalibreBookManager.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/13.
//

import Foundation
import Combine
import RealmSwift
import SwiftUI
import OSLog
import Kingfisher
import CryptoSwift

#if canImport(R2Shared)
import R2Shared
import R2Streamer
#endif

class CalibreBookManager: ObservableObject {
    private let logger = Logger(subsystem: "YetAnotherEBookReader", category: "CalibreBookManager")

    weak var container: AppContainerProtocol?
    let databaseService: DatabaseService

    @Published var booksInShelf = [String: CalibreBook]()
    @Published var booksAnnotation = [String: CalibreBook]()

    @Published var selectedBookId: String? = nil {
        didSet {
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
            guard let resolver = container ?? AppContainer.shared else {
                fatalError("LibraryResolver must be available if no repository is provided")
            }
            self.bookRepository = RealmBookRepository(databaseService: databaseService, libraryResolver: resolver)
        }

        if let repo = readingPositionRepository {
            self.readingPositionRepository = repo
        } else {
            self.readingPositionRepository = RealmReadingPositionRepository(databaseService: databaseService, container: container)
        }

        if let repo = annotationRepository {
            self.annotationRepository = repo
        } else {
            self.annotationRepository = RealmAnnotationRepository(databaseService: databaseService)
        }
    }

    private func getRealm() -> Realm? {
        if Thread.isMainThread {
            return databaseService.realm
        } else if let conf = databaseService.realmConf {
            return try? Realm(configuration: conf)
        }
        return nil
    }

    // MARK: - Initialization & Realm Sync

    func populateBookShelf() {
        let books = bookRepository.getAllBooksInShelf()
        books.forEach { book in
            var updatedBook = book
            updatedBook.formats.forEach { formatRaw, formatInfo in
                guard let format = Format(rawValue: formatRaw) else {
                    return
                }
                var formatInfoNew = formatInfo
                if let cacheInfo = getCacheInfo(book: updatedBook, format: format),
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
                    self.updateBook(book: updatedBook)
                }
            }

            self.booksInShelf[updatedBook.inShelfId] = updatedBook
            print("booksInShelfRealm \(updatedBook.inShelfId)")
        }
    }

    // MARK: - Realm Converters

    func convert(bookRealm: CalibreBookRealm) -> CalibreBook? {
        guard let library = queryLibrary(for: bookRealm) else { return nil }
        return convert(library: library, bookRealm: bookRealm)
    }

    func convert(library: CalibreLibrary, bookRealm: CalibreBookRealm) -> CalibreBook {
        return bookRealm.toDomain(library: library)
    }

    func queryLibrary(for bookRealm: CalibreBookRealm) -> CalibreLibrary? {
        guard let serverUUID = bookRealm.serverUUID,
              let libraryName = bookRealm.libraryName
        else { return nil }

        return container?.calibreLibraries[CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName)]
    }

    func getBookRealm(forPrimaryKey: String) -> CalibreBookRealm? {
        return bookRepository.getBookRealm(id: forPrimaryKey)
    }

    // MARK: - Realm CRUD

    func updateBook(book: CalibreBook) {
        bookRepository.saveBook(book)

        if readingBook?.inShelfId == book.inShelfId {
            readingBook = book
        }
        if book.inShelf {
            booksInShelf[book.inShelfId] = book
        }
    }

    func queryBookRealm(book: CalibreBook, realm: Realm) -> CalibreBookRealm? {
        let key = CalibreBookRealm.PrimaryKey(serverUUID: book.library.server.uuid.uuidString, libraryName: book.library.name, id: book.id.description)
        return bookRepository.getBookRealm(id: key)
    }

    func updateBookRealm(book: CalibreBook, realm: Realm) {
        bookRepository.saveBook(book)
    }

    func removeFromRealm(book: CalibreBook) {
        let key = CalibreBookRealm.PrimaryKey(serverUUID: book.library.server.uuid.uuidString, libraryName: book.library.name, id: book.id.description)
        removeFromRealm(for: key)
    }

    func removeFromRealm(for primaryKey: String) {
        bookRepository.deleteBook(id: primaryKey)
    }

    // MARK: - Shelf Management

    func shouldAutoUpdateGoodreads(library: CalibreLibrary) -> (CalibreServerDSReaderHelper, CalibreDSReaderHelperPrefs.Options, CalibreGoodreadsSyncPrefs.PluginPrefs)? {
        guard let serverManager = container?.serverManager else { return nil }

        // must have dsreader helper info and enabled by server
        guard let dsreaderHelperServer = serverManager.queryServerDSReaderHelper(server: library.server), dsreaderHelperServer.port > 0 else { return nil }
        guard let configuration = dsreaderHelperServer.configuration, let dsreader_helper_prefs = configuration.dsreader_helper_prefs, dsreader_helper_prefs.plugin_prefs.Options.goodreadsSyncEnabled else { return nil }

        // check if user disabled auto update
        let dsreaderHelperLibrary = library.pluginDSReaderHelperWithDefault
        guard dsreaderHelperLibrary.isEnabled else { return nil }

        // check if profile name exists
        let goodreadsSync = library.pluginGoodreadsSyncWithDefault
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

        container?.calibreUpdatedSubject.send(.book(book))
    }

    func removeFromShelf(inShelfId: String) {
        if readingBook?.inShelfId == inShelfId {
            readingBook?.inShelf = false
        }

        guard var book = booksInShelf[inShelfId] else { return }
        book.inShelf = false

        guard let realm = getRealm() else { return }
        updateBookRealm(book: book, realm: realm)

        booksInShelf.removeValue(forKey: inShelfId)

        if readingPositionRepository.getPositions(forBookId: book.bookPrefId).first?.id == container?.deviceName,
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

                if let position = readingPositionRepository.getPosition(forBookId: book.bookPrefId, deviceName: container?.deviceName ?? ""), position.lastProgress > 99 {
                    do {
                        try await connector.addToShelf(goodreads_id: goodreadsId, shelfName: "read")
                    } catch {
                        logger.error("Failed to add book \(book.title) to Goodreads read shelf: \(error.localizedDescription)")
                    }
                }
            }
        }

        container?.calibreUpdatedSubject.send(.deleted(book.inShelfId))
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
            print("cacheInfo: \(cacheInfo.0) \(cacheInfo.1!) vs \(formatInfo.serverSize) \(formatInfo.serverMTime)")
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
                print("onOpenURL \(bookId)")
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
                print("onOpenURL \(error)")
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

        guard let realm = getRealm() else { return nil }
        if let bookRealm = queryBookRealm(book: book, realm: realm) {
            book = convert(library: library, bookRealm: bookRealm)
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
                print("Streamer \(fileURL)")
                return
            }

            book.title = publication.metadata.title
            if let cover = publication.cover, let coverData = cover.pngData(), let coverUrl = book.coverURL, let kfImageCache = container?.kfImageCache {
                kfImageCache.storeToDisk(coverData, forKey: coverUrl.absoluteString)
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

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            AppContainer.SaveBooksMetadataRealmQueue.async {
                guard let entries = task.booksMetadataEntry,
                      let json = task.booksMetadataJSON,
                      let realmSaveBooksMetadata = self.container?.realmSaveBooksMetadata else {
                    continuation.resume()
                    return
                }

                let serverUUID = task.library.server.uuid.uuidString
                let libraryName = task.library.name
                let saveSignpost = AppPerformanceSignpost.begin("MetadataRealmSave", "Library: \(task.library.id), Books: \(task.books.count)")
                try? realmSaveBooksMetadata.write {
                    task.books.map {
                        (
                            obj: realmSaveBooksMetadata.object(
                                ofType: CalibreBookRealm.self,
                                forPrimaryKey: CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName, id: $0.description)
                            ),
                            entry: entries[$0.description],
                            root: json[$0.description] as? NSDictionary
                        )
                    }.forEach {
                        guard let obj = $0.obj else { return }

                        if let entryOptional = $0.entry, let entry = entryOptional, let root = $0.root {
                            calibreServerService.handleLibraryBookOne(library: task.library, bookRealm: obj, entry: entry, root: root)
                            task.booksUpdated.insert(obj.idInLib)
                            if obj.inShelf {
                                task.booksInShelf.append(self.convert(library: task.library, bookRealm: obj))
                            } else if task.annotationsData != nil {
                                task.booksAnnotation.append(self.convert(library: task.library, bookRealm: obj))
                            }
                        } else {
                            // null data, treat as deleted, update lastSynced to lastModified to prevent further actions
                            obj.lastSynced = obj.lastModified
                            task.booksDeleted.insert(obj.idInLib)
                        }
                    }
                }
                AppPerformanceSignpost.end("MetadataRealmSave", saveSignpost, "Library: \(task.library.id), Books: \(task.books.count)")
                continuation.resume()
            }
        }

        task.booksInShelf.forEach { newBook in
            self.booksInShelf[newBook.inShelfId] = newBook
            container?.calibreUpdatedSubject.send(.book(newBook))
        }
        task.booksAnnotation.forEach { newBook in
            self.booksAnnotation[newBook.inShelfId] = newBook
        }

        if task.request.getAnnotations, let annotationsResult = task.booksAnnotationsEntry {
            for book in task.booksInShelf {
                for (formatKey, _) in book.formats {
                    guard let format = Format(rawValue: formatKey),
                          let entry = annotationsResult["\(book.id):\(formatKey)"]
                    else { continue }

                    let positions = readingPositionRepository.syncPositions(entries: entry.last_read_positions, forBookId: book.bookPrefId)
                    for pos in positions {
                        do {
                            let setTask = try calibreServerService.buildSetLastReadPositionTask(library: task.library, bookId: book.id, format: format, entry: pos)
                            Task {
                                await calibreServerService.setLastReadPositionByTask(task: setTask)
                            }
                        } catch {
                            logger.error("Failed to build set last read position task: \(error.localizedDescription)")
                        }
                    }

                    if annotationRepository.syncHighlights(entries: entry.annotations_map.highlight ?? [], forBookId: book.bookPrefId) > 0 || annotationRepository.syncBookmarks(entries: entry.annotations_map.bookmark ?? [], forBookId: book.bookPrefId) > 0 {
                        do {
                            let updateTask = try calibreServerService.buildUpdateAnnotationsTask(
                                 library: task.library,
                                 bookId: book.id,
                                 format: format,
                                 highlights: annotationRepository.getHighlights(forBookId: book.bookPrefId, excludeRemoved: false).compactMap { $0.toCalibreBookAnnotationHighlightEntry() },
                                 bookmarks: annotationRepository.getBookmarks(forBookId: book.bookPrefId, excludeRemoved: true).map { $0.toCalibreBookAnnotationBookmarkEntry() }
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

            for book in task.booksAnnotation {
                for (formatKey, _) in book.formats {
                    guard let _ = Format(rawValue: formatKey),
                          let entry = annotationsResult["\(book.id):\(formatKey)"]
                    else { continue }

                    _ = readingPositionRepository.syncPositions(entries: entry.last_read_positions, forBookId: book.bookPrefId)
                    _ = annotationRepository.syncHighlights(entries: entry.annotations_map.highlight ?? [], forBookId: book.bookPrefId)
                    _ = annotationRepository.syncBookmarks(entries: entry.annotations_map.bookmark ?? [], forBookId: book.bookPrefId)
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

        if request.books.count == 1,
           let book = self.getBook(
            for: CalibreBookRealm.PrimaryKey(
                serverUUID: task.library.server.uuid.uuidString,
                libraryName: task.library.name,
                id: task.request.books.first!.description
            )
           ) {
            container?.calibreUpdatedSubject.send(.book(book))
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
                guard let realmConf = self.databaseService.realmConf,
                      let realm = try? Realm(configuration: realmConf) else { return }

                try? realm.write {
                    lss.value.del.forEach { id in
                        if progress % 100 == 0 {
                            DispatchQueue.main.async {
                                self.container?.librarySyncStatus[lss.key]?.msg = "Removing deleted \(progress) / \(total)"
                            }
                        }

                        let primaryKey = CalibreBookRealm.PrimaryKey(
                            serverUUID: lss.value.library.server.uuid.uuidString,
                            libraryName: lss.value.library.name,
                            id: id.description)

                        if let object = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey) {
                            realm.delete(object)
                        }
                        progress += 1
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
        let libraryBooks = booksInShelf.values
            .filter { serverIds.isEmpty || serverIds.contains($0.library.server.id) }
            .filter { bookInShelfIds.isEmpty || bookInShelfIds.contains($0.inShelfId) }
            .reduce(into: [CalibreLibrary: [CalibreBook]]()) { partialResult, book in
                if partialResult[book.library] == nil {
                    partialResult[book.library] = []
                }
                partialResult[book.library]?.append(book)
            }

        if serverReachableChanged && libraryBooks.isEmpty {
            container?.calibreUpdatedSubject.send(.shelf)
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
