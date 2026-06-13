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

final class ModelData: ObservableObject, CalibreServerConfigProvider, LibraryProvider {
    static var shared: ModelData?
    
    func getLibraries() -> [String: CalibreLibrary] {
        return calibreLibraries
    }
    
    @Published var deviceName = UIDevice.current.name {
        didSet {
            calibreServerService.updateDeviceName(deviceName)
        }
    }
    
        var calibreServers: [String: CalibreServer] {
        get { serverManager.calibreServers }
        set { serverManager.calibreServers = newValue }
    }
    var calibreServerInfoStaging: [String: CalibreServerInfo] {
        get { serverManager.calibreServerInfoStaging }
        set { serverManager.calibreServerInfoStaging = newValue }
    }
    
    var calibreLibraries: [String: CalibreLibrary] {
        get { libraryManager.calibreLibraries }
        set { libraryManager.calibreLibraries = newValue }
    }
    var calibreLibraryInfoStaging: [String: CalibreLibraryInfo] {
        get { libraryManager.calibreLibraryInfoStaging }
        set { libraryManager.calibreLibraryInfoStaging = newValue }
    }
    var localLibrary: CalibreLibrary? {
        get { libraryManager.localLibrary }
        set { libraryManager.localLibrary = newValue }
    }
    
    @Published var activeTab = 0
    var documentServer: CalibreServer? {
        get { serverManager.documentServer }
        set { serverManager.documentServer = newValue }
    }
    
    //for LibraryInfoView
    @Published var defaultFormat = Format.PDF
    var formatReaderMap = [Format: [ReaderType]]()
    var formatList = [Format]()
    
    static let SaveBooksMetadataRealmQueue = DispatchQueue(label: "saveBooksMetadata", qos: .userInitiated)
    
    @Published var booksInShelf = [String: CalibreBook]()
    @Published var booksAnnotation = [String: CalibreBook]()
    
    let bookImportedSubject = PassthroughSubject<BookImportInfo, Never>()
    let dismissAllSubject = PassthroughSubject<String, Never>()
    
    let recentShelfModelSubject = PassthroughSubject<[BookModel], Never>()
    let discoverShelfModelSubject = PassthroughSubject<[ShelfModelSection], Never>()
    
    var presentingStack = [Binding<Bool>]()
    
    var currentBookId: String = "" {
        didSet {
            self.selectedBookId = currentBookId
        }
    }

    @Published var selectedBookId: String? = nil {
        didSet {
            if let selectedBookId = selectedBookId,
               readingBookInShelfId != selectedBookId {
                readingBookInShelfId = selectedBookId
            }
        }
    }
    
    let bookReaderActivitySubject = PassthroughSubject<ScenePhase, Never>()
    
    var calibreCancellables = Set<AnyCancellable>()
    
    @Published var downloadManager = BookDownloadManager()
    @Published var sessionManager = ReadingSessionManager()

    var readingBookInShelfId: String? {
        get { sessionManager.readingBookInShelfId }
        set { sessionManager.readingBookInShelfId = newValue }
    }
    var readingBook: CalibreBook? {
        get { sessionManager.readingBook }
        set { sessionManager.readingBook = newValue }
    }
    var readerInfo: ReaderInfo? {
        get { sessionManager.readerInfo }
        set { sessionManager.readerInfo = newValue }
    }
    var presentingEBookReaderFromShelf: Bool {
        get { sessionManager.presentingEBookReaderFromShelf }
        set { sessionManager.presentingEBookReaderFromShelf = newValue }
    }
    var selectedPosition: String {
        get { sessionManager.selectedPosition }
        set { sessionManager.selectedPosition = newValue }
    }
    
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
    
    static var RealmSchemaVersion:UInt64 = 138
    var realm: Realm!
    var realmSaveBooksMetadata: Realm!
    var realmConf: Realm.Configuration!
    
    var logger: CalibreActivityLogger!
    
    let kfImageCache = ImageCache.default
    var authResponsor = AuthResponsor()
    
    var databaseService = DatabaseService.shared
    
    lazy var serverManager = CalibreServerManager(modelData: self, databaseService: self.databaseService)
    lazy var libraryManager = CalibreLibraryManager(modelData: self, databaseService: self.databaseService)
    
    lazy var calibreServerService = CalibreServerService(logger: self.logger, config: self, database: self.databaseService)

    lazy var librarySearchManager = CalibreLibrarySearchManager(service: self.calibreServerService, modelData: self)
    
    lazy var shelfDataModel = YabrShelfDataModel(service: self.calibreServerService, searchManager: librarySearchManager, modelData: self)
    
    let probeLibraryLastModifiedSubject = PassthroughSubject<CalibreSyncLibraryRequest, Never>()
    
    let syncServerHelperConfigSubject = PassthroughSubject<String, Never>()
    
    var probeTimer: AnyCancellable?
    
    /// inShelfId for single book
    /// empty string for full update
    let calibreUpdatedSubject = PassthroughSubject<calibreUpdatedSignal, Never>()
    
    var librarySyncStatus: [String: CalibreSyncStatus] {
        get { libraryManager.librarySyncStatus }
        set { libraryManager.librarySyncStatus = newValue }
    }

    @Published var fontsManager = FontsManager()
    var userFontInfos: [String: FontInfo] {
        get { fontsManager.userFontInfos }
        set { fontsManager.userFontInfos = newValue }
    }

    @Published var bookModelSection = [ShelfModelSection]()

