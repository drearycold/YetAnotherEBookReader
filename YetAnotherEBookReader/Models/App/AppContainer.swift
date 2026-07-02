//
//  AppContainer.swift
//  YetAnotherEBookReader
//
//  Phase 4 of the AppContainer elimination plan: AppContainer is the new
//  composition root. It owns every repository, manager, service, and
//  runtime state that used to live on AppContainer, and conforms to the
//  three narrow protocols (AppContainerProtocol, CalibreServerConfigProvider,
//  LibraryProvider) that services depend on.
//
//  `AppContainer` coexists with `AppContainer` during 4a-4d. Phase 4e deletes
//  AppContainer and renames all callers; for the transitional period, both
//  types share `AppContainer.RealmSchemaVersion` so the two can boot
//  side-by-side in preview contexts.
//

import Foundation
import Combine
import RealmSwift
import SwiftUI
import OSLog
import Kingfisher
import CryptoSwift

final class AppContainer: ObservableObject, AppContainerProtocol, LibraryProvider {
    static var shared: AppContainer?

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
    lazy var sessionManager = ReadingSessionManager(container: self)

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

    static var RealmSchemaVersion: UInt64 = 141
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
    lazy var readingPositionRepository: ReadingPositionRepositoryProtocol = RealmReadingPositionRepository(
        databaseService: databaseService,
        realmConfigurationProvider: serverScopedRealmProvider
    )
    lazy var annotationRepository: AnnotationRepositoryProtocol = RealmAnnotationRepository(databaseService: databaseService)
    lazy var activityLogRepository: ActivityLogRepositoryProtocol = RealmActivityLogRepository(databaseService: databaseService, bookRepository: self.bookRepository, container: self)
    lazy var readerPreferenceRepository: ReaderPreferenceRepositoryProtocol = RealmReaderPreferenceRepository { [weak self] server in
        self?.serverScopedRealmProvider.configuration(for: server)
            ?? BookAnnotation.getBookPreferenceServerConfig(server)
    }
    lazy var folioReaderProfileRepository: FolioReaderProfileRepositoryProtocol = RealmFolioReaderProfileRepository(realmConfiguration: self.realmConf)

    lazy var serverManager = CalibreServerManager(container: self, databaseService: self.databaseService, serverRepository: self.serverRepository)
    lazy var libraryManager = CalibreLibraryManager(container: self, databaseService: self.databaseService, libraryRepository: self.libraryRepository)
    lazy var databaseBootstrapper = DatabaseBootstrapper(container: self)
    lazy var bookManager = CalibreBookManager(container: self, databaseService: self.databaseService, bookRepository: self.bookRepository, readingPositionRepository: self.readingPositionRepository, annotationRepository: self.annotationRepository)

    var serverScopedRealmProvider: ServerScopedRealmConfigurationProviding = DefaultServerScopedRealmConfigurationProvider()

    lazy var calibreServerService = CalibreServerService(logger: self.logger ?? CalibreActivityLogger(realmConf: Realm.Configuration.defaultConfiguration), config: self, database: self.databaseService)
    lazy var searchCacheRepository = RealmSearchCacheStore(container: self)
    lazy var librarySearchService = LibrarySearchService(service: self.calibreServerService, repository: self.searchCacheRepository)
    lazy var unifiedSearchService = UnifiedSearchService(
        repository: self.searchCacheRepository,
        librarySearchService: self.librarySearchService,
        libraryProvider: self
    )
    lazy var categoryCacheRepository: CategoryCacheRepository = self.searchCacheRepository
    lazy var libraryCategoryService = LibraryCategoryService(service: self.calibreServerService, repository: self.categoryCacheRepository)
    lazy var unifiedCategoryService = UnifiedCategoryService(repository: self.categoryCacheRepository, libraryProvider: self)

    @MainActor lazy var shelfDataModel = YabrShelfDataModel(unifiedSearchService: self.unifiedSearchService, container: self)

    let probeLibraryLastModifiedSubject = PassthroughSubject<CalibreSyncLibraryRequest, Never>()

    var probeTimer: AnyCancellable?

    /// inShelfId for single book
    /// empty string for full update
    let calibreUpdatedSubject = PassthroughSubject<calibreUpdatedSignal, Never>()
    private var calibreUpdateContinuations = [UUID: AsyncStream<calibreUpdatedSignal>.Continuation]()

    @Published var fontsManager = FontsManager()

    var isDatabaseReady: Bool {
        realm != nil && realmSaveBooksMetadata != nil && databaseService.realm != nil
    }

    func getBook(for primaryKey: String) -> CalibreBook? {
        bookManager.getBook(for: primaryKey)
    }

    @MainActor
    func refreshDatabase() {
        databaseService.realm?.refresh()
    }

