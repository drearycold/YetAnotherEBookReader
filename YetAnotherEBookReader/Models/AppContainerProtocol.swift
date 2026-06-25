//
//  AppContainerProtocol.swift
//  YetAnotherEBookReader
//
//  Phase 3 of the ModelData elimination plan: a single facade protocol
//  that aggregates all repositories, managers, services, and runtime
//  state so that future phases can swap the concrete `ModelData` for a
//  lighter container. Today, `ModelData` is the only conformer.
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

protocol AppContainerProtocol: AnyObject {
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

    // MARK: - App-wide events

    var calibreUpdatedSubject: PassthroughSubject<calibreUpdatedSignal, Never> { get }
    var bookImportedSubject: PassthroughSubject<BookImportInfo, Never> { get }
    var dismissAllSubject: PassthroughSubject<String, Never> { get }
    var recentShelfItemsSubject: PassthroughSubject<[ShelfBookItem], Never> { get }
    var discoverShelfItemsSubject: PassthroughSubject<[ShelfSectionItem], Never> { get }
    var bookReaderActivitySubject: PassthroughSubject<ScenePhase, Never> { get }
    var probeLibraryLastModifiedSubject: PassthroughSubject<CalibreSyncLibraryRequest, Never> { get }
}
