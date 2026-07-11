//
//  AppContainer.swift
//  YetAnotherEBookReader
//
//  Phase 4 of the AppContainer elimination plan: AppContainer is the new
//  composition root. It owns every repository, manager, service, and
//  runtime state that used to live on AppContainer, and conforms to the
//  narrow protocols that services depend on.
//

import Foundation
import SwiftUI
import OSLog

enum ReaderOpenPlacement {
    case currentWorkspace
    case registryOnly
}

struct ReaderOpenRequest: Equatable {
    let presentationID: ReaderPresentation.ID
    let targetWorkspaceID: UUID?
}

struct ReaderPresentationTransfer: Equatable {
    let presentationID: ReaderPresentation.ID
    let targetWorkspaceID: UUID
}

enum UITestingMockLibraryFixture {
    static func installEPUBFixture(
        at destinationURL: URL,
        sourceURL: URL? = nil,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> Bool {
        let source = sourceURL ?? bundle.url(
            forResource: UITestingConfiguration.mockEPUBResourceName,
            withExtension: "epub"
        )
        guard let source, source != destinationURL else { return false }

        do {
            let parentURL = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: source, to: destinationURL)
            return true
        } catch {
            return false
        }
    }

    static func makeBooks(library: CalibreLibrary) -> [CalibreBook] {
        let baseDate = Date(timeIntervalSince1970: 1_645_495_322)
        return [
            makeBook(
                id: 1,
                library: library,
                title: "Mock Book Title",
                author: "Mock Author",
                tag: "Mock Tag",
                series: "Mock Series",
                lastModified: baseDate,
                epubSize: 1_024_000,
                inShelf: true,
                cached: true
            ),
            makeBook(
                id: 2,
                library: library,
                title: "Alpha Browse Book",
                author: "Alpha Author",
                tag: "Alpha Tag",
                series: "Alpha Series",
                lastModified: baseDate.addingTimeInterval(60),
                epubSize: 2_048_000,
                inShelf: false,
                cached: false
            ),
            makeBook(
                id: 3,
                library: library,
                title: "Beta Browse Book",
                author: "Beta Author",
                tag: "Beta Tag",
                series: "Beta Series",
                lastModified: baseDate.addingTimeInterval(120),
                epubSize: 3_072_000,
                inShelf: false,
                cached: false
            )
        ]
    }

    static func makeCategoryResults(
        library: CalibreLibrary,
        books: [CalibreBook]
    ) -> [LibraryCategoryResult] {
        [
            makeCategoryResult(
                library: library,
                categoryName: "Authors",
                books: books,
                value: { $0.authors.first ?? "" }
            ),
            makeCategoryResult(
                library: library,
                categoryName: "Tags",
                books: books,
                value: { $0.tags.first ?? "" }
            ),
            makeCategoryResult(
                library: library,
                categoryName: "Series",
                books: books,
                value: { $0.series }
            )
        ]
    }

    private static func makeCategoryResult(
        library: CalibreLibrary,
        categoryName: String,
        books: [CalibreBook],
        value: (CalibreBook) -> String
    ) -> LibraryCategoryResult {
        let items = books.map { book in
            LibraryCategoryItem(
                name: value(book),
                averageRating: Double(book.rating) / 2,
                count: 1,
                url: "/ajax/category/\(categoryName.lowercased())/\(book.id)"
            )
        }

        return LibraryCategoryResult(
            libraryId: library.id,
            categoryName: categoryName,
            items: items,
            generation: library.lastModified,
            totalNumber: books.count
        )
    }

    private static func makeBook(
        id: Int32,
        library: CalibreLibrary,
        title: String,
        author: String,
        tag: String,
        series: String,
        lastModified: Date,
        epubSize: UInt64,
        inShelf: Bool,
        cached: Bool
    ) -> CalibreBook {
        var book = CalibreBook(id: id, library: library)
        book.title = title
        book.authors = [author]
        book.tags = [tag]
        book.series = series
        book.seriesIndex = Double(id)
        book.lastModified = lastModified
        book.lastSynced = lastModified
        book.lastUpdated = lastModified
        book.timestamp = lastModified
        book.inShelf = inShelf
        book.formats[Format.EPUB.rawValue] = FormatInfo(
            selected: true,
            filename: "\(title).epub",
            serverSize: epubSize,
            serverMTime: lastModified,
            cached: cached,
            cacheSize: cached ? epubSize : 0,
            cacheMTime: cached ? lastModified : .distantPast,
            manifest: nil
        )
        return book
    }
}

