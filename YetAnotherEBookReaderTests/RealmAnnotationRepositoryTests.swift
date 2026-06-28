//
//  RealmAnnotationRepositoryTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-24.
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
final class RealmAnnotationRepositoryTests: XCTestCase {
    private var databaseService: DatabaseService!
    private var repository: RealmAnnotationRepository!
    private var realmConfig: Realm.Configuration!
    
    override func setUpWithError() throws {
        realmConfig = MockDatabaseService.inMemoryConfiguration()
        databaseService = DatabaseService()
        databaseService.setup(conf: realmConfig)
        repository = RealmAnnotationRepository(databaseService: databaseService)
    }
    
    override func tearDownWithError() throws {
        databaseService = nil
        repository = nil
        realmConfig = nil
    }
    
    func testBookmarkCRUD() throws {
        let bookId = "1^test_lib@server-uuid"
        let pos = "epubcfi(/4/2/10/1:0)"
        let bookmark = TestFixtures.makeBookmark(bookId: bookId, pos: pos, title: "Bookmark 1")
        
        // 1. Initially empty
        XCTAssertTrue(repository.getBookmarks(forBookId: bookId, excludeRemoved: true).isEmpty)
        XCTAssertNil(repository.getBookmark(byPos: pos, bookId: bookId))
        
        // 2. Save
        let (status, oldTitle) = repository.saveBookmark(bookmark)
        XCTAssertEqual(status, 1) // Added new
        XCTAssertNil(oldTitle)
        
        // 3. Fetch
        let bookmarks = repository.getBookmarks(forBookId: bookId, excludeRemoved: true)
        XCTAssertEqual(bookmarks.count, 1)
        XCTAssertEqual(bookmarks.first?.title, "Bookmark 1")
        
        let fetched = repository.getBookmark(byPos: pos, bookId: bookId)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Bookmark 1")
        
        // 4. Remove
        repository.removeBookmark(pos: pos, bookId: bookId)
        XCTAssertTrue(repository.getBookmarks(forBookId: bookId, excludeRemoved: true).isEmpty)
        
        // Removed bookmark is still present if excludeRemoved is false
        let allBookmarks = repository.getBookmarks(forBookId: bookId, excludeRemoved: false)
        XCTAssertEqual(allBookmarks.count, 1)
        XCTAssertTrue(allBookmarks.first?.removed ?? false)
    }
    
    func testSaveBookmark_updatesExisting_inPlace() throws {
        let bookId = "2^test_lib@server-uuid"
        let pos = "epubcfi(/4/2/12/1:0)"
        let bookmark1 = TestFixtures.makeBookmark(bookId: bookId, pos: pos, title: "Initial Title")
        
        _ = repository.saveBookmark(bookmark1)
        
        // 1. Update with a different title
        let bookmark2 = TestFixtures.makeBookmark(bookId: bookId, pos: pos, title: "Updated Title")
        let (status2, oldTitle2) = repository.saveBookmark(bookmark2)
        XCTAssertEqual(status2, 2) // Updated
        XCTAssertEqual(oldTitle2, "Initial Title")
        
        let fetched2 = repository.getBookmark(byPos: pos, bookId: bookId)
        XCTAssertEqual(fetched2?.title, "Updated Title")
        
        // 2. Save again with same title
        let bookmark3 = TestFixtures.makeBookmark(bookId: bookId, pos: pos, title: "Updated Title")
        let (status3, oldTitle3) = repository.saveBookmark(bookmark3)
        XCTAssertEqual(status3, 0) // No change
        XCTAssertEqual(oldTitle3, "Updated Title")
    }
    
    func testHighlightCRUD() throws {
        let bookId = "1^test_lib@server-uuid"
        let highlightId = UUID().uuidString
        let highlight = TestFixtures.makeHighlight(id: highlightId, bookId: bookId, content: "Highlight Text")
        
        // 1. Initially empty
        XCTAssertTrue(repository.getHighlights(forBookId: bookId, excludeRemoved: true).isEmpty)
        XCTAssertNil(repository.getHighlight(byId: highlightId))
        
        // 2. Save
        repository.saveHighlight(highlight)
        
        // 3. Fetch
        let highlights = repository.getHighlights(forBookId: bookId, excludeRemoved: true)
        XCTAssertEqual(highlights.count, 1)
        XCTAssertEqual(highlights.first?.content, "Highlight Text")
        
        let fetched = repository.getHighlight(byId: highlightId)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.content, "Highlight Text")
        
        // 4. Delete
        repository.removeHighlight(id: highlightId)
        XCTAssertTrue(repository.getHighlights(forBookId: bookId, excludeRemoved: true).isEmpty)
        
