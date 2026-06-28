//
//  BookMetadataSyncWorkerTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-28.
//

import XCTest
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
    
    func testNoAnnotationsDoesNotOpenAnnotationRepository() async {
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
            needUpload: true
        )
        
        _ = await worker.executeSync(jobs: [job])
        
        XCTAssertFalse(annotationRepo.syncHighlightsCalled)
        XCTAssertFalse(annotationRepo.syncBookmarksCalled)
        XCTAssertFalse(annotationRepo.getBookmarksCalled)
        XCTAssertFalse(annotationRepo.getHighlightsCalled)
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
}

// MARK: - Helper Mock Subclasses

class ThreadCheckReadingPositionRepository: MockReadingPositionRepository {
    var wasSyncCalledOnBackgroundThread = false
    override func syncPositions(entries lastReadPositions: [CalibreBookLastReadPositionEntry], forBookId bookId: String) -> [CalibreBookLastReadPositionEntry] {
        wasSyncCalledOnBackgroundThread = !Thread.isMainThread
        return super.syncPositions(entries: lastReadPositions, forBookId: bookId)
    }
}

class ThreadCheckAnnotationRepository: MockAnnotationRepository {
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
