//
//  BookMetadataSyncWorkerTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-28.
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

final class BookMetadataSyncWorkerTests: XCTestCase {
    
    private var readingPositionRepo: ThreadCheckReadingPositionRepository!
    private var annotationRepo: ThreadCheckAnnotationRepository!
    private var worker: BookMetadataSyncWorker!
    private var library: CalibreLibrary!
    private var book: CalibreBook!
    
    override func setUp() {
        super.setUp()
        readingPositionRepo = ThreadCheckReadingPositionRepository()
        annotationRepo = ThreadCheckAnnotationRepository()
        worker = BookMetadataSyncWorker(
            readingPositionRepository: readingPositionRepo,
            annotationRepository: annotationRepo
        )
        
        let server = CalibreServer(
            uuid: UUID(),
            name: "TestServer",
            baseUrl: "http://localhost",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        library = CalibreLibrary(
            server: server,
            key: "TestLib",
            name: "TestLib"
        )
        book = CalibreBook(id: 123, library: library)
    }
    
    override func tearDown() {
        readingPositionRepo = nil
        annotationRepo = nil
        worker = nil
        library = nil
        book = nil
        super.tearDown()
    }
    
    func testSyncExecutedOnBackgroundThread() async {
        let entry = CalibreBookAnnotationsResult(
            last_read_positions: [
                CalibreBookLastReadPositionEntry(
                    device: "test-device",
                    cfi: "pos",
                    epoch: 1234.0,
                    pos_frac: 0.5
                )
            ],
            annotations_map: CalibreBookAnnotationsMap(
                bookmark: [
                    CalibreBookAnnotationBookmarkEntry(
                        type: "bookmark",
                        timestamp: "2026-06-28T09:00:00Z",
                        pos_type: "cfi",
                        pos: "pos",
                        title: "bookmark"
                    )
                ],
                highlight: [
                    CalibreBookAnnotationHighlightEntry(
                        type: "highlight",
                        timestamp: "2026-06-28T09:00:00Z",
                        uuid: "uuid",
                        highlightedText: "text"
                    )
                ]
            )
        )
        
        let job = BookMetadataSyncWorker.SyncJob(
            book: book,
            formatKey: "epub",
            format: .EPUB,
            entry: entry,
            needUpload: true
        )
        
        _ = await worker.executeSync(jobs: [job])
        
        XCTAssertTrue(readingPositionRepo.wasSyncCalledOnBackgroundThread)
        XCTAssertTrue(annotationRepo.wasSyncHighlightsCalledOnBackgroundThread)
        XCTAssertTrue(annotationRepo.wasSyncBookmarksCalledOnBackgroundThread)
    }
    
    func testHighlightPendingDoesNotBlockBookmarkSync() async {
        annotationRepo.syncHighlightsReturn = 1
        annotationRepo.syncBookmarksReturn = 1
        
        let entry = CalibreBookAnnotationsResult(
            last_read_positions: [],
            annotations_map: CalibreBookAnnotationsMap(
                bookmark: [
                    CalibreBookAnnotationBookmarkEntry(
                        type: "bookmark",
                        timestamp: "2026-06-28T09:00:00Z",
                        pos_type: "cfi",
                        pos: "pos",
                        title: "bookmark"
                    )
                ],
                highlight: [
                    CalibreBookAnnotationHighlightEntry(
                        type: "highlight",
                        timestamp: "2026-06-28T09:00:00Z",
                        uuid: "uuid",
                        highlightedText: "text"
                    )
                ]
            )
        )
        
        let job = BookMetadataSyncWorker.SyncJob(
            book: book,
            formatKey: "epub",
            format: .EPUB,
            entry: entry,
            needUpload: true
        )
        
        _ = await worker.executeSync(jobs: [job])
        
        XCTAssertTrue(annotationRepo.syncHighlightsCalled)
        XCTAssertTrue(annotationRepo.syncBookmarksCalled)
    }
    
    func testNoAnnotationsDoesNotOpenAnnotationRepositoryWhenUploadNotNeeded() async {
        let entry = CalibreBookAnnotationsResult(
            last_read_positions: [],
            annotations_map: CalibreBookAnnotationsMap(
                bookmark: [],
                highlight: nil
            )
        )
        
        let job = BookMetadataSyncWorker.SyncJob(
            book: book,
            formatKey: "epub",
            format: .EPUB,
            entry: entry,
            needUpload: false
        )
        
        _ = await worker.executeSync(jobs: [job])
        
        XCTAssertFalse(annotationRepo.syncHighlightsCalled)
        XCTAssertFalse(annotationRepo.syncBookmarksCalled)
        XCTAssertFalse(annotationRepo.getBookmarksCalled)
        XCTAssertFalse(annotationRepo.getHighlightsCalled)
    }

    func testEmptyRemoteAnnotationsStillDiscoverPendingLocalUploads() async {
        annotationRepo.syncHighlightsReturn = 1
        annotationRepo.syncBookmarksReturn = 1
        annotationRepo.getHighlightsReturn = [
            TestFixtures.makeHighlight(bookId: book.bookPrefId, content: "text")
        ]
        annotationRepo.getBookmarksReturn = [
            TestFixtures.makeBookmark(bookId: book.bookPrefId, pos: "epubcfi(/4/2/4)", title: "bookmark")
        ]

        let entry = CalibreBookAnnotationsResult(
            last_read_positions: [],
            annotations_map: CalibreBookAnnotationsMap(
                bookmark: [],
                highlight: []
            )
        )

        let job = BookMetadataSyncWorker.SyncJob(
            book: book,
            formatKey: "epub",
            format: .EPUB,
            entry: entry,
            needUpload: true
        )

        let outcome = await worker.executeSync(jobs: [job])

        XCTAssertTrue(annotationRepo.syncHighlightsCalled)
        XCTAssertTrue(annotationRepo.syncBookmarksCalled)
        XCTAssertEqual(outcome.annotationsToUpload.count, 1)
        XCTAssertEqual(outcome.annotationsToUpload.first?.highlights.count, 1)
        XCTAssertEqual(outcome.annotationsToUpload.first?.bookmarks.count, 1)
    }
    
    func testEmptyJobsResumesContinuation() async {
        let outcome = await worker.executeSync(jobs: [])
        XCTAssertTrue(outcome.positionsToUpload.isEmpty)
        XCTAssertTrue(outcome.annotationsToUpload.isEmpty)
    }
    
    func testPendingChangesIncludeUploadTasks() async {
        let posEntry = CalibreBookLastReadPositionEntry(
            device: "test-device",
            cfi: "pos",
            epoch: 1234.0,
            pos_frac: 0.5
        )
        
        readingPositionRepo.syncPositionsReturn = [posEntry]
        annotationRepo.syncHighlightsReturn = 1
        annotationRepo.syncBookmarksReturn = 0
        
        let bookmark = BookBookmark(
            id: "bookmark-id",
            bookId: book.bookPrefId,
            page: 2,
            pos_type: "cfi",
            pos: "cfi",
            title: "title",
            date: Date(),
            removed: false
        )
        annotationRepo.getBookmarksReturn = [bookmark]
        
        let entry = CalibreBookAnnotationsResult(
            last_read_positions: [posEntry],
            annotations_map: CalibreBookAnnotationsMap(
                bookmark: [],
                highlight: [
                    CalibreBookAnnotationHighlightEntry(
                        type: "highlight",
                        timestamp: "2026-06-28T09:00:00Z",
                        uuid: "uuid",
                        highlightedText: "text"
                    )
                ]
            )
        )
        
        let job = BookMetadataSyncWorker.SyncJob(
            book: book,
            formatKey: "epub",
            format: .EPUB,
            entry: entry,
            needUpload: true
        )
        
        let outcome = await worker.executeSync(jobs: [job])
        
        XCTAssertEqual(outcome.positionsToUpload.count, 1)
        XCTAssertEqual(outcome.positionsToUpload.first?.entries.count, 1)
        XCTAssertEqual(outcome.annotationsToUpload.count, 1)
        XCTAssertEqual(outcome.annotationsToUpload.first?.bookmarks.count, 1)
    }

    @MainActor
    func testDifferentInMemoryRealmsDoNotShareStoreIdentity() async throws {
        let positionRealm = try await Realm(configuration: Realm.Configuration(inMemoryIdentifier: "worker-pos"))
        let annotationRealm = try await Realm(configuration: Realm.Configuration(inMemoryIdentifier: "worker-ann"))

        readingPositionRepo.getRealmReturn = positionRealm
        annotationRepo.getRealmReturn = annotationRealm

        let entry = CalibreBookAnnotationsResult(
            last_read_positions: [],
            annotations_map: CalibreBookAnnotationsMap(
                bookmark: [],
                highlight: [
                    CalibreBookAnnotationHighlightEntry(
                        type: "highlight",
                        timestamp: "2026-06-28T09:00:00Z",
                        uuid: "uuid",
                        highlightedText: "text"
                    )
                ]
            )
        )

        let job = BookMetadataSyncWorker.SyncJob(
            book: book,
            formatKey: "epub",
            format: .EPUB,
            entry: entry,
            needUpload: false
        )

        _ = await worker.executeSync(jobs: [job])

        XCTAssertTrue(readingPositionRepo.syncPositionsInRealmCalled)
        XCTAssertTrue(annotationRepo.syncHighlightsInRealmCalled)
        XCTAssertTrue(annotationRepo.syncBookmarksInRealmCalled)
        XCTAssertEqual(
            readingPositionRepo.syncPositionsInRealmRealmParam?.configuration.inMemoryIdentifier,
            positionRealm.configuration.inMemoryIdentifier
        )
        XCTAssertEqual(
            annotationRepo.syncHighlightsInRealmRealmParam?.configuration.inMemoryIdentifier,
            annotationRealm.configuration.inMemoryIdentifier
        )
        XCTAssertEqual(
            annotationRepo.syncBookmarksInRealmRealmParam?.configuration.inMemoryIdentifier,
            annotationRealm.configuration.inMemoryIdentifier
        )
    }

    @MainActor
    func testInRealmSyncRunsOutsideOuterWriteTransaction() async throws {
        let sharedRealm = try await Realm(configuration: Realm.Configuration(inMemoryIdentifier: "worker-shared"))
        readingPositionRepo.getRealmReturn = sharedRealm
        annotationRepo.getRealmReturn = sharedRealm

        let entry = CalibreBookAnnotationsResult(
            last_read_positions: [
                CalibreBookLastReadPositionEntry(
                    device: "test-device",
                    cfi: "pos",
                    epoch: 1234.0,
                    pos_frac: 0.5
                )
            ],
            annotations_map: CalibreBookAnnotationsMap(
                bookmark: [
                    CalibreBookAnnotationBookmarkEntry(
                        type: "bookmark",
                        timestamp: "2026-06-28T09:00:00Z",
                        pos_type: "cfi",
                        pos: "pos",
                        title: "bookmark"
                    )
                ],
                highlight: [
                    CalibreBookAnnotationHighlightEntry(
                        type: "highlight",
                        timestamp: "2026-06-28T09:00:00Z",
                        uuid: "uuid",
                        highlightedText: "text"
                    )
                ]
            )
        )

        let job = BookMetadataSyncWorker.SyncJob(
            book: book,
            formatKey: "epub",
            format: .EPUB,
            entry: entry,
            needUpload: true
        )

        _ = await worker.executeSync(jobs: [job])

        XCTAssertEqual(readingPositionRepo.syncPositionsInRealmWasInWriteTransaction, false)
        XCTAssertEqual(annotationRepo.syncHighlightsInRealmWasInWriteTransaction, false)
        XCTAssertEqual(annotationRepo.syncBookmarksInRealmWasInWriteTransaction, false)
    }
    
    @MainActor
    func testExecuteSyncWithRealRepositoriesAndSharedRealm() async {
        let conf = Realm.Configuration(inMemoryIdentifier: "worker-tests", objectTypes: [
            BookDeviceReadingPositionRealm.self,
            BookDeviceReadingPositionHistoryRealm.self,
            BookHighlightRealm.self,
            BookBookmarkRealm.self
        ])
        let dbService = DatabaseService()
        dbService.setup(conf: conf)
        
        let positionRepository = RealmReadingPositionRepository(databaseService: dbService)
        let annotationRepository = RealmAnnotationRepository(databaseService: dbService)
        
        let localWorker = BookMetadataSyncWorker(
            readingPositionRepository: positionRepository,
            annotationRepository: annotationRepository
        )
        
        let posEntry = CalibreBookLastReadPositionEntry(
            device: "test-device",
            cfi: "epubcfi(/4/2/4);vnd_readerName=FolioReader]",
            epoch: 1234.0,
            pos_frac: 0.5
        )
        
        let entry = CalibreBookAnnotationsResult(
            last_read_positions: [posEntry],
            annotations_map: CalibreBookAnnotationsMap(
                bookmark: [
                    CalibreBookAnnotationBookmarkEntry(
                        type: "bookmark",
                        timestamp: "2026-06-28T09:00:00Z",
                        pos_type: "epubcfi",
                        pos: "epubcfi(/4/2/4)",
                        title: "bookmark"
                    )
                ],
                highlight: [
                    CalibreBookAnnotationHighlightEntry(
                        type: "highlight",
                        timestamp: "2026-06-28T09:00:00Z",
                        uuid: "AAAAAAAAAAAAAAAAAAAAAA",
                        highlightedText: "text",
                        spineIndex: 2
                    )
                ]
            )
        )
        
        let job = BookMetadataSyncWorker.SyncJob(
            book: book,
            formatKey: "epub",
            format: .EPUB,
            entry: entry,
            needUpload: false
        )
        
        _ = await localWorker.executeSync(jobs: [job])
        
        let realm = try! await Realm(configuration: conf)
        let savedPositions = realm.objects(BookDeviceReadingPositionRealm.self)
        XCTAssertEqual(savedPositions.count, 1)
        XCTAssertEqual(savedPositions.first?.deviceId, "test-device")
        
        let savedBookmarks = realm.objects(BookBookmarkRealm.self)
        XCTAssertEqual(savedBookmarks.count, 1)
        XCTAssertEqual(savedBookmarks.first?.pos, "epubcfi(/4/2/4)")
        
        let savedHighlights = realm.objects(BookHighlightRealm.self)
        XCTAssertEqual(savedHighlights.count, 1)
        XCTAssertEqual(savedHighlights.first?.content, "text")
    }
}

// MARK: - Helper Mock Subclasses

class ThreadCheckReadingPositionRepository: MockReadingPositionRepository, @unchecked Sendable {
    var wasSyncCalledOnBackgroundThread = false
    var syncPositionsInRealmWasInWriteTransaction: Bool?

