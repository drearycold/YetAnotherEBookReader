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

final class ModelData: ObservableObject, CalibreServerConfigProvider, LibraryProvider {
    static var shared: ModelData?

    func getLibraries() -> [String: CalibreLibrary] {
        return libraryManager.calibreLibraries
    }

    func isServerReachable(server: CalibreServer, isPublic: Bool) -> Bool? {
        return serverManager.isServerReachable(server: server, isPublic: isPublic)
    }

    func isServerReachable(server: CalibreServer) -> Bool {
        return serverManager.isServerReachable(server: server)
    }

    // MARK: - CalibreServerConfigProvider Conformance (Protocol-required)

    func updateBook(book: CalibreBook) {
        bookManager.updateBook(book: book)
    }

    func getBookRealm(forPrimaryKey: String) -> CalibreBookRealm? {
        return bookManager.getBookRealm(forPrimaryKey: forPrimaryKey)
    }

    func getPreferredFormat(for book: CalibreBook) -> Format? {
        return sessionManager.getPreferredFormat(for: book)
    }

    // MARK: - CalibreServerConfigProvider Conformance
    // These computed properties are kept ONLY for protocol conformance.
    // All internal callers should use the underlying manager properties directly.

    var calibreLibraries: [String: CalibreLibrary] {
        get { libraryManager.calibreLibraries }
        set { libraryManager.calibreLibraries = newValue }
    }
    var librarySyncStatus: [String: CalibreSyncStatus] {
        get { libraryManager.librarySyncStatus }
        set { libraryManager.librarySyncStatus = newValue }
    }
    var calibreServerInfoStaging: [String: CalibreServerInfo] {
        get { serverManager.calibreServerInfoStaging }
        set { serverManager.calibreServerInfoStaging = newValue }
    }
    var calibreServers: [String: CalibreServer] {
        get { serverManager.calibreServers }
        set { serverManager.calibreServers = newValue }
    }
    var booksInShelf: [String: CalibreBook] {
        get { bookManager.booksInShelf }
        set { bookManager.booksInShelf = newValue }
    }
    
    @Published var deviceName = UIDevice.current.name {
        didSet {
            calibreServerService.updateDeviceName(deviceName)
        }
    }

    static let SaveBooksMetadataRealmQueue = DispatchQueue(label: "saveBooksMetadata", qos: .userInitiated)

    let bookImportedSubject = PassthroughSubject<BookImportInfo, Never>()
    let dismissAllSubject = PassthroughSubject<String, Never>()

    let recentShelfItemsSubject = PassthroughSubject<[ShelfBookItem], Never>()
    let discoverShelfItemsSubject = PassthroughSubject<[ShelfSectionItem], Never>()

    var presentingStack = [Binding<Bool>]()

    let bookReaderActivitySubject = PassthroughSubject<ScenePhase, Never>()

    var calibreCancellables = Set<AnyCancellable>()

    @Published var downloadManager = BookDownloadManager()
    lazy var sessionManager = ReadingSessionManager(modelData: self)
    
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
    
    static var RealmSchemaVersion: UInt64 = 140
    var realm: Realm?
    var realmSaveBooksMetadata: Realm?
    var realmConf: Realm.Configuration?
    
    var logger: CalibreActivityLogger?
    
    let kfImageCache = ImageCache.default
    var authResponsor = AuthResponsor()
    
    var databaseService = DatabaseService.shared
    
    lazy var serverRepository: ServerRepositoryProtocol = RealmServerRepository(databaseService: databaseService)
    lazy var libraryRepository: LibraryRepositoryProtocol = RealmLibraryRepository(databaseService: databaseService, serverResolver: self)
    lazy var bookRepository: BookRepositoryProtocol = RealmBookRepository(databaseService: databaseService, libraryResolver: self)
    lazy var readingPositionRepository: ReadingPositionRepositoryProtocol = RealmReadingPositionRepository(databaseService: databaseService, modelData: self)
    lazy var annotationRepository: AnnotationRepositoryProtocol = RealmAnnotationRepository(databaseService: databaseService)
    lazy var activityLogRepository: ActivityLogRepositoryProtocol = RealmActivityLogRepository(databaseService: databaseService, bookRepository: self.bookRepository, modelData: self)
    lazy var readerPreferenceRepository: ReaderPreferenceRepositoryProtocol = RealmReaderPreferenceRepository()
    lazy var folioReaderProfileRepository: FolioReaderProfileRepositoryProtocol = RealmFolioReaderProfileRepository(realmConfiguration: self.realmConf)
    