enum ReaderSceneActivity {
    static let activityType = "com.drearycold.dsreader.reader"
    private static let presentationIDKey = "presentationID"

    static func make(presentationID: ReaderPresentation.ID, title: String) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        activity.title = title
        activity.userInfo = [presentationIDKey: presentationID.uuidString]
        activity.targetContentIdentifier = presentationID.uuidString
        activity.isEligibleForHandoff = false
        activity.isEligibleForSearch = false
        return activity
    }

    static func presentationID(from activity: NSUserActivity) -> ReaderPresentation.ID? {
        guard activity.activityType == activityType,
              let value = activity.userInfo?[presentationIDKey] as? String
        else { return nil }
        return UUID(uuidString: value)
    }
}

final class AppContainer: AppContainerProtocol, LibraryProvider {
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

    var deviceName = UIDevice.current.name {
        didSet {
            calibreServerService.updateDeviceName(deviceName)
        }
    }

    private let bookImportBroadcaster = ManagerAsyncBroadcaster<BookImportInfo>()
    private let dismissAllBroadcaster = ManagerAsyncBroadcaster<String>()

    private let readerOpenRequestBroadcaster = ManagerAsyncBroadcaster<ReaderOpenRequest>()
    private let readerPresentationTransferBroadcaster = ManagerAsyncBroadcaster<ReaderPresentationTransfer>()
    private var activeReaderWorkspaceID: UUID?
    private var activeAppSceneIDs = Set<UUID>()
    private var transferringReaderPresentationIDs = Set<ReaderPresentation.ID>()
    private var probeTimerTask: Task<Void, Never>?
    private static let probeIntervalNanoseconds: UInt64 = 60 * 1_000_000_000
    var readerWindowSupportOverride: Bool?
    var readerWindowRequestHandler: ((NSUserActivity?) -> Void)?
    var readerPresentationPersistenceStore: ReaderPresentationPersistenceStore = UserDefaultsReaderPresentationPersistenceStore()

    var downloadManager = BookDownloadManager()
    lazy var sessionManager = ReadingSessionManager(
        container: self,
        persistenceStore: readerPresentationPersistenceStore
    )

    var updatingMetadata = false {
        didSet {
            if updatingMetadata {
                updatingMetadataSucceed = false
                updatingMetadataStatus = "Updating"
            }
        }
    }
    var updatingMetadataStatus = "" {
        didSet {
            if updatingMetadataStatus == "Success" || updatingMetadataStatus == "Deleted" {
                updatingMetadataSucceed = true
            }
        }
    }
    var updatingMetadataSucceed = false

    private var defaultLog = Logger()

    var logger: CalibreActivityLogger?

    let coverCache: BookCoverCaching = DefaultBookCoverCache()

