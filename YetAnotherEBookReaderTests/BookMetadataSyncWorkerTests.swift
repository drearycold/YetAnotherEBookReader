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
        library = CalibreLibrary(server: server, key: "TestLib", name: "TestLib")
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

        _ = await worker.executeSync(jobs: [
            BookMetadataSyncWorker.SyncJob(
                book: book,
                format: .EPUB,
                entry: entry,
                needUpload: true
            )
        ])

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

        _ = await worker.executeSync(jobs: [
            BookMetadataSyncWorker.SyncJob(
                book: book,
                format: .EPUB,
                entry: entry,
                needUpload: true
            )
        ])

        XCTAssertTrue(annotationRepo.syncHighlightsCalled)
        XCTAssertTrue(annotationRepo.syncBookmarksCalled)
    }

    func testNoAnnotationsSkipsAnnotationRepositoryWhenUploadNotNeeded() async {
        let entry = CalibreBookAnnotationsResult(
            last_read_positions: [],
            annotations_map: CalibreBookAnnotationsMap(
                bookmark: [],
                highlight: nil
            )
        )

        _ = await worker.executeSync(jobs: [
            BookMetadataSyncWorker.SyncJob(
                book: book,
                format: .EPUB,
                entry: entry,
                needUpload: false
            )
        ])

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

        let outcome = await worker.executeSync(jobs: [
            BookMetadataSyncWorker.SyncJob(
                book: book,
                format: .EPUB,
                entry: entry,
                needUpload: true
            )
        ])

        XCTAssertTrue(annotationRepo.syncHighlightsCalled)
        XCTAssertTrue(annotationRepo.syncBookmarksCalled)
        XCTAssertEqual(outcome.annotationsToUpload.count, 1)
        XCTAssertEqual(outcome.annotationsToUpload.first?.highlights.count, 1)
        XCTAssertEqual(outcome.annotationsToUpload.first?.bookmarks.count, 1)
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
        annotationRepo.getBookmarksReturn = [
            BookBookmark(
                id: "bookmark-id",
                bookId: book.bookPrefId,
                page: 2,
                pos_type: "cfi",
                pos: "cfi",
                title: "title",
                date: Date(),
                removed: false
            )
        ]

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

        let outcome = await worker.executeSync(jobs: [
            BookMetadataSyncWorker.SyncJob(
                book: book,
                format: .EPUB,
                entry: entry,
                needUpload: true
            )
        ])

        XCTAssertEqual(outcome.positionsToUpload.count, 1)
        XCTAssertEqual(outcome.positionsToUpload.first?.entries.count, 1)
        XCTAssertEqual(outcome.annotationsToUpload.count, 1)
        XCTAssertEqual(outcome.annotationsToUpload.first?.bookmarks.count, 1)
    }

    func testEmptyJobsResumesContinuation() async {
        let outcome = await worker.executeSync(jobs: [])
        XCTAssertTrue(outcome.positionsToUpload.isEmpty)
        XCTAssertTrue(outcome.annotationsToUpload.isEmpty)
    }

    @MainActor
    func testRealRepositoriesPersistPositionHighlightAndBookmark() async {
        let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString, objectTypes: [
            BookDeviceReadingPositionRealm.self,
            BookDeviceReadingPositionHistoryRealm.self,
            BookHighlightRealm.self,
            BookBookmarkRealm.self
        ])
        let databaseService = DatabaseService()
        databaseService.setup(conf: config)

        let positionRepository = RealmReadingPositionRepository(databaseService: databaseService)
        let annotationRepository = RealmAnnotationRepository(databaseService: databaseService)
        let realWorker = BookMetadataSyncWorker(
            readingPositionRepository: positionRepository,
            annotationRepository: annotationRepository
        )

        let remotePosition = TestFixtures.makeReadingPosition(
            id: "test-device",
            readerName: ReaderType.YabrEPUB.rawValue,
            lastReadPage: 7,
            epoch: 1234.0
        )

        let entry = CalibreBookAnnotationsResult(
            last_read_positions: [
                remotePosition.toEntry()
            ],
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
                        removed: false,
                        startCfi: "/6/4",
                        endCfi: "/6/6",
                        highlightedText: "text",
                        style: ["which": "yellow"],
                        spineName: "chap-1",
                        spineIndex: 2,
                        tocFamilyTitles: ["Chapter 1"],
                        notes: nil
                    )
                ]
            )
        )

        let outcome = await realWorker.executeSync(jobs: [
            BookMetadataSyncWorker.SyncJob(
                book: book,
                format: .EPUB,
                entry: entry,
                needUpload: false
            )
        ])

        XCTAssertTrue(outcome.positionsToUpload.isEmpty)
        XCTAssertTrue(outcome.annotationsToUpload.isEmpty)
        XCTAssertEqual(positionRepository.getPositions(forBookId: book.bookPrefId).count, 1)
        XCTAssertEqual(annotationRepository.getBookmarks(forBookId: book.bookPrefId, excludeRemoved: true).count, 1)
        XCTAssertEqual(annotationRepository.getHighlights(forBookId: book.bookPrefId, excludeRemoved: true).count, 1)
    }
}

// MARK: - Helper Mock Subclasses

final class ThreadCheckReadingPositionRepository: MockReadingPositionRepository, @unchecked Sendable {
    var wasSyncCalledOnBackgroundThread = false

    override func syncPositions(entries lastReadPositions: [CalibreBookLastReadPositionEntry], forBookId bookId: String) -> [CalibreBookLastReadPositionEntry] {
        wasSyncCalledOnBackgroundThread = !Thread.isMainThread
        return super.syncPositions(entries: lastReadPositions, forBookId: bookId)
    }
}

final class ThreadCheckAnnotationRepository: MockAnnotationRepository, @unchecked Sendable {
    var wasSyncHighlightsCalledOnBackgroundThread = false
    var wasSyncBookmarksCalledOnBackgroundThread = false

    override func syncHighlights(entries: [CalibreBookAnnotationHighlightEntry], forBookId bookId: String) -> Int {
        wasSyncHighlightsCalledOnBackgroundThread = !Thread.isMainThread
        return super.syncHighlights(entries: entries, forBookId: bookId)
    }

    override func syncBookmarks(entries: [CalibreBookAnnotationBookmarkEntry], forBookId bookId: String) -> Int {
        wasSyncBookmarksCalledOnBackgroundThread = !Thread.isMainThread
        return super.syncBookmarks(entries: entries, forBookId: bookId)
    }
}
