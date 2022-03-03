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
import ShelfView

import CryptoSwift
#if canImport(R2Shared)
import R2Shared
import R2Streamer
#endif

final class ModelData: ObservableObject {
    static var shared: ModelData?
    
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
    
    let serverAddedPublisher = NotificationCenter.default.publisher(
        for: .YABR_ServerAdded
    ).eraseToAnyPublisher()
    
    var presentingStack = [Binding<Bool>]()
    
    var currentBookId: Int32 = -1 {
        didSet {
            self.selectedBookId = currentBookId
        }
    }

    @Published var selectedBookId: Int32? = nil {
        didSet {
            guard let selectedBookId = selectedBookId,
                  let book = self.calibreServerLibraryBooks[selectedBookId]
                  else { return }
            self.readingBook = book
        }
    }
    
    @Published var selectedPosition = ""
    @Published var updatedReadingPosition = BookDeviceReadingPosition(id: UIDevice().name, readerName: "")
    let bookReaderClosedPublisher = NotificationCenter.default.publisher(
        for: .YABR_BookReaderClosed
    ).eraseToAnyPublisher()
    let bookReaderEnterBackgroundPublished = NotificationCenter.default.publisher(
        for: .YABR_BookReaderEnterBackground
    ).eraseToAnyPublisher()
    var bookReaderEnterBackgroundCancellable: AnyCancellable? = nil
    