        let allHighlights = repository.getHighlights(forBookId: bookId, excludeRemoved: false)
        XCTAssertEqual(allHighlights.count, 1)
        XCTAssertTrue(allHighlights.first?.removed ?? false)
    }
    
    func testUpdateHighlightNote() throws {
        let bookId = "1^test_lib@server-uuid"
        let highlightId = UUID().uuidString
        let highlight = TestFixtures.makeHighlight(id: highlightId, bookId: bookId, note: "Initial Note")
        
        repository.saveHighlight(highlight)
        
        let initialFetched = repository.getHighlight(byId: highlightId)
        XCTAssertEqual(initialFetched?.note, "Initial Note")
        
        // Update Note
        repository.updateHighlightNote(id: highlightId, note: "Updated Note")
        
        let updatedFetched = repository.getHighlight(byId: highlightId)
        XCTAssertEqual(updatedFetched?.note, "Updated Note")
        XCTAssertGreaterThan(updatedFetched?.date ?? Date.distantPast, initialFetched?.date ?? Date.distantFuture)
    }
    
    func testSyncBookmarks() throws {
        let bookId = "sync^test_lib@server-uuid"
        let pos1 = "epubcfi(/4/2/2/1:0)"
        let pos2 = "epubcfi(/6/2/4/1:0)"
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
        
        let dateLocal = Date().addingTimeInterval(-3600) // 1 hour ago
        let dateServerNewer = Date() // Now
        let dateServerOlder = Date().addingTimeInterval(-7200) // 2 hours ago
        
        // Local bookmark
        let localBookmark = TestFixtures.makeBookmark(bookId: bookId, page: 2, pos: pos1, title: "Local Title", date: dateLocal)
        _ = repository.saveBookmark(localBookmark)
        
        let entries = [
            // 1. Newer bookmark from server -> should replace local
            CalibreBookAnnotationBookmarkEntry(
                type: "bookmark",
                timestamp: dateFormatter.string(from: dateServerNewer),
                pos_type: "epubcfi",
                pos: pos1,
                title: "New Server Title",
                removed: false
            ),
            // 2. Newer bookmark for new pos -> should add
            CalibreBookAnnotationBookmarkEntry(
                type: "bookmark",
                timestamp: dateFormatter.string(from: dateServerNewer),
                pos_type: "epubcfi",
                pos: pos2,
                title: "New Bookmark Pos",
                removed: false
            ),
            // 3. Older bookmark from server -> should be ignored
            CalibreBookAnnotationBookmarkEntry(
                type: "bookmark",
                timestamp: dateFormatter.string(from: dateServerOlder),
                pos_type: "epubcfi",
                pos: pos1,
                title: "Older Server Title",
                removed: false
            )
        ]
        
        // Call sync
        let pendingCount = repository.syncBookmarks(entries: entries, forBookId: bookId)
        
        let bookmarks = repository.getBookmarks(forBookId: bookId, excludeRemoved: true)
        XCTAssertEqual(bookmarks.count, 2)
        
        let bookmark1 = bookmarks.first(where: { $0.pos == pos1 })
        XCTAssertEqual(bookmark1?.title, "New Server Title")
        XCTAssertEqual(bookmark1?.page, 2)
        
        let bookmark2 = bookmarks.first(where: { $0.pos == pos2 })
        XCTAssertEqual(bookmark2?.title, "New Bookmark Pos")
        XCTAssertEqual(bookmark2?.page, 3)
        
        XCTAssertEqual(pendingCount, 0)
    }
    
    func testSyncHighlights() throws {
        let bookId = "sync_hl^test_lib@server-uuid"
        
        let calibreId1 = "AAAAAAAAAAAAAAAAAAAAAA"
        let folioId1 = try XCTUnwrap(uuidCalibreToFolio(calibreId1))
        
        let calibreId2 = "BBBBBBBBBBBBBBBBBBBBBB"
        let folioId2 = try XCTUnwrap(uuidCalibreToFolio(calibreId2))
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
        
        let dateLocal = Date().addingTimeInterval(-3600) // 1 hour ago
        let dateServerNewer = Date() // Now
        
        // 1. Existing local highlight
        let localHighlight = TestFixtures.makeHighlight(id: folioId1, bookId: bookId, date: dateLocal, note: "Local Note")
        repository.saveHighlight(localHighlight)
        
        let entries = [
            // Server updates localHighlight (folioId1) with newer timestamp
            CalibreBookAnnotationHighlightEntry(
                type: "highlight",
                timestamp: dateFormatter.string(from: dateServerNewer),
                uuid: calibreId1,
                removed: false,
                ranges: nil,
                startCfi: "/6/4",
                endCfi: "/6/6",
                highlightedText: "Updated Text from Server",
                style: ["which": "green"],
                spineName: "chap-1",
                spineIndex: 2,
                tocFamilyTitles: ["TOC Title"],
                notes: "Updated Server Note"
            ),
            // Server adds new highlight
            CalibreBookAnnotationHighlightEntry(
                type: "highlight",
                timestamp: dateFormatter.string(from: dateServerNewer),
                uuid: calibreId2,
                removed: false,
                ranges: nil,
                startCfi: "/6/8",
                endCfi: "/6/10",
                highlightedText: "New Highlight Text",
                style: nil, // defaults to yellow
                spineName: "chap-2",
                spineIndex: 5,
                tocFamilyTitles: nil,
                notes: "New Note"
            )
        ]
        
        let pendingCount = repository.syncHighlights(entries: entries, forBookId: bookId)
        
        let highlights = repository.getHighlights(forBookId: bookId, excludeRemoved: true)
        XCTAssertEqual(highlights.count, 2)
        
        let hl1 = repository.getHighlight(byId: folioId1)
        XCTAssertEqual(hl1?.content, "Highlight content")
        XCTAssertEqual(hl1?.note, "Updated Server Note")
        XCTAssertEqual(hl1?.type, BookHighlightStyle.green.rawValue)
        
        let hl2 = repository.getHighlight(byId: folioId2)
        XCTAssertEqual(hl2?.content, "New Highlight Text")
        XCTAssertEqual(hl2?.note, "New Note")
        XCTAssertEqual(hl2?.page, 6) // spineIndex 5 + 1
        XCTAssertEqual(hl2?.type, BookHighlightStyle.yellow.rawValue)
        
        XCTAssertEqual(pendingCount, 0)
    }
    
    func testSyncHighlights_duplicateAndInvalidEntriesBehavior() throws {
        let bookId = "sync_hl_duplicates^test_lib@server-uuid"
        
        let calibreId1 = "CCCCCCCCCCCCCCCCCCCCCC"
        let folioId1 = try XCTUnwrap(uuidCalibreToFolio(calibreId1))
        
        let calibreId2 = "DDDDDDDDDDDDDDDDDDDDDD"
        let folioId2 = try XCTUnwrap(uuidCalibreToFolio(calibreId2))
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
        
        let baseDate = Date()
        let dateOlder = baseDate.addingTimeInterval(-60)
        let dateNewer = baseDate
        
        let entries = [
            // 1. Older duplicate for ID1 (valid)
            CalibreBookAnnotationHighlightEntry(
                type: "highlight",
                timestamp: dateFormatter.string(from: dateOlder),
                uuid: calibreId1,
                removed: false,
                ranges: nil,
                startCfi: "/6/4",
                endCfi: "/6/6",
                highlightedText: "Older valid highlight text",
                style: nil,
                spineName: "chap-1",
                spineIndex: 2,
                tocFamilyTitles: nil,
                notes: "Older valid note"
            ),
            // 2. Newer duplicate for ID1 (valid) -> should win over the older duplicate
            CalibreBookAnnotationHighlightEntry(
                type: "highlight",
                timestamp: dateFormatter.string(from: dateNewer),
                uuid: calibreId1,
                removed: false,
                ranges: nil,
                startCfi: "/6/4",
                endCfi: "/6/6",
                highlightedText: "Newer valid highlight text",
                style: nil,
                spineName: "chap-1",
                spineIndex: 2,
                tocFamilyTitles: nil,
                notes: "Newer valid note"
            ),
            // 3. Valid older duplicate for ID2
            CalibreBookAnnotationHighlightEntry(
                type: "highlight",
                timestamp: dateFormatter.string(from: dateOlder),
                uuid: calibreId2,
                removed: false,
                ranges: nil,
                startCfi: "/6/8",
                endCfi: "/6/10",
                highlightedText: "Older valid ID2 text",
                style: nil,
                spineName: "chap-1",
                spineIndex: 3,
                tocFamilyTitles: nil,
                notes: "Older valid ID2 note"
            ),
            // 4. Newer duplicate for ID2 with missing spineIndex (invalid normal entry)
            // -> This newer duplicate should be excluded before deduplication,
            // so the older valid duplicate for ID2 is kept and wins.
            CalibreBookAnnotationHighlightEntry(
                type: "highlight",
                timestamp: dateFormatter.string(from: dateNewer),
                uuid: calibreId2,
                removed: false,
                ranges: nil,
                startCfi: "/6/8",
                endCfi: "/6/10",
                highlightedText: "Newer invalid ID2 text",
                style: nil,
                spineName: "chap-1",
                spineIndex: nil,
                tocFamilyTitles: nil,
                notes: "Newer invalid ID2 note"
            )
        ]
        
        let pendingCount = repository.syncHighlights(entries: entries, forBookId: bookId)
        
        let highlights = repository.getHighlights(forBookId: bookId, excludeRemoved: true)
        XCTAssertEqual(highlights.count, 2)
        
        // ID1 check: newest valid wins ("Newer valid highlight text")
        let hl1 = repository.getHighlight(byId: folioId1)
        XCTAssertNotNil(hl1)
        XCTAssertEqual(hl1?.note, "Newer valid note")
        XCTAssertEqual(hl1?.content, "Newer valid highlight text")
        
        // ID2 check: newer invalid is filtered, so older valid wins ("Older valid ID2 text")
        let hl2 = repository.getHighlight(byId: folioId2)
        XCTAssertNotNil(hl2)
        XCTAssertEqual(hl2?.note, "Older valid ID2 note")
        XCTAssertEqual(hl2?.content, "Older valid ID2 text")
        
        XCTAssertEqual(pendingCount, 0)
    }
}