    lazy var serverManager = CalibreServerManager(modelData: self, databaseService: self.databaseService, serverRepository: self.serverRepository)
    lazy var libraryManager = CalibreLibraryManager(modelData: self, databaseService: self.databaseService, libraryRepository: self.libraryRepository)
    lazy var bookManager = CalibreBookManager(modelData: self, databaseService: self.databaseService, bookRepository: self.bookRepository, readingPositionRepository: self.readingPositionRepository, annotationRepository: self.annotationRepository)
    
    lazy var calibreServerService = CalibreServerService(logger: self.logger ?? CalibreActivityLogger(realmConf: Realm.Configuration.defaultConfiguration), config: self, database: self.databaseService)
    lazy var searchCacheRepository = RealmSearchCacheStore(modelData: self)
    lazy var librarySearchService = LibrarySearchService(service: self.calibreServerService, repository: self.searchCacheRepository)
    lazy var unifiedSearchService = UnifiedSearchService(
        repository: self.searchCacheRepository,
        librarySearchService: self.librarySearchService,
        libraryProvider: self
    )
    lazy var categoryCacheRepository: CategoryCacheRepository = self.searchCacheRepository
    lazy var libraryCategoryService = LibraryCategoryService(service: self.calibreServerService, repository: self.categoryCacheRepository)
    lazy var unifiedCategoryService = UnifiedCategoryService(repository: self.categoryCacheRepository, libraryProvider: self)
    
    lazy var shelfDataModel = YabrShelfDataModel(unifiedSearchService: self.unifiedSearchService, modelData: self)
    
    let probeLibraryLastModifiedSubject = PassthroughSubject<CalibreSyncLibraryRequest, Never>()
    
    let syncServerHelperConfigSubject = PassthroughSubject<String, Never>()
    
    var probeTimer: AnyCancellable?
    
    /// inShelfId for single book
    /// empty string for full update
    let calibreUpdatedSubject = PassthroughSubject<calibreUpdatedSignal, Never>()

    @Published var fontsManager = FontsManager()

    var isDatabaseReady: Bool {
        databaseService.realm != nil
    }

    func getBook(for primaryKey: String) -> CalibreBook? {
        bookManager.getBook(for: primaryKey)
    }

    @MainActor
    func refreshDatabase() {
        databaseService.realm?.refresh()
    }

    init(mock: Bool = false) {
        ModelData.shared = self
        
        // Ensure default configuration is set early to prevent crashes in SwiftUI views using ObservedResults
        ModelData.RealmSchemaVersion = 140
        let initialConf = Realm.Configuration(
            schemaVersion: ModelData.RealmSchemaVersion,
            migrationBlock: { _, _ in }
        )
        Realm.Configuration.defaultConfiguration = initialConf
        self.realmConf = initialConf
        
        kfImageCache.diskStorage.config.expiration = .days(28)
        KingfisherManager.shared.defaultOptions = [.requestModifier(AuthPlugin(modelData: self))]
        ImageDownloader.default.authenticationChallengeResponder = authResponsor
        
        downloadManager.modelData = self
        
        fontsManager.reloadCustomFonts()
        
//        calibreServerService.defaultUrlSessionConfiguration.timeoutIntervalForRequest = 600
//        calibreServerService.defaultUrlSessionConfiguration.httpMaximumConnectionsPerHost = 2
        
        libraryManager.registerProbeLibraryLastModifiedCancellable()
        
        registerRecentShelfUpdater()
        
        downloadManager.bookDownloadedSubject.sink { book in
            self.calibreUpdatedSubject.send(.book(book))
        }.store(in: &calibreCancellables)
        
        serverManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &calibreCancellables)
        
        libraryManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &calibreCancellables)
        
        bookManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &calibreCancellables)
        
        sessionManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &calibreCancellables)
        
        if mock {
            try? tryInitializeDatabase() { _ in
                
            }
            initializeDatabase()
            
            let library = libraryManager.calibreLibraries.first!.value
            
            var book = CalibreBook(id: 1, library: library)
            
            book.title = "Mock Book Title"
            
            book.formats[Format.EPUB.rawValue] = .init(filename: book.title + ".epub", serverSize: 1024000, serverMTime: Date(timeIntervalSince1970: 1645495322), cached: true, cacheSize: 1024000, cacheMTime: Date(timeIntervalSince1970: 1645495322), manifest: nil)
            if let bookSavedUrl = getSavedUrl(book: book, format: Format.EPUB),
               FileManager.default.fileExists(atPath: bookSavedUrl.path) == false {
                FileManager.default.createFile(atPath: bookSavedUrl.path, contents: String("EPUB").data(using: .utf8), attributes: nil)
            }
            
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
            
            self.readingPositionRepository.savePosition(position, forBookId: book.bookPrefId)
            
            self.bookManager.readingBook = book
            
            
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
            self.bookManager.booksInShelf[self.bookManager.readingBook!.inShelfId] = self.bookManager.readingBook
            
            cleanCalibreActivities(startDatetime: Date())
            logStartCalibreActivity(type: "Mock", request: URLRequest(url: URL(string: "http://calibre-server.lan:8080/")!), startDatetime: Date(), bookId: 1, libraryId: library.id)
        }
    }
    
    func tryInitializeDatabase(statusHandler: @escaping (String) -> Void) throws {
        ModelData.RealmSchemaVersion = UInt64(YabrAppInfo.shared.build) ?? 1
        var conf = Realm.Configuration(
            schemaVersion: ModelData.RealmSchemaVersion,
            migrationBlock: { migration, oldSchemaVersion in
                if oldSchemaVersion < 138 {
                    migration.deleteData(forType: "CalibreUnifiedSearchObject")
                    migration.deleteData(forType: "CalibreUnifiedOffsets")
                }
                if oldSchemaVersion < 139 {
                    migration.deleteData(forType: "CalibreUnifiedCategoryObject")
                    migration.deleteData(forType: "CalibreUnifiedCategoryItemObject")
                }
                if oldSchemaVersion < 140 {
                    // Removed deprecated properties from CalibreLibrarySearchObject:
                    // generation, totalNumber, bookIds, books. Realm automatically
                    // drops removed columns during migration.
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
            conf.fileURL = applicationSupportURL.appendingPathComponent("default.realm")
            if let documentDirectoryURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
                let existingRealmURL = documentDirectoryURL.appendingPathComponent("default.realm")
                if FileManager.default.fileExists(atPath: existingRealmURL.path) {
                    try? FileManager.default.moveItem(at: existingRealmURL, to: conf.fileURL!)
                }
            }
        }
        
        let _ = try Realm(configuration: conf)
        conf.migrationBlock = nil
        
        Realm.Configuration.defaultConfiguration = conf
        realmConf = conf
    }
    
    func initializeDatabase() {
        guard let realmConf = realmConf else { return }
        realm = try? Realm(configuration: realmConf)
        logger = CalibreActivityLogger(realmConf: realmConf)
        databaseService.setup(conf: realmConf)
        downloadManager.setup(modelData: self, realmConf: realmConf)
        ModelData.SaveBooksMetadataRealmQueue.sync {
            self.realmSaveBooksMetadata = try? Realm(
                configuration: realmConf, queue: ModelData.SaveBooksMetadataRealmQueue
            )
        }
        
        serverManager.populateServers()
        
        populateLibraries()
        
        populateBookShelf()
        
        populateLocalLibraryBooks()
        
        calibreUpdatedSubject.send(.shelf)
        
        cleanCalibreActivities(startDatetime: Date(timeIntervalSinceNow: TimeInterval(-86400*7)))
        
        migrateLegacyReadPosData()
    }
    
    func migrateLegacyReadPosData() {
        DispatchQueue.global(qos: .background).async {
            guard let realmConf = self.realmConf,
                  let realm = try? Realm(configuration: realmConf) else {
                return
            }
            
            let bookKeysToMigrate = realm.objects(CalibreBookRealm.self)
                .filter("readPosData != nil")
                .compactMap { $0.primaryKey }
            
            guard !bookKeysToMigrate.isEmpty else { return }
            
            print("migrateLegacyReadPosData: Found \(bookKeysToMigrate.count) legacy reading positions to migrate.")
            
            for key in bookKeysToMigrate {
                guard let realmConf = self.realmConf,
                      let freshRealm = try? Realm(configuration: realmConf),
                      let bookRealm = freshRealm.object(ofType: CalibreBookRealm.self, forPrimaryKey: key),
                      let serverUUID = bookRealm.serverUUID,
                      let libraryName = bookRealm.libraryName
                else {
                    continue
                }
                
                if let library = self.library(forServerUUID: serverUUID, libraryName: libraryName) {
                    bookRealm.migrateReadPos(library: library, repository: self.readingPositionRepository)
                }
                
                try? freshRealm.write {
                    bookRealm.readPosData = nil
                }
            }
            
            print("migrateLegacyReadPosData: Completed background migration of legacy reading positions.")
        }
    }
    
    // → bookManager (Phase 2: move populateBookShelf logic here)
    func populateBookShelf() {
        bookManager.populateBookShelf()
    }

    // → libraryManager (Phase 2: move populateLibraries logic here)
    func populateLibraries() {
        libraryManager.populateLibraries()
    }

    // → libraryManager (Phase 2: move populateLocalLibraryBooks logic here)
    func populateLocalLibraryBooks() {
        libraryManager.populateLocalLibraryBooks()
    }

    // only move file when triggered by in-app importer, DO NOT MOVE FROM OTHER PLACES
    // → bookManager (Phase 2: move onOpenURL logic here)
    func onOpenURL(url: URL, doMove: Bool, doOverwrite: Bool, asNew: Bool, knownBookId: Int32? = nil) -> BookImportInfo {
        bookManager.onOpenURL(url: url, doMove: doMove, doOverwrite: doOverwrite, asNew: asNew, knownBookId: knownBookId)
    }

    // → bookManager (Phase 2: move calcLocalFileBookId logic here)
    func calcLocalFileBookId(for fileURL: URL) -> Int32? {
        bookManager.calcLocalFileBookId(for: fileURL)
    }

    // → bookManager (Phase 2: move loadLocalLibraryBookMetadata logic here)
    func loadLocalLibraryBookMetadata(fileURL: URL, in library: CalibreLibrary, on server: CalibreServer, knownBookId: Int32? = nil) -> Int32? {
        bookManager.loadLocalLibraryBookMetadata(fileURL: fileURL, in: library, on: server, knownBookId: knownBookId)
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
    
    // user preferred -> default -> unsupported
    // → libraryManager + serverManager (has actual logic: updates defaultLibrary, persists Realm)
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
    
    // → bookManager + libraryManager (has actual logic: filters/grouping/spawning tasks)
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

    @discardableResult
    @MainActor
    func probeLibrary(request: CalibreProbeLibraryRequest) async -> CalibreLibraryProbeTask {
        return await libraryManager.probeLibrary(request: request)
    }

    @MainActor
    func removeLibrary(library: CalibreLibrary) async {
        await libraryManager.removeLibrary(library: library)
    }

    @MainActor
    func getBooksMetadata(request: CalibreBooksMetadataRequest) async {
        await bookManager.getBooksMetadata(request: request)
    }

    @MainActor
    func syncLibrary(request: CalibreSyncLibraryRequest) async {
        await libraryManager.syncLibrary(request: request)
    }

    func cleanCalibreActivities(startDatetime: Date) {
        guard let logger = logger else { return }
        Task {
            await logger.cleanCalibreActivities(startDatetime: startDatetime)
        }
    }

    func logStartCalibreActivity(type: String, request: URLRequest, startDatetime: Date, bookId: Int32?, libraryId: String?) {
        guard let logger = logger else { return }
        Task {
            await logger.logStartCalibreActivity(type: type, request: request, startDatetime: startDatetime, bookId: bookId, libraryId: libraryId)
        }
    }

    func logFinishCalibreActivity(type: String, request: URLRequest, startDatetime: Date, finishDatetime: Date, errMsg: String) {
        guard let logger = logger else { return }
        Task {
            await logger.logFinishCalibreActivity(type: type, request: request, startDatetime: startDatetime, finishDatetime: finishDatetime, errMsg: errMsg)
        }
    }
}

extension ModelData: LibraryResolver {
    func library(forServerUUID serverUUID: String, libraryName: String) -> CalibreLibrary? {
        return libraryManager.calibreLibraries[CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName)]
    }
}

extension ModelData: ServerResolver {
    func server(forUUID uuid: String) -> CalibreServer? {
        return serverManager.calibreServers[uuid]
    }
}