    func resetDatabaseBootstrapState(clearConfiguration: Bool = false) {
        realm = nil
        realmSaveBooksMetadata = nil
        logger = nil
        databaseService.realm = nil
        if clearConfiguration {
            realmConf = nil
            databaseService.realmConf = nil
        }
    }

    deinit {
        calibreUpdateContinuations.values.forEach { $0.finish() }
    }

    @MainActor
    func publishCalibreUpdate(_ signal: calibreUpdatedSignal) {
        for continuation in calibreUpdateContinuations.values {
            continuation.yield(signal)
        }
        calibreUpdatedSubject.send(signal)
    }

    @MainActor
    func calibreUpdates() -> AsyncStream<calibreUpdatedSignal> {
        let id = UUID()
        return AsyncStream { [weak self] continuation in
            self?.calibreUpdateContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.calibreUpdateContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    @MainActor
    func publishLegacyRecentShelfItems(_ books: [ShelfBookItem]) {
        recentShelfItemsSubject.send(books)
    }

    @MainActor
    func publishLegacyDiscoverShelfItems(_ sections: [ShelfSectionItem]) {
        discoverShelfItemsSubject.send(sections)
    }

    init(
        mock: Bool = false,
        testRealmEnvironment: TestRealmEnvironment? = nil
    ) {
        AppContainer.shared = self

        setupRealmDefaults()

        if let env = testRealmEnvironment {
            // Test path: install the in-memory main Realm + in-memory
            // server-scoped provider before any of the mock population
            // runs, so repositories and managers observe consistent
            // test-only Realm configurations from the very first
            // access. The mock block below calls populateLibraries()
            // and initializeDatabase(), both of which need this to
            // already be wired.
            Realm.Configuration.defaultConfiguration = env.mainRealmConfiguration
            self.realmConf = env.mainRealmConfiguration
            DatabaseService.shared.setup(conf: env.mainRealmConfiguration)
            self.serverScopedRealmProvider = env.serverScopedRealmProvider
        }

        setupImageCache()
        wireCrossManagerSubscriptions()
        wireObjectWillChangeForwarding()

        if mock {
            // In the test path the in-memory main Realm is already
            // wired; skip tryInitializeDatabase so the production
            // DatabaseMigrator does not overwrite realmConf with a
            // file-backed configuration. initializeDatabase() still
            // runs so the bootstrap opens the (in-memory) Realm and
            // populates the libraries.
            if testRealmEnvironment == nil {
                try? tryInitializeDatabase { _ in }
            }
            try? initializeDatabase()

            // If the bootstrap failed (e.g. file-descriptor exhaustion
            // in long test runs opening many in-memory Realms), the
            // libraries dict stays empty. Skip the mock-data population
            // rather than force-unwrapping nil — tests that depend on
            // this state will fail their own assertions, but the
            // container still constructs and the rest of the app stays
            // usable.
            guard let library = libraryManager.calibreLibraries.first?.value else {
                return
            }

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

            self.readingPositionRepository.savePosition(position, for: book)

            self.bookManager.readingBook = book

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
        AppContainer.RealmSchemaVersion = 141
        let initialConf = Realm.Configuration(
            schemaVersion: AppContainer.RealmSchemaVersion,
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
        KingfisherManager.shared.defaultOptions = [.requestModifier(AuthPlugin(container: self))]
        ImageDownloader.default.authenticationChallengeResponder = authResponsor

        downloadManager.container = self
        fontsManager.reloadCustomFonts()
    }

    /// Wire subscriptions that cross manager boundaries (so the originating
    /// `init` body stays focused on `objectWillChange` plumbing).
    private func wireCrossManagerSubscriptions() {
        libraryManager.registerProbeLibraryLastModifiedCancellable()
    }

    /// Forward each manager's `objectWillChange` to our own so SwiftUI views
    /// observing the container redraw on manager-level mutations.
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
        AppContainer.RealmSchemaVersion = schemaVersion
        let conf = try DatabaseMigrator().makeConfiguration(schemaVersion: schemaVersion, statusHandler: statusHandler)
        Realm.Configuration.defaultConfiguration = conf
        realmConf = conf
    }

    func initializeDatabase() throws {
        guard let realmConf = realmConf else {
            defaultLog.error("initializeDatabase called without a Realm configuration")
            throw DatabaseBootstrapError.realmConfigurationMissing
        }
        do {
            try databaseBootstrapper.bootstrap(realmConf: realmConf)
        } catch {
            defaultLog.error("initializeDatabase failed: \(error.localizedDescription)")
            throw error
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

extension AppContainer: LibraryResolver {
    func library(forServerUUID serverUUID: String, libraryName: String) -> CalibreLibrary? {
        return libraryManager.calibreLibraries[CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName)]
    }
}

extension AppContainer: ServerResolver {
    func server(forUUID uuid: String) -> CalibreServer? {
        return serverManager.calibreServers[uuid]
    }
}
