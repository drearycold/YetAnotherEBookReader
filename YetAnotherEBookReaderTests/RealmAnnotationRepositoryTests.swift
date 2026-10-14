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
    
    /// YabrPDF highlights saved under the shelf identity move to the annotation
    /// id; other readers' highlights and the ones already in place stay.
    func testRefileHighlightsMovesMisfiledYabrPDFHighlights() throws {
        let shelfId = "server^lib@1"
        let prefId = "lib-key - 1"
        let misfiled = TestFixtures.makeHighlight(bookId: shelfId, readerName: ReaderType.YabrPDF.rawValue, note: "kept")
        let removed = TestFixtures.makeHighlight(bookId: shelfId, readerName: ReaderType.YabrPDF.rawValue, removed: true)
        let otherReader = TestFixtures.makeHighlight(bookId: shelfId, readerName: ReaderType.YabrEPUB.rawValue)
        let inPlace = TestFixtures.makeHighlight(bookId: prefId, readerName: ReaderType.YabrPDF.rawValue)
        [misfiled, removed, otherReader, inPlace].forEach(repository.saveHighlight)

        XCTAssertEqual(repository.refileHighlights(fromBookId: shelfId, toBookId: prefId, readerName: ReaderType.YabrPDF.rawValue), 2)

        let visible = repository.getHighlights(forBookId: prefId, excludeRemoved: true)
        XCTAssertEqual(Set(visible.map(\.id)), [misfiled.id, inPlace.id])
        XCTAssertEqual(visible.first { $0.id == misfiled.id }?.note, "kept")
        XCTAssertEqual(repository.getHighlights(forBookId: prefId, excludeRemoved: false).count, 3, "a removed one moves too, still removed")
        XCTAssertEqual(repository.getHighlights(forBookId: shelfId, excludeRemoved: false).map(\.id), [otherReader.id])
        XCTAssertEqual(repository.refileHighlights(fromBookId: shelfId, toBookId: prefId, readerName: ReaderType.YabrPDF.rawValue), 0, "idempotent")
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
    
    /// To calibre a new title is a new bookmark, so retitling one removes the old title (which
    /// the next sync uploads) and adds the new one at the same position.
    func testSaveBookmarkRetitlesByRemovingTheOldTitle() throws {
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
        let all = repository.getBookmarks(forBookId: bookId, excludeRemoved: false)
        XCTAssertEqual(all.filter(\.removed).map(\.title), ["Initial Title"])
        XCTAssertEqual(all.filter { !$0.removed }.map(\.title), ["Updated Title"])
        
        // 2. Save again with same title
        let bookmark3 = TestFixtures.makeBookmark(bookId: bookId, pos: pos, title: "Updated Title")
        let (status3, oldTitle3) = repository.saveBookmark(bookmark3)
        XCTAssertEqual(status3, 0) // No change
        XCTAssertEqual(oldTitle3, "Updated Title")
    }

    /// calibre keeps one bookmark per title, so a title the book already has gets a number, as
    /// calibre's viewer numbers its default titles. A removed bookmark's title is free again.
    func testSaveBookmarkNumbersATitleTheBookAlreadyHas() {
        let bookId = "titles^test_lib@server-uuid"
        let title = "Chapter 3, p. 42"
        for pos in ["epubcfi(/6/2)", "epubcfi(/6/4)", "epubcfi(/6/6)"] {
            XCTAssertEqual(repository.saveBookmark(TestFixtures.makeBookmark(bookId: bookId, pos: pos, title: title)).0, 1)
        }
        XCTAssertEqual(
            Set(repository.getBookmarks(forBookId: bookId, excludeRemoved: true).map(\.title)),
            [title, "\(title) #2", "\(title) #3"]
        )

        // Saving one again at its position keeps its number.
        XCTAssertEqual(repository.saveBookmark(TestFixtures.makeBookmark(bookId: bookId, pos: "epubcfi(/6/6)", title: title)).0, 0)
        XCTAssertEqual(repository.getBookmark(byPos: "epubcfi(/6/6)", bookId: bookId)?.title, "\(title) #3")

        repository.removeBookmark(pos: "epubcfi(/6/2)", bookId: bookId)
        XCTAssertEqual(repository.saveBookmark(TestFixtures.makeBookmark(bookId: bookId, pos: "epubcfi(/6/8)", title: title)).0, 1)
        XCTAssertEqual(repository.getBookmark(byPos: "epubcfi(/6/8)", bookId: bookId)?.title, title)
    }

    func testUniqueTitleNumbersLikeCalibresViewer() {
        XCTAssertEqual(BookmarkMerge.uniqueTitle("Chapter 1", avoiding: []), "Chapter 1")
        XCTAssertEqual(BookmarkMerge.uniqueTitle("Chapter 1", avoiding: ["Chapter 1"]), "Chapter 1 #2")
        XCTAssertEqual(BookmarkMerge.uniqueTitle("Chapter 1", avoiding: ["Chapter 1", "Chapter 1 #2"]), "Chapter 1 #3")
        XCTAssertEqual(BookmarkMerge.uniqueTitle("Chapter 1", avoiding: ["Chapter 1 #2"]), "Chapter 1")
    }

    func testBookmarkPageComesFromItsPosition() throws {
        XCTAssertEqual(BookBookmark.page(posType: "epubcfi", pos: "epubcfi(/6/4[chap-1]!/4/2/10/1:0)"), 3)
        XCTAssertEqual(BookBookmark.page(posType: "epubcfi", pos: "epubcfi(/4)"), 2)
        XCTAssertNil(BookBookmark.page(posType: "epubcfi", pos: "invalid_cfi"))
        XCTAssertNil(BookBookmark.page(posType: "epubcfi", pos: "epubcfi(/x/2)"))

        let location = try String(decoding: JSONEncoder().encode(PDFBookmark.Location(page: 42, offset: CGPoint(x: 10, y: 700.5))), as: UTF8.self)
        XCTAssertEqual(BookBookmark.page(posType: BookBookmarkRealm.PDFBookmarkPosType, pos: location), 42)
        XCTAssertNil(BookBookmark.page(posType: BookBookmarkRealm.PDFBookmarkPosType, pos: "{}"))
        XCTAssertNil(BookBookmark.page(posType: "unknown", pos: "epubcfi(/4)"))
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
    
    /// calibre's bookmarks are told apart by title: each is one here, whatever its position,
    /// and the local one calibre hasn't got is uploaded.
    func testSyncBookmarks() throws {
        let bookId = "sync^test_lib@server-uuid"
        let pos1 = "epubcfi(/4/2/2/1:0)"
        let pos2 = "epubcfi(/6/2/4/1:0)"
        
        let dateLocal = Date().addingTimeInterval(-3600) // 1 hour ago
        let dateServerNewer = Date() // Now
        let dateServerOlder = Date().addingTimeInterval(-7200) // 2 hours ago
        
        // Local bookmark
        let localBookmark = TestFixtures.makeBookmark(bookId: bookId, page: 2, pos: pos1, title: "Local Title", date: dateLocal)
        _ = repository.saveBookmark(localBookmark)
        
        let entries = [
            bookmarkEntry("New Server Title", at: pos1, dateServerNewer),
            bookmarkEntry("New Bookmark Pos", at: pos2, dateServerNewer),
            bookmarkEntry("Older Server Title", at: pos1, dateServerOlder)
        ]
        
        let upload = repository.syncBookmarks(entries: entries, forBookId: bookId, posType: "epubcfi")
        
        let bookmarks = repository.getBookmarks(forBookId: bookId, excludeRemoved: true)
        XCTAssertEqual(Set(bookmarks.map(\.title)), ["Local Title", "New Server Title", "New Bookmark Pos", "Older Server Title"])
        XCTAssertEqual(bookmarks.first { $0.title == "New Server Title" }?.page, 2)
        XCTAssertEqual(bookmarks.first { $0.title == "New Bookmark Pos" }?.page, 3)
        XCTAssertEqual(upload.map(\.title), ["Local Title"])
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

    func testSyncAnnotations_acceptsNonFractionalISO8601Timestamps() throws {
        let bookId = "sync_non_fractional^test_lib@server-uuid"

        let bookmarkEntry = CalibreBookAnnotationBookmarkEntry(
            type: "bookmark",
            timestamp: "2026-06-28T09:00:00Z",
            pos_type: "epubcfi",
            pos: "epubcfi(/4/2/4)",
            title: "bookmark",
            removed: false
        )

        let highlightEntry = CalibreBookAnnotationHighlightEntry(
            type: "highlight",
            timestamp: "2026-06-28T09:00:00Z",
            uuid: "AAAAAAAAAAAAAAAAAAAAAA",
            removed: false,
            ranges: nil,
            startCfi: "/6/4",
            endCfi: "/6/6",
            highlightedText: "text",
            style: nil,
            spineName: "chap-1",
            spineIndex: 2,
            tocFamilyTitles: nil,
            notes: nil
        )

        let bookmarkUpload = repository.syncBookmarks(entries: [bookmarkEntry], forBookId: bookId, posType: "epubcfi")
        let highlightPending = repository.syncHighlights(entries: [highlightEntry], forBookId: bookId)

        let bookmarks = repository.getBookmarks(forBookId: bookId, excludeRemoved: true)
        let highlights = repository.getHighlights(forBookId: bookId, excludeRemoved: true)

        XCTAssertTrue(bookmarkUpload.isEmpty)
        XCTAssertEqual(highlightPending, 0)
        XCTAssertEqual(bookmarks.count, 1)
        XCTAssertEqual(bookmarks.first?.pos, "epubcfi(/4/2/4)")
        XCTAssertEqual(highlights.count, 1)
        XCTAssertEqual(highlights.first?.content, "text")
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
    
    @MainActor
    func testSyncHighlightsStressCheck() throws {
        let bookId = "stress_hl^test_lib@server-uuid"
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
        
        var entries = [CalibreBookAnnotationHighlightEntry]()
        let baseDate = Date()
        for i in 1...500 {
            let uuid = UUID()
            var uuidBytes = uuid.uuid
            let data = Data(bytes: &uuidBytes, count: 16)
            let calibreId = data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            
            entries.append(CalibreBookAnnotationHighlightEntry(
                type: "highlight",
                timestamp: dateFormatter.string(from: baseDate.addingTimeInterval(Double(i))),
                uuid: calibreId,
                removed: false,
                ranges: nil,
                startCfi: "/6/4",
                endCfi: "/6/6",
                highlightedText: "Text \(i)",
                style: nil,
                spineName: "chap-1",
                spineIndex: 2,
                tocFamilyTitles: nil,
                notes: "Note \(i)"
            ))
        }
        
        let pending = repository.syncHighlights(entries: entries, forBookId: bookId)
        XCTAssertEqual(pending, 0)
        
        let highlights = repository.getHighlights(forBookId: bookId, excludeRemoved: true)
        XCTAssertEqual(highlights.count, 500)
    }
    
    @MainActor
    func testSyncBookmarksLinearizationSpecialCases() throws {
        let bookId = "sync_bm_special^test_lib@server-uuid"
        let pos1 = "epubcfi(/4/2/2/1:0)"
        let pos2 = "epubcfi(/6/2/4/1:0)"
        
        let dateLocal = Date().addingTimeInterval(-3600)
        let dateServerNewer = Date()
        let dateServerOlder = Date().addingTimeInterval(-7200)
        
        // 1. Save local bookmark
        let localBookmark = TestFixtures.makeBookmark(bookId: bookId, page: 2, pos: pos1, title: "Local", date: dateLocal)
        _ = repository.saveBookmark(localBookmark)
        
        // 2. Sync entries:
        // - remoteNewer: the same bookmark, newer on the server -> taken
        // - remoteOlder: an older copy of it -> only the newest of a title counts
        // - remoteInvalidCFI: invalid CFI -> no reader can open it, not added
        // - remoteNewPos: another bookmark -> added
        let remoteNewer = bookmarkEntry("Local", at: pos1, dateServerNewer)
        let remoteOlder = bookmarkEntry("Local", at: pos1, dateServerOlder)
        let remoteInvalidCFI = bookmarkEntry("Invalid CFI Title", at: "invalid_cfi", dateServerNewer)
        let remoteNewPos = bookmarkEntry("New Pos Title", at: pos2, dateServerNewer)
        
        let entries = [remoteNewer, remoteOlder, remoteInvalidCFI, remoteNewPos]
        let upload = repository.syncBookmarks(entries: entries, forBookId: bookId, posType: "epubcfi")
        
        let bookmarks = repository.getBookmarks(forBookId: bookId, excludeRemoved: true)
        XCTAssertEqual(bookmarks.count, 2)
        
        let bm1 = try XCTUnwrap(bookmarks.first(where: { $0.pos == pos1 }))
        XCTAssertEqual(bm1.title, "Local")
        XCTAssertEqual(bm1.date.timeIntervalSince(dateServerNewer), 0, accuracy: 0.001)
        
        let bm2 = bookmarks.first(where: { $0.pos == pos2 })
        XCTAssertEqual(bm2?.title, "New Pos Title")
        
        XCTAssertTrue(upload.isEmpty)

        // A newer local copy is what the server gets.
        _ = repository.saveBookmark(TestFixtures.makeBookmark(bookId: bookId, page: 3, pos: "epubcfi(/6/8)", title: "Mine", date: dateServerNewer))
        let olderOnServer = bookmarkEntry("Mine", at: "epubcfi(/6/8)", dateServerOlder)
        XCTAssertEqual(repository.syncBookmarks(entries: entries + [olderOnServer], forBookId: bookId, posType: "epubcfi").map(\.title), ["Mine"])
    }
    
    @MainActor
    func testSyncBookmarksStressCheck() throws {
        let bookId = "stress_bm^test_lib@server-uuid"
        
        var entries = [CalibreBookAnnotationBookmarkEntry]()
        let baseDate = Date()
        for i in 1...500 {
            entries.append(bookmarkEntry("Bookmark \(i)", at: "epubcfi(/\(i * 2)/2/2/1:0)", baseDate.addingTimeInterval(Double(i))))
        }
        
        let upload = repository.syncBookmarks(entries: entries, forBookId: bookId, posType: "epubcfi")
        XCTAssertTrue(upload.isEmpty)
        
        let bookmarks = repository.getBookmarks(forBookId: bookId, excludeRemoved: true)
        XCTAssertEqual(bookmarks.count, 500)
    }

    // MARK: - Bookmarks on two devices
    //
    // Each device syncs with one calibre server: it merges the server's bookmarks and uploads what
    // the merge returns, which the server merges the way calibre does.

    /// A PDF reader titles bookmarks by chapter and page; two on one page get numbers, and both
    /// reach another device. The device that made them doesn't upload them again.
    func testTwoPDFBookmarksOnOnePageReachAnotherDevice() throws {
        let deviceA = makeDevice(), deviceB = makeDevice()
        var server = [CalibreBookAnnotationBookmarkEntry]()
        let posType = BookBookmarkRealm.PDFBookmarkPosType
        let title = PDFBookmark.title(outlineLabel: "Chapter 3", pageNumber: 42)
        for y in [100.0, 600.0] {
            let pdfBookmark = PDFBookmark(pos: .init(page: 42, offset: CGPoint(x: 0, y: y)), title: title, date: Date())
            _ = deviceA.repository.saveBookmark(try XCTUnwrap(BookBookmark(bookId: deviceA.bookId, pdfBookmark: pdfBookmark)))
        }

        XCTAssertEqual(deviceA.sync(&server, posType: posType).map(\.title), ["Chapter 3, p. 42", "Chapter 3, p. 42 #2"])
        XCTAssertTrue(deviceB.sync(&server, posType: posType).isEmpty)

        let received = deviceB.visible.compactMap { $0.toPDFBookmark() }.sorted { $0.pos < $1.pos }
        XCTAssertEqual(received.map(\.title), ["Chapter 3, p. 42", "Chapter 3, p. 42 #2"])
        XCTAssertEqual(received.map(\.pos.page), [42, 42])
        XCTAssertTrue(deviceA.sync(&server, posType: posType).isEmpty, "nothing left to upload")
    }

    /// Before titles were unique, two bookmarks could share one, and calibre kept the newer. The
    /// one the server has keeps the title; the other gets a number and is uploaded once.
    func testDuplicateTitlesFromBeforeGetNumbers() throws {
        let deviceA = makeDevice(), deviceB = makeDevice()
        let now = Date()
        let older = TestFixtures.makeBookmark(bookId: deviceA.bookId, page: 3, pos: "epubcfi(/6/2)", title: "Chapter 3", date: now.addingTimeInterval(-120))
        let newer = TestFixtures.makeBookmark(bookId: deviceA.bookId, page: 3, pos: "epubcfi(/6/8)", title: "Chapter 3", date: now.addingTimeInterval(-60))
        try deviceA.store([older, newer])
        var server = [bookmarkEntry("Chapter 3", at: "epubcfi(/6/8)", newer.date)]

        let upload = deviceA.sync(&server)
        XCTAssertEqual(upload.map(\.title), ["Chapter 3 #2"])
        XCTAssertEqual(upload.map(\.pos), ["epubcfi(/6/2)"])
        XCTAssertEqual(deviceA.titlesByPos, ["epubcfi(/6/2)": "Chapter 3 #2", "epubcfi(/6/8)": "Chapter 3"])

        XCTAssertTrue(deviceB.sync(&server).isEmpty)
        XCTAssertEqual(deviceB.titlesByPos, deviceA.titlesByPos)
        XCTAssertTrue(deviceA.sync(&server).isEmpty)

        // Without a copy on the server, the newer keeps the title.
        let deviceC = makeDevice()
        try deviceC.store([older, newer].map { var copy = $0; copy.id = UUID().uuidString; copy.bookId = deviceC.bookId; return copy })
        var emptyServer = [CalibreBookAnnotationBookmarkEntry]()
        XCTAssertEqual(deviceC.sync(&emptyServer).map(\.title), ["Chapter 3", "Chapter 3 #2"])
        XCTAssertEqual(deviceC.titlesByPos, ["epubcfi(/6/2)": "Chapter 3 #2", "epubcfi(/6/8)": "Chapter 3"])
    }

    /// A removal is uploaded, reaches the other device, and a device's stale copy doesn't bring
    /// the bookmark back.
    func testARemovedBookmarkIsNotResurrected() throws {
        let deviceA = makeDevice(), deviceB = makeDevice(), stale = makeDevice()
        let made = Date().addingTimeInterval(-60)
        var server = [CalibreBookAnnotationBookmarkEntry]()
        _ = deviceA.repository.saveBookmark(TestFixtures.makeBookmark(bookId: deviceA.bookId, page: 3, pos: "epubcfi(/6/2)", title: "Chapter 3", date: made))
        _ = deviceA.sync(&server)
        _ = deviceB.sync(&server)
        try stale.store([TestFixtures.makeBookmark(bookId: stale.bookId, page: 3, pos: "epubcfi(/6/2)", title: "Chapter 3", date: made)])

        deviceA.repository.removeBookmark(pos: "epubcfi(/6/2)", bookId: deviceA.bookId)
        let upload = deviceA.sync(&server)
        XCTAssertEqual(upload.map(\.title), ["Chapter 3"])
        XCTAssertEqual(upload.map(\.removed), [true])

        XCTAssertTrue(deviceB.sync(&server).isEmpty)
        XCTAssertTrue(deviceB.visible.isEmpty)
        XCTAssertTrue(stale.sync(&server).isEmpty, "the stale copy isn't uploaded")
        XCTAssertTrue(stale.visible.isEmpty)
        XCTAssertTrue(deviceA.sync(&server).isEmpty)
        XCTAssertTrue(deviceA.visible.isEmpty)
        XCTAssertEqual(server.map(\.removed), [true])
    }

    /// Uploads carry milliseconds, so timestamps a millisecond or so apart are one edit, and the
    /// server's copy wins that tie. An edit made soon after a sync is newer, not a tie.
    func testAnEditSoonAfterASyncIsNewer() throws {
        let device = makeDevice()
        let synced = Date().addingTimeInterval(-0.05)
        _ = device.repository.saveBookmark(TestFixtures.makeBookmark(bookId: device.bookId, page: 3, pos: "epubcfi(/6/2)", title: "Chapter 3", date: synced))
        var server = [bookmarkEntry("Chapter 3", at: "epubcfi(/6/2)", synced)]
        XCTAssertTrue(device.sync(&server).isEmpty, "the server's copy is this one")

        device.repository.removeBookmark(pos: "epubcfi(/6/2)", bookId: device.bookId)
        XCTAssertEqual(device.sync(&server).map(\.removed), [true])
        XCTAssertTrue(device.visible.isEmpty)
    }

    /// A retitled bookmark is one bookmark on the other device too: the old title is removed.
    func testARetitledBookmarkDoesNotDuplicate() throws {
        let deviceA = makeDevice(), deviceB = makeDevice()
        var server = [CalibreBookAnnotationBookmarkEntry]()
        _ = deviceA.repository.saveBookmark(TestFixtures.makeBookmark(bookId: deviceA.bookId, page: 3, pos: "epubcfi(/6/2)", title: "Chapter 3", date: Date().addingTimeInterval(-60)))
        _ = deviceA.sync(&server)
        _ = deviceB.sync(&server)

        var retitled = try XCTUnwrap(deviceA.repository.getBookmark(byPos: "epubcfi(/6/2)", bookId: deviceA.bookId))
        retitled.title = "Where the storm starts"
        retitled.date = Date()
        XCTAssertEqual(deviceA.repository.saveBookmark(retitled).0, 2)

        let upload = deviceA.sync(&server)
        XCTAssertEqual(upload.map(\.title), ["Chapter 3", "Where the storm starts"])
        XCTAssertEqual(upload.map(\.removed), [true, false])

        XCTAssertTrue(deviceB.sync(&server).isEmpty)
        XCTAssertEqual(deviceB.titlesByPos, ["epubcfi(/6/2)": "Where the storm starts"])
        XCTAssertTrue(deviceA.sync(&server).isEmpty)
        XCTAssertEqual(deviceA.titlesByPos, deviceB.titlesByPos)
    }

    /// Two devices bookmark different places under one title before syncing. calibre would keep
    /// one; the second device to sync gives its own a number, so both are kept everywhere.
    func testOneTitleAtTwoPlacesKeepsBothBookmarks() throws {
        let deviceA = makeDevice(), deviceB = makeDevice()
        var server = [CalibreBookAnnotationBookmarkEntry]()
        _ = deviceA.repository.saveBookmark(TestFixtures.makeBookmark(bookId: deviceA.bookId, page: 3, pos: "epubcfi(/6/2)", title: "Chapter 3", date: Date().addingTimeInterval(-60)))
        _ = deviceB.repository.saveBookmark(TestFixtures.makeBookmark(bookId: deviceB.bookId, page: 3, pos: "epubcfi(/6/8)", title: "Chapter 3", date: Date()))

        XCTAssertEqual(deviceA.sync(&server).map(\.title), ["Chapter 3"])
        XCTAssertEqual(deviceB.sync(&server).map(\.title), ["Chapter 3 #2"])
        XCTAssertTrue(deviceA.sync(&server).isEmpty)

        let expected = ["epubcfi(/6/2)": "Chapter 3", "epubcfi(/6/8)": "Chapter 3 #2"]
        XCTAssertEqual(deviceA.titlesByPos, expected)
        XCTAssertEqual(deviceB.titlesByPos, expected)
        XCTAssertTrue(deviceB.sync(&server).isEmpty)
    }

    /// A removal of another bookmark with the title doesn't remove this one: it's uploaded as
    /// newer, so the server keeps it.
    func testARemovalElsewhereKeepsTheBookmarkHere() throws {
        let device = makeDevice()
        let made = Date().addingTimeInterval(-120)
        _ = device.repository.saveBookmark(TestFixtures.makeBookmark(bookId: device.bookId, page: 3, pos: "epubcfi(/6/2)", title: "Chapter 3", date: made))
        var server = [bookmarkEntry("Chapter 3", at: "epubcfi(/6/8)", made.addingTimeInterval(60), removed: true)]

        let upload = device.sync(&server)
        XCTAssertEqual(upload.map(\.pos), ["epubcfi(/6/2)"])
        XCTAssertEqual(upload.map(\.removed), [false])
        XCTAssertEqual(device.titlesByPos, ["epubcfi(/6/2)": "Chapter 3"])
        XCTAssertEqual(server.map(\.pos), ["epubcfi(/6/2)"], "the upload is newer than the removal")
        XCTAssertTrue(device.sync(&server).isEmpty)
    }

    /// calibre keeps each format's bookmarks apart. An EPUB's sync merges and uploads FolioReader's
    /// bookmarks only: the book's PDF bookmarks stay out, and a PDF bookmark in the EPUB's list
    /// isn't added.
    func testAFormatSyncsItsReadersBookmarksOnly() throws {
        let device = makeDevice()
        let pdfPos = try String(decoding: JSONEncoder().encode(PDFBookmark.Location(page: 5, offset: .zero)), as: UTF8.self)
        _ = device.repository.saveBookmark(TestFixtures.makeBookmark(bookId: device.bookId, page: 5, pos_type: BookBookmarkRealm.PDFBookmarkPosType, pos: pdfPos, title: "PDF bookmark"))
        _ = device.repository.saveBookmark(TestFixtures.makeBookmark(bookId: device.bookId, page: 3, pos: "epubcfi(/6/2)", title: "EPUB bookmark"))
        var server = [
            bookmarkEntry("Stray PDF bookmark", at: pdfPos, Date(), posType: BookBookmarkRealm.PDFBookmarkPosType),
            bookmarkEntry("From calibre", at: "epubcfi(/6/4)", Date())
        ]

        XCTAssertEqual(device.sync(&server).map(\.title), ["EPUB bookmark"])
        XCTAssertEqual(Set(device.visible.map(\.title)), ["PDF bookmark", "EPUB bookmark", "From calibre"])
    }

    // MARK: - Helpers

    private func bookmarkEntry(
        _ title: String,
        at pos: String,
        _ date: Date,
        removed: Bool = false,
        posType: String = "epubcfi"
    ) -> CalibreBookAnnotationBookmarkEntry {
        CalibreBookAnnotationBookmarkEntry(
            type: "bookmark",
            timestamp: BookBookmark.dateFormatter.string(from: date),
            pos_type: posType,
            pos: pos,
            title: title,
            removed: removed
        )
    }

    private func makeDevice() -> BookmarkDevice {
        let configuration = MockDatabaseService.inMemoryConfiguration()
        let databaseService = DatabaseService()
        databaseService.setup(conf: configuration)
        return BookmarkDevice(
            configuration: configuration,
            repository: RealmAnnotationRepository(databaseService: databaseService),
            bookId: "devices^test_lib@server-uuid"
        )
    }
}

/// One device's bookmarks of a book.
private struct BookmarkDevice {
    let configuration: Realm.Configuration
    let repository: RealmAnnotationRepository
    let bookId: String

    var visible: [BookBookmark] {
        repository.getBookmarks(forBookId: bookId, excludeRemoved: true)
    }

    /// Titles by position; two at one position show as one entry joining both.
    var titlesByPos: [String: String] {
        Dictionary(visible.map { ($0.pos, $0.title) }) { [$0, $1].sorted().joined(separator: " + ") }
    }

    /// Stores bookmarks as they are, as older versions could leave them.
    func store(_ bookmarks: [BookBookmark]) throws {
        let realm = try Realm(configuration: configuration)
        try realm.write {
            bookmarks.forEach { realm.add($0.makeRealmObject()) }
        }
    }

    /// Syncs as `BookMetadataSyncWorker` does, then merges the upload into `server` as calibre
    /// does: per title the newest timestamp, the server's own on a tie. Returns the upload.
    func sync(_ server: inout [CalibreBookAnnotationBookmarkEntry], posType: String = "epubcfi") -> [CalibreBookAnnotationBookmarkEntry] {
        let upload = repository.syncBookmarks(entries: server, forBookId: bookId, posType: posType)
        var merged = server
        for entry in upload {
            if let index = merged.firstIndex(where: { $0.title == entry.title }) {
                if entry.timestamp > merged[index].timestamp {
                    merged[index] = entry
                }
            } else {
                merged.append(entry)
            }
        }
        server = merged
        return upload
    }
}