    override func syncPositions(entries lastReadPositions: [CalibreBookLastReadPositionEntry], forBookId bookId: String) -> [CalibreBookLastReadPositionEntry] {
        wasSyncCalledOnBackgroundThread = !Thread.isMainThread
        return super.syncPositions(entries: lastReadPositions, forBookId: bookId)
    }

    override func syncPositions(entries lastReadPositions: [CalibreBookLastReadPositionEntry], forBookId bookId: String, in realm: Realm) -> [CalibreBookLastReadPositionEntry] {
        syncPositionsInRealmWasInWriteTransaction = realm.isInWriteTransaction
        return super.syncPositions(entries: lastReadPositions, forBookId: bookId, in: realm)
    }
}

class ThreadCheckAnnotationRepository: MockAnnotationRepository, @unchecked Sendable {
    var wasSyncHighlightsCalledOnBackgroundThread = false
    var wasSyncBookmarksCalledOnBackgroundThread = false
    var syncHighlightsInRealmWasInWriteTransaction: Bool?
    var syncBookmarksInRealmWasInWriteTransaction: Bool?
    
    override func syncHighlights(entries: [CalibreBookAnnotationHighlightEntry], forBookId bookId: String) -> Int {
        wasSyncHighlightsCalledOnBackgroundThread = !Thread.isMainThread
        return super.syncHighlights(entries: entries, forBookId: bookId)
    }
    
    override func syncBookmarks(entries: [CalibreBookAnnotationBookmarkEntry], forBookId bookId: String) -> Int {
        wasSyncBookmarksCalledOnBackgroundThread = !Thread.isMainThread
        return super.syncBookmarks(entries: entries, forBookId: bookId)
    }

    override func syncHighlights(entries: [CalibreBookAnnotationHighlightEntry], forBookId bookId: String, in realm: Realm) -> Int {
        syncHighlightsInRealmWasInWriteTransaction = realm.isInWriteTransaction
        return super.syncHighlights(entries: entries, forBookId: bookId, in: realm)
    }

    override func syncBookmarks(entries: [CalibreBookAnnotationBookmarkEntry], forBookId bookId: String, in realm: Realm) -> Int {
        syncBookmarksInRealmWasInWriteTransaction = realm.isInWriteTransaction
        return super.syncBookmarks(entries: entries, forBookId: bookId, in: realm)
    }
}