    let databaseService = DatabaseService()

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
            ?? DefaultServerScopedRealmConfigurationProvider().configuration(for: server)
    }
    lazy var folioReaderProfileRepository: FolioReaderProfileRepositoryProtocol = RealmFolioReaderProfileRepository(realmConfiguration: self.databaseService.realmConf)

    lazy var serverManager = CalibreServerManager(container: self, databaseService: self.databaseService, serverRepository: self.serverRepository)
    lazy var libraryManager = CalibreLibraryManager(container: self, databaseService: self.databaseService, libraryRepository: self.libraryRepository)
    lazy var databaseBootstrapper = DatabaseBootstrapper(container: self)
    lazy var bookManager = CalibreBookManager(container: self, databaseService: self.databaseService, bookRepository: self.bookRepository, readingPositionRepository: self.readingPositionRepository, annotationRepository: self.annotationRepository)

    var serverScopedRealmProvider: ServerScopedRealmConfigurationProviding = DefaultServerScopedRealmConfigurationProvider()

    lazy var calibreServerService = CalibreServerService(logger: self.logger ?? CalibreActivityLogger(repository: self.activityLogRepository), config: self, database: self.databaseService)
    private lazy var defaultSearchCacheStore = RealmSearchCacheStore(
        databaseService: self.databaseService,
        librarySnapshotProvider: self
    )
    lazy var searchCacheRepository: SearchCacheRepository = self.defaultSearchCacheStore
    lazy var librarySearchService = LibrarySearchService(service: self.calibreServerService, repository: self.searchCacheRepository)
    lazy var unifiedSearchService = UnifiedSearchService(
        repository: self.searchCacheRepository,
        librarySearchService: self.librarySearchService,
        libraryProvider: self
    )
    lazy var categoryCacheRepository: CategoryCacheRepository = self.defaultSearchCacheStore
    lazy var libraryCategoryService = LibraryCategoryService(service: self.calibreServerService, repository: self.categoryCacheRepository)
    lazy var unifiedCategoryService = UnifiedCategoryService(repository: self.categoryCacheRepository, libraryProvider: self)

    @MainActor lazy var shelfDataModel = YabrShelfDataModel(unifiedSearchService: self.unifiedSearchService, container: self)

    private let probeLibraryLastModifiedBroadcaster = ManagerAsyncBroadcaster<CalibreSyncLibraryRequest>()

    /// inShelfId for single book
    /// empty string for full update
    private let calibreUpdateBroadcaster = ManagerAsyncBroadcaster<calibreUpdatedSignal>()

    var fontsManager = FontsManager()

    var isDatabaseReady: Bool {
        databaseService.realm != nil && databaseService.metadataRealm != nil
    }

    func getBook(for primaryKey: String) -> CalibreBook? {
        bookManager.getBook(for: primaryKey)
    }

    @MainActor
    func refreshDatabase() {
        databaseService.refreshMainRealm()
    }

    func resetDatabaseBootstrapState(clearConfiguration: Bool = false) {
        logger = nil
        databaseService.reset(clearConfiguration: clearConfiguration)
    }

    deinit {
        calibreUpdateBroadcaster.finish()
        bookImportBroadcaster.finish()
        dismissAllBroadcaster.finish()
        readerOpenRequestBroadcaster.finish()
        readerPresentationTransferBroadcaster.finish()
        probeLibraryLastModifiedBroadcaster.finish()
        probeTimerTask?.cancel()
    }

    @MainActor
    func publishBookImport(_ info: BookImportInfo) {
        bookImportBroadcaster.send(info)
    }

    func bookImportEvents() -> AsyncStream<BookImportInfo> {
        bookImportBroadcaster.stream()
    }

    @MainActor
    func publishDismissAll(_ reason: String) {
        dismissAllBroadcaster.send(reason)
    }

    func dismissAllEvents() -> AsyncStream<String> {
        dismissAllBroadcaster.stream()
    }

    @MainActor
    func setActiveReaderWorkspace(id: UUID?) {
        activeReaderWorkspaceID = id
    }

    @MainActor
    func clearActiveReaderWorkspace(id: UUID) {
        if activeReaderWorkspaceID == id {
            activeReaderWorkspaceID = nil
        }
    }

    @MainActor
    func markAppSceneActive(id: UUID) {
        let wasEmpty = activeAppSceneIDs.isEmpty
        activeAppSceneIDs.insert(id)
        if wasEmpty {
            enableProbeTimer()
        }
    }

    @MainActor
    func markAppSceneBackground(id: UUID) {
        activeAppSceneIDs.remove(id)
        if activeAppSceneIDs.isEmpty {
            disableProbeTimer()
        }
    }

    @MainActor
    private func enableProbeTimer() {
        probeTimerTask?.cancel()
        serverManager.probeServersReachability(with: [], updateLibrary: true)
        probeTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: Self.probeIntervalNanoseconds)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                self?.serverManager.probeServersReachability(with: [], updateLibrary: true)
            }
        }
    }

    @MainActor
    private func disableProbeTimer() {
        probeTimerTask?.cancel()
        probeTimerTask = nil
    }

    @discardableResult
    func openReader(
        book: CalibreBook,
        readerInfo: ReaderInfo? = nil,
        source: ReaderPresentationSource,
        placement: ReaderOpenPlacement = .currentWorkspace,
        targetWorkspaceID: UUID? = nil,
        reuseExisting: Bool = true
    ) -> ReaderPresentation {
        let presentation = sessionManager.openReader(
            book: book,
            readerInfo: readerInfo,
            source: source,
            reuseExisting: reuseExisting
        )
        if placement == .currentWorkspace {
            readerOpenRequestBroadcaster.send(
                ReaderOpenRequest(
                    presentationID: presentation.id,
                    targetWorkspaceID: targetWorkspaceID
                )
            )
        }
        return presentation
    }

    func readerOpenRequests() -> AsyncStream<ReaderOpenRequest> {
        readerOpenRequestBroadcaster.stream()
    }

    @MainActor
    func publishReaderPresentationTransfer(presentationID: ReaderPresentation.ID, targetWorkspaceID: UUID) {
        readerPresentationTransferBroadcaster.send(
            ReaderPresentationTransfer(
                presentationID: presentationID,
                targetWorkspaceID: targetWorkspaceID
            )
        )
    }

    func readerPresentationTransfers() -> AsyncStream<ReaderPresentationTransfer> {
        readerPresentationTransferBroadcaster.stream()
    }

    @MainActor
    var supportsReaderWindows: Bool {
        if let readerWindowSupportOverride {
            return readerWindowSupportOverride
        }
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return UIDevice.current.userInterfaceIdiom == .pad && UIApplication.shared.supportsMultipleScenes
        #endif
    }

    @MainActor
    func requestEmptyReaderWindow() -> Bool {
        guard supportsReaderWindows else { return false }
        requestReaderScene(userActivity: nil)
        return true
    }

    @MainActor
    func requestReaderWindow(for presentation: ReaderPresentation) -> Bool {
        guard supportsReaderWindows else { return false }
        let activity = ReaderSceneActivity.make(presentationID: presentation.id, title: presentation.title)
        requestReaderScene(userActivity: activity)
        return true
    }

    @MainActor
    func markReaderPresentationTransfer(id: ReaderPresentation.ID) {
        transferringReaderPresentationIDs.insert(id)
    }

    @MainActor
    func consumeReaderPresentationTransfer(id: ReaderPresentation.ID?) -> Bool {
        guard let id else { return false }
        return transferringReaderPresentationIDs.remove(id) != nil
    }

    @MainActor
    private func requestReaderScene(userActivity: NSUserActivity?) {
        if let readerWindowRequestHandler {
            readerWindowRequestHandler(userActivity)
        } else {
            UIApplication.shared.requestSceneSessionActivation(nil, userActivity: userActivity, options: nil, errorHandler: nil)
        }
    }

    @MainActor
    func publishCalibreUpdate(_ signal: calibreUpdatedSignal) {
        calibreUpdateBroadcaster.send(signal)
    }

    @MainActor
    func calibreUpdates() -> AsyncStream<calibreUpdatedSignal> {
        calibreUpdateBroadcaster.stream()
    }

    func publishProbeLibraryLastModifiedRequest(_ request: CalibreSyncLibraryRequest) {
        probeLibraryLastModifiedBroadcaster.send(request)
    }

    func probeLibraryLastModifiedRequests() -> AsyncStream<CalibreSyncLibraryRequest> {
        probeLibraryLastModifiedBroadcaster.stream()
    }

    init(
        mock: Bool = false,
        testRealmEnvironment: TestRealmEnvironment? = nil
    ) {
        AppContainer.shared = self
        if mock {
            readerPresentationPersistenceStore = InMemoryReaderPresentationPersistenceStore()
        }

        setupRealmDefaults()

        if let env = testRealmEnvironment {
            // Test path: install the in-memory main Realm + in-memory
            // server-scoped provider before any of the mock population
            // runs, so repositories and managers observe consistent
            // test-only Realm configurations from the very first
            // access. The mock block below calls populateLibraries()
            // and initializeDatabase(), both of which need this to
            // already be wired.
            databaseService.installTestConfiguration(env.mainRealmConfiguration)
            self.serverScopedRealmProvider = env.serverScopedRealmProvider
        }

        setupCoverCache()
        wireCrossManagerSubscriptions()

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
            let uiTestingMockLibrary = makeUITestingMockLibraryIfNeeded()
            guard let library = uiTestingMockLibrary ?? libraryManager.calibreLibraries.first?.value else {
                return
            }

            let mockBooks = UITestingMockLibraryFixture.makeBooks(library: library)
            guard let book = mockBooks.first else { return }

            if UITestingConfiguration.isEnabled(),
               let bookSavedURL = getSavedUrl(book: book, format: Format.EPUB) {
                removeFolioCache(book: book, format: .EPUB)
                if UITestingMockLibraryFixture.installEPUBFixture(at: bookSavedURL) == false {
                    defaultLog.error("Unable to install the UI-testing EPUB fixture")
                }
            }

            var position = BookDeviceReadingPosition(
                id: self.deviceName,
                readerName: UITestingConfiguration.mockReaderType.rawValue,
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
            mockBooks.forEach { self.bookRepository.saveBook($0) }

            if UITestingConfiguration.isEnabled() {
                self.readerPreferenceRepository.saveFolioPreferences(
                    UITestingConfiguration.mockFolioReaderPreferences(),
                    for: book
                )
            }

            self.bookManager.readingBook = book

            self.bookManager.booksInShelf[self.bookManager.readingBook!.inShelfId] = self.bookManager.readingBook
            self.bookManager.isShelfLoaded = true

            if UITestingConfiguration.isEnabled() {
                seedMockBrowseSearchCache(books: mockBooks, library: library)
                seedMockBrowseCategoryCache(books: mockBooks, library: library)
            }

            cleanCalibreActivities(startDatetime: Date())
            logStartCalibreActivity(type: "Mock", request: URLRequest(url: URL(string: "http://calibre-server.lan:8080/")!), startDatetime: Date(), bookId: 1, libraryId: library.id)
            Task { @MainActor [weak self] in
                self?.publishCalibreUpdate(.shelf)
            }
        }
    }

    private func seedMockBrowseSearchCache(books: [CalibreBook], library: CalibreLibrary) {
        let targetSource = library.server.isLocal
            ? URL(fileURLWithPath: "/realm").absoluteString
            : library.server.baseUrl.replacingOccurrences(of: ".", with: "_")
        try? searchCacheRepository.saveLibrarySourceResult(
            libraryId: library.id,
            search: "",
            sortBy: .Modified,
            sortAsc: false,
            filters: [:],
            sourceUrl: targetSource,
            result: LibrarySourceSearchResult(
                generation: library.lastModified,
                totalNumber: books.count,
                bookIds: books.map(\.id),
                books: books
            )
        )
    }

    private func seedMockBrowseCategoryCache(books: [CalibreBook], library: CalibreLibrary) {
        for result in UITestingMockLibraryFixture.makeCategoryResults(library: library, books: books) {
            try? categoryCacheRepository.saveLibraryCategoryResult(
                libraryId: library.id,
                categoryName: result.categoryName,
                result: result
            )
        }
    }

    private func makeUITestingMockLibraryIfNeeded() -> CalibreLibrary? {
        guard UITestingConfiguration.isEnabled() else { return nil }

        let server = CalibreServer(
            uuid: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "UI Test Server",
            baseUrl: ".",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        var library = CalibreLibrary(server: server, key: "ui-test", name: "UI Test Library")
        library.lastModified = Date(timeIntervalSince1970: 1645495322)

        try? serverRepository.saveServer(server)
        serverManager.calibreServers[server.id] = server
        try? libraryRepository.saveLibrary(library)
        libraryManager.calibreLibraries[library.id] = library

        return library
    }

    // MARK: - Init helpers

    /// Pre-populate the Realm default configuration so SwiftUI views using
    /// `ObservedResults` don't crash before `tryInitializeDatabase` has produced
    /// the real configuration.
    private func setupRealmDefaults() {
        databaseService.installInitialDefaultConfiguration()
    }

    /// Configure cover cache and authenticated HTTP image requests.
    private func setupCoverCache() {
        coverCache.configureAuthentication(serverProvider: self)

        downloadManager.container = self
        fontsManager.reloadCustomFonts()
    }

    /// Wire subscriptions that cross manager boundaries.
    private func wireCrossManagerSubscriptions() {
        libraryManager.startProbeLibraryLastModifiedTask()
    }

    func tryInitializeDatabase(statusHandler: @escaping (String) -> Void) throws {
        try databaseService.prepareProductionConfiguration(statusHandler: statusHandler)
    }

    func initializeDatabase() throws {
        guard let realmConf = databaseService.realmConf else {
            defaultLog.error("initializeDatabase called without a Realm configuration")
            throw DatabaseBootstrapError.realmConfigurationMissing
        }
        do {
            try MainActor.assumeIsolated {
                try databaseBootstrapper.bootstrap(realmConf: realmConf)
            }
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
        let pluginDictionaryViewer = library.pluginDictionaryViewerOptions(
            configuration: dsreaderHelperServer.configuration
        )
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

private struct AppContainerEnvironmentKey: EnvironmentKey {
    static var defaultValue: AppContainer {
        guard let shared = AppContainer.shared else {
            assertionFailure("Missing AppContainer environment")
            return AppContainer(mock: true)
        }
        return shared
    }
}

extension EnvironmentValues {
    var appContainer: AppContainer {
        get { self[AppContainerEnvironmentKey.self] }
        set { self[AppContainerEnvironmentKey.self] = newValue }
    }
}

private struct ReaderWorkspaceIDEnvironmentKey: EnvironmentKey {
    static var defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var readerWorkspaceID: UUID? {
        get { self[ReaderWorkspaceIDEnvironmentKey.self] }
        set { self[ReaderWorkspaceIDEnvironmentKey.self] = newValue }
    }
}
