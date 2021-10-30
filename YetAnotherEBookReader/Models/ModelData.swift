//
//  ModelData.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/25.
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

final class ModelData: ObservableObject {
    @Published var deviceName = UIDevice.current.name
    
    @Published var calibreServers = [String: CalibreServer]()
    @Published var calibreServerInfo: CalibreServerInfo?
    @Published var calibreServerInfoStaging = [String: CalibreServerInfo]()
    
    @Published var currentCalibreServerId = "" {
        didSet {
            guard oldValue != currentCalibreServerId else { return }
            
            UserDefaults.standard.set(currentCalibreServerId, forKey: Constants.KEY_DEFAULTS_SELECTED_SERVER_ID)
            
            currentBookId = 0
            filteredBookList.removeAll()
            calibreServerLibraryBooks.removeAll()
            
            guard let server = calibreServers[currentCalibreServerId] else { return }
            
            let tmpLastLibrary = CalibreLibrary(server: server, key: server.lastLibrary, name: server.lastLibrary)
            if let library = calibreLibraries[tmpLastLibrary.id] {
                currentCalibreLibraryId = library.id
                return
            }
            
            let tmpDefaultLibrary = CalibreLibrary(server: server, key: server.defaultLibrary, name: server.defaultLibrary)
            
            if let library = calibreLibraries[tmpDefaultLibrary.id] {
                currentCalibreLibraryId = library.id
                return
            }
            
            let serverLibraryIDs = calibreLibraries.compactMap {
                guard $0.value.server.id == server.id else { return nil }
                return $0.key
            } as [String]
            currentCalibreLibraryId = serverLibraryIDs.first ?? "Empty Server"
            
        }
    }
    var currentCalibreServer: CalibreServer? {
        calibreServers[currentCalibreServerId]
    }
    
    @Published var calibreLibraries = [String: CalibreLibrary]()
    @Published var currentCalibreLibraryId = "" {
        didSet {
            guard oldValue != currentCalibreLibraryId else { return }
            
            guard let library = calibreLibraries[currentCalibreLibraryId] else { return }
            guard var server = calibreServers[currentCalibreServerId] else { return }
            
            server.lastLibrary = library.name
            try? updateServerRealm(server: server)
            
            UserDefaults.standard.set(currentCalibreLibraryId, forKey: Constants.KEY_DEFAULTS_SELECTED_LIBRARY_ID)
            
            calibreServerLibraryUpdating = true
            currentBookId = 0
            filteredBookList.removeAll()
            calibreServerLibraryBooks.removeAll()
            DispatchQueue.global(qos: .utility).async { [self] in
                let realm = try! Realm(configuration: realmConf)
                populateServerLibraryBooks(realm: realm)
                updateFilteredBookList()
                
                DispatchQueue.main.sync {
                    calibreServerLibraryUpdating = false
                    //currentBookId = self.filteredBookList.first ?? 0
                }
            }
        }
    }
    var currentCalibreLibrary: CalibreLibrary? {
        calibreLibraries[currentCalibreLibraryId]
    }
    var currentCalibreServerLibraries: [CalibreLibrary] {
        calibreLibraries.values.filter { $0.server.id == currentCalibreServerId }
    }
    
    /// Used for server level activities
    @Published var calibreServerUpdating = false
    @Published var calibreServerUpdatingStatus: String? = nil
    
    /// Used for library level activities
    @Published var calibreServerLibraryUpdating = false
    @Published var calibreServerLibraryUpdatingProgress = 0
    @Published var calibreServerLibraryUpdatingTotal = 0
    
    @Published var calibreServerLibraryBooks = [Int32: CalibreBook]()
    
    @Published var activeTab = 0
    var documentServer: CalibreServer?
    var localLibrary: CalibreLibrary?
    
    //for LibraryInfoView
    @Published var defaultFormat = Format.PDF
    var formatReaderMap = [Format: [ReaderType]]()
    var formatList = [Format]()
    
    @Published var searchString = "" {
        didSet {
            if searchString != oldValue {
                updateFilteredBookList()
            }
        }
    }
    @Published var filterCriteriaRating = Set<String>() {
        didSet {
            if filterCriteriaRating != oldValue {
                updateFilteredBookList()
            }
        }
    }
    
    @Published var filterCriteriaFormat = Set<String>() {
        didSet {
            if filterCriteriaFormat != oldValue {
                updateFilteredBookList()
            }
        }
    }
    @Published var filterCriteriaIdentifier = Set<String>() {
        didSet {
            if filterCriteriaIdentifier != oldValue {
                updateFilteredBookList()
            }
        }
    }
    @Published var filterCriteriaShelved = FilterCriteriaShelved.none {
        didSet {
            if filterCriteriaShelved != oldValue {
                updateFilteredBookList()
            }
        }
    }
    @Published var filterCriteriaSeries = Set<String>() {
        didSet {
            if filterCriteriaSeries != oldValue {
                updateFilteredBookList()
            }
        }
    }
    
    @Published var filteredBookList = [Int32]()
    
    @Published var booksInShelf = [String: CalibreBook]()
    let booksRefreshedPublisher = NotificationCenter.default.publisher(
        for: .YABR_BooksRefreshed
    ).eraseToAnyPublisher()
    
    let readingBookRemovedFromShelfPublisher = NotificationCenter.default.publisher(
        for: .YABR_ReadingBookRemovedFromShelf
    ).eraseToAnyPublisher()
    
    let bookImportedPublisher = NotificationCenter.default.publisher(
        for: .YABR_BookImported
    ).eraseToAnyPublisher()
    
    let dismissAllPublisher = NotificationCenter.default.publisher(
        for: .YABR_DismissAll
    ).eraseToAnyPublisher()
    
    var presentingStack = [Binding<Bool>]()
    
    var currentBookId: Int32 = -1 {
        didSet {
            self.selectedBookId = currentBookId
        }
    }

    @Published var selectedBookId: Int32? = nil {
        didSet {
            guard let selectedBookId = selectedBookId else { return }
            self.readingBook = self.calibreServerLibraryBooks[selectedBookId]
        }
    }
    
    @Published var selectedPosition = ""
    @Published var updatedReadingPosition = BookDeviceReadingPosition(id: UIDevice().name, readerName: "")
    
    var readingBookInShelfId: String? = nil {
        didSet {
            guard let readingBookInShelfId = readingBookInShelfId else {
                readingBook = nil
                return
            }
            if readingBook?.inShelfId != readingBookInShelfId {
                readingBook = booksInShelf[readingBookInShelfId]
            }
            if readingBook != nil {
                readerInfo = prepareBookReading(book: readingBook!)
            }
        }
    }
    @Published var readingBook: CalibreBook? = nil {
        didSet {
            guard let readingBook = readingBook else {
                self.selectedPosition = ""
                return
            }
            
            if let position = getDeviceReadingPosition(book: readingBook) {
                self.selectedPosition = position.id
            } else if let position = getLatestReadingPosition(book: readingBook) {
                self.selectedPosition = position.id
            } else {
                let pair = defaultReaderForDefaultFormat(book: readingBook)
                self.selectedPosition = getInitialReadingPosition(book: readingBook, format: pair.0, reader: pair.1).id
            }
        }
    }
    
    @Published var readerInfo: ReaderInfo? = nil
    
    @Published var presentingEBookReaderFromShelf = false
        
    @Published var loadLibraryResult = "Waiting"
    
