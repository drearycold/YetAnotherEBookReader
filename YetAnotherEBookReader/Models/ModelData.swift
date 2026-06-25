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

final class ModelData: ObservableObject, AppContainerProtocol, CalibreServerConfigProvider, LibraryProvider {
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
    lazy var databaseBootstrapper = DatabaseBootstrapper(modelData: self)
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

        setupRealmDefaults()
        setupImageCache()
        wireCrossManagerSubscriptions()
        wireObjectWillChangeForwarding()

        if mock {
            try? tryInitializeDatabase { _ in }
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

    // MARK: - Init helpers

    /// Pre-populate `Realm.Configuration.defaultConfiguration` with an empty
    /// migration block so SwiftUI views using `ObservedResults` don't crash
    /// before `tryInitializeDatabase` has produced the real configuration.
    private func setupRealmDefaults() {
        ModelData.RealmSchemaVersion = 140
        let initialConf = Realm.Configuration(
            schemaVersion: ModelData.RealmSchemaVersion,
            migrationBlock: { _, _ in }
        )
        Realm.Configuration.defaultConfiguration = initialConf
        self.realmConf = initialConf
    }

    /// Configure the Kingfisher image cache and register the auth challenge
    /// responder so the rest of the app can issue authenticated HTTP image
    /// requests via `KFImage`.
    private func setupImageCache() {
        kfImageCache.diskStorage.config.expiration = .days(28)
        KingfisherManager.shared.defaultOptions = [.requestModifier(AuthPlugin(modelData: self))]
        ImageDownloader.default.authenticationChallengeResponder = authResponsor

        downloadManager.modelData = self
        fontsManager.reloadCustomFonts()
    }

    /// Wire subscriptions that cross manager boundaries (so the originating
    /// `init` body stays focused on `objectWillChange` plumbing).
    private func wireCrossManagerSubscriptions() {
        libraryManager.registerProbeLibraryLastModifiedCancellable()
        registerRecentShelfUpdater()

        downloadManager.bookDownloadedSubject.sink { [weak self] book in
            self?.calibreUpdatedSubject.send(.book(book))
        }.store(in: &calibreCancellables)
    }

    /// Forward each manager's `objectWillChange` to our own so SwiftUI views
    /// observing `modelData` redraw on manager-level mutations.
    private func wireObjectWillChangeForwarding() {
        forwardObjectWillChange(of: serverManager)
        forwardObjectWillChange(of: libraryManager)
        forwardObjectWillChange(of: bookManager)
        forwardObjectWillChange(of: sessionManager)
    }

    private func forwardObjectWillChange<Manager: ObservableObject>(of manager: Manager) {
        manager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &calibreCancellables)
    }
    
    func tryInitializeDatabase(statusHandler: @escaping (String) -> Void) throws {
        let schemaVersion = UInt64(YabrAppInfo.shared.build) ?? 1
        ModelData.RealmSchemaVersion = schemaVersion
        let conf = try DatabaseMigrator().makeConfiguration(schemaVersion: schemaVersion, statusHandler: statusHandler)
        Realm.Configuration.defaultConfiguration = conf
        realmConf = conf
    }
    
    func initializeDatabase() {
        guard let realmConf = realmConf else { return }
        do {
            try databaseBootstrapper.bootstrap(realmConf: realmConf)
        } catch {
            // Leave realm nil so YetAnotherEBookReaderApp keeps the upgrade UI
            // visible. The bootstrapper already logged the underlying error.
            defaultLog.error("initializeDatabase failed: \(error.localizedDescription)")
        }
    }

    func migrateLegacyReadPosData() {
        databaseBootstrapper.migrateLegacyReadPosData()
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