    init(mock: Bool = false) {
        ModelData.shared = self
        
        // Ensure default configuration is set early to prevent crashes in SwiftUI views using ObservedResults
        ModelData.RealmSchemaVersion = 138
        let initialConf = Realm.Configuration(
            schemaVersion: ModelData.RealmSchemaVersion,
            migrationBlock: { _, _ in }
        )
        Realm.Configuration.defaultConfiguration = initialConf
        self.realmConf = initialConf
        
        kfImageCache.diskStorage.config.expiration = .days(28)
        KingfisherManager.shared.defaultOptions = [.requestModifier(AuthPlugin(modelData: self))]
        ImageDownloader.default.authenticationChallengeResponder = authResponsor
        
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

        downloadManager.modelData = self
        sessionManager.setup(modelData: self)
        
        fontsManager.reloadCustomFonts()
        
//        calibreServerService.defaultUrlSessionConfiguration.timeoutIntervalForRequest = 600
//        calibreServerService.defaultUrlSessionConfiguration.httpMaximumConnectionsPerHost = 2
        
        libraryManager.registerProbeLibraryLastModifiedCancellable()
        
        registerRecentShelfUpdater()
        
        downloadManager.bookDownloadedSubject.sink { book in
            self.calibreUpdatedSubject.send(.book(book))
        }.store(in: &calibreCancellables)
        
        serverManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &calibreCancellables)
        
        libraryManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &calibreCancellables)
        
        if mock {
            try? tryInitializeDatabase() { _ in
                
            }
            initializeDatabase()
            
            let library = calibreLibraries.first!.value
            
            var book = CalibreBook(id: 1, library: library)
            
            book.title = "Mock Book Title"
            
            book.formats[Format.EPUB.rawValue] = .init(filename: book.title + ".epub", serverSize: 1024000, serverMTime: Date(timeIntervalSince1970: 1645495322), cached: true, cacheSize: 1024000, cacheMTime: Date(timeIntervalSince1970: 1645495322), manifest: nil)
            if let bookSavedUrl = getSavedUrl(book: book, format: Format.EPUB),
               FileManager.default.fileExists(atPath: bookSavedUrl.path) == false {
                FileManager.default.createFile(atPath: bookSavedUrl.path, contents: String("EPUB").data(using: .utf8), attributes: nil)
            }
            book.readPos = BookAnnotation(id: book.id, library: book.library, localFilename: book.title + ".epub")
            
            var position = BookDeviceReadingPosition(
                id: self.deviceName,
                readerName: ReaderType.YabrEPUB.rawValue,
                maxPage: 99,
                lastReadPage: 1,
                lastReadChapter: "Mock Last Chapter",
                lastChapterProgress: 5,
                lastProgress: 1,
                furthestReadPage: 98,
                furthestReadChapter: "Mock Furthest Chapter",
                lastPosition: [1,1,1]
            )
            position.epoch = 1645495322
            
            book.readPos.updatePosition(position)
            
            self.readingBook = book
            
            
//                title: "Mock Title",
//                authors: ["Mock Author", "Mock Auther 2"],
//                comments: "<p>Mock Comment",
//                publisher: "Mock Publisher",
//                series: "Mock Series",
//                rating: 8,
//                size: 12345678,
//                pubDate: Date.init(timeIntervalSince1970: TimeInterval(1262275200)),
//                timestamp: Date.init(timeIntervalSince1970: TimeInterval(1262275200)),
//                lastModified: Date.init(timeIntervalSince1970: TimeInterval(1577808000)),
//                lastSynced: Date.init(timeIntervalSince1970: TimeInterval(1577808000)),
//                lastUpdated: Date.init(timeIntervalSince1970: TimeInterval(1577808000)),
//                tags: ["Mock"],
//                formats: ["EPUB" : FormatInfo(
//                            filename: "file:///mock",
//                            serverSize: 123456,
//                            serverMTime: Date.init(timeIntervalSince1970: TimeInterval(1577808000)),
//                            cached: false, cacheSize: 123456,
//                            cacheMTime: Date.init(timeIntervalSince1970: TimeInterval(1577808000))
//                )],
//                readPos: readPos,
//                identifiers: [:],
//                inShelf: true,
//                inShelfName: "Default")
            self.booksInShelf[self.readingBook!.inShelfId] = self.readingBook
            
            cleanCalibreActivities(startDatetime: Date())
            logStartCalibreActivity(type: "Mock", request: URLRequest(url: URL(string: "http://calibre-server.lan:8080/")!), startDatetime: Date(), bookId: 1, libraryId: library.id)
        }
    }
    
    func tryInitializeDatabase(statusHandler: @escaping (String) -> Void) throws {
        ModelData.RealmSchemaVersion = UInt64(YabrAppInfo.shared.build) ?? 1
        realmConf = Realm.Configuration(
            schemaVersion: ModelData.RealmSchemaVersion,
            migrationBlock: { migration, oldSchemaVersion in
                if oldSchemaVersion < 138 {
                    migration.deleteData(forType: "CalibreUnifiedSearchObject")
                    migration.deleteData(forType: "CalibreUnifiedOffsets")
                }
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
                        if let authorsOld = oldObject?.dynamicList("authors") {
                            var authors = Array<DynamicObject>(authorsOld)
                            ["First", "Second", "Third"].forEach {
                                newObject?.setValue(authors.popFirst(), forKey: "author\($0)")
                                
                            }
                            newObject?.dynamicList("authorsMore").append(objectsIn: authors)
                        }
                        
                        if let tagsOld = oldObject?.dynamicList("tags") {
                            var tags = Array<DynamicObject>(tagsOld)
                            ["First", "Second", "Third"].forEach {
                                newObject?.setValue(tags.popFirst(), forKey: "tag\($0)")
                            }
                            newObject?.dynamicList("tagsMore").append(objectsIn: tags)
                        }
                        
                    }
                }
                if oldSchemaVersion < 46 {
                    migration.enumerateObjects(ofType: CalibreBookRealm.className()) { oldObject, newObject in
                        if let lastModified = oldObject?.value(forKey: "lastModified") {
                            newObject?.setValue(lastModified, forKey: "lastModified")
                        }
                    }
                }
                if oldSchemaVersion < 80 {
                    migration.enumerateObjects(ofType: BookDeviceReadingPositionHistoryRealm.className()) { oldObject, newObject in
                        if let bookId = oldObject?.value(forKey: "bookId") as? Int32 {
                            if let libraryId = oldObject?.value(forKey: "libraryId") as? String,
                               let libraryName = libraryId.components(separatedBy: " - ").last {
                                newObject?.setValue("\(libraryName.replacingOccurrences(of: " ", with: "_")) - \(bookId)", forUndefinedKey: "bookId")
                            } else {
                                newObject?.setValue("Unknown - \(bookId)", forUndefinedKey: "bookId")
                            }
                        } else if let bookId = oldObject?.value(forKey: "bookId") as? String {
                            let components = bookId.components(separatedBy: " - ")
                            let newId = components.suffix(2).joined(separator: " - ")
                            newObject?.setValue(newId, forUndefinedKey: "bookId")
                        }
                    }
                }
                
                if oldSchemaVersion < 90 {
                    /**
                     migrate to UUID based server id
                     1. create new objects with valid UUID, remove old objects,
                     */
                    var servers = [UUID: (baseUrl: String, username: String?)]()
                    migration.enumerateObjects(ofType: CalibreServerRealm.className()) { oldObject, newObject in
                        guard let oldObject = oldObject, let newObject = newObject else { return }
                        guard let baseUrl = oldObject["baseUrl"] as? String else { return }
                        
//                        if let newObject = newObject {
//                            migration.delete(newObject)
//                        }
                        
                        let serverUUID = baseUrl.hasPrefix(".") ? CalibreServer.LocalServerUUID : .init()
//                        let uuidObject = oldObject.copy()
                        newObject["primaryKey"] = serverUUID.uuidString
//                        migration.create(CalibreServerRealm.className(), value: uuidObject)
                        print("\(#function) oldObject=\(oldObject) newObject=\(newObject)")
                        
                        servers[serverUUID] = (baseUrl: baseUrl, username: oldObject["username"] as? String)
                    }
                    
                    var libraries = [String: (serverUUID: UUID, baseUrl: String?, username: String?, key: String?, name: String?)]()
                    migration.enumerateObjects(ofType: CalibreLibraryRealm.className()) { oldObject, newObject in
                        guard let oldObject = oldObject, let newObject = newObject else { return }
                        guard let serverUUID = servers.first(where: {
                            $1.baseUrl == (oldObject["serverUrl"] as? String) && $1.username == (oldObject["serverUsername"] as? String)
                        })?.key else { return }
                        
                        let primaryKey = CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID.uuidString, libraryName: (oldObject["name"] as? String) ?? "Calibre Library")
                        
                        newObject["serverUUID"] = serverUUID.uuidString
                        newObject["primaryKey"] = primaryKey
                        print("\(#function) primaryKey=\(primaryKey) oldObject=\(oldObject) newObject=\(newObject)")
                        
                        libraries[primaryKey] = (
                            serverUUID: serverUUID,
                            baseUrl: oldObject["serverUrl"] as? String,
                            username: oldObject["serverUsername"] as? String,
                            key: oldObject["key"] as? String,
                            name: oldObject["name"] as? String
                        )
                    }
                    
                    var count = 0
                    migration.enumerateObjects(ofType: CalibreBookRealm.className()) { oldObject, newObject in
                        guard let oldObject = oldObject, let newObject = newObject else { return }
                        
                        guard let libraryInfo = libraries.first(where: {
                            $1.baseUrl == (oldObject["serverUrl"] as? String)
                            && $1.username == (oldObject["serverUsername"] as? String)
                            && $1.key != nil
                            && $1.name == (oldObject["libraryName"] as? String)
                        })?.value else {
                            migration.delete(newObject)
                            return
                        }
                        
                        let primaryKey = CalibreBookRealm.PrimaryKey(
                            serverUUID: libraryInfo.serverUUID.uuidString,
                            libraryName: (oldObject["libraryName"] as? String) ?? "Calibre Library",
                            id: (oldObject["id"] as! Int32).description
                        )
                                                
                        newObject["serverUUID"] = libraryInfo.serverUUID.uuidString
                        newObject["primaryKey"] = primaryKey
                        count += 1
                        
                        print("\(#function) count=\(count) oldKey=\(oldObject["primaryKey"]!) newKey=\(newObject["primaryKey"]!)")
                        
                        if count % 1000 == 0 {
                            statusHandler("Progress \(count)")
                        }
                    }
                    
//                    fatalError("TODO")
                    statusHandler("Finalizing...")
                }
                
                if oldSchemaVersion < 104 {
                    migration.renameProperty(onType: CalibreBookRealm.className(), from: "id", to: "idInLib")
                }
                
                if oldSchemaVersion < 110 {
                    migration.enumerateObjects(ofType: CalibreUnifiedCategoryObject.className()) { oldObject, newObject in
                        newObject?["search"] = ""
                        if let items = oldObject?["items"] as? RealmSwift.List<DynamicObject> {
                            newObject?["itemsCount"] = items.count
                        }
                    }
                }
                
                if oldSchemaVersion < 125 {
                    migration.renameProperty(onType: FolioReaderPreferenceRealm.className(), from: "structuralTocLevel", to: "structuralTrackingTocLevel")
                }
                
                if oldSchemaVersion < 128 {
                    if (oldSchemaVersion >= 125) {
                        migration.renameProperty(onType: FolioReaderPreferenceRealm.className(), from: "currentNavigationMenuBookListSyle", to: "currentNavigationMenuBookListStyle")
                    } else {
                        migration.renameProperty(onType: FolioReaderPreferenceRealm.className(), from: "currentNavigationBookListStyle", to: "currentNavigationMenuBookListStyle")
                    }
                }
                if oldSchemaVersion < 131 {
                    migration.enumerateObjects(ofType: ReadiumPreferenceRealm.className()) { oldObject, newObject in
                        newObject?["offsetFirstPage"] = oldObject?["offsetFirstPage"] as? Bool
                    }
                }
                if oldSchemaVersion < 133 {
                    var count = 0
                    migration.enumerateObjects(ofType: CalibreActivityLogEntry.className()) { oldObject, newObject in
                        newObject?["id"] = UUID().uuidString
                        count += 1
                    }
                    print("Migrated \(count) CalibreActivityLogEntry records.")
                }
                
                if oldSchemaVersion < 134 {
                    // Migrate CalibreServerDSReaderHelper into CalibreServerRealm
                    var newServersMap = [String: MigrationObject]()
                    migration.enumerateObjects(ofType: CalibreServerRealm.className()) { oldServer, newServer in
                        guard let oldServer = oldServer, let newServer = newServer else { return }
                        let primaryKey = oldServer["primaryKey"] as? String ?? ""
                        newServersMap[primaryKey] = newServer
                    }

                    migration.enumerateObjects(ofType: "CalibreServerDSReaderHelperRealm") { oldHelper, _ in
                        guard let oldHelper = oldHelper else { return }
                        let serverId = oldHelper["id"] as? String ?? ""
                        if let newServer = newServersMap[serverId] {
                            var newHelperDict: [String: Any] = [
                                "port": oldHelper["port"] ?? 0
                            ]
                            if let data = oldHelper["data"] {
                                newHelperDict["configurationData"] = data
                            }
                            newServer["dsreaderHelper"] = newHelperDict
                        }
                    }
                }
                
                if oldSchemaVersion < 135 {
                    // Fix missing primary keys in CalibreLibraryRealm
                    migration.enumerateObjects(ofType: CalibreLibraryRealm.className()) { oldObject, newObject in
                        guard let oldObject = oldObject, let newObject = newObject else { return }
                        let serverUUID = oldObject["serverUUID"] as? String ?? "-"
                        let libraryName = oldObject["name"] as? String ?? "-"
                        let primaryKey = CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName)
                        newObject["primaryKey"] = primaryKey
                    }
                }
            },
            shouldCompactOnLaunch: { fileSize, dataSize in
                return dataSize * 2 < fileSize || (dataSize + 33554432) < fileSize
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
        
        let _ = try Realm(configuration: realmConf)
        realmConf.migrationBlock = nil
        
        Realm.Configuration.defaultConfiguration = realmConf
    }
    
    func initializeDatabase() {
        realm = try! Realm(
            configuration: realmConf
        )
        logger = CalibreActivityLogger(realmConf: realmConf)
        databaseService.setup(conf: realmConf)
        downloadManager.setup(modelData: self, realmConf: realmConf)
        ModelData.SaveBooksMetadataRealmQueue.sync {
            self.realmSaveBooksMetadata = try! Realm(
                configuration: realmConf, queue: ModelData.SaveBooksMetadataRealmQueue
            )
        }
        
        serverManager.populateServers()
        
        populateLibraries()
        
        populateBookShelf()
        
        populateLocalLibraryBooks()
        
        calibreUpdatedSubject.send(.shelf)
        
        cleanCalibreActivities(startDatetime: Date(timeIntervalSinceNow: TimeInterval(-86400*7)))
    }
    
    func importCustomFonts(urls: [URL]) -> [CFArray]? {
        return fontsManager.importCustomFonts(urls: urls)
    }
    
    func removeCustomFonts(at offsets: IndexSet) {
        fontsManager.removeCustomFonts(at: offsets)
    }
    
    func reloadCustomFonts() {
        fontsManager.reloadCustomFonts()
    }
    
    func populateBookShelf() {
        let booksInShelfRealm = realm.objects(CalibreBookRealm.self).filter(
            NSPredicate(format: "inShelf = true")
        )
        
        booksInShelfRealm.forEach {
            // print(bookRealm)
            guard let serverUUIDString = $0.serverUUID,
                  let server = calibreServers[serverUUIDString],
                  let libraryName = $0.libraryName,
                  let library = calibreLibraries[CalibreLibrary(server: server, key: "", name: libraryName).id]
            else { return }
            
//            guard let server = calibreServers[CalibreServer(name: "", baseUrl: $0.serverUrl!, hasPublicUrl: false, publicUrl: "", hasAuth: $0.serverUsername?.count ?? 0 > 0, username: $0.serverUsername!, password: "").id] else {
//                print("ERROR booksInShelfRealm missing server \($0)")
//                return
//            }
//            guard  else {
//                print("ERROR booksInShelfRealm missing library \($0)")
//                return
//            }
            
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
            
//            self.shelfDataModel.addToShelf(book: book)
            
            print("booksInShelfRealm \(book.inShelfId)")
        }
    }
    
    func populateLibraries() {
        libraryManager.populateLibraries()
    }
    
    func populateLocalLibraryBooks() {
        libraryManager.populateLocalLibraryBooks()
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
    
    func convert(bookRealm: CalibreBookRealm) -> CalibreBook? {
//        let serverId = { () -> String in
//            let serverUrl = bookRealm.serverUrl ?? "."
//            if let username = bookRealm.serverUsername,
//               username.isEmpty == false {
//                return "\(username) @ \(serverUrl)"
//            } else {
//                return serverUrl
//            }
//        }()
        guard let library = queryLibrary(for: bookRealm) else { return nil }
        
        return convert(library: library, bookRealm: bookRealm)
    }
    
    func convert(library: CalibreLibrary, bookRealm: CalibreBookRealm) -> CalibreBook {
        let calibreBook = CalibreBook(managedObject: bookRealm, library: library)
        
        return calibreBook
    }
    
    func queryLibrary(for bookRealm: CalibreBookRealm) -> CalibreLibrary? {
        guard let serverUUID = bookRealm.serverUUID,
              let libraryName = bookRealm.libraryName
        else { return nil }
        
        return calibreLibraries[CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName)]
    }
    
    func getCustomDictViewer() -> (Bool, URL?) {
        return (UserDefaults.standard.bool(forKey: Constants.KEY_DEFAULTS_MDICT_VIEWER_ENABLED),
            UserDefaults.standard.url(forKey: Constants.KEY_DEFAULTS_MDICT_VIEWER_URL)
        )
    }
    
    func getCustomDictViewerNew(library: CalibreLibrary) -> (Bool, URL?) {
        var result: (Bool, URL?) = (false, nil)
        guard let dsreaderHelperServer = serverManager.queryServerDSReaderHelper(server: library.server) else { return result }
        let pluginDictionaryViewer = library.pluginDictionaryViewerWithDefault
        guard pluginDictionaryViewer.isEnabled else { return result }

        let connector = DSReaderHelperConnector(calibreServerService: calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: nil)
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
        let selectedFormats = book.formats.filter { $0.value.selected == true }
        if selectedFormats.count == 1,
           let firstFormatRaw = selectedFormats.first?.key,
           let firstFormat = Format(rawValue: firstFormatRaw) {
            return firstFormat
        }
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
    
            func updateLibraryRealm(library: CalibreLibrary, realm: Realm) throws {
        try libraryManager.updateLibraryRealm(library: library, realm: realm)
    }
    
    func hideLibrary(libraryId: String) {
        libraryManager.hideLibrary(libraryId: libraryId)
    }
    
    func restoreLibrary(libraryId: String) {
        libraryManager.restoreLibrary(libraryId: libraryId)
    }
    
    func queryLibraryBookRealmCount(library: CalibreLibrary, realm: Realm) -> Int {
        return libraryManager.queryLibraryBookRealmCount(library: library, realm: realm)
    }
    
    func updateServerLibraryInfo(serverInfo: CalibreServerInfo) {
        libraryManager.updateServerLibraryInfo(serverInfo: serverInfo)
        
        guard let server = calibreServers[serverInfo.server.id] else { return }
        if server.defaultLibrary != serverInfo.defaultLibrary {
            calibreServers[server.id]!.defaultLibrary = serverInfo.defaultLibrary
            do {
                try serverManager.updateServerRealm(server: calibreServers[server.id]!)
            } catch {
                
            }
        }
    }
    
    func updateBook(book: CalibreBook) {
        updateBookRealm(book: book, realm: (try? Realm(configuration: self.realmConf)) ?? self.realm)
        
        if readingBook?.inShelfId == book.inShelfId {
            readingBook = book
        }
        if book.inShelf {
            booksInShelf[book.inShelfId] = book
        }
    }
    
    func queryBookRealm(book: CalibreBook, realm: Realm) -> CalibreBookRealm? {
        return realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: CalibreBookRealm.PrimaryKey(serverUUID: book.library.server.uuid.uuidString, libraryName: book.library.name, id: book.id.description))
    }
    
    func updateBookRealm(book: CalibreBook, realm: Realm) {
        let bookRealm = book.managedObject()
        try? realm.write {
            realm.add(bookRealm, update: .modified)
        }
    }
    
    func removeFromRealm(book: CalibreBook) {
        removeFromRealm(for: CalibreBookRealm.PrimaryKey(serverUUID: book.library.server.uuid.uuidString, libraryName: book.library.name, id: book.id.description))
    }
    
    func removeFromRealm(for primaryKey: String) {
        guard let object = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey) else { return }
        
        try? realm.write {
            realm.delete(object)
        }
    }
    
    func shouldAutoUpdateGoodreads(library: CalibreLibrary) -> (CalibreServerDSReaderHelper, CalibreDSReaderHelperPrefs.Options, CalibreGoodreadsSyncPrefs.PluginPrefs)? {
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
        
        if let library = calibreLibraries[book.library.id],
           let goodreadsId = book.identifiers["goodreads"],
           let (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync) = shouldAutoUpdateGoodreads(library: library),
           dsreaderHelperLibrary.autoUpdateGoodreadsBookShelf {
            let connector = DSReaderHelperConnector(calibreServerService: calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: goodreadsSync)
            let ret = connector.addToShelf(goodreads_id: goodreadsId, shelfName: "currently-reading")
        }
        
        calibreUpdatedSubject.send(.book(book))
    }
    
    func removeFromShelf(inShelfId: String) {
        if readingBook?.inShelfId == inShelfId {
            readingBook?.inShelf = false
//            NotificationCenter.default.post(Notification(name: .YABR_ReadingBookRemovedFromShelf))
        }
        
        guard var book = booksInShelf[inShelfId] else { return }
        book.inShelf = false

        updateBookRealm(book: book, realm: (try? Realm(configuration: self.realmConf)) ?? self.realm)
        
        booksInShelf.removeValue(forKey: inShelfId)
        
        if book.readPos.getDevices().first?.id == deviceName,
           let library = calibreLibraries[book.library.id],
           let goodreadsId = book.identifiers["goodreads"],
           let (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync) = shouldAutoUpdateGoodreads(library: library),
           dsreaderHelperLibrary.autoUpdateGoodreadsBookShelf {
            let connector = DSReaderHelperConnector(calibreServerService: calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: goodreadsSync)
            let ret = connector.removeFromShelf(goodreads_id: goodreadsId, shelfName: "currently-reading")
            
            if let position = book.readPos.getPosition(deviceName), position.lastProgress > 99 {
                connector.addToShelf(goodreads_id: goodreadsId, shelfName: "read")
            }
        }

        calibreUpdatedSubject.send(.deleted(book.inShelfId))
    }
    
    func startDownloadFormat(book: CalibreBook, format: Format, overwrite: Bool = false) -> Bool {
        return downloadManager.startDownload(book, format: format, overwrite: overwrite)
    }
    
    func cancelDownloadFormat(book: CalibreBook, format: Format) {
        return downloadManager.cancelDownload(book, format: format)
    }
    
    func pauseDownloadFormat(book: CalibreBook, format: Format) {
        return downloadManager.pauseDownload(book, format: format)
    }
    
    func resumeDownloadFormat(book: CalibreBook, format: Format) -> Bool {
        let result = downloadManager.resumeDownload(book, format: format)
        if !result {
            downloadManager.cancelDownload(book, format: format)
        }
        return result
    }
    
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

