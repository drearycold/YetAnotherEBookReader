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
    
    var documentServer: CalibreServer? {
        get { serverManager.documentServer }
        set { serverManager.documentServer = newValue }
    }
    
    //for LibraryInfoView
    var defaultFormat: Format {
        get { sessionManager.defaultFormat }
        set { sessionManager.defaultFormat = newValue }
    }
    var formatReaderMap: [Format: [ReaderType]] {
        get { sessionManager.formatReaderMap }
        set { sessionManager.formatReaderMap = newValue }
    }
    var formatList: [Format] {
        get { sessionManager.formatList }
        set { sessionManager.formatList = newValue }
    }
    
    static let SaveBooksMetadataRealmQueue = DispatchQueue(label: "saveBooksMetadata", qos: .userInitiated)
    
    var booksInShelf: [String: CalibreBook] {
        get { bookManager.booksInShelf }
        set { bookManager.booksInShelf = newValue }
    }
    var booksAnnotation: [String: CalibreBook] {
        get { bookManager.booksAnnotation }
        set { bookManager.booksAnnotation = newValue }
    }
    
    let bookImportedSubject = PassthroughSubject<BookImportInfo, Never>()
    let dismissAllSubject = PassthroughSubject<String, Never>()
    
    let recentShelfItemsSubject = PassthroughSubject<[ShelfBookItem], Never>()
    let discoverShelfItemsSubject = PassthroughSubject<[ShelfSectionItem], Never>()
    
    var presentingStack = [Binding<Bool>]()
    
    var currentBookId: String {
        get { bookManager.currentBookId }
        set { bookManager.currentBookId = newValue }
    }

    var selectedBookId: String? {
        get { bookManager.selectedBookId }
        set { bookManager.selectedBookId = newValue }
    }
    
    let bookReaderActivitySubject = PassthroughSubject<ScenePhase, Never>()
    
    var calibreCancellables = Set<AnyCancellable>()
    
    @Published var downloadManager = BookDownloadManager()
    lazy var sessionManager = ReadingSessionManager(modelData: self)

    var readingBookInShelfId: String? {
        get { bookManager.readingBookInShelfId }
        set { bookManager.readingBookInShelfId = newValue }
    }
    var readingBook: CalibreBook? {
        get { bookManager.readingBook }
        set { bookManager.readingBook = newValue }
    }
    var readerInfo: ReaderInfo? {
        get { sessionManager.readerInfo }
        set { sessionManager.readerInfo = newValue }
    }
    var presentingEBookReaderFromShelf: Bool {
        get { bookManager.presentingEBookReaderFromShelf }
        set { bookManager.presentingEBookReaderFromShelf = newValue }
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
    
    static var RealmSchemaVersion: UInt64 = 140
    var realm: Realm!
    var realmSaveBooksMetadata: Realm!
    var realmConf: Realm.Configuration!
    
    var logger: CalibreActivityLogger!
    
    let kfImageCache = ImageCache.default
    var authResponsor = AuthResponsor()
    
    var databaseService = DatabaseService.shared
    
    lazy var serverRepository: ServerRepositoryProtocol = RealmServerRepository(databaseService: databaseService)
    lazy var libraryRepository: LibraryRepositoryProtocol = RealmLibraryRepository(databaseService: databaseService, serverResolver: self)
    lazy var bookRepository: BookRepositoryProtocol = RealmBookRepository(databaseService: databaseService, libraryResolver: self)
    lazy var readingPositionRepository: ReadingPositionRepositoryProtocol = RealmReadingPositionRepository(databaseService: databaseService, modelData: self)
    lazy var annotationRepository: AnnotationRepositoryProtocol = RealmAnnotationRepository(databaseService: databaseService)
    lazy var readerPreferenceRepository: ReaderPreferenceRepositoryProtocol = RealmReaderPreferenceRepository()
    
    lazy var serverManager = CalibreServerManager(modelData: self, databaseService: self.databaseService, serverRepository: self.serverRepository)
    lazy var libraryManager = CalibreLibraryManager(modelData: self, databaseService: self.databaseService, libraryRepository: self.libraryRepository)
    lazy var bookManager = CalibreBookManager(modelData: self, databaseService: self.databaseService, bookRepository: self.bookRepository, readingPositionRepository: self.readingPositionRepository, annotationRepository: self.annotationRepository)
    
    lazy var calibreServerService = CalibreServerService(logger: self.logger, config: self, database: self.databaseService)
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
    
    var librarySyncStatus: [String: CalibreSyncStatus] {
        get { libraryManager.librarySyncStatus }
        set { libraryManager.librarySyncStatus = newValue }
    }

    @Published var fontsManager = FontsManager()
    var userFontInfos: [String: FontInfo] {
        get { fontsManager.userFontInfos }
        set { fontsManager.userFontInfos = newValue }
    }

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
            
            let library = calibreLibraries.first!.value
            
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
        
        migrateLegacyReadPosData()
    }
    
    func migrateLegacyReadPosData() {
        DispatchQueue.global(qos: .background).async {
            guard let realm = try? Realm(configuration: self.realmConf) else {
                return
            }
            
            let bookKeysToMigrate = realm.objects(CalibreBookRealm.self)
                .filter("readPosData != nil")
                .compactMap { $0.primaryKey }
            
            guard !bookKeysToMigrate.isEmpty else { return }
            
            print("migrateLegacyReadPosData: Found \(bookKeysToMigrate.count) legacy reading positions to migrate.")
            
            for key in bookKeysToMigrate {
                guard let freshRealm = try? Realm(configuration: self.realmConf),
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
        bookManager.populateBookShelf()
    }
    
    func populateLibraries() {
        libraryManager.populateLibraries()
    }
    
    func populateLocalLibraryBooks() {
        libraryManager.populateLocalLibraryBooks()
    }
    
    // only move file when triggered by in-app importer, DO NOT MOVE FROM OTHER PLACES
    func onOpenURL(url: URL, doMove: Bool, doOverwrite: Bool, asNew: Bool, knownBookId: Int32? = nil) -> BookImportInfo {
        bookManager.onOpenURL(url: url, doMove: doMove, doOverwrite: doOverwrite, asNew: asNew, knownBookId: knownBookId)
    }
    
    func calcLocalFileBookId(for fileURL: URL) -> Int32? {
        bookManager.calcLocalFileBookId(for: fileURL)
    }
    
    func loadLocalLibraryBookMetadata(fileURL: URL, in library: CalibreLibrary, on server: CalibreServer, knownBookId: Int32? = nil) -> Int32? {
        bookManager.loadLocalLibraryBookMetadata(fileURL: fileURL, in: library, on: server, knownBookId: knownBookId)
    }
    
    func convert(bookRealm: CalibreBookRealm) -> CalibreBook? {
        bookManager.convert(bookRealm: bookRealm)
    }
    
    func convert(library: CalibreLibrary, bookRealm: CalibreBookRealm) -> CalibreBook {
        bookManager.convert(library: library, bookRealm: bookRealm)
    }
    
    func queryLibrary(for bookRealm: CalibreBookRealm) -> CalibreLibrary? {
        bookManager.queryLibrary(for: bookRealm)
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
        sessionManager.getPreferredFormat()
    }
    
    func getPreferredFormat(for book: CalibreBook) -> Format? {
        sessionManager.getPreferredFormat(for: book)
    }
    
    func updatePreferredFormat(for format: Format) {
        sessionManager.updatePreferredFormat(for: format)
    }
    
    // user preferred -> default -> unsupported
    func getPreferredReader(for format: Format) -> ReaderType {
        sessionManager.getPreferredReader(for: format)
    }
    
    func updatePreferredReader(for format: Format, with reader: ReaderType) {
        sessionManager.updatePreferredReader(for: format, with: reader)
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
        bookManager.updateBook(book: book)
    }
    
    func queryBookRealm(book: CalibreBook, realm: Realm) -> CalibreBookRealm? {
        bookManager.queryBookRealm(book: book, realm: realm)
    }
    
    func updateBookRealm(book: CalibreBook, realm: Realm) {
        bookManager.updateBookRealm(book: book, realm: realm)
    }
    
    func removeFromRealm(book: CalibreBook) {
        bookManager.removeFromRealm(book: book)
    }
    
    func removeFromRealm(for primaryKey: String) {
        bookManager.removeFromRealm(for: primaryKey)
    }
    
    func shouldAutoUpdateGoodreads(library: CalibreLibrary) -> (CalibreServerDSReaderHelper, CalibreDSReaderHelperPrefs.Options, CalibreGoodreadsSyncPrefs.PluginPrefs)? {
        bookManager.shouldAutoUpdateGoodreads(library: library)
    }
    
    func addToShelf(book: CalibreBook, formats: [Format]) {
        bookManager.addToShelf(book: book, formats: formats)
    }
    
    func removeFromShelf(inShelfId: String) {
        bookManager.removeFromShelf(inShelfId: inShelfId)
    }
    
    func startDownloadFormatNew(book: CalibreBook, format: Format, overwrite: Bool = false) -> Result<Void, DownloadStartError> {
        return downloadManager.startDownloadNew(book, format: format, overwrite: overwrite)
    }

    @available(*, deprecated, message: "Use startDownloadFormatNew instead")
    func startDownloadFormat(book: CalibreBook, format: Format, overwrite: Bool = false) -> Bool {
        switch startDownloadFormatNew(book: book, format: format, overwrite: overwrite) {
        case .success:
            return true
        case .failure:
            return false
        }
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
        bookManager.clearCache(inShelfId: inShelfId)
    }
    
    func addedCache(book: CalibreBook, format: Format) {
        bookManager.addedCache(book: book, format: format)
    }
    
    func clearCache(book: CalibreBook, format: Format) {
        bookManager.clearCache(book: book, format: format)
    }
    
    func getCacheInfo(book: CalibreBook, format: Format) -> (UInt64, Date?)? {
        bookManager.getCacheInfo(book: book, format: format)
    }
    
    
    func updateCurrentPosition(alertDelegate: AlertDelegate?) {
        sessionManager.updateCurrentPosition(alertDelegate: alertDelegate)
    }


    func goToPreviousBook() {
        bookManager.goToPreviousBook()
    }
    
    func goToNextBook() {
        bookManager.goToNextBook()
    }
    
    func defaultReaderForDefaultFormat(book: CalibreBook) -> (Format, ReaderType) {
        sessionManager.defaultReaderForDefaultFormat(book: book)
    }
    
    func formatOfReader(readerName: String) -> Format? {
        sessionManager.formatOfReader(readerName: readerName)
    }
    
    func prepareBookReading(book: CalibreBook) -> ReaderInfo {
        sessionManager.prepareBookReading(book: book)
    }
    
    func prepareBookReading(url: URL, format: Format, readerType: ReaderType, position: BookDeviceReadingPosition) {
        sessionManager.prepareBookReading(url: url, format: format, readerType: readerType, position: position)
    }
    
    func removeDeleteBooksFromServer(server: CalibreServer) {
        bookManager.removeDeleteBooksFromServer(server: server)
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
    
    func updateServerDSReaderHelper(serverId: String, dsreaderHelper: CalibreServerDSReaderHelper) {
        serverManager.updateServerDSReaderHelper(serverId: serverId, dsreaderHelper: dsreaderHelper)
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
            .flatMap { serverId -> AnyPublisher<Result<(id: String, port: Int, data: Data), URLError>, Never> in
                if let server = self.calibreServers[serverId],
                   let dsreaderHelperServer = self.serverManager.queryServerDSReaderHelper(server: server),
                   let publisher = DSReaderHelperConnector(calibreServerService: self.calibreServerService, server: server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: nil).refreshConfiguration() {
                    return publisher
                        .map { Result.success($0) }
                        .catch { Just(Result.failure($0)) }
                        .eraseToAnyPublisher()
                } else {
                    return Just(Result.failure(URLError(.unknown))).eraseToAnyPublisher()
                }
            }
            .map { result -> (id: String, port: Int, data: Data, config: CalibreDSReaderHelperConfiguration?, error: URLError?) in
                switch result {
                case .success(let task):
                    return (
                        id: task.id,
                        port: task.port,
                        data: task.data,
                        config: try? JSONDecoder().decode(CalibreDSReaderHelperConfiguration.self, from: task.data),
                        error: nil
                    )
                case .failure(let error):
                    return (id: "", port: 0, data: Data(), config: nil, error: error)
                }
            }
            .receive(on: DispatchQueue.main)
            .sink { task in
                if let error = task.error {
                    self.defaultLog.error("Failed to sync server helper configuration: \(error.localizedDescription)")
                    return
                }
                if let config = task.config, config.dsreader_helper_prefs != nil {
                    let dsreaderHelper = CalibreServerDSReaderHelper(port: task.port)
                    dsreaderHelper.configurationData = task.data
                    
                    self.serverManager.updateServerDSReaderHelper(serverId: task.id, dsreaderHelper: dsreaderHelper)
                }
            }
            .store(in: &calibreCancellables)
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
        await bookManager.getBooksMetadata(request: request)
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
        sessionManager.getReadingStatistics(list: list, limitDays: limitDays)
    }
    
    func getBookRealm(forPrimaryKey: String) -> CalibreBookRealm? {
        bookManager.getBookRealm(forPrimaryKey: forPrimaryKey)
    }
    
    func bookExists(forPrimaryKey: String) -> Bool {
        bookManager.bookExists(forPrimaryKey: forPrimaryKey)
    }
}

extension ModelData: LibraryResolver {
    func library(forServerUUID serverUUID: String, libraryName: String) -> CalibreLibrary? {
        return calibreLibraries[CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName)]
    }
}

extension ModelData: ServerResolver {
    func server(forUUID uuid: String) -> CalibreServer? {
        return calibreServers[uuid]
    }
}