    @Published var updatingMetadata = false {
        didSet {
            if updatingMetadata {
                updatingMetadataSucceed = false
                updatingMetadataStatus = "Updating"
            }
        }
    }
    @Published var updatingMetadataStatus = "" {
        didSet {
            if updatingMetadataStatus == "Success" || updatingMetadataStatus == "Deleted" {
                updatingMetadataSucceed = true
            }
        }
    }
    @Published var updatingMetadataSucceed = false
    
    private var defaultLog = Logger()
    
    static var RealmSchemaVersion:UInt64 = 1
    private var realm: Realm!
    private var realmConf: Realm.Configuration!
    
    let kfImageCache = ImageCache.default
    var authResponsor = AuthResponsor()
    
    lazy var downloadService = BookFormatDownloadService(modelData: self)
    @Published var activeDownloads: [URL: BookFormatDownload] = [:]

    lazy var calibreServerService = CalibreServerService(modelData: self)
    
    var calibreServiceCancellable: AnyCancellable?
    var shelfRefreshCancellable: AnyCancellable?
    
    @Published var userFontInfos = [String: FontInfo]()

    var resourceFileDictionary: NSDictionary?

    init(mock: Bool = false) {
        //Load content of Info.plist into resourceFileDictionary dictionary
        if let path = Bundle.main.path(forResource: "Info", ofType: "plist") {
            resourceFileDictionary = NSDictionary(contentsOfFile: path)
        }
        
        ModelData.RealmSchemaVersion = UInt64(resourceFileDictionary?.value(forKey: "CFBundleVersion") as? String ?? "1") ?? 1
        realmConf = Realm.Configuration(
            schemaVersion: ModelData.RealmSchemaVersion
        )
        realm = try! Realm(
            configuration: realmConf
        )
        
        if let applicationSupportURL = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            realmConf.fileURL = applicationSupportURL.appendingPathComponent("default.realm")
            if let documentDirectoryURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
                let existingRealmURL = documentDirectoryURL.appendingPathComponent("default.realm")
                if FileManager.default.fileExists(atPath: existingRealmURL.path) {
                    try? FileManager.default.moveItem(at: existingRealmURL, to: realmConf.fileURL!)
                }
            }
        }
        
        kfImageCache.diskStorage.config.expiration = .never
        KingfisherManager.shared.defaultOptions = [.requestModifier(AuthPlugin(modelData: self))]
        ImageDownloader.default.authenticationChallengeResponder = authResponsor
        
        let serversCached = realm.objects(CalibreServerRealm.self).sorted(by: [SortDescriptor(keyPath: "username"), SortDescriptor(keyPath: "baseUrl")])
        serversCached.forEach { serverRealm in
            guard serverRealm.baseUrl != nil else { return }
            let calibreServer = CalibreServer(
                name: serverRealm.name ?? serverRealm.baseUrl!,
                baseUrl: serverRealm.baseUrl!,
                publicUrl: serverRealm.publicUrl ?? "",
                username: serverRealm.username ?? "",
                password: serverRealm.password ?? "",
                defaultLibrary: serverRealm.defaultLibrary ?? "",
                lastLibrary: serverRealm.lastLibrary ?? ""
            )
            calibreServers[calibreServer.id] = calibreServer
            
            if calibreServer.username.isEmpty == false && calibreServer.password.isEmpty == false {
                if let url = URL(string: calibreServer.baseUrl), let host = url.host, let port = url.port {
                    var authMethod = NSURLAuthenticationMethodDefault
                    if url.scheme == "http" {
                        authMethod = NSURLAuthenticationMethodHTTPDigest
                    }
                    if url.scheme == "https" {
                        authMethod = NSURLAuthenticationMethodHTTPBasic
                    }
                    let protectionSpace = URLProtectionSpace.init(host: host,
                                                                  port: port,
                                                                  protocol: url.scheme,
                                                                  realm: "calibre",
                                                                  authenticationMethod: authMethod)
                    let userCredential = URLCredential(user: calibreServer.username,
                                                       password: calibreServer.password,
                                                       persistence: .permanent)
                    URLCredentialStorage.shared.set(userCredential, for: protectionSpace)
                }
                if let url = URL(string: calibreServer.publicUrl), let host = url.host, let port = url.port {
                    var authMethod = NSURLAuthenticationMethodDefault
                    if url.scheme == "http" {
                        authMethod = NSURLAuthenticationMethodHTTPDigest
                    }
                    if url.scheme == "https" {
                        authMethod = NSURLAuthenticationMethodHTTPBasic
                    }
                    let protectionSpace = URLProtectionSpace.init(host: host,
                                                                  port: port,
                                                                  protocol: url.scheme,
                                                                  realm: "calibre",
                                                                  authenticationMethod: authMethod)
                    let userCredential = URLCredential(user: calibreServer.username,
                                                       password: calibreServer.password,
                                                       persistence: .permanent)
                    URLCredentialStorage.shared.set(userCredential, for: protectionSpace)
                }
            }
        }
        
        if let lastServerId = UserDefaults.standard.string(forKey: Constants.KEY_DEFAULTS_SELECTED_SERVER_ID), calibreServers[lastServerId] != nil {
            currentCalibreServerId = lastServerId
        }
        
        populateLibraries()
        
        if currentCalibreLibraryId.isEmpty == false {
            DispatchQueue(label: "data").async {
                let realm = try! Realm(configuration: self.realmConf)
                self.populateServerLibraryBooks(realm: realm)
            }
        }
        
        populateBookShelf()
        
        populateLocalLibraryBooks()
        
        switch UIDevice.current.userInterfaceIdiom {
            case .phone:
                defaultFormat = Format.EPUB
            case .pad:
                defaultFormat = Format.PDF
            default:
                defaultFormat = Format.EPUB
        }
        
        formatReaderMap[Format.EPUB] = [ReaderType.YabrEPUB, ReaderType.ReadiumEPUB]
        formatReaderMap[Format.PDF] = [ReaderType.YabrPDF, ReaderType.ReadiumPDF]
        formatReaderMap[Format.CBZ] = [ReaderType.ReadiumCBZ]

        downloadService.modelData = self
        
        self.reloadCustomFonts()
        
        if mock {
            let library = calibreLibraries.first!.value
            
            var readPos = BookReadingPosition()
            readPos.updatePosition("Mock Device", BookDeviceReadingPosition(id: "Mock Device", readerName: ReaderType.YabrEPUB.rawValue, maxPage: 99, lastReadPage: 1, lastReadChapter: "Mock Last Chapter", lastChapterProgress: 5, lastProgress: 1, furthestReadPage: 98, furthestReadChapter: "Mock Furthest Chapter", lastPosition: [1,1,1]))
            
            self.readingBook = CalibreBook(
                id: 1,
                library: library,
                title: "Mock Title",
                authors: ["Mock Author", "Mock Auther 2"],
                comments: "<p>Mock Comment",
                publisher: "Mock Publisher",
                series: "Mock Series",
                rating: 8,
                size: 12345678,
                pubDate: Date.init(timeIntervalSince1970: TimeInterval(1262275200)),
                timestamp: Date.init(timeIntervalSince1970: TimeInterval(1262275200)),
                lastModified: Date.init(timeIntervalSince1970: TimeInterval(1577808000)),
                tags: ["Mock"],
                formats: ["EPUB" : FormatInfo(
                            filename: "file:///mock",
                            serverSize: 123456,
                            serverMTime: Date.init(timeIntervalSince1970: TimeInterval(1577808000)),
                            cached: false, cacheSize: 123456,
                            cacheMTime: Date.init(timeIntervalSince1970: TimeInterval(1577808000))
                )],
                readPos: readPos,
                identifiers: [:],
                inShelf: true,
                inShelfName: "Default")
            self.booksInShelf[self.readingBook!.inShelfId] = self.readingBook
        }
    }
    
    func importCustomFonts(urls: [URL]) -> [CFArray]? {
        guard let documentDirectory = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        else { return nil }
        
        let fontsDirectory = documentDirectory.appendingPathComponent("Fonts",  isDirectory: true)
        guard let _ = try? FileManager.default.createDirectory(atPath: fontsDirectory.path, withIntermediateDirectories: true, attributes: nil) else { return nil }
    
        var fontDescriptorArrays = [CFArray]()

        urls.forEach { url in
            guard let ctFontDescriptorArray = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
            else { return }
            
            let fontDestFile = fontsDirectory.appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.moveItem(atPath: url.path, toPath: fontDestFile.path)
                fontDescriptorArrays.append(ctFontDescriptorArray)
            } catch {
                print("importCustomFonts \(error.localizedDescription)")
            }
        }
        
        return fontDescriptorArrays
    }
    
    func removeCustomFonts(at offsets: IndexSet) {
        let list = userFontInfos.sorted {
            ( $0.value.displayName ?? $0.key) < ( $1.value.displayName ?? $1.key)
        }
        let candidates = offsets.map { list[$0] }
        candidates.forEach { (fontId, fontInfo) in
            guard let fileURL = fontInfo.fileURL else { return }
            try? FileManager.default.removeItem(atPath: fileURL.path)
        }
    }
    
    func reloadCustomFonts() {
        if let userFontDescriptors = loadUserFonts() {
            self.userFontInfos = userFontDescriptors.mapValues { FontInfo(descriptor: $0) }
        } else {
            self.userFontInfos.removeAll()
        }
        
    }
    
    func populateBookShelf() {
        let booksInShelfRealm = realm.objects(CalibreBookRealm.self).filter(
            NSPredicate(format: "inShelf = true")
        )
        
        booksInShelfRealm.forEach {
            // print(bookRealm)
            guard let server = calibreServers[CalibreServer(name: "", baseUrl: $0.serverUrl!, publicUrl: "", username: $0.serverUsername!, password: "").id] else {
                print("ERROR booksInShelfRealm missing server \($0)")
                return
            }
            guard let library = calibreLibraries[CalibreLibrary(server: server, key: "", name: $0.libraryName!).id] else {
                print("ERROR booksInShelfRealm missing library \($0)")
                return
            }
            
            var book = self.convert(library: library, bookRealm: $0)
            
            book.formats.forEach { formatRaw, formatInfo in
                guard let format = Format(rawValue: formatRaw) else {
//                    var formatInfo = formatInfo
//                    formatInfo.cached = false
//                    book.formats[formatRaw] = formatInfo
                    return
                }
                var formatInfoNew = formatInfo
                if let cacheInfo = getCacheInfo(book: book, format: format),
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
                    book.formats[formatRaw] = formatInfoNew
                    self.updateBook(book: book)
                }
            }
            
            self.booksInShelf[book.inShelfId] = book
            
            print("booksInShelfRealm \(book.inShelfId)")
        }
    }
    
    func populateLibraries() {
        guard let currentCalibreServer = calibreServers[currentCalibreServerId]
                else { return }
        
        let librariesCached = realm.objects(CalibreLibraryRealm.self)

        librariesCached.forEach { libraryRealm in
            guard let calibreServer = calibreServers[CalibreServer(name: "", baseUrl: libraryRealm.serverUrl!, publicUrl: "", username: libraryRealm.serverUsername!, password: "").id] else {
                print("Unknown Server: \(libraryRealm)")
                return
            }
            let calibreLibrary = CalibreLibrary(
                server: calibreServer,
                key: libraryRealm.key ?? libraryRealm.name!,
                name: libraryRealm.name!,
                customColumnInfos: libraryRealm.customColumns.reduce(into: [String: CalibreCustomColumnInfo]()) {
                    $0[$1.label] = CalibreCustomColumnInfo(managedObject: $1)
                },
                readPosColumnName: libraryRealm.readPosColumnName,
                goodreadsSync: CalibreLibraryGoodreadsSync(managedObject: libraryRealm.goodreadsSync ?? CalibreLibraryGoodreadsSyncRealm())
                )
            
            calibreLibraries[calibreLibrary.id] = calibreLibrary
        }
        
        if let lastCalibreLibrary = UserDefaults.standard.string(forKey: Constants.KEY_DEFAULTS_SELECTED_LIBRARY_ID), calibreLibraries[lastCalibreLibrary] != nil {
            currentCalibreLibraryId = lastCalibreLibrary
        } else {
            let defaultLibrary = CalibreLibrary(server: currentCalibreServer, key: currentCalibreServer.defaultLibrary, name: currentCalibreServer.defaultLibrary)
            currentCalibreLibraryId = defaultLibrary.id
        }
        
        print("populateLibraries \(calibreLibraries)")
    }
    
    /**
            Must not run on main thread
     */
    func populateServerLibraryBooks(realm: Realm) {
        guard let currentCalibreLibrary = currentCalibreLibrary else {
            return
        }
        
        let booksCached = realm.objects(CalibreBookRealm.self).filter(
            NSPredicate(format: "serverUrl = %@ AND serverUsername = %@ AND libraryName = %@",
                        currentCalibreLibrary.server.baseUrl,
                        currentCalibreLibrary.server.username,
                        currentCalibreLibrary.name
            )
        )
        let booksCount = booksCached.count
        DispatchQueue.main.sync {
            self.calibreServerLibraryUpdatingTotal = booksCount
            self.calibreServerLibraryUpdatingProgress = 0
        }
        
        var calibreServerLibraryBooks = [Int32: CalibreBook]()
        booksCached.forEach { bookRealm in
            calibreServerLibraryBooks[bookRealm.id] = self.convert(library: currentCalibreLibrary, bookRealm: bookRealm)
            DispatchQueue.main.async {
                self.calibreServerLibraryUpdatingProgress += 1
            }
        }
        
        DispatchQueue.main.sync {
            self.calibreServerLibraryBooks = calibreServerLibraryBooks
            postProcessForLocalLibrary()
        }
    }
    
    func populateLocalLibraryBooks() {
        guard let documentDirectoryURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return
        }
        
        let tmpServer = CalibreServer(name: "Document Folder", baseUrl: ".", publicUrl: "", username: "", password: "")
        documentServer = calibreServers[tmpServer.id]
        if documentServer == nil || documentServer?.name != tmpServer.name {
            calibreServers[tmpServer.id] = tmpServer
            documentServer = calibreServers[tmpServer.id]
            do {
                try updateServerRealm(server: documentServer!)
            } catch {
                
            }
            if calibreServers.count == 1 {
                currentCalibreServerId = documentServer!.id
            }
        }
        
        let localLibraryURL = documentDirectoryURL.appendingPathComponent("Local Library", isDirectory: true)
        
        if FileManager.default.fileExists(atPath: localLibraryURL.path) == false {
            do {
                try FileManager.default.createDirectory(atPath: localLibraryURL.path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print(error)
            }
        }
        
        let tmpLibrary = CalibreLibrary(
            server: documentServer!,
            key: localLibraryURL.lastPathComponent,
            name: localLibraryURL.lastPathComponent)
        localLibrary = calibreLibraries[tmpLibrary.id]
        if localLibrary == nil {
            calibreLibraries[tmpLibrary.id] = tmpLibrary
            localLibrary = calibreLibraries[tmpLibrary.id]
            do {
                try updateLibraryRealm(library: localLibrary!)
            } catch {
                
            }
            if calibreLibraries.count == 1 {
                currentCalibreLibraryId = localLibrary!
                    .id
            }
        }
        
        guard let dirEnum = FileManager.default.enumerator(atPath: localLibraryURL.path) else {
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

            print("populateLocalLibraryBooks \(fileName)")
            let fileURL = documentServer!.localBaseUrl!.appendingPathComponent(localLibrary!.key, isDirectory: true).appendingPathComponent(fileName, isDirectory: false)

            loadLocalLibraryBookMetadata(fileURL: fileURL, in: localLibrary!, on: documentServer!)
        }
        
        let removedBooks: [CalibreBook] = booksInShelf.compactMap { inShelfId, book in
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
        
        removedBooks.forEach {
            self.removeFromShelf(inShelfId: $0.inShelfId)
            // self.removeFromRealm(book: $0)
            print("populateLocalLibraryBooks removeFromShelf \($0)")
        }
        
        postProcessForLocalLibrary()
    }
    
    // only move file when triggered by in-app importer, DO NOT MOVE FROM OTHER PLACES
    func onOpenURL(url: URL, doMove: Bool, doOverwrite: Bool, asNew: Bool, knownBookId: Int32? = nil) -> BookImportInfo {
        var bookImportInfo = BookImportInfo(url: url, bookId: nil, error: nil)
        
        guard let documentServer = documentServer,
              let localLibrary = localLibrary,
              let localBaseUrl = documentServer.localBaseUrl else {
            return bookImportInfo.with(error: .libraryAbsent)
        }
        
        guard let format = Format(rawValue: url.pathExtension.uppercased()) else {
            return bookImportInfo.with(error: .formatUnsupported)
        }

        if url.isFileURL {
            let _ = url.startAccessingSecurityScopedResource()
//            else {
//                print("onOpenURL url.startAccessingSecurityScopedResource() -> false")
//                return bookImportInfo.with(error: .securityFail)
//            }
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            do {
                guard let bookId = knownBookId ?? calcLocalFileBookId(for: url) else { return bookImportInfo.with(error: .idCalcFail) }
                print("onOpenURL \(bookId)")
                bookImportInfo.bookId = bookId
                
                // check for identical file
                let bookForQuery = CalibreBook(id: bookId, library: localLibrary)
                if let book = booksInShelf[bookForQuery.inShelfId],
                   let readerInfo = prepareBookReading(book: book),
                   readerInfo.url.pathExtension.lowercased() == url.pathExtension.lowercased() {
                    return bookImportInfo
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
        
        if let bookRealm = queryBookRealm(book: book, realm: realm) {
            book = convert(library: library, bookRealm: bookRealm)
        }
        
        book.title = fileURL.deletingPathExtension().lastPathComponent
        book.lastModified = Date()

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
            if let cover = publication.cover, let coverData = cover.pngData(), let coverUrl = book.coverURL {
                self.kfImageCache.storeToDisk(coverData, forKey: coverUrl.absoluteString)
            }
            
            self.updateBook(book: book)
        }
        #endif
        return bookId
    }
    
    //remove non existing books from library list
    func postProcessForLocalLibrary() {
        guard currentCalibreLibrary?.server.isLocal == true else { return }
        
        calibreServerLibraryUpdating = true
        calibreServerLibraryUpdatingProgress = 0
        calibreServerLibraryUpdatingTotal = calibreServerLibraryBooks.count
        
        calibreServerLibraryBooks = calibreServerLibraryBooks.filter {
            $0.value.inShelf
        }
        updateFilteredBookList()

        calibreServerLibraryUpdatingProgress = calibreServerLibraryBooks.count
        calibreServerLibraryUpdatingTotal = calibreServerLibraryBooks.count
        calibreServerLibraryUpdating = false
    }
    
    func updateFilteredBookList() {
        let searchTerms = searchString.trimmingCharacters(in: .whitespacesAndNewlines).split { $0.isWhitespace }
        let filteredBookList = calibreServerLibraryBooks.values.filter { [self] (book) -> Bool in
            guard searchTerms.isEmpty || searchTerms.filter({ term in
                book.title.localizedCaseInsensitiveContains(term) || book.authors.filter({ $0.localizedCaseInsensitiveContains(term) }).count > 0
            }).count == searchTerms.count
            else { return false }
            if !(filterCriteriaRating.isEmpty || filterCriteriaRating.contains(book.ratingDescription)) {
                return false
            }
            if !filterCriteriaFormat.isEmpty && filterCriteriaFormat.intersection(book.formats.compactMap { $0.key }).isEmpty {
                return false
            }
            if !filterCriteriaIdentifier.isEmpty && filterCriteriaIdentifier.intersection(book.identifiers.compactMap { $0.key }).isEmpty {
                return false
            }
            if !filterCriteriaSeries.isEmpty && filterCriteriaSeries.contains(book.seriesDescription) == false {
                return false
            }
            switch filterCriteriaShelved {
            case .shelvedOnly:
                if book.inShelf == false {
                    return false
                }
                break
            case .notShelvedOnly:
                if book.inShelf == true {
                    return false
                }
                break
            case .none:
                break
            }
            return true
        }.sorted { (lhs, rhs) -> Bool in
            lhs.title < rhs.title
        }.map({ $0.id })
        if !Thread.isMainThread {
            DispatchQueue.main.sync {
                self.filteredBookList = filteredBookList
            }
        } else {
            self.filteredBookList = filteredBookList
        }
        print("updateFilteredBookList finished count=\(self.filteredBookList.count)")
    }
    
    func convert(library: CalibreLibrary, bookRealm: CalibreBookRealm) -> CalibreBook {
        let formatsVer1 = bookRealm.formats().reduce(
            into: [String: FormatInfo]()
        ) { result, entry in
            result[entry.key] = FormatInfo(serverSize: 0, serverMTime: .distantPast, cached: false, cacheSize: 0, cacheMTime: .distantPast)
        }
//        let formatsVer2 = try? JSONSerialization.jsonObject(with: bookRealm.formatsData! as Data, options: []) as? [String: FormatInfo]
        let decoder = JSONDecoder()
        let formatsVer2 = (try? decoder.decode([String:FormatInfo].self, from: bookRealm.formatsData! as Data))
                ?? formatsVer1
        
        //print("CONVERT \(bookRealm.title) \(formatsVer1) \(formatsVer2)")
        
        var calibreBook = CalibreBook(
            id: bookRealm.id,
            library: library,
            title: bookRealm.title,
            comments: bookRealm.comments,
            publisher: bookRealm.publisher,
            series: bookRealm.series,
            rating: bookRealm.rating,
            size: bookRealm.size,
            pubDate: bookRealm.pubDate,
            timestamp: bookRealm.timestamp,
            lastModified: bookRealm.lastModified,
            formats: formatsVer2,
            readPos: bookRealm.readPos(),
            inShelf: bookRealm.inShelf,
            inShelfName: bookRealm.inShelfName)
        if bookRealm.identifiersData != nil {
            calibreBook.identifiers = bookRealm.identifiers()
        }
        if bookRealm.userMetaData != nil {
            calibreBook.userMetadatas = bookRealm.userMetadatas()
        }
        calibreBook.authors.append(contentsOf: bookRealm.authors)
        calibreBook.tags.append(contentsOf: bookRealm.tags)
        
        if calibreBook.readPos.getDevices().count > 1 {
            if let pos = calibreBook.readPos.getPosition(deviceName), pos.lastReadPage == 0 {
                calibreBook.readPos.removePosition(deviceName)
            }
        }
        
        return calibreBook
    }
    
    func updateStoreReadingPosition(enabled: Bool, value: String) {
        calibreLibraries[currentCalibreLibraryId]?.readPosColumnName = enabled ? value : nil
        do {
            try updateLibraryRealm(library: calibreLibraries[currentCalibreLibraryId]!)
        } catch {
            
        }
    }
    
    func updateGoodreadsSync(goodreadsSync: CalibreLibraryGoodreadsSync) {
        calibreLibraries[currentCalibreLibraryId]?.goodreadsSync = goodreadsSync
        do {
            try updateLibraryRealm(library: calibreLibraries[currentCalibreLibraryId]!)
        } catch {
            
        }
    }
    
    func getCustomDictViewer() -> (Bool, URL?) {
        return (UserDefaults.standard.bool(forKey: Constants.KEY_DEFAULTS_MDICT_VIEWER_ENABLED),
            UserDefaults.standard.url(forKey: Constants.KEY_DEFAULTS_MDICT_VIEWER_URL)
        )
    }
    
    func updateCustomDictViewer(enabled: Bool, value: String?) -> URL? {
        UserDefaults.standard.set(enabled, forKey: Constants.KEY_DEFAULTS_MDICT_VIEWER_ENABLED)
        guard let value = value else { return nil }
        let url = URL(string: value)
        UserDefaults.standard.set(url, forKey: Constants.KEY_DEFAULTS_MDICT_VIEWER_URL)
        return url
    }
    
    func getPreferredFormat() -> Format {
        return Format(rawValue: UserDefaults.standard.string(forKey: Constants.KEY_DEFAULTS_PREFERRED_FORMAT) ?? "" ) ?? defaultFormat
    }
    
    func getPreferredFormat(for book: CalibreBook) -> Format? {
        if book.formats[getPreferredFormat().rawValue] != nil {
            return getPreferredFormat()
        } else if let format = book.formats.compactMap({ Format(rawValue: $0.key) }).first {
            return format
        }
        return nil
    }
    
    func updatePreferredFormat(for format: Format) {
        UserDefaults.standard.setValue(format.rawValue, forKey: Constants.KEY_DEFAULTS_PREFERRED_FORMAT)
    }
    
    // user preferred -> default -> unsupported
    func getPreferredReader(for format: Format) -> ReaderType {
        return ReaderType(
            rawValue: UserDefaults.standard.string(forKey: "\(Constants.KEY_DEFAULTS_PREFERRED_READER_PREFIX)\(format.rawValue)") ?? ""
        ) ?? formatReaderMap[format]?.first ?? ReaderType.UNSUPPORTED
    }
    
    func updatePreferredReader(for format: Format, with reader: ReaderType) {
        UserDefaults.standard.setValue(reader.rawValue, forKey: "\(Constants.KEY_DEFAULTS_PREFERRED_READER_PREFIX)\(format.rawValue)")
    }
    
    func addServer(server: CalibreServer, libraries: [CalibreLibrary]) {
        calibreServers[server.id] = server
        do {
            try updateServerRealm(server: server)
        } catch {
            
        }
        
        libraries.forEach { (library) in
            calibreLibraries[library.id] = library
            do {
                try updateLibraryRealm(library: library)
            } catch {
            
            }
        }
    }
    
    func updateServerRealm(server: CalibreServer) throws {
        let serverRealm = CalibreServerRealm()
        serverRealm.name = server.name
        serverRealm.baseUrl = server.baseUrl
        serverRealm.publicUrl = server.publicUrl
        serverRealm.username = server.username
        serverRealm.password = server.password
        serverRealm.defaultLibrary = server.defaultLibrary
        serverRealm.lastLibrary = server.lastLibrary
        try realm.write {
            realm.add(serverRealm, update: .all)
        }
    }
    
    func updateLibraryRealm(library: CalibreLibrary) throws {
        let libraryRealm = CalibreLibraryRealm()
        libraryRealm.key = library.key
        libraryRealm.name = library.name
        libraryRealm.serverUrl = library.server.baseUrl
        libraryRealm.serverUsername = library.server.username
        libraryRealm.readPosColumnName = library.readPosColumnName
        libraryRealm.goodreadsSync = library.goodreadsSync.managedObject()
        libraryRealm.customColumns.append(objectsIn: library.customColumnInfos.values.map { $0.managedObject() })
        try realm.write {
            realm.add(libraryRealm, update: .all)
        }
    }
    
    func updateBook(book: CalibreBook) {
        updateBookRealm(book: book, realm: realm)
        if currentCalibreLibraryId == book.library.id {
            calibreServerLibraryBooks[book.id] = book
        }
        if readingBook?.inShelfId == book.inShelfId {
            readingBook = book
        }
        if book.inShelf {
            booksInShelf[book.inShelfId] = book
        }
    }
    
    /**
        should run on non-main thread
     */
    func updateBooks(books: [CalibreBook]) {
        let realm = try! Realm(configuration: self.realmConf)
        books.forEach { (book) in
            self.updateBookRealm(book: book, realm: realm)
            DispatchQueue.main.async {
                self.calibreServerLibraryUpdatingProgress += 1
            }
        }
        
    }
    
    func queryBookRealm(book: CalibreBook, realm: Realm) -> CalibreBookRealm? {
        return realm.objects(CalibreBookRealm.self).filter(
            NSPredicate(format: "serverUrl = %@ AND serverUsername = %@ AND libraryName = %@ AND id = %@",
                        book.library.server.baseUrl,
                        book.library.server.username,
                        book.library.name,
                        NSNumber(value: book.id)
            )
        ).first
    }

    func updateBookRealm(book: CalibreBook, realm: Realm) {
        let bookRealm = CalibreBookRealm()
        bookRealm.id = book.id
        bookRealm.serverUrl = book.library.server.baseUrl
        bookRealm.serverUsername = book.library.server.username
        bookRealm.libraryName = book.library.name
        bookRealm.title = book.title
        bookRealm.authors.append(objectsIn: book.authors)
        bookRealm.comments = book.comments
        bookRealm.publisher = book.publisher
        bookRealm.series = book.series
        bookRealm.rating = book.rating
        bookRealm.size = book.size
        bookRealm.pubDate = book.pubDate
        bookRealm.timestamp = book.timestamp
        bookRealm.lastModified = book.lastModified
        bookRealm.tags.append(objectsIn: book.tags)
        bookRealm.inShelf = book.inShelf
        bookRealm.inShelfName = book.inShelfName
        
        do {
            let encoder = JSONEncoder()
            bookRealm.formatsData = try encoder.encode(book.formats) as NSData
            
            //bookRealm.identifiersData = try JSONSerialization.data(withJSONObject: book.identifiers, options: []) as NSData
            bookRealm.identifiersData = try JSONEncoder().encode(book.identifiers) as NSData
            
            bookRealm.userMetaData = try JSONSerialization.data(withJSONObject: book.userMetadatas, options: []) as NSData
            
            let deviceMapSerialize = try book.readPos.getCopy().compactMapValues { (value) throws -> Any? in
                try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            }
            bookRealm.readPosData = try JSONSerialization.data(withJSONObject: ["deviceMap": deviceMapSerialize], options: []) as NSData
            
            try realm.write {
                realm.add(bookRealm, update: .modified)
            }
        } catch {
            print("updateBookRealm error=\(error.localizedDescription)")
        }
    }
    
    func removeFromRealm(book: CalibreBook) {
        let bookRealm = CalibreBookRealm()
        bookRealm.id = book.id
        bookRealm.serverUrl = book.library.server.baseUrl
        bookRealm.serverUsername = book.library.server.username
        bookRealm.libraryName = book.library.name
        
        let objects = realm.objects(CalibreBookRealm.self).filter( "primaryKey = '\(bookRealm.primaryKey!)'" )
        
        try? realm.write {
            realm.delete(objects)
        }
    }
    
    
    /// update server library infos,
    /// make sure libraries' server ids equal to serverId
    /// - Parameters:
    ///   - serverId: id of target server
    ///   - libraries: library list
    ///   - defaultLibrary: key of default library
    /// - TODO: update & remove
    func updateServerLibraryInfo(serverInfo: CalibreServerInfo) {
        guard let server = calibreServers[serverInfo.server.id] else { return }
        
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
                try updateLibraryRealm(library: calibreLibraries[libraryId]!)
            } catch {
                
            }
        }
        
        if server.defaultLibrary != serverInfo.defaultLibrary {
            calibreServers[server.id]!.defaultLibrary = serverInfo.defaultLibrary
            do {
                try updateServerRealm(server: calibreServers[server.id]!)
            } catch {
                
            }
        }
    }
    
    func addToShelf(_ bookId: Int32, shelfName: String) {
        guard var book = calibreServerLibraryBooks[bookId] else {
            return
        }
        
        book.inShelfName = shelfName
        book.inShelf = true
        book.timestamp = Date()
        
        calibreServerLibraryBooks[bookId] = book
        
        if readingBook?.id == bookId {
            readingBook = book
        }
        
        updateBookRealm(book: book, realm: self.realm)
        booksInShelf[book.inShelfId] = book
        
        if let library = calibreLibraries[book.library.id],
           let goodreadsId = book.identifiers["goodreads"],
           library.goodreadsSync.isEnabled,
           library.goodreadsSync.profileName.isEmpty == false {
            let connector = GoodreadsSyncConnector(server: book.library.server, profileName: book.library.goodreadsSync.profileName)
            let ret = connector.addToShelf(goodreads_id: goodreadsId, shelfName: "currently-reading")
        }
    }
    
    func removeFromShelf(inShelfId: String) {
        if readingBook?.inShelfId == inShelfId {
            readingBook?.inShelf = false
            NotificationCenter.default.post(Notification(name: Notification.Name("YABR.readingBookRemovedFromShelf")))
        }
        
        guard var book = booksInShelf[inShelfId] else { return }
        book.inShelf = false

        updateBookRealm(book: book, realm: self.realm)
        if book.library.id == currentCalibreLibraryId {
            calibreServerLibraryBooks[book.id]?.inShelf = false
        }
        booksInShelf.removeValue(forKey: inShelfId)
        
        postProcessForLocalLibrary()
        
        if let library = calibreLibraries[book.library.id],
           let goodreadsId = book.identifiers["goodreads"],
           library.goodreadsSync.isEnabled,
           library.goodreadsSync.profileName.isEmpty == false {
            let connector = GoodreadsSyncConnector(server: library.server, profileName: library.goodreadsSync.profileName)
            let ret = connector.removeFromShelf(goodreads_id: goodreadsId, shelfName: "currently-reading")
            
            if let position = getDeviceReadingPosition(book: book), position.lastProgress > 99 {
                connector.addToShelf(goodreads_id: goodreadsId, shelfName: "read")
            }
        }
    }
    
    func startDownloadFormat(book: CalibreBook, format: Format, overwrite: Bool = false) -> Bool {
        return downloadService.startDownload(book, format: format, overwrite: overwrite)
    }
    
    func cancelDownloadFormat(book: CalibreBook, format: Format) {
        return downloadService.cancelDownload(book, format: format)
    }
    
    func pauseDownloadFormat(book: CalibreBook, format: Format) {
        return downloadService.pauseDownload(book, format: format)
    }
    
    func resumeDownloadFormat(book: CalibreBook, format: Format) -> Bool {
        let result = downloadService.resumeDownload(book, format: format)
        if !result {
            downloadService.cancelDownload(book, format: format)
        }
        return result
    }
    
    func startBatchDownload(bookIds: [Int32], formats: [String]) {
        
    }
    
    func clearCache(inShelfId: String) {
        guard let book = booksInShelf[inShelfId] else {
            return
        }
        
        book.formats.filter { $1.cached }.forEach {
            guard let format = Format(rawValue: $0.key) else { return }
            clearCache(book: book,  format: format)
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
        
        updateBook(book: newBook)

        if newBook.inShelf == false {
            addToShelf(newBook.id, shelfName: newBook.tags.first ?? "Untagged")
        }
        
        if format == Format.EPUB {
            removeFolioCache(book: newBook, format: format)
        }
    }
    
    func clearCache(book: CalibreBook, format: Format) {
        guard let bookFileURL = getSavedUrl(book: book, format: format) else { return }
        
        if FileManager.default.fileExists(atPath: bookFileURL.path) {
            do {
                try FileManager.default.removeItem(at: bookFileURL)
            } catch {
                defaultLog.error("clearCache \(error.localizedDescription)")
            }
        }
        var newBook = book
        
        newBook.formats[format.rawValue]?.cacheMTime = .distantPast
        newBook.formats[format.rawValue]?.cacheSize = 0
        newBook.formats[format.rawValue]?.cached = false

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
    
    
    func getSelectedReadingPosition(book: CalibreBook) -> BookDeviceReadingPosition? {
        return book.readPos.getPosition(selectedPosition)
    }
    
    func getDeviceReadingPosition(book: CalibreBook) -> BookDeviceReadingPosition? {
        return book.readPos.getPosition(deviceName)
    }
    
    func getInitialReadingPosition(book: CalibreBook, format: Format, reader: ReaderType) -> BookDeviceReadingPosition {
        return BookDeviceReadingPosition(id: deviceName, readerName: reader.rawValue)
    }
    
    func getLatestReadingPosition(book: CalibreBook) -> BookDeviceReadingPosition? {
        return book.readPos.getDevices().first
    }
    
    func getLatestReadingPosition(book: CalibreBook, by reader: ReaderType) -> BookDeviceReadingPosition? {
        return book.readPos.getDevices().first
    }
    
    func updateCurrentPosition(alertDelegate: AlertDelegate) {
        guard var readingBook = self.readingBook else {
            return
        }
        guard let readerInfo = self.readerInfo else {
            return
        }
        
        defaultLog.info("pageNumber:  \(self.updatedReadingPosition.lastPosition[0])")
        defaultLog.info("pageOffsetX: \(self.updatedReadingPosition.lastPosition[1])")
        defaultLog.info("pageOffsetY: \(self.updatedReadingPosition.lastPosition[2])")
        
        readingBook.readPos.updatePosition(deviceName, updatedReadingPosition)
        readingBook.lastModified = Date()
        
        self.updateBook(book: readingBook)
        
        calibreServerService.setLastReadPosition(book: readingBook, format: readerInfo.format, position: updatedReadingPosition)
        
        if let realmConfig = getBookPreferenceConfig(book: readingBook, format: readerInfo.format),
           let bookId = realmConfig.fileURL?.deletingPathExtension().lastPathComponent {
            let highlightProvider = FolioReaderRealmHighlightProvider(realmConfig: realmConfig)
            
            let highlights = highlightProvider.folioReaderHighlight(bookId: bookId)
            calibreServerService.updateAnnotations(book: readingBook, format: readerInfo.format, highlights: highlights)
        }
        
        guard let readPosColumnName = calibreLibraries[readingBook.library.id]?.readPosColumnName else {
            return
        }

        let ret = calibreServerService.updateBookReadingPosition(book: readingBook, columnName: readPosColumnName, alertDelegate: alertDelegate) { [self] in
            if floor(updatedReadingPosition.lastProgress) > readerInfo.position.lastProgress,
               let library = calibreLibraries[readingBook.library.id],
               let goodreadsId = readingBook.identifiers["goodreads"],
               library.goodreadsSync.isEnabled,
               library.goodreadsSync.profileName.isEmpty == false {
                let connector = GoodreadsSyncConnector(server: library.server, profileName: library.goodreadsSync.profileName)
                connector.updateReadingProgress(goodreads_id: goodreadsId, progress: updatedReadingPosition.lastProgress)
            }
        }
        if ret != 0 {
            updatingMetadataStatus = "Internal Error"
            updatingMetadata = false
            alertDelegate.alert(msg: updatingMetadataStatus)
        }
    }
    
    func updateReadingPosition(book: CalibreBook, alertDelegate: AlertDelegate) {
        self.updateBook(book: book)
        
        guard let readPosColumnName = calibreLibraries[book.library.id]?.readPosColumnName else {
            return
        }

        let ret = calibreServerService.updateBookReadingPosition(book: book, columnName: readPosColumnName, alertDelegate: alertDelegate) {
            // empty
        }
        if ret != 0 {
            updatingMetadataStatus = "Internal Error"
            updatingMetadata = false
            alertDelegate.alert(msg: updatingMetadataStatus)
        }
    }
    
    
    func goToPreviousBook() {
        if let curIndex = filteredBookList.firstIndex(of: currentBookId), curIndex > 0 {
            currentBookId = filteredBookList[curIndex-1]
        }
    }
    
    func goToNextBook() {
        if let curIndex = filteredBookList.firstIndex(of: selectedBookId ?? currentBookId), curIndex < filteredBookList.count - 1 {
            currentBookId = filteredBookList[curIndex + 1]
        }
    }
    
    func defaultReaderForDefaultFormat(book: CalibreBook) -> (Format, ReaderType) {
        if book.formats.contains(where: { $0.key == defaultFormat.rawValue }) {
            return (defaultFormat, formatReaderMap[defaultFormat]!.first!)
        } else {
            return book.formats.keys.compactMap {
                Format(rawValue: $0)
            }
            .reversed()
            .reduce((Format.UNKNOWN, ReaderType.UNSUPPORTED)) {
                ($1, formatReaderMap[$1]!.first!)
            }
        }
    }
    
    func formatOfReader(readerName: String) -> Format? {
        let formats = formatReaderMap.filter {
            $0.value.contains(where: { reader in reader.rawValue == readerName } )
        }
        return formats.first?.key
    }
    
    func prepareBookReading(book: CalibreBook) -> ReaderInfo? {
        var candidatePositions = [BookDeviceReadingPosition]()

        //preference: device, latest, selected, any
        if let position = getDeviceReadingPosition(book: book) {
            candidatePositions.append(position)
        }
        if let position = getLatestReadingPosition(book: book) {
            candidatePositions.append(position)
        }
        if let position = getSelectedReadingPosition(book: book) {
            candidatePositions.append(position)
        }
        candidatePositions.append(contentsOf: book.readPos.getDevices())
        if let format = getPreferredFormat(for: book) {
            candidatePositions.append(getInitialReadingPosition(book: book, format: format, reader: getPreferredReader(for: format)))
        }
        
        var formatReaderPairArray = [(Format, ReaderType, BookDeviceReadingPosition)]()
        candidatePositions.forEach { position in
            formatReaderPairArray.append(
                contentsOf: formatReaderMap.compactMap {
                    guard let index = $0.value.firstIndex(where: { $0.rawValue == position.readerName }) else { return nil }
                    return ($0.key, $0.value[index], position)
                } as [(Format, ReaderType, BookDeviceReadingPosition)]
            )
        }
        
        guard let formatReaderPair = formatReaderPairArray.first else { return nil }
        guard let savedURL = getSavedUrl(book: book, format: formatReaderPair.0) else { return nil }
        guard FileManager.default.fileExists(atPath: savedURL.path) else {
            return nil
        }
        
        return ReaderInfo(url: savedURL, format: formatReaderPair.0, readerType: formatReaderPair.1, position: formatReaderPair.2)
    }
    
    func prepareBookReading(url: URL, format: Format, readerType: ReaderType, position: BookDeviceReadingPosition) {
        let readerInfo = ReaderInfo(
            url: url,
            format: format,
            readerType: readerType,
            position: position
        )
        self.readerInfo = readerInfo
    }
    
    func removeLibrary(libraryId: String) -> Bool {
        guard let library = calibreLibraries[libraryId] else { return false }
        
        //remove cached book files
        let libraryBooksInShelf = booksInShelf.filter {
            $0.value.library.id == libraryId
        }
        libraryBooksInShelf.forEach {
            self.clearCache(inShelfId: $0.key)
            self.removeFromShelf(inShelfId: $0.key)     //just in case
        }
        
        //remove library info
        do {
            let booksCached = realm.objects(CalibreBookRealm.self).filter(
                NSPredicate(format: "serverUrl = %@ AND serverUsername = %@ AND libraryName = %@",
                            library.server.baseUrl,
                            library.server.username,
                            library.name
                )
            )
            try realm.write {
                realm.delete(booksCached)
            }
        } catch {
            return false
        }
        
        return true
    }
    
    func removeServer(serverId: String) -> Bool {
        guard let server = calibreServers[serverId] else { return false }
        
        let libraries = calibreLibraries.filter {
            $0.value.server == server
        }
        
        var isSuccess = true
        libraries.forEach {
            let result = removeLibrary(libraryId: $0.key)
            isSuccess = isSuccess && result
        }
        if !isSuccess {
            return false
        }
        
        //remove library info
        libraries.forEach {
            calibreLibraries.removeValue(forKey: $0.key)
        }
        do {
            let serverLibraryRealms = realm.objects(CalibreLibraryRealm.self).filter(
                NSPredicate(format: "serverUrl = %@ AND serverUsername = %@",
                            server.baseUrl,
                            server.username
                ))
            try realm.write {
                realm.delete(serverLibraryRealms)
            }
        } catch {
            return false
        }
        
        //remove server
        calibreServers.removeValue(forKey: serverId)
        do {
            let serverRealms = realm.objects(CalibreServerRealm.self).filter(
                NSPredicate(format: "baseUrl = %@ AND username = %@",
                            server.baseUrl,
                            server.username
                )
            )
            try realm.write {
                realm.delete(serverRealms)
            }
        } catch {
            return false
        }
        
        //reset current server id
        currentCalibreServerId = calibreServers.keys.first!
        
        return true
    }
    
    func updateServer(oldServer: CalibreServer, newServer: CalibreServer) {
        do {
            try self.updateServerRealm(server: newServer)
        } catch {
            
        }
        self.calibreServers.removeValue(forKey: oldServer.id)
        self.calibreServers[newServer.id] = newServer
        
        guard oldServer.id != newServer.id else { return }  //minor changes
        
        calibreServerUpdating = true
        calibreServerUpdatingStatus = "Updating..."
        
            //if major change occured
        DispatchQueue(label: "data").async {
            let realm = try! Realm(configuration: self.realmConf)

            //remove old server from realm
            realm.objects(CalibreServerRealm.self).forEach { serverRealm in
                guard serverRealm.baseUrl == oldServer.baseUrl && serverRealm.username == oldServer.username else {
                    return
                }
                do {
                    try realm.write {
                        realm.delete(serverRealm)
                    }
                } catch {
                    
                }
            }
            
            //update library
            let librariesCached = realm.objects(CalibreLibraryRealm.self)
            librariesCached.forEach { oldLibraryRealm in
                guard oldLibraryRealm.serverUrl == oldServer.baseUrl && oldLibraryRealm.serverUsername == oldServer.username else { return }
                    
                let oldLibrary = CalibreLibrary(
                    server: oldServer,
                    key: oldLibraryRealm.key!,
                    name: oldLibraryRealm.name!,
                    customColumnInfos: oldLibraryRealm.customColumns.reduce(into: [String: CalibreCustomColumnInfo]()) {
                        $0[$1.label] = CalibreCustomColumnInfo(managedObject: $1)
                    },
                    readPosColumnName: oldLibraryRealm.readPosColumnName,
                    goodreadsSync: CalibreLibraryGoodreadsSync(managedObject: oldLibraryRealm.goodreadsSync  ?? CalibreLibraryGoodreadsSyncRealm()))
                
                
                let newLibrary = CalibreLibrary(
                    server: newServer,
                    key: oldLibraryRealm.key!,
                    name: oldLibraryRealm.name!,
                    customColumnInfos: oldLibrary.customColumnInfos,
                    readPosColumnName: oldLibraryRealm.readPosColumnName,
                    goodreadsSync: oldLibrary.goodreadsSync)
                
                do {
                    try realm.write {
                        realm.delete(oldLibraryRealm)
                    }
                } catch {
                    
                }
                
                DispatchQueue.main.sync {
                    do {
                       try self.updateLibraryRealm(library: newLibrary)
                    } catch {}
                    self.calibreLibraries.removeValue(forKey: oldLibrary.id)
                    self.calibreLibraries[newLibrary.id] = newLibrary
                }
                
            }
            
            //update books
            let booksCached = realm.objects(CalibreBookRealm.self)
            do {
                try realm.write {
                    booksCached.forEach { oldBookRealm in
                        guard oldBookRealm.serverUrl == oldServer.baseUrl && oldBookRealm.serverUsername == oldServer.username else { return }
                        let newBookRealm = CalibreBookRealm(value: oldBookRealm)
                        newBookRealm.serverUrl = newServer.baseUrl
                        newBookRealm.serverUsername = newServer.username
                        
                        realm.delete(oldBookRealm)
                        realm.add(newBookRealm, update: .all)
                    }
                }
            } catch {
                
            }
            
            DispatchQueue.main.sync {
                //reload shelf
                self.realm.refresh()

                self.booksInShelf.removeAll(keepingCapacity: true)
                self.populateBookShelf()
                
                //reload book list
                self.calibreServerUpdating = false
                self.calibreServerUpdatingStatus = "Finished"
                
                self.currentCalibreServerId = newServer.id
            }
        }
    }
    
    func syncLibrary(alertDelegate: AlertDelegate) {
        guard let server = currentCalibreServer,
              let library = currentCalibreLibrary
              else {
            return
        }
        if server.isLocal {
            populateLocalLibraryBooks()
            calibreServerUpdatingStatus = ""
        } else {
            calibreServerService.getCustomColumns(library: library) { columnInfos in
                var library = library
                library.customColumnInfos = columnInfos
                self.calibreLibraries[library.id] = library
                try? self.updateLibraryRealm(library: library)
                
                self.calibreServerService.syncLibrary(server: server, library: library, alertDelegate: alertDelegate)
            }
        }
    }
    
    func probeServersReachability(with serverIds: [String]) {
        calibreServiceCancellable?.cancel()
        
        calibreServers.filter {
            $0.value.isLocal == false
        }.forEach { serverId, server in
            [true, false].forEach { isPublic in
                let infoId = serverId + " " + isPublic.description
                
                if calibreServerInfoStaging[infoId] == nil,
                   let url = URL(string: isPublic ? server.publicUrl : server.baseUrl) {
                    calibreServerInfoStaging[infoId] =
                        CalibreServerInfo(server: server, isPublic: isPublic, url: url, reachable: false, errorMsg: "", probingTask: nil, defaultLibrary: server.defaultLibrary, libraryMap: [:])
                }
            }
        }
        
        let probingList = calibreServerInfoStaging.filter {
            if serverIds.isEmpty {
                return true
            } else {
                return serverIds.contains($0.value.server.id)
            }
        }.sorted {
            if $0.value.reachable == $1.value.reachable {
                return $0.key < $1.key
            }
            return !$0.value.reachable  //put unreachable first
        }
        
        calibreServiceCancellable = probingList.publisher.flatMap {
            self.calibreServerService.probeServerReachabilityNew(serverInfo: $0.value)
        }
        .collect()
        .eraseToAnyPublisher()
        .receive(on: DispatchQueue.main)
        .sink { results in
            results.forEach {  (id, libraryInfo) in
                guard var serverInfo = self.calibreServerInfoStaging[id] else { return }
                if libraryInfo.libraryMap.isEmpty {
                    serverInfo.reachable = false
                    serverInfo.errorMsg = "Error Message to be Populated"
                } else {
                    serverInfo.reachable = true
                    serverInfo.libraryMap = libraryInfo.libraryMap
                    if let defaultLibrary = libraryInfo.defaultLibrary {
                        serverInfo.defaultLibrary = defaultLibrary
                    }
                }
                self.calibreServerInfoStaging[id] = serverInfo
            }
            
            self.shelfRefreshCancellable?.cancel()
            
            self.refreshShelfMetadata(with: serverIds)
        }
    }
    
    func isServerReachable(server: CalibreServer, isPublic: Bool) -> Bool? {
        return calibreServerInfoStaging.filter {
            $1.server.id == server.id && $1.isPublic == isPublic
        }.first?.value.reachable
    }
    
    func refreshShelfMetadata(with serverIds: [String]) {
        shelfRefreshCancellable?.cancel()
        
        shelfRefreshCancellable = booksInShelf.values
            .filter {
                if serverIds.isEmpty {
                    return true
                } else {
                    return serverIds.contains($0.library.server.id)
                }
            }
            .compactMap(calibreServerService.buildMetadataTask(book:))
            .publisher.flatMap(calibreServerService.getMetadata(task:))
            .collect()
            .eraseToAnyPublisher()
            .receive(on: DispatchQueue.main)
            .sink { results in
                results.compactMap { (task, entry) -> CalibreBook? in
                    print("refreshShelfMetadata \(task) \(entry)")
                    
                    guard var book = self.booksInShelf[task.inShelfId] else { return nil }
                    
                    book.formats = entry.format_metadata.reduce(
                        into: book.formats
                    ) { result, format in
                        var formatInfo = result[format.key.uppercased()] ?? FormatInfo(serverSize: 0, serverMTime: .distantPast, cached: false, cacheSize: 0, cacheMTime: .distantPast)
                        
                        formatInfo.serverSize = format.value.size
                        
                        let dateFormatter = ISO8601DateFormatter()
                        dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
                        if let mtime = dateFormatter.date(from: format.value.mtime) {
                            formatInfo.serverMTime = mtime
                        }
                        
                        result[format.key.uppercased()] = formatInfo
                    }
                    
                    return book
                }.forEach {
                    self.updateBook(book: $0)
                }
                
                NotificationCenter.default.post(Notification(name: Notification.Name("YABR.booksRefreshed")))
            }
    }
    
        
}