//        if newBook.inShelf == false {
//            addToShelf(newBook.inShelfId)
//        }
        
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
                defaultLog.error("clearCache \(error.localizedDescription)")
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
    
    
    func updateCurrentPosition(alertDelegate: AlertDelegate?) {
        guard let readingBook = self.readingBook,
              let updatedReadingPosition = readingBook.readPos.getDevices().first,
              let readerInfo = self.readerInfo
        else {
            return
        }

        defaultLog.info("pageNumber:  \(updatedReadingPosition.lastPosition[0])")
        defaultLog.info("pageOffsetX: \(updatedReadingPosition.lastPosition[1])")
        defaultLog.info("pageOffsetY: \(updatedReadingPosition.lastPosition[2])")

        refreshShelfMetadataV2(with: [readingBook.library.server.id], for: [readingBook.inShelfId], serverReachableChanged: true)

        if floor(updatedReadingPosition.lastProgress) > readerInfo.position.lastProgress || updatedReadingPosition.lastProgress < floor(readerInfo.position.lastProgress),
           let library = calibreLibraries[readingBook.library.id],
           let goodreadsId = readingBook.identifiers["goodreads"],
           let (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync) = shouldAutoUpdateGoodreads(library: library),
           dsreaderHelperLibrary.autoUpdateGoodreadsProgress {
            let connector = DSReaderHelperConnector(calibreServerService: calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: goodreadsSync)
            connector.updateReadingProgress(goodreads_id: goodreadsId, progress: updatedReadingPosition.lastProgress)

            if goodreadsSync.isEnabled, goodreadsSync.readingProgressColumnName.count > 1 {
                calibreServerService.updateMetadata(library: library, bookId: readingBook.id, metadata: [
                    [goodreadsSync.readingProgressColumnName, Int(updatedReadingPosition.lastProgress)]
                ])
            }
        }

    }


    func goToPreviousBook() {        //MARK: FIXME
//        if let curIndex = filteredBookList.firstIndex(of: currentBookId), curIndex > 0 {
//            currentBookId = filteredBookList[curIndex-1]
//        }
    }
    
    func goToNextBook() {
        //MARK: FIXME
//        if let curIndex = filteredBookList.firstIndex(of: selectedBookId ?? currentBookId), curIndex < filteredBookList.count - 1 {
//            currentBookId = filteredBookList[curIndex + 1]
//        }
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
    
    func prepareBookReading(book: CalibreBook) -> ReaderInfo {
        return sessionManager.prepareBookReading(book: book)
    }
    
    func prepareBookReading(url: URL, format: Format, readerType: ReaderType, position: BookDeviceReadingPosition) {
        sessionManager.prepareBookReading(url: url, format: format, readerType: readerType, position: position)
    }
    
    func removeDeleteBooksFromServer(server: CalibreServer) {
        librarySyncStatus.filter {
             $0.value.library.server.id == server.id && $0.value.del.count > 0
        }.forEach { lss in
            self.librarySyncStatus[lss.key]?.isSync = true
            var progress = 0
            let total = lss.value.del.count
            DispatchQueue.global(qos: .userInitiated).async {
                guard let realm = try? Realm(configuration: self.realmConf) else { return }
                
                try? realm.write {
                    lss.value.del.forEach { id in
                        if progress % 100 == 0 {
                            DispatchQueue.main.async {
                                self.librarySyncStatus[lss.key]?.msg = "Removing deleted \(progress) / \(total)"
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
                    self.librarySyncStatus[lss.key]?.del.removeAll()
                    self.librarySyncStatus[lss.key]?.isSync = false
                    self.librarySyncStatus[lss.key]?.msg = nil
                }
            }
        }
        
        serverManager.probeServersReachability(with: [server.id], updateLibrary: false, autoUpdateOnly: true, incremental: false)
    }
    
        func probeServersReachability(with serverIds: Set<String>, updateLibrary: Bool = false, autoUpdateOnly: Bool = true, incremental: Bool = true) {
        serverManager.probeServersReachability(with: serverIds, updateLibrary: updateLibrary, autoUpdateOnly: autoUpdateOnly, incremental: incremental)
    }
    
    func isServerReachable(server: CalibreServer) -> Bool {
        return serverManager.isServerReachable(server: server)
    }
    
    func isServerReachable(server: CalibreServer, isPublic: Bool) -> Bool? {
        return serverManager.isServerReachable(server: server, isPublic: isPublic)
    }
    
    func isServerProbing(server: CalibreServer) -> Bool {
        return serverManager.isServerProbing(server: server)
    }
    
    func getServerInfo(server: CalibreServer) -> CalibreServerInfo? {
        return serverManager.getServerInfo(server: server)
    }
    
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
            calibreUpdatedSubject.send(.shelf)
            return
        }
        
        libraryBooks.forEach { library, books in
            Task {
                await self.getBooksMetadata(request: .init(library: library, books: books.map { $0.id }, getAnnotations: true))
            }
        }
    }
    
        @discardableResult
    @MainActor
    func probeServer(request: CalibreProbeServerRequest) async -> CalibreServerInfo? {
        return await serverManager.probeServer(request: request)
    }
    
    @MainActor
    func removeServer(server: CalibreServer) async {
        await serverManager.removeServer(server: server)
    }
    
    func addServer(server: CalibreServer, libraries: [CalibreLibrary]) {
        serverManager.addServer(server: server, libraries: libraries)
    }
    
    func updateServerRealm(server: CalibreServer) throws {
        try serverManager.updateServerRealm(server: server)
    }
    
    func queryServerDSReaderHelper(server: CalibreServer) -> CalibreServerDSReaderHelper? {
        return serverManager.queryServerDSReaderHelper(server: server)
    }
    
    func updateServerDSReaderHelper(serverId: String, dsreaderHelper: CalibreServerDSReaderHelper, realm: Realm) {
        serverManager.updateServerDSReaderHelper(serverId: serverId, dsreaderHelper: dsreaderHelper, realm: realm)
    }
    
    @discardableResult
    @MainActor
    func probeLibrary(request: CalibreProbeLibraryRequest) async -> CalibreLibraryProbeTask {
        return await libraryManager.probeLibrary(request: request)
    }
    
    @MainActor
    func removeLibrary(library: CalibreLibrary) async {
        await libraryManager.removeLibrary(library: library)
    }
    
    func registerProbeLibraryLastModifiedCancellable() {
        libraryManager.registerProbeLibraryLastModifiedCancellable()
    }
    
    func registerSyncServerHelperConfigCancellable() {
        let queue = DispatchQueue(label: "sync-server-helper", qos: .userInitiated)
        syncServerHelperConfigSubject
            .receive(on: queue)
            .flatMap { serverId -> AnyPublisher<(id: String, port: Int, data: Data), URLError> in
                if let server = self.calibreServers[serverId],
                   let dsreaderHelperServer = self.serverManager.queryServerDSReaderHelper(server: server),
                   let publisher = DSReaderHelperConnector(calibreServerService: self.calibreServerService, server: server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: nil).refreshConfiguration() {
                    return publisher
                } else {
                    return Just((id: serverId, port: 0, data: Data())).setFailureType(to: URLError.self).eraseToAnyPublisher()
                }
            }
            .map { task -> (id: String, port: Int, data: Data, config: CalibreDSReaderHelperConfiguration?) in
                return (
                    id: task.id,
                    port: task.port,
                    data: task.data,
                    config: try? JSONDecoder().decode(CalibreDSReaderHelperConfiguration.self, from: task.data)
                )
            }
            .receive(on: DispatchQueue.main)
            .sink { completion in
                
            } receiveValue: { task in
                if let config = task.config, config.dsreader_helper_prefs != nil {
                    let dsreaderHelper = CalibreServerDSReaderHelper(port: task.port)
                    dsreaderHelper.configurationData = task.data
                    
                    self.serverManager.updateServerDSReaderHelper(serverId: task.id, dsreaderHelper: dsreaderHelper, realm: self.realm)
                }
            }.store(in: &calibreCancellables)
    }
    
    @MainActor
    func syncLibrary(request: CalibreSyncLibraryRequest) async {
        await libraryManager.syncLibrary(request: request)
    }
    
    func saveBookMetadata(metadata: CalibreSyncLibraryBooksMetadata) async {
        await libraryManager.saveBookMetadata(metadata: metadata)
    }
    
    @MainActor
    func getBooksMetadata(request: CalibreBooksMetadataRequest) async {
        self.librarySyncStatus[request.library.id]?.isUpd = true
        
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
        
        var task = calibreServerService.buildBooksMetadataTask(library: request.library, books: books, getAnnotations: request.getAnnotations) ?? CalibreBooksTask(request: request)
        
        task = await calibreServerService.getBooksMetadata(task: task)
        
        if task.request.getAnnotations {
            task = await calibreServerService.getAnnotations(task: task)
        }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ModelData.SaveBooksMetadataRealmQueue.async {
                guard let entries = task.booksMetadataEntry,
                      let json = task.booksMetadataJSON else {
                    continuation.resume()
                    return
                }
                
                let serverUUID = task.library.server.uuid.uuidString
                let libraryName = task.library.name
                try? self.realmSaveBooksMetadata.write {
                    task.books.map {
                        (
                            obj: self.realmSaveBooksMetadata.object(
                                ofType: CalibreBookRealm.self,
                                forPrimaryKey: CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName, id: $0.description)
                            ),
                            entry: entries[$0.description],
                            root: json[$0.description] as? NSDictionary
                        )
                    }.forEach {
                        guard let obj = $0.obj else { return }
                        
                        if let entryOptional = $0.entry, let entry = entryOptional, let root = $0.root {
                            self.calibreServerService.handleLibraryBookOne(library: task.library, bookRealm: obj, entry: entry, root: root)
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
                continuation.resume()
            }
        }
        
        task.booksInShelf.forEach { newBook in
            self.booksInShelf[newBook.inShelfId] = newBook
            self.calibreUpdatedSubject.send(.book(newBook))
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
                    
                    let positions = book.readPos.positions(added: entry.last_read_positions)
                    for pos in positions {
                        if let setTask = self.calibreServerService.buildSetLastReadPositionTask(library: task.library, bookId: book.id, format: format, entry: pos) {
                            Task {
                                await self.calibreServerService.setLastReadPositionByTask(task: setTask)
                            }
                        }
                    }
                    
                    if book.readPos.highlights(added: entry.annotations_map.highlight ?? []) > 0 || book.readPos.bookmarks(added: entry.annotations_map.bookmark ?? []) > 0 {
                        if let updateTask = self.calibreServerService.buildUpdateAnnotationsTask(
                            library: task.library,
                            bookId: book.id,
                            format: format,
                            highlights: book.readPos.highlights(excludeRemoved: false).compactMap { $0.toCalibreBookAnnotationHighlightEntry() },
                            bookmarks: book.readPos.bookmarks().map { $0.toCalibreBookAnnotationBookmarkEntry() }
                        ) {
                            Task {
                                await self.calibreServerService.updateAnnotationByTask(task: updateTask)
                            }
                        }
                    }
                }
            }
            
            for book in task.booksAnnotation {
                for (formatKey, _) in book.formats {
                    guard let _ = Format(rawValue: formatKey),
                          let entry = annotationsResult["\(book.id):\(formatKey)"]
                    else { continue }
                    
                    _ = book.readPos.positions(added: entry.last_read_positions)
                    _ = book.readPos.highlights(added: entry.annotations_map.highlight ?? [])
                    _ = book.readPos.bookmarks(added: entry.annotations_map.bookmark ?? [])
                }
            }
        }
        
        let booksHandled = task.booksUpdated.union(task.booksError).union(task.booksDeleted)
        
        self.librarySyncStatus[task.library.id]?.upd.subtract(booksHandled)
        
        if task.booksError.isEmpty == false {
            self.librarySyncStatus[task.library.id]?.err.formUnion(task.booksError)
            self.librarySyncStatus[task.library.id]?.del.formUnion(task.booksDeleted)
            let booksRetry = task.books.filter { booksHandled.contains($0) == false }
            
            if booksRetry.isEmpty == false {
                booksRetry.chunks(size: max(booksRetry.count / 16, 1)).forEach { chunk in
                    Task {
                        await self.getBooksMetadata(request: .init(library: task.library, books: chunk, getAnnotations: task.request.getAnnotations))
                    }
                }
            }
        }
        
        self.librarySyncStatus[task.library.id]?.isUpd = false
        
        if request.books.count == 1,
           let book = self.getBook(
            for: CalibreBookRealm.PrimaryKey(
                serverUUID: task.library.server.uuid.uuidString,
                libraryName: task.library.name,
                id: task.request.books.first!.description
            )
           ) {
            self.calibreUpdatedSubject.send(.book(book))
        }
    }
    
    func logStartCalibreActivity(type: String, request: URLRequest, startDatetime: Date, bookId: Int32?, libraryId: String?) {
        Task {
            await logger.logStartCalibreActivity(type: type, request: request, startDatetime: startDatetime, bookId: bookId, libraryId: libraryId)
        }
    }
    
    func logFinishCalibreActivity(type: String, request: URLRequest, startDatetime: Date, finishDatetime: Date, errMsg: String) {
        Task {
            await logger.logFinishCalibreActivity(type: type, request: request, startDatetime: startDatetime, finishDatetime: finishDatetime, errMsg: errMsg)
        }
    }
    
    func cleanCalibreActivities(startDatetime: Date) {
        Task {
            await logger.cleanCalibreActivities(startDatetime: startDatetime)
        }
    }
    /**
     key: inShelfId
     */
    func listBookDeviceReadingPositionHistory(library: CalibreLibrary? = nil, bookId: Int32? = nil, startDateAfter: Date? = nil) -> [String:[BookDeviceReadingPositionHistory]] {
        return sessionManager.listBookDeviceReadingPositionHistory(library: library, bookId: bookId, startDateAfter: startDateAfter)
    }
    
    func getReadingStatistics(list: [BookDeviceReadingPositionHistory], limitDays: Int) -> [Double] {
        return BookDeviceReadingPositionHistory.getReadingStatistics(list: list, limitDays: limitDays)
    }
    
    func getBookRealm(forPrimaryKey: String) -> CalibreBookRealm? {
        return realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: forPrimaryKey)
    }
    
}