    var readingBookInShelfId: String? = nil {
        didSet {
            guard let readingBookInShelfId = readingBookInShelfId else {
                readingBook = nil
                return
            }
            if readingBook?.inShelfId != readingBookInShelfId {
                readingBook = booksInShelf[readingBookInShelfId]
            }
            if readingBook == nil,
               let bookRealm = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: readingBookInShelfId) {
                readingBook = convert(bookRealm: bookRealm)
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
            
            if let position = getDeviceReadingPosition(book: readingBook), position.lastReadPage > 0 {
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
    var realm: Realm!
    var realmConf: Realm.Configuration!
    
    let activityDispatchQueue = DispatchQueue(label: "io.github.dsreader.activity")
    
    let kfImageCache = ImageCache.default
    var authResponsor = AuthResponsor()
    
    lazy var downloadService = BookFormatDownloadService(modelData: self)
    @Published var activeDownloads: [URL: BookFormatDownload] = [:]

    lazy var calibreServerService = CalibreServerService(modelData: self)
    
    var calibreServiceCancellable: AnyCancellable?
    var shelfRefreshCancellable: AnyCancellable?
    var dshelperRefreshCancellable: AnyCancellable?
    var syncLibrariesIncrementalCancellable: AnyCancellable?
    
    lazy var metadataQueue: OperationQueue = {
        var queue = OperationQueue()
        queue.name = "Book Metadata queue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    var getBooksMetadataSubject = PassthroughSubject<CalibreBooksTask, Never>()
    var getBooksMetadataCancellable: AnyCancellable?
    
    @Published var librarySyncStatus = [String: (isSync: Bool, isError: Bool, msg: String)]()

    @Published var userFontInfos = [String: FontInfo]()

    @Published var bookModelSection = [BookModelSection]()

    var resourceFileDictionary: NSDictionary?

    init(mock: Bool = false) {
        ModelData.shared = self
        
        //Load content of Info.plist into resourceFileDictionary dictionary
        if let path = Bundle.main.path(forResource: "Info", ofType: "plist") {
            resourceFileDictionary = NSDictionary(contentsOfFile: path)
        }
        
        ModelData.RealmSchemaVersion = UInt64(resourceFileDictionary?.value(forKey: "CFBundleVersion") as? String ?? "1") ?? 1
        realmConf = Realm.Configuration(
            schemaVersion: ModelData.RealmSchemaVersion,
            migrationBlock: { migration, oldSchemaVersion in
                if oldSchemaVersion < 42 {  //CalibreServerRealm's hasPublicUrl and hasAuth
                    migration.enumerateObjects(ofType: CalibreServerRealm.className()) { oldObject, newObject in
                        //print("migrationBlock \(String(describing: oldObject)) \(String(describing: newObject))")
                        if let publicUrl = oldObject!["publicUrl"] as? String {
                            newObject!["hasPublicUrl"] = publicUrl.count > 0
                        }
                        if let username = oldObject!["username"] as? String, let password = oldObject!["password"] as? String {
                            newObject!["hasAuth"] = username.count > 0 && password.count > 0
                        }
                    }
                }
                if oldSchemaVersion < 44 {  //authos to first/second/more, tags to first/second/third/more
                    migration.enumerateObjects(ofType: CalibreBookRealm.className()) { oldObject, newObject in
                        if let authors = oldObject?.dynamicList("authors") {
                            ["First", "Second", "Third"].forEach {
                                newObject?.setValue(authors.first, forKey: "author\($0)")
                                authors.removeFirst()
                            }
                            newObject?.dynamicList("authorsMore").append(objectsIn: authors)
                        }
                        
                        if let authors = oldObject?.dynamicList("tags") {
                            ["First", "Second", "Third"].forEach {
                                newObject?.setValue(authors.first, forKey: "tag\($0)")
                                authors.removeFirst()
                            }
                            newObject?.dynamicList("tagsMore").append(objectsIn: authors)
                        }
                        
                    }
                }
            }
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
        
        realm = try! Realm(
            configuration: realmConf
        )
        
        
        kfImageCache.diskStorage.config.expiration = .never
        KingfisherManager.shared.defaultOptions = [.requestModifier(AuthPlugin(modelData: self))]
        ImageDownloader.default.authenticationChallengeResponder = authResponsor
        
        let serversCached = realm.objects(CalibreServerRealm.self).sorted(by: [SortDescriptor(keyPath: "username"), SortDescriptor(keyPath: "baseUrl")])
        serversCached.forEach { serverRealm in
            guard serverRealm.baseUrl != nil else { return }
            let calibreServer = CalibreServer(
                name: serverRealm.name ?? serverRealm.baseUrl!,
                baseUrl: serverRealm.baseUrl!,
                hasPublicUrl: serverRealm.hasPublicUrl,
                publicUrl: serverRealm.publicUrl ?? "",
                hasAuth: serverRealm.hasAuth,
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
        
        DispatchQueue.global(qos: .userInitiated).async {
            let bookModelSection = self.updateBookModel()
            DispatchQueue.main.async {
                self.bookModelSection = bookModelSection
            }
        }
        
        cleanCalibreActivities(startDatetime: Date(timeIntervalSinceNow: TimeInterval(-86400*7)))
        
        getBooksMetadataCancellable = getBooksMetadataSubject.flatMap { task in
            self.calibreServerService.getBooksMetadata(task: task)
        }
        .subscribe(on: DispatchQueue.global())
        .sink(receiveCompletion: { completion in
            print("getBookMetadataCancellable error \(completion)")
        }, receiveValue: { result in
//            print("getBookMetadataCancellable response \(result.response)")
            
            let decoder = JSONDecoder()
            guard let realm = try? Realm(configuration: self.realmConf) else { return }

            do {
                guard let data = result.data else {
                    print("getBookMetadataCancellable nildata \(result.library.name)")
                    return
                }
                let entries = try decoder.decode([String:CalibreBookEntry?].self, from: data)
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? NSDictionary
                
                try realm.write {
                    result.books.forEach { id in
                        guard let obj = realm.object(
                                ofType: CalibreBookRealm.self,
                                forPrimaryKey: CalibreBookRealm.PrimaryKey(serverUsername: result.library.server.username, serverUrl: result.library.server.baseUrl, libraryName: result.library.name, id: id)),
                              let entryOptional = entries[id],
                              let entry = entryOptional,
                              let root = json?[id] as? NSDictionary else {
                            return
                        }
                        
                        self.calibreServerService.handleLibraryBookOne(library: result.library, bookRealm: obj, entry: entry, root: root)
                    }
                }
                
                NotificationCenter.default.post(Notification(name: .YABR_BooksRefreshed))

                print("getBookMetadataCancellable count \(result.library.name) \(entries.count)")
            } catch {
                print("getBookMetadataCancellable decode \(result.library.name) \(error)")
            }
        })
        
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
                lastSynced: Date.init(timeIntervalSince1970: TimeInterval(1577808000)),
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
            
            cleanCalibreActivities(startDatetime: Date())
            logStartCalibreActivity(type: "Mock", request: URLRequest(url: URL(string: "http://calibre-server.lan:8080/")!), startDatetime: Date(), bookId: 1, libraryId: library.id)
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
            guard let server = calibreServers[CalibreServer(name: "", baseUrl: $0.serverUrl!, hasPublicUrl: false, publicUrl: "", hasAuth: $0.serverUsername?.count ?? 0 > 0, username: $0.serverUsername!, password: "").id] else {
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
            guard let calibreServer = calibreServers[CalibreServer(name: "", baseUrl: libraryRealm.serverUrl!, hasPublicUrl: false, publicUrl: "", hasAuth: libraryRealm.serverUsername?.count ?? 0 > 0, username: libraryRealm.serverUsername!, password: "").id] else {
                print("Unknown Server: \(libraryRealm)")
                return
            }
            let calibreLibrary = CalibreLibrary(
                server: calibreServer,
                key: libraryRealm.key ?? libraryRealm.name!,
                name: libraryRealm.name!,
                autoUpdate: libraryRealm.autoUpdate,
                discoverable: libraryRealm.discoverable,
                lastModified: libraryRealm.lastModified,
                customColumnInfos: libraryRealm.customColumns.reduce(into: [String: CalibreCustomColumnInfo]()) {
                    $0[$1.label] = CalibreCustomColumnInfo(managedObject: $1)
                },
                pluginColumns: {
                    var result = [String: CalibreLibraryPluginColumnInfo]()
                    if let plugin = libraryRealm.pluginDSReaderHelper {
                        result[CalibreLibrary.PLUGIN_DSREADER_HELPER] = CalibreLibraryDSReaderHelper(managedObject: plugin)
                    }
                    if let plugin = libraryRealm.pluginDictionaryViewer {
                        result[CalibreLibrary.PLUGIN_DICTIONARY_VIEWER] = CalibreLibraryDictionaryViewer(managedObject: plugin)
                    }
                    if let plugin = libraryRealm.pluginReadingPosition {
                        result[CalibreLibrary.PLUGIN_READING_POSITION] = CalibreLibraryReadingPosition(managedObject: plugin)
                    }
                    if let plugin = libraryRealm.pluginGoodreadsSync {
                        result[CalibreLibrary.PLUGIN_GOODREADS_SYNC] = CalibreLibraryGoodreadsSync(managedObject: plugin)
                    }
                    if let plugin = libraryRealm.pluginCountPages {
                        result[CalibreLibrary.PLUGIN_COUNT_PAGES] = CalibreLibraryCountPages(managedObject: plugin)
                    }
                    return result
                }()
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
        
        let tmpServer = CalibreServer(name: "Document Folder", baseUrl: ".", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
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
                try updateLibraryRealm(library: localLibrary!, realm: self.realm)
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
            guard filterCriteriaRating.isEmpty || filterCriteriaRating.contains(book.ratingDescription) else { return false }
            guard filterCriteriaFormat.isEmpty || filterCriteriaFormat.intersection(book.formats.compactMap { $0.key }).isEmpty == false else { return false }
            guard filterCriteriaIdentifier.isEmpty || filterCriteriaIdentifier.intersection(book.identifiers.compactMap { $0.key }).isEmpty == false else { return false }
            guard filterCriteriaSeries.isEmpty || filterCriteriaSeries.contains(book.seriesDescription) else { return false }
            guard filterCriteriaShelved == .none || (filterCriteriaShelved == .shelvedOnly && book.inShelf) || (filterCriteriaShelved == .notShelvedOnly && !book.inShelf) else { return false }
            
            return true
        }.sorted { (lhs, rhs) -> Bool in
            if filterCriteriaSeries.isEmpty == false {
                if lhs.series != rhs.series {
                    return lhs.series < rhs.series
                }
                if lhs.seriesIndex != rhs.seriesIndex {
                    return lhs.seriesIndex < rhs.seriesIndex
                }
            }
            return lhs.title < rhs.title
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
    
    func convert(bookRealm: CalibreBookRealm) -> CalibreBook? {
        let serverId = { () -> String in
            let serverUrl = bookRealm.serverUrl ?? "."
            if let username = bookRealm.serverUsername,
               username.isEmpty == false {
                return "\(username) @ \(serverUrl)"
            } else {
                return serverUrl
            }
        }()
        guard let libraryName = bookRealm.libraryName else { return nil }
        let libraryId = "\(serverId) - \(libraryName)"
        guard let library = calibreLibraries[libraryId] else { return nil }
        
        return convert(library: library, bookRealm: bookRealm)
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
            seriesIndex: bookRealm.seriesIndex,
            rating: bookRealm.rating,
            size: bookRealm.size,
            pubDate: bookRealm.pubDate,
            timestamp: bookRealm.timestamp,
            lastModified: bookRealm.lastModified,
            lastSynced: bookRealm.lastSynced,
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
        if let authorFirst = bookRealm.authorFirst {
            calibreBook.authors.append(authorFirst)
        }
        if let authorSecond = bookRealm.authorSecond {
            calibreBook.authors.append(authorSecond)
        }
        if let authorThird = bookRealm.authorThird {
            calibreBook.authors.append(authorThird)
        }
        calibreBook.authors.append(contentsOf: bookRealm.authorsMore)
        
        if let tagFirst = bookRealm.tagFirst {
            calibreBook.tags.append(tagFirst)
        }
        if let tagSecond = bookRealm.tagSecond {
            calibreBook.tags.append(tagSecond)
        }
        if let tagThird = bookRealm.tagThird {
            calibreBook.tags.append(tagThird)
        }
        calibreBook.tags.append(contentsOf: bookRealm.tagsMore)
        
        if calibreBook.readPos.getDevices().count > 1 {
            if let pos = calibreBook.readPos.getPosition(deviceName), pos.lastReadPage == 0 {
                calibreBook.readPos.removePosition(deviceName)
            }
        }
        
        return calibreBook
    }
    
    func updateLibraryPluginColumnInfo(libraryId: String, columnInfo: CalibreLibraryPluginColumnInfo) -> CalibreLibrary? {
        guard calibreLibraries.contains(where: { $0.key == libraryId }) else { return nil }
        calibreLibraries[libraryId]?.pluginColumns[columnInfo.getID()] = columnInfo
        
        guard let library = calibreLibraries[libraryId] else { return nil }
        try? updateLibraryRealm(library: library, realm: self.realm)
        return library
    }
    
    func getCustomDictViewer() -> (Bool, URL?) {
        return (UserDefaults.standard.bool(forKey: Constants.KEY_DEFAULTS_MDICT_VIEWER_ENABLED),
            UserDefaults.standard.url(forKey: Constants.KEY_DEFAULTS_MDICT_VIEWER_URL)
        )
    }
    
    func getCustomDictViewerNew(library: CalibreLibrary) -> (Bool, URL?) {
        var result: (Bool, URL?) = (false, nil)
        guard let dsreaderHelperServer = queryServerDSReaderHelper(server: library.server),
              let pluginDictionaryViewer = library.pluginDictionaryViewerWithDefault,
              pluginDictionaryViewer.isEnabled() else { return result }

        let connector = DSReaderHelperConnector(calibreServerService: calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: CalibreLibraryGoodreadsSync())
        guard let endpoint = connector.endpointDictLookup() else { return result }
        result.1 = endpoint.url
        result.0 = result.1 != nil
        
        return result
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
                try updateLibraryRealm(library: library, realm: self.realm)
            } catch {
            
            }
        }
    }
    
    func updateServerRealm(server: CalibreServer) throws {
        let serverRealm = CalibreServerRealm()
        serverRealm.name = server.name
        serverRealm.baseUrl = server.baseUrl
        serverRealm.hasPublicUrl = server.hasPublicUrl
        serverRealm.publicUrl = server.publicUrl
        serverRealm.hasAuth = server.hasAuth
        serverRealm.username = server.username
        serverRealm.password = server.password
        serverRealm.defaultLibrary = server.defaultLibrary
        serverRealm.lastLibrary = server.lastLibrary
        try realm.write {
            realm.add(serverRealm, update: .all)
        }
    }
    
    func updateLibraryRealm(library: CalibreLibrary, realm: Realm) throws {
        let libraryRealm = CalibreLibraryRealm()
        libraryRealm.key = library.key
        libraryRealm.name = library.name
        libraryRealm.serverUrl = library.server.baseUrl
        libraryRealm.serverUsername = library.server.username
        libraryRealm.autoUpdate = library.autoUpdate
        libraryRealm.discoverable = library.discoverable
        libraryRealm.lastModified = library.lastModified
        library.pluginColumns.forEach {
            if let plugin = $0.value as? CalibreLibraryDSReaderHelper {
                libraryRealm.pluginDSReaderHelper = plugin.managedObject()
            }
            if let plugin = $0.value as? CalibreLibraryReadingPosition {
                libraryRealm.pluginReadingPosition = plugin.managedObject()
            }
            if let plugin = $0.value as? CalibreLibraryGoodreadsSync {
                libraryRealm.pluginGoodreadsSync = plugin.managedObject()
            }
            if let plugin = $0.value as? CalibreLibraryCountPages {
                libraryRealm.pluginCountPages = plugin.managedObject()
            }
        }
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
            NSPredicate(format: "id = %@ AND serverUrl = %@ AND serverUsername = %@ AND libraryName = %@",
                        NSNumber(value: book.id),
                        book.library.server.baseUrl,
                        book.library.server.username,
                        book.library.name
            )
        ).first
    }

    func queryLibraryBookRealmCount(library: CalibreLibrary, realm: Realm) -> Int {
        return realm.objects(CalibreBookRealm.self).filter(
            NSPredicate(format: "serverUrl = %@ AND serverUsername = %@ AND libraryName = %@",
                        library.server.baseUrl,
                        library.server.username,
                        library.name
            )
        ).count
    }
    
    func updateBookRealm(book: CalibreBook, realm: Realm) {
        let bookRealm = CalibreBookRealm()
        bookRealm.id = book.id
        bookRealm.serverUrl = book.library.server.baseUrl
        bookRealm.serverUsername = book.library.server.username
        bookRealm.libraryName = book.library.name
        bookRealm.title = book.title

        var authors = book.authors
        bookRealm.authorFirst = authors.popFirst() ?? "Unknown"
        bookRealm.authorSecond = authors.popFirst()
        bookRealm.authorThird = authors.popFirst()
        bookRealm.authorsMore.replaceSubrange(bookRealm.authorsMore.indices, with: authors)

        bookRealm.comments = book.comments
        bookRealm.publisher = book.publisher
        bookRealm.series = book.series
        bookRealm.seriesIndex = book.seriesIndex
        bookRealm.rating = book.rating
        bookRealm.size = book.size
        bookRealm.pubDate = book.pubDate
        bookRealm.timestamp = book.timestamp
        bookRealm.lastModified = book.lastModified
        bookRealm.lastSynced = book.lastSynced
        
        var tags = book.tags
        bookRealm.tagFirst = tags.popFirst()
        bookRealm.tagSecond = tags.popFirst()
        bookRealm.tagThird = tags.popFirst()
        bookRealm.tagsMore.replaceSubrange(bookRealm.tagsMore.indices, with: tags)

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
    
    func queryServerDSReaderHelper(server: CalibreServer) -> CalibreServerDSReaderHelper? {
        guard let realm = Thread.isMainThread ? self.realm : try? Realm(configuration: self.realmConf) else { return nil }
        
        let objs = realm.objects(CalibreServerDSReaderHelperRealm.self).filter(
            NSPredicate(format: "id = %@", server.id)
        )
        guard objs.count > 0 else { return nil }
//        objs.forEach {
//            print("\(#function) \($0)")
//        }
        return CalibreServerDSReaderHelper(managedObject: objs.first!)
    }
    
    func updateServerDSReaderHelper(dsreaderHelper: CalibreServerDSReaderHelper, realm: Realm) {
        let obj = dsreaderHelper.managedObject()
        try? realm.write {
            realm.add(obj, update: .all)
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
                try updateLibraryRealm(library: calibreLibraries[libraryId]!, realm: self.realm)
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
    
    func shouldAutoUpdateGoodreads(library: CalibreLibrary) -> (CalibreServerDSReaderHelper, CalibreLibraryDSReaderHelper, CalibreLibraryGoodreadsSync)? {
        // must have dsreader helper info and enabled by server
        guard let dsreaderHelperServer = queryServerDSReaderHelper(server: library.server), dsreaderHelperServer.port > 0 else { return nil }
        guard let configuration = dsreaderHelperServer.configuration, let dsreader_helper_prefs = configuration.dsreader_helper_prefs, dsreader_helper_prefs.plugin_prefs.Options.goodreadsSyncEnabled else { return nil }
        
        // check if user disabled auto update
        guard let dsreaderHelperLibrary = library.pluginDSReaderHelperWithDefault, dsreaderHelperLibrary.isEnabled() else { return nil }
        
        // check if profile name exists
        guard let goodreadsSync = library.pluginGoodreadsSyncWithDefault, goodreadsSync.isEnabled() else { return nil }
        guard let goodreads_sync_prefs = configuration.goodreads_sync_prefs, goodreads_sync_prefs.plugin_prefs.Users.contains(where: { $0.key == goodreadsSync.profileName }) else { return nil }
        
        return (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync)
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
           let (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync) = shouldAutoUpdateGoodreads(library: library),
           dsreaderHelperLibrary.autoUpdateGoodreadsBookShelf {
            let connector = DSReaderHelperConnector(calibreServerService: calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: goodreadsSync)
            let ret = connector.addToShelf(goodreads_id: goodreadsId, shelfName: "currently-reading")
        }
    }
    
    func removeFromShelf(inShelfId: String) {
        if readingBook?.inShelfId == inShelfId {
            readingBook?.inShelf = false
            NotificationCenter.default.post(Notification(name: .YABR_ReadingBookRemovedFromShelf))
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
           let (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync) = shouldAutoUpdateGoodreads(library: library),
           dsreaderHelperLibrary.autoUpdateGoodreadsBookShelf {
            let connector = DSReaderHelperConnector(calibreServerService: calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: goodreadsSync)
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
        let updatedReadingPosition = self.updatedReadingPosition
        
        defaultLog.info("pageNumber:  \(updatedReadingPosition.lastPosition[0])")
        defaultLog.info("pageOffsetX: \(updatedReadingPosition.lastPosition[1])")
        defaultLog.info("pageOffsetY: \(updatedReadingPosition.lastPosition[2])")
        
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
        
        if let pluginReadingPosition = calibreLibraries[readingBook.library.id]?.pluginReadingPositionWithDefault, pluginReadingPosition.isEnabled() {
            let ret = calibreServerService.updateBookReadingPosition(book: readingBook, columnName: pluginReadingPosition.readingPositionCN, alertDelegate: alertDelegate, success: nil)
            
            if ret != 0 {
                updatingMetadataStatus = "Internal Error"
                updatingMetadata = false
                alertDelegate.alert(msg: updatingMetadataStatus)
                return
            }
        }
        
        if floor(updatedReadingPosition.lastProgress) > readerInfo.position.lastProgress || updatedReadingPosition.lastProgress < floor(readerInfo.position.lastProgress),
           let library = calibreLibraries[readingBook.library.id],
           let goodreadsId = readingBook.identifiers["goodreads"],
           let (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync) = shouldAutoUpdateGoodreads(library: library),
           dsreaderHelperLibrary.autoUpdateGoodreadsProgress {
            let connector = DSReaderHelperConnector(calibreServerService: calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: goodreadsSync)
            connector.updateReadingProgress(goodreads_id: goodreadsId, progress: updatedReadingPosition.lastProgress)
            
            if goodreadsSync.isEnabled(), goodreadsSync.readingProgressColumnName.count > 1 {
                calibreServerService.updateMetadata(library: library, bookId: readingBook.id, metadata: [
                    [goodreadsSync.readingProgressColumnName, Int(updatedReadingPosition.lastProgress)]
                ])
            }
        }
        
    }
    
    /// used for removing position entries
    func updateReadingPosition(book: CalibreBook, alertDelegate: AlertDelegate) {
        self.updateBook(book: book)
        
        guard let pluginReadingPosition = calibreLibraries[book.library.id]?.pluginReadingPositionWithDefault, pluginReadingPosition.isEnabled() else {
            return
        }

        let ret = calibreServerService.updateBookReadingPosition(book: book, columnName: pluginReadingPosition.readingPositionCN, alertDelegate: alertDelegate) {
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
                try? self.updateLibraryRealm(library: library, realm: self.realm)
                
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
            
            self.refreshShelfMetadata(with: serverIds)
            
            self.refreshServerDSHelperConfiguration(
                with: self.calibreServers.filter {
                    $0.value.isLocal == false
                }.map{ $0.key }
            )
            
            self.syncLibrariesIncremental(
                with: self.calibreServers.filter {
                    $0.value.isLocal == false
                }.map{ $0.key }
            )
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
                    //print("refreshShelfMetadata \(task) \(entry)")
                    
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
                
                NotificationCenter.default.post(Notification(name: .YABR_BooksRefreshed))
            }
    }
    
    func refreshServerDSHelperConfiguration(with serverIds: [String]) {
        dshelperRefreshCancellable?.cancel()
        
        dshelperRefreshCancellable = serverIds.publisher.flatMap { serverId -> AnyPublisher<(id: String, port: Int, data: Data), URLError> in
            guard let server = self.calibreServers[serverId],
                  let dsreaderHelperServer = self.queryServerDSReaderHelper(server: server),
                  let publisher = DSReaderHelperConnector(calibreServerService: self.calibreServerService, server: server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: nil).refreshConfiguration()
            else {
                return Just((id: serverId, port: 0, data: Data())).setFailureType(to: URLError.self).eraseToAnyPublisher()
            }
            
            return publisher
        }
        .sink(receiveCompletion: { completion in
            
        }, receiveValue: { task in
            let decoder = JSONDecoder()
            var config: CalibreDSReaderHelperConfiguration? = nil
            do {
                config = try decoder.decode(CalibreDSReaderHelperConfiguration.self, from: task.data)
            } catch {
                print(error)
            }
            print("\(#function) \(task.id) \(task.port)")
            if let config = config, config.dsreader_helper_prefs != nil, let realm = try? Realm(configuration: self.realmConf) {
                let dsreaderHelperServer = CalibreServerDSReaderHelper(id: task.id, port: task.port, configurationData: task.data, configuration: config)
                
                self.updateServerDSReaderHelper(dsreaderHelper: dsreaderHelperServer, realm: realm)
            }
        })
    }
    
    func syncLibrariesIncremental(with serverIds: [String]) {
        syncLibrariesIncrementalCancellable?.cancel()
        
        syncLibrariesIncrementalCancellable = calibreLibraries.filter {
            serverIds.contains( $0.value.server.id )
        }.map { $0.value }.publisher.flatMap { library -> AnyPublisher<CalibreCustomColumnInfoResult, Never> in
            guard (self.librarySyncStatus[library.id]?.isSync ?? false) == false else {
                print("\(#function) isSync \(library.id)")
                return Just(CalibreCustomColumnInfoResult(library: library, result: ["just_syncing":[:]]))
                    .setFailureType(to: Never.self).eraseToAnyPublisher()
            }
            DispatchQueue.main.sync {
                self.librarySyncStatus[library.id] = (true, false, "")
            }
            print("\(#function) startSync \(library.id)")

            return self.calibreServerService.getCustomColumnsPublisher(library: library)
        }
        .flatMap { customColumnResult -> AnyPublisher<CalibreCustomColumnInfoResult, Never> in
            var filter = ""     //  "last_modified:>2022-02-20T00:00:00.000000+00:00"
            if let realm = try? Realm(configuration: self.realmConf),
               let libraryRealm = realm.objects(CalibreLibraryRealm.self).filter(
                NSPredicate(format: "serverUrl = %@ AND serverUsername = %@ AND name = %@",
                            customColumnResult.library.server.baseUrl,
                            customColumnResult.library.server.username,
                            customColumnResult.library.name
                )).first {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions.formUnion(.withColonSeparatorInTimeZone)
                formatter.timeZone = .current
                let lastModifiedStr = formatter.string(from: libraryRealm.lastModified)
                filter = "last_modified:>=\(lastModifiedStr)"
            }
            print("\(#function) syncLibraryPublisher \(customColumnResult.library.id) \(filter)")
            return self.calibreServerService.syncLibraryPublisher(resultPrev: customColumnResult, filter: filter)
        }
        .subscribe(on: DispatchQueue.global())
        .sink { complete in
            
        } receiveValue: { results in
            self.syncLibrariesSinkValue(results: results)
        }
    }
    
    func syncLibrariesSinkValue(results: CalibreCustomColumnInfoResult) {
        var library = results.library
        print("\(#function) receiveValue \(library.id)")
        
        guard results.result["just_syncing"] == nil else { return }
        var isError = false
        
        defer {
            DispatchQueue.main.async {
                self.calibreLibraries[library.id] = library
                try? self.updateLibraryRealm(library: library, realm: self.realm)
                
                self.librarySyncStatus[library.id]?.isSync = false
                self.librarySyncStatus[library.id]?.isError = isError
                print("\(#function) finishSync \(library.id)")
            }
        }
        
        guard results.result["error"] == nil else {
            isError = true
            return
        }
        
        if let result = results.result["result"] {
            library.customColumnInfos = result
            
            DispatchQueue.main.async {
                self.librarySyncStatus[library.id]?.msg = "Success"
            }
        }
        
        guard results.list.book_ids.first != -1 else {
            isError = true
            return
        }
        
        guard let realm = try? Realm(configuration: self.realmConf) else {
            isError = true
            return
        }
        
        let dateFormatter = ISO8601DateFormatter()
        let dateFormatter2 = ISO8601DateFormatter()
        dateFormatter2.formatOptions.formUnion(.withFractionalSeconds)
        
        results.list.book_ids.chunks(size: 256).forEach { chunk in
            try? realm.write {
                chunk.map {$0.description}.forEach { id in
                    guard let lastModifiedStr = results.list.data.last_modified[id]?.v,
                          let lastModified = dateFormatter.date(from: lastModifiedStr) ?? dateFormatter2.date(from: lastModifiedStr) else { return }
                    realm.create(CalibreBookRealm.self, value: [
                        "primaryKey": CalibreBookRealm.PrimaryKey(serverUsername: library.server.username, serverUrl: library.server.baseUrl, libraryName: library.name, id: id),
                        "lastModified": lastModified
                    ], update: .modified)
                }
            }
        }
        
        let partialPrimaryKey = CalibreBookRealm.PrimaryKey(serverUsername: library.server.username, serverUrl: library.server.baseUrl, libraryName: library.name, id: "")
        
        try? realm.objects(CalibreBookRealm.self).filter(
            NSPredicate(format: "lastSynced < lastModified AND primaryKey BEGINSWITH %@", partialPrimaryKey)
        ).map { result throws -> Int32 in
            result.id
        }.chunks(size: 256).forEach { chunk in
            print("\(#function) \(library.name) \(chunk)")
            if let task = calibreServerService.buildBooksMetadataTask(library: library, books: chunk.map{ $0.description }) {
                getBooksMetadataSubject.send(task)
            }
        }
        
        if currentCalibreLibraryId == library.id,
           results.list.book_ids.isEmpty == false {
            DispatchQueue.main.async {
                self.currentCalibreLibraryId = ""
                self.currentCalibreLibraryId = library.id
            }
        }
    }
    
    
    func logStartCalibreActivity(type: String, request: URLRequest, startDatetime: Date, bookId: Int32?, libraryId: String?) {
        activityDispatchQueue.async {
            guard let realm = try? Realm(configuration: self.realmConf) else { return }
            
            let obj = CalibreActivityLogEntry()
            
            obj.type = type
            
            obj.startDatetime = startDatetime
            obj.bookId = bookId ?? 0
            obj.libraryId = libraryId
            
            obj.endpoingURL = request.url?.absoluteString
            obj.httpMethod = request.httpMethod
            obj.httpBody = request.httpBody
            request.allHTTPHeaderFields?.forEach {
                obj.requestHeaders.append($0.key)
                obj.requestHeaders.append($0.value)
            }
            
            try? realm.write {
                realm.add(obj)
            }
        }
    }
    
    func logFinishCalibreActivity(type: String, request: URLRequest, startDatetime: Date, finishDatetime: Date, errMsg: String) {
        activityDispatchQueue.async {
            guard let realm = try? Realm(configuration: self.realmConf) else { return }
            
            guard let activity = realm.objects(CalibreActivityLogEntry.self).filter(
                NSPredicate(format: "type = %@ AND startDatetime = %@ AND endpoingURL = %@",
                            type,
                            startDatetime as NSDate,
                            request.url?.absoluteString ?? ""
                )
            ).first else { return }
            
            try? realm.write {
                activity.finishDatetime = finishDatetime
                activity.errMsg = errMsg
            }
        }
    }
    
    func removeCalibreActivity(obj: CalibreActivityLogEntry) {
        guard let realm = try? Realm(configuration: self.realmConf) else { return }

        try? realm.write {
            realm.delete(obj)
        }
    }
    
    func listCalibreActivities(libraryId: String? = nil, bookId: Int32? = nil, startDatetime: Date = Date(timeIntervalSinceNow: TimeInterval(-86400))) -> [CalibreActivityLogEntry] {
        guard let realm = try? Realm(configuration: self.realmConf) else { return [] }
        
        var pred = NSPredicate()
        if let libraryId = libraryId {
            if let bookId = bookId {
                pred = NSPredicate(
                    format: "startDatetime >= %@ AND libraryId = %@ AND bookId = %@",
                    Date(timeIntervalSinceNow: TimeInterval(-86400)) as NSDate,
                    libraryId,
                    NSNumber(value: bookId)
                )
            } else {
                pred = NSPredicate(
                    format: "startDatetime >= %@ AND libraryId = %@",
                    Date(timeIntervalSinceNow: TimeInterval(-86400)) as NSDate,
                    libraryId
                )
            }
        } else {
            pred = NSPredicate(
                format: "startDatetime > %@",
                Date(timeIntervalSinceNow: TimeInterval(-86400)) as NSDate
            )
        }
        
        let activities = realm.objects(CalibreActivityLogEntry.self).filter(pred)
        
        return activities.map { $0 }.sorted { $1.startDatetime < $0.startDatetime }
    }
    
    func cleanCalibreActivities(startDatetime: Date) {
        let activities = realm.objects(CalibreActivityLogEntry.self).filter(
            NSPredicate(
                format: "startDatetime < %@",
                startDatetime as NSDate
            )
        )
        try? realm.write {
            realm.delete(activities)
        }
    }
    
    func logBookDeviceReadingPositionHistoryStart(book: CalibreBook, startPosition: BookDeviceReadingPosition, startDatetime: Date) {
        activityDispatchQueue.async {
            guard let realm = try? Realm(configuration: self.realmConf) else { return }
            
            let historyEntry = BookDeviceReadingPositionHistoryRealm()
            historyEntry.bookId = book.id
            historyEntry.libraryId = book.library.id
            historyEntry.startDatetime = startDatetime
            historyEntry.startPosition = startPosition.managedObject()
            
            try? realm.write {
                realm.add(historyEntry)
            }
        }
    }
    
    func logBookDeviceReadingPositionHistoryFinish(book: CalibreBook, endPosition: BookDeviceReadingPosition) {
        activityDispatchQueue.async {
            guard let realm = try? Realm(configuration: self.realmConf) else { return }
            
            guard let historyEntry = realm.objects(BookDeviceReadingPositionHistoryRealm.self).filter(
                NSPredicate(format: "bookId = %@ AND libraryId = %@",
                            NSNumber(value: book.id),
                            book.library.id
                )
            ).sorted(by: [SortDescriptor(keyPath: "startDatetime", ascending: false)]).first else { return }
            
            guard historyEntry.endPosition == nil else { return }
            
            try? realm.write {
                historyEntry.endPosition = endPosition.managedObject()
            }
        }
    }
    
    func listBookDeviceReadingPositionHistory(bookId: Int32? = nil, libraryId: String? = nil, startDateAfter: Date? = nil) -> [BookDeviceReadingPositionHistoryRealm] {
        guard let realm = try? Realm(configuration: self.realmConf) else { return [] }

        var pred: NSPredicate? = nil
        if let bookId = bookId, let libraryId = libraryId {
            pred = NSPredicate(format: "bookId = %@ AND libraryId = %@",
                               NSNumber(value: bookId), libraryId
                   )
            if let startDateAfter = startDateAfter {
                pred = NSPredicate(
                    format: "bookId = %@ AND libraryId = %@ AND startDatetime >= %@",
                    NSNumber(value: bookId), libraryId, startDateAfter as NSDate
                )
            }
        } else {
            if let startDateAfter = startDateAfter {
                pred = NSPredicate(
                    format: "startDatetime >= %@",
                    startDateAfter as NSDate
                )
            }
        }
        
        var results = realm.objects(BookDeviceReadingPositionHistoryRealm.self);
        if let predNotNil = pred {
            results = results.filter(predNotNil)
        }
        results = results.sorted(by: [SortDescriptor(keyPath: "startDatetime", ascending: false)])
        print("\(#function) \(results.count)")
        return results.map {$0}
    }
    
    func getReadingStatistics(bookId: Int32? = nil, libraryId: String? = nil, limitDays: Int = 7) -> [Double] {
        let startDate = Calendar.current.startOfDay(for: Date(timeIntervalSinceNow: Double(-86400 * (limitDays))))
        
        let list = listBookDeviceReadingPositionHistory(bookId: bookId, libraryId: libraryId, startDateAfter: startDate)
        let result = list.reduce(into: [Double].init(repeating: 0.0, count: limitDays+1) ) { result, history in
            guard let epoch = history.endPosition?.epoch, epoch > history.startDatetime.timeIntervalSince1970 else { return }
            let duration = epoch - history.startDatetime.timeIntervalSince1970
            let readDayDate = Calendar.current.startOfDay(for: history.startDatetime)
            let nowDayDate = Calendar.current.startOfDay(for: Date())
            let offset = limitDays - Int(floor(nowDayDate.timeIntervalSince(readDayDate) / 86400.0))
            if offset < 0 || offset > limitDays { return }
            result[offset] += duration / 60
        }
        return result
    }
    
    func updateBookModel() -> [BookModelSection] {
        var bookModelSection = [BookModelSection]()

        guard let realm = try? Realm(configuration: self.realmConf) else { return [] }
        
        for sectionInfo in [("lastModified", "Modified", "last_modified"),
                            ("timestamp", "New in Library", "last_added"),
                            ("pubDate", "Last Published", "last_published")] {
            let results = realm.objects(CalibreBookRealm.self)
                .sorted(byKeyPath: sectionInfo.0, ascending: false)
                
            var bookModel = [BookModel]()
            for i in 0 ..< results.count {
                if bookModel.count > 20 {
                    break
                }
                if let book = self.convert(bookRealm: results[i]),
                   book.library.discoverable,
                   let coverURL = book.coverURL {
                    bookModel.append(BookModel(bookCoverSource: coverURL.absoluteString, bookId: book.inShelfId, bookTitle: book.title, bookProgress: Int(self.getLatestReadingPosition(book: book)?.lastProgress ?? 0.0), bookStatus: .READY))
                    
                    // print("updateBookModel \(sectionInfo.0) \(book)")
                }
            }
            
            let section = BookModelSection(sectionName: sectionInfo.1, sectionId: sectionInfo.2, sectionBooks: bookModel)
            bookModelSection.append(section)
        }
        
        let emptyBook = CalibreBook(id: 0, library: self.currentCalibreLibrary!)
        
        guard let deviceMapSerialize = try? emptyBook.readPos.getCopy().compactMapValues( { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ),
              let readPosDataEmpty = try? JSONSerialization.data(withJSONObject: ["deviceMap": deviceMapSerialize], options: []) as NSData else {
            return []
        }
        

        let resultsWithReadPos = realm.objects(CalibreBookRealm.self)
            .filter(NSPredicate(format: "readPosData != nil AND readPosData != %@", readPosDataEmpty))
            .compactMap {
                self.convert(bookRealm: $0)
            }
            .filter { book in
                let lastProgress =
                book.readPos.getDevices().max { lhs, rhs in
                    lhs.lastProgress < rhs.lastProgress
                }?.lastProgress ?? 0.0
                return lastProgress > 5.0 && lastProgress < 99.0
            }
            .sorted { lb, rb in
                lb.readPos.getDevices().max { lhs, rhs in
                    lhs.lastProgress < rhs.lastProgress
                }?.lastProgress ?? 0.0 > rb.readPos.getDevices().max { lhs, rhs in
                    lhs.lastProgress < rhs.lastProgress
                }?.lastProgress ?? 0.0
            }
        print("resultsWithReadPos count=\(resultsWithReadPos.count)")
        
        var authorSet = Set<String>()
        var seriesSet = Set<String>()
        var tagSet = Set<String>()
        
        resultsWithReadPos.forEach { book in
//            print("resultsWithReadPos \(book.title)")
//            print("resultsWithReadPos \(String(describing: bookRealm.readPosData))")
//            guard let book = modelData.convert(bookRealm: bookRealm) else { return }
//            print("resultsWithReadPos pos=\(book)")
            if let author = book.authors.first {
                authorSet.insert(author)
            }
            if book.series.count > 0 {
                seriesSet.insert(book.series)
            }
            if let tag = book.tags.first {
                tagSet.insert(tag)
            }
            
            //guard let book = modelData.convert(bookRealm: bookRealm) else { return }
        }
//        print("resultsWithReadPos \(authorSet) \(seriesSet) \(tagSet)")
        
        let readingSection = BookModelSection(
            sectionName: "Reading",
            sectionId: "reading",
            sectionBooks: resultsWithReadPos
                .filter {
                    $0.inShelf == false
                }
                .map { book in
                    BookModel(
                        bookCoverSource: book.coverURL?.absoluteString ?? ".",
                        bookId: book.inShelfId,
                        bookTitle: book.title,
                        bookProgress: Int(
                            book.readPos.getDevices().max { lhs, rhs in
                                lhs.lastProgress < rhs.lastProgress
                            }?.lastProgress ?? 0.0),
                        bookStatus: .READY
                    )
                }
        )
        bookModelSection.append(readingSection)
        
        [
            (seriesSet, "series", "seriesIndex", true),
            (authorSet, "authorFirst", "pubDate", false),
            (tagSet, "tagFirst", "pubDate", false)
        ].forEach { def in
            def.0.sorted().forEach { member in
                let books: [BookModel] = realm.objects(CalibreBookRealm.self)
                    .filter(NSPredicate(format: "%K == %@", def.1, member))
                    .sorted(byKeyPath: def.2, ascending: def.3)
                    .prefix(10)
                    .compactMap {
                        self.convert(bookRealm: $0)
                    }
                    .map { book in
                        BookModel(
                            bookCoverSource: book.coverURL?.absoluteString ?? ".",
                            bookId: book.inShelfId,
                            bookTitle: book.title,
                            bookProgress: Int(
                                book.readPos.getDevices().max { lhs, rhs in
                                    lhs.lastProgress < rhs.lastProgress
                                }?.lastProgress ?? 0.0),
                            bookStatus: .READY
                        )
                    }
                
                guard books.count > 1 else { return }
                
                let readingSection = BookModelSection(
                    sectionName: member,
                    sectionId: member,
                    sectionBooks: books)

                bookModelSection.append(readingSection)
            }
        }

        return bookModelSection
    }
    
}
