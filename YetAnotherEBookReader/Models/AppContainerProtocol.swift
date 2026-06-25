//
//  AppContainerProtocol.swift
//  YetAnotherEBookReader
//
//  Phase 3 of the AppContainer elimination plan: a single facade protocol
//  that aggregates all repositories, managers, services, and runtime
//  state so that future phases can swap the concrete `AppContainer` for a
//  lighter container. Today, both `AppContainer` and `AppContainer`
//  conform to it side-by-side during Phase 4; Phase 4e drops `AppContainer`.
//
//  `CalibreServerConfigProvider` and `LibraryProvider` continue to exist
//  as their own narrow protocols; `AppContainerProtocol` is independent
//  and is conformed to alongside the other two.
//

import Foundation
import Combine
import RealmSwift
import SwiftUI
import Kingfisher

protocol AppContainerProtocol: AnyObject, LibraryResolver, ServerResolver {
    // MARK: - Repositories

    var serverRepository: ServerRepositoryProtocol { get }
    var libraryRepository: LibraryRepositoryProtocol { get }
    var bookRepository: BookRepositoryProtocol { get }
    var readingPositionRepository: ReadingPositionRepositoryProtocol { get }
    var annotationRepository: AnnotationRepositoryProtocol { get }
    var activityLogRepository: ActivityLogRepositoryProtocol { get }
    var readerPreferenceRepository: ReaderPreferenceRepositoryProtocol { get }
    var folioReaderProfileRepository: FolioReaderProfileRepositoryProtocol { get }
    var searchCacheRepository: RealmSearchCacheStore { get }
    var categoryCacheRepository: CategoryCacheRepository { get }

    // MARK: - Managers

    var serverManager: CalibreServerManager { get }
    var libraryManager: CalibreLibraryManager { get }
    var bookManager: CalibreBookManager { get }
    var sessionManager: ReadingSessionManager { get }
    var downloadManager: BookDownloadManager { get }
    var fontsManager: FontsManager { get }
    var databaseBootstrapper: DatabaseBootstrapper { get }
    var shelfDataModel: YabrShelfDataModel { get }

    // MARK: - Services

    var calibreServerService: CalibreServerService { get }
    var librarySearchService: LibrarySearchService { get }
    var unifiedSearchService: UnifiedSearchService { get }
    var libraryCategoryService: LibraryCategoryService { get }
    var unifiedCategoryService: UnifiedCategoryService { get }

    // MARK: - Database

    var databaseService: DatabaseService { get }
    var isDatabaseReady: Bool { get }

    // MARK: - Runtime state

    var realm: Realm? { get set }
    var realmSaveBooksMetadata: Realm? { get set }
    var realmConf: Realm.Configuration? { get set }
    var logger: CalibreActivityLogger? { get set }
    var probeTimer: AnyCancellable? { get set }
    var calibreCancellables: Set<AnyCancellable> { get set }
    var authResponsor: AuthResponsor { get }
    var kfImageCache: ImageCache { get }
    var presentingStack: [Binding<Bool>] { get set }

    // MARK: - Calibre cache (used directly by services/repositories)

    var calibreLibraries: [String: CalibreLibrary] { get set }
    var calibreServers: [String: CalibreServer] { get set }
    var calibreServerInfoStaging: [String: CalibreServerInfo] { get set }
    var librarySyncStatus: [String: CalibreSyncStatus] { get set }
    var booksInShelf: [String: CalibreBook] { get set }
    var deviceName: String { get set }

    // MARK: - Sync progress (CalibreServerConfigProvider surface)

    var updatingMetadata: Bool { get set }
    var updatingMetadataStatus: String { get set }
    var updatingMetadataSucceed: Bool { get set }

    // MARK: - App-wide events

    var calibreUpdatedSubject: PassthroughSubject<calibreUpdatedSignal, Never> { get }
    var bookImportedSubject: PassthroughSubject<BookImportInfo, Never> { get }
    var dismissAllSubject: PassthroughSubject<String, Never> { get }
    var recentShelfItemsSubject: PassthroughSubject<[ShelfBookItem], Never> { get }
    var discoverShelfItemsSubject: PassthroughSubject<[ShelfSectionItem], Never> { get }
    var bookReaderActivitySubject: PassthroughSubject<ScenePhase, Never> { get }
    var probeLibraryLastModifiedSubject: PassthroughSubject<CalibreSyncLibraryRequest, Never> { get }

    // MARK: - Database lifecycle / activity log helpers
    // Exposed so `DatabaseBootstrapper` and `CalibreActivityLogger` (which
    // take a weak `AppContainerProtocol`) can be reused by both the legacy
    // `AppContainer` and the new `AppContainer` during Phase 4.

    func getBook(for primaryKey: String) -> CalibreBook?

    @MainActor
    func refreshDatabase()

    func tryInitializeDatabase(statusHandler: @escaping (String) -> Void) throws
    func initializeDatabase()
    func migrateLegacyReadPosData()

    func getCustomDictViewer() -> (Bool, URL?)
    func getCustomDictViewerNew(library: CalibreLibrary) -> (Bool, URL?)
    func updateCustomDictViewer(enabled: Bool, value: String?) -> URL?

    func cleanCalibreActivities(startDatetime: Date)
    func logStartCalibreActivity(type: String, request: URLRequest, startDatetime: Date, bookId: Int32?, libraryId: String?)
    func logFinishCalibreActivity(type: String, request: URLRequest, startDatetime: Date, finishDatetime: Date, errMsg: String)
}

// MARK: - Default `LibraryResolver` / `ServerResolver` implementations
//
// Both `AppContainer` and `AppContainer` use the cached dictionaries
// (`calibreLibraries`, `calibreServers`) as the single source of truth for
// these lookups. The default extension lets them share one implementation
// while keeping `LibraryResolver` / `ServerResolver` as separate narrow
// protocols (for repository code that should not need the full
// `AppContainerProtocol`).

extension AppContainerProtocol {
    func library(forServerUUID serverUUID: String, libraryName: String) -> CalibreLibrary? {
        return calibreLibraries[CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName)]
    }

    func server(forUUID uuid: String) -> CalibreServer? {
        return calibreServers[uuid]
    }
}
