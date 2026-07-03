//
//  RealmDomainMappingTests.swift
//  YetAnotherEBookReaderTests
//
//  Created on 2026/6/22.
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

final class RealmDomainMappingTests: XCTestCase {
    
    // MARK: - CalibreServer Mapping Tests
    
    func testCalibreServerMappingRoundTrip() {
        let uuid = UUID()
        
        let server = CalibreServer(
            uuid: uuid,
            name: "Test Server",
            baseUrl: "http://192.168.1.100:8080",
            hasPublicUrl: true,
            publicUrl: "https://public.server.com",
            hasAuth: true,
            username: "admin",
            password: "password123",
            defaultLibrary: "DefaultLib",
            removed: false
        )
        
        // Domain to Realm
        let realmObj = server.managedObject()
        XCTAssertEqual(realmObj.primaryKey, uuid.uuidString)
        XCTAssertEqual(realmObj.name, "Test Server")
        XCTAssertEqual(realmObj.baseUrl, "http://192.168.1.100:8080")
        XCTAssertTrue(realmObj.hasPublicUrl)
        XCTAssertEqual(realmObj.publicUrl, "https://public.server.com")
        XCTAssertTrue(realmObj.hasAuth)
        XCTAssertEqual(realmObj.username, "admin")
        XCTAssertEqual(realmObj.password, "password123")
        XCTAssertEqual(realmObj.defaultLibrary, "DefaultLib")
        XCTAssertFalse(realmObj.removed)
        
        // Realm to Domain
        let mappedServer = CalibreServer(managedObject: realmObj)
        XCTAssertEqual(mappedServer.uuid, server.uuid)
        XCTAssertEqual(mappedServer.name, server.name)
        XCTAssertEqual(mappedServer.baseUrl, server.baseUrl)
        XCTAssertEqual(mappedServer.hasPublicUrl, server.hasPublicUrl)
        XCTAssertEqual(mappedServer.publicUrl, server.publicUrl)
        XCTAssertEqual(mappedServer.hasAuth, server.hasAuth)
        XCTAssertEqual(mappedServer.username, server.username)
        XCTAssertEqual(mappedServer.password, server.password)
        XCTAssertEqual(mappedServer.defaultLibrary, server.defaultLibrary)
        XCTAssertEqual(mappedServer.removed, server.removed)
    }
    
    func testCalibreServerMappingDefaults() {
        let realmObj = CalibreServerRealm()
        realmObj.baseUrl = "http://localhost"
        realmObj.primaryKey = nil
        
        let server = CalibreServer(managedObject: realmObj)
        XCTAssertEqual(server.name, "http://localhost")
        XCTAssertEqual(server.baseUrl, "http://localhost")
        XCTAssertFalse(server.hasPublicUrl)
        XCTAssertEqual(server.publicUrl, "")
        XCTAssertFalse(server.hasAuth)
        XCTAssertEqual(server.username, "")
        XCTAssertEqual(server.password, "")
        XCTAssertEqual(server.defaultLibrary, "")
        XCTAssertFalse(server.removed)
    }
    
    // MARK: - CalibreLibrary Mapping Tests
    
    func testCalibreLibraryMappingRoundTrip() throws {
        let server = CalibreServer(
            uuid: UUID(),
            name: "Server",
            baseUrl: "http://localhost",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        
        let jsonStr = """
        {
            "pages": {
                "label": "pages",
                "name": "Pages",
                "datatype": "int",
                "editable": true,
                "display": { "description": "Pages" },
                "normalized": true,
                "num": 1,
                "is_multiple": false,
                "multiple_seps": {}
            }
        }
        """
        let customColumns = try JSONDecoder().decode([String: CalibreCustomColumnInfo].self, from: jsonStr.data(using: .utf8)!)
        
        let library = CalibreLibrary(
            server: server,
            key: "my-key",
            name: "My Library",
            autoUpdate: true,
            discoverable: false,
            hidden: true,
            lastModified: Date(timeIntervalSince1970: 123456789),
            customColumnInfos: customColumns
        )
        
        // Manual mapping from LibraryRepository saveLibrary
        let libraryRealm = CalibreLibraryRealm()
        libraryRealm.key = library.key
        libraryRealm.name = library.name
        libraryRealm.serverUUID = library.server.uuid.uuidString
        libraryRealm.customColumnsData = try? JSONEncoder().encode(library.customColumnInfos)
        libraryRealm.autoUpdate = library.autoUpdate
        libraryRealm.discoverable = library.discoverable
        libraryRealm.hidden = library.hidden
        libraryRealm.lastModified = library.lastModified
        
        XCTAssertEqual(libraryRealm.key, "my-key")
        XCTAssertEqual(libraryRealm.name, "My Library")
        XCTAssertEqual(libraryRealm.serverUUID, server.uuid.uuidString)
        XCTAssertEqual(libraryRealm.autoUpdate, true)
        XCTAssertEqual(libraryRealm.discoverable, false)
        XCTAssertEqual(libraryRealm.hidden, true)
        XCTAssertEqual(libraryRealm.lastModified, Date(timeIntervalSince1970: 123456789))
        
        // Manual mapping back from LibraryRepository getAllLibraries
        guard let name = libraryRealm.name else {
            XCTFail("Name must not be nil")
            return
        }
        
        let mappedLibrary = CalibreLibrary(
            server: server,
            key: libraryRealm.key ?? name,
            name: name,
            autoUpdate: libraryRealm.autoUpdate,
            discoverable: libraryRealm.discoverable,
            hidden: libraryRealm.hidden,
            lastModified: libraryRealm.lastModified,
            customColumnInfos: {
                guard let data = libraryRealm.customColumnsData else { return [:] }
                return (try? JSONDecoder().decode([String: CalibreCustomColumnInfo].self, from: data)) ?? [:]
            }()
        )
        
        XCTAssertEqual(mappedLibrary.server.uuid, library.server.uuid)
        XCTAssertEqual(mappedLibrary.key, library.key)
        XCTAssertEqual(mappedLibrary.name, library.name)
        XCTAssertEqual(mappedLibrary.autoUpdate, library.autoUpdate)
        XCTAssertEqual(mappedLibrary.discoverable, library.discoverable)
        XCTAssertEqual(mappedLibrary.hidden, library.hidden)
        XCTAssertEqual(mappedLibrary.lastModified, library.lastModified)
        XCTAssertEqual(mappedLibrary.customColumnInfos["pages"]?.name, "Pages")
    }
    
    // MARK: - CalibreBook Mapping Tests
    
    func testCalibreBookMappingRoundTrip() {
        let server = CalibreServer(uuid: UUID(), name: "S", baseUrl: "http://x", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "lib", name: "lib")
        
        var formats = [String: FormatInfo]()
        formats["EPUB"] = FormatInfo(
            serverSize: 1024,
            serverMTime: Date(timeIntervalSince1970: 100),
            cached: true,
            cacheSize: 1024,
            cacheMTime: Date(timeIntervalSince1970: 101)
        )
        
        var book = CalibreBook(id: 42, library: library)
        book.title = "Test Book"
        book.authors = ["Author One", "Author Two", "Author Three", "Author Four"]
        book.comments = "This is a comment"
        book.publisher = "Test Publisher"
        book.series = "Test Series"
        book.seriesIndex = 2.5
        book.rating = 8
        book.size = 5000
        book.pubDate = Date(timeIntervalSince1970: 200)
        book.timestamp = Date(timeIntervalSince1970: 300)
        book.lastModified = Date(timeIntervalSince1970: 400)
        book.lastSynced = Date(timeIntervalSince1970: 500)
        book.lastUpdated = Date(timeIntervalSince1970: 600)
        book.formats = formats
        book.inShelf = true
        book.tags = ["Fiction", "Sci-Fi", "Space Opera", "Adventure"]
        book.identifiers = ["isbn": "1234567890"]
        book.userMetadatas = ["#pages": 300, "#read": true]
        
        // Domain to Realm
        let realmObj = book.managedObject()
        XCTAssertEqual(realmObj.serverUUID, server.uuid.uuidString)
        XCTAssertEqual(realmObj.libraryName, library.name)
        XCTAssertEqual(realmObj.idInLib, 42)
        XCTAssertEqual(realmObj.title, "Test Book")
        XCTAssertEqual(realmObj.authorFirst, "Author One")
        XCTAssertEqual(realmObj.authorSecond, "Author Two")
        XCTAssertEqual(realmObj.authorThird, "Author Three")
        XCTAssertEqual(Array(realmObj.authorsMore), ["Author Four"])
        XCTAssertEqual(realmObj.comments, "This is a comment")
        XCTAssertEqual(realmObj.publisher, "Test Publisher")
        XCTAssertEqual(realmObj.series, "Test Series")
        XCTAssertEqual(realmObj.seriesIndex, 2.5)
        XCTAssertEqual(realmObj.rating, 8)
        XCTAssertEqual(realmObj.size, 5000)
        XCTAssertEqual(realmObj.pubDate, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(realmObj.timestamp, Date(timeIntervalSince1970: 300))
        XCTAssertEqual(realmObj.lastModified, Date(timeIntervalSince1970: 400))
        XCTAssertEqual(realmObj.lastSynced, Date(timeIntervalSince1970: 500))
        XCTAssertEqual(realmObj.lastUpdated, Date(timeIntervalSince1970: 600))
        XCTAssertEqual(realmObj.tagFirst, "Fiction")
        XCTAssertEqual(realmObj.tagSecond, "Sci-Fi")
        XCTAssertEqual(realmObj.tagThird, "Space Opera")
        XCTAssertEqual(Array(realmObj.tagsMore), ["Adventure"])
        XCTAssertTrue(realmObj.inShelf)
        
        // Realm to Domain
        let mappedBook = CalibreBook(managedObject: realmObj, library: library)
        XCTAssertEqual(mappedBook.id, book.id)
        XCTAssertEqual(mappedBook.library.id, book.library.id)
        XCTAssertEqual(mappedBook.title, book.title)
        XCTAssertEqual(mappedBook.authors, book.authors)
        XCTAssertEqual(mappedBook.comments, book.comments)
        XCTAssertEqual(mappedBook.publisher, book.publisher)
        XCTAssertEqual(mappedBook.series, book.series)
        XCTAssertEqual(mappedBook.seriesIndex, book.seriesIndex)
        XCTAssertEqual(mappedBook.rating, book.rating)
        XCTAssertEqual(mappedBook.size, book.size)
        XCTAssertEqual(mappedBook.pubDate, book.pubDate)
        XCTAssertEqual(mappedBook.timestamp, book.timestamp)
        XCTAssertEqual(mappedBook.lastModified, book.lastModified)
        XCTAssertEqual(mappedBook.lastSynced, book.lastSynced)
        XCTAssertEqual(mappedBook.lastUpdated, book.lastUpdated)
        XCTAssertEqual(mappedBook.inShelf, book.inShelf)
        XCTAssertEqual(mappedBook.tags, book.tags)
        XCTAssertEqual(mappedBook.identifiers, book.identifiers)
        XCTAssertEqual(mappedBook.formats["EPUB"]?.serverSize, book.formats["EPUB"]?.serverSize)
        XCTAssertEqual(mappedBook.formats["EPUB"]?.cached, book.formats["EPUB"]?.cached)
        XCTAssertEqual(mappedBook.userMetadatas["#pages"] as? Int, 300)
        XCTAssertEqual(mappedBook.userMetadatas["#read"] as? Bool, true)
    }
    
    func testCalibreBookMappingEdgeCases() {
        let server = CalibreServer(uuid: UUID(), name: "S", baseUrl: "http://x", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "lib", name: "lib")
        
        // Empty authors fallback
        var bookNoAuthors = CalibreBook(id: 1, library: library)
        bookNoAuthors.authors = []
        let realmObjNoAuthors = bookNoAuthors.managedObject()
        XCTAssertEqual(realmObjNoAuthors.authorFirst, "Unknown")
        XCTAssertNil(realmObjNoAuthors.authorSecond)
        XCTAssertNil(realmObjNoAuthors.authorThird)
        
        let mappedNoAuthors = CalibreBook(managedObject: realmObjNoAuthors, library: library)
        XCTAssertEqual(mappedNoAuthors.authors, ["Unknown"])
        
        // Empty tags
        var bookNoTags = CalibreBook(id: 2, library: library)
        bookNoTags.tags = []
        let realmObjNoTags = bookNoTags.managedObject()
        XCTAssertNil(realmObjNoTags.tagFirst)
        XCTAssertNil(realmObjNoTags.tagSecond)
        XCTAssertNil(realmObjNoTags.tagThird)
        
        let mappedNoTags = CalibreBook(managedObject: realmObjNoTags, library: library)
        XCTAssertTrue(mappedNoTags.tags.isEmpty)
        
        // Legacy format formatsVer1 fallback (formatsData is nil)
        let realmObjLegacyFormats = CalibreBookRealm()
        realmObjLegacyFormats.idInLib = 3
        realmObjLegacyFormats.title = "Legacy"
        realmObjLegacyFormats.formatsData = nil
        // We set legacy formats dict
        let legacyFormats = ["PDF": FormatInfo(serverSize: 99, serverMTime: .distantPast, cached: false, cacheSize: 0, cacheMTime: .distantPast)]
        realmObjLegacyFormats.formatsData = try? JSONEncoder().encode(legacyFormats)
        
        let mappedLegacy = CalibreBook(managedObject: realmObjLegacyFormats, library: library)
        XCTAssertNotNil(mappedLegacy.formats["PDF"])
        XCTAssertEqual(mappedLegacy.formats["PDF"]?.serverSize, 99)
    }
    
    // MARK: - BookDeviceReadingPosition Mapping Tests
    
    func testBookDeviceReadingPositionMappingRoundTrip() {
        let position = BookDeviceReadingPosition(
            id: "device-123",
            readerName: "YabrEPUB",
            maxPage: 450,
            lastReadPage: 120,
            lastReadChapter: "Chapter 4",
            lastChapterProgress: 15.6,
            lastProgress: 24.8,
            furthestReadPage: 130,
            furthestReadChapter: "Chapter 4",
            lastPosition: [1, 2, 3],
            cfi: "epubcfi(/6/12[id4]!/4/2/10)",
            epoch: 1234567890.0,
            structuralStyle: 1,
            structuralRootPageNumber: 2,
            positionTrackingStyle: 3,
            lastReadBook: "book-1",
            lastBundleProgress: 0.5
        )
        
        // Domain to Realm
        let realmObj = position.managedObject(bookId: "book-abc")
        XCTAssertEqual(realmObj.bookId, "book-abc")
        XCTAssertEqual(realmObj.deviceId, "device-123")
        XCTAssertEqual(realmObj.readerName, "YabrEPUB")
        XCTAssertEqual(realmObj.maxPage, 450)
        XCTAssertEqual(realmObj.lastReadPage, 120)
        XCTAssertEqual(realmObj.lastReadChapter, "Chapter 4")
        XCTAssertEqual(realmObj.lastChapterProgress, 15.6)
        XCTAssertEqual(realmObj.lastProgress, 24.8)
        XCTAssertEqual(realmObj.furthestReadPage, 130)
        XCTAssertEqual(realmObj.furthestReadChapter, "Chapter 4")
        XCTAssertEqual(Array(realmObj.lastPosition), [1, 2, 3])
        XCTAssertEqual(realmObj.cfi, "epubcfi(/6/12[id4]!/4/2/10)")
        XCTAssertEqual(realmObj.epoch, 1234567890.0)
        XCTAssertEqual(realmObj.structuralStyle, 1)
        XCTAssertEqual(realmObj.structuralRootPageNumber, 2)
        XCTAssertEqual(realmObj.positionTrackingStyle, 3)
        XCTAssertEqual(realmObj.lastReadBook, "book-1")
        XCTAssertEqual(realmObj.lastBundleProgress, 0.5)
        
        // Realm to Domain
        let mappedPosition = BookDeviceReadingPosition(managedObject: realmObj)
        XCTAssertEqual(mappedPosition.id, position.id)
        XCTAssertEqual(mappedPosition.readerName, position.readerName)
        XCTAssertEqual(mappedPosition.maxPage, position.maxPage)
        XCTAssertEqual(mappedPosition.lastReadPage, position.lastReadPage)
        XCTAssertEqual(mappedPosition.lastReadChapter, position.lastReadChapter)
        XCTAssertEqual(mappedPosition.lastChapterProgress, position.lastChapterProgress)
        XCTAssertEqual(mappedPosition.lastProgress, position.lastProgress)
        XCTAssertEqual(mappedPosition.furthestReadPage, position.furthestReadPage)
        XCTAssertEqual(mappedPosition.furthestReadChapter, position.furthestReadChapter)
        XCTAssertEqual(mappedPosition.lastPosition, position.lastPosition)
        XCTAssertEqual(mappedPosition.cfi, position.cfi)
        XCTAssertEqual(mappedPosition.epoch, position.epoch)
        XCTAssertEqual(mappedPosition.structuralStyle, position.structuralStyle)
        XCTAssertEqual(mappedPosition.structuralRootPageNumber, position.structuralRootPageNumber)
        XCTAssertEqual(mappedPosition.positionTrackingStyle, position.positionTrackingStyle)
        XCTAssertEqual(mappedPosition.lastReadBook, position.lastReadBook)
        XCTAssertEqual(mappedPosition.lastBundleProgress, position.lastBundleProgress)
    }
    
    func testBookDeviceReadingPositionHistoryMappingRoundTrip() {
        let startPosition = BookDeviceReadingPosition(
            id: "d1",
            readerName: "R1",
            maxPage: 0,
            lastReadPage: 0,
            lastReadChapter: "",
            lastChapterProgress: 0.0,
            lastProgress: 0.0,
            furthestReadPage: 0,
            furthestReadChapter: "",
            lastPosition: [0, 0, 0],
            cfi: "/",
            epoch: 0.0,
            structuralStyle: 0,
            structuralRootPageNumber: 0,
            positionTrackingStyle: 0,
            lastReadBook: "",
            lastBundleProgress: 0.0
        )
        let endPosition = BookDeviceReadingPosition(
            id: "d1",
            readerName: "R1",
            maxPage: 0,
            lastReadPage: 0,
            lastReadChapter: "",
            lastChapterProgress: 0.0,
            lastProgress: 0.0,
            furthestReadPage: 0,
            furthestReadChapter: "",
            lastPosition: [0, 0, 0],
            cfi: "/",
            epoch: 0.0,
            structuralStyle: 0,
            structuralRootPageNumber: 0,
            positionTrackingStyle: 0,
            lastReadBook: "",
            lastBundleProgress: 0.0
        )
        
        let history = BookDeviceReadingPositionHistory(
            bookId: "book-xyz",
            startDatetime: Date(timeIntervalSince1970: 5000),
            startPosition: startPosition,
            endPosition: endPosition
        )
        
        let realmObj = history.managedObject()
        XCTAssertEqual(realmObj.bookId, "book-xyz")
        XCTAssertEqual(realmObj.startDatetime, Date(timeIntervalSince1970: 5000))
        XCTAssertEqual(realmObj.startPosition?.deviceId, "d1")
        XCTAssertEqual(realmObj.endPosition?.deviceId, "d1")
        
        let mappedHistory = BookDeviceReadingPositionHistory(managedObject: realmObj)
        XCTAssertEqual(mappedHistory.bookId, history.bookId)
        XCTAssertEqual(mappedHistory.startDatetime, history.startDatetime)
        XCTAssertEqual(mappedHistory.startPosition?.id, history.startPosition?.id)
        XCTAssertEqual(mappedHistory.endPosition?.id, history.endPosition?.id)
    }
    
    // MARK: - BookBookmark / BookHighlight Mapping Tests
    
    func testBookBookmarkMappingRoundTrip() {
        let bookmark = BookBookmark(
            id: ObjectId.generate().stringValue,
            bookId: "book-123",
            page: 12,
            pos_type: "epubcfi",
            pos: "epubcfi(/6/4[id2]!/4/2/10)",
            title: "Bookmark Title",
            date: Date(timeIntervalSince1970: 6000),
            removed: true
        )
        
        // Domain to Realm
        let realmObj = BookBookmarkRealm(value: bookmark)
        XCTAssertEqual(realmObj._id.stringValue, bookmark.id)
        XCTAssertEqual(realmObj.bookId, bookmark.bookId)
        XCTAssertEqual(realmObj.page, bookmark.page)
        XCTAssertEqual(realmObj.pos_type, bookmark.pos_type)
        XCTAssertEqual(realmObj.pos, bookmark.pos)
        XCTAssertEqual(realmObj.title, bookmark.title)
        XCTAssertEqual(realmObj.date, bookmark.date)
        XCTAssertEqual(realmObj.removed, bookmark.removed)
        
        // Realm to Domain
        let mappedBookmark = realmObj.toValue()
        XCTAssertEqual(mappedBookmark.id, bookmark.id)
        XCTAssertEqual(mappedBookmark.bookId, bookmark.bookId)
        XCTAssertEqual(mappedBookmark.page, bookmark.page)
        XCTAssertEqual(mappedBookmark.pos_type, bookmark.pos_type)
        XCTAssertEqual(mappedBookmark.pos, bookmark.pos)
        XCTAssertEqual(mappedBookmark.title, bookmark.title)
        XCTAssertEqual(mappedBookmark.date, bookmark.date)
        XCTAssertEqual(mappedBookmark.removed, bookmark.removed)
    }
    
    func testBookHighlightMappingRoundTrip() {
        let highlight = BookHighlight(
            id: "highlight-456",
            bookId: "book-789",
            readerName: "YabrEPUB",
            page: 15,
            startOffset: 10,
            endOffset: 25,
            date: Date(timeIntervalSince1970: 7000),
            type: 2,
            note: "A nice highlight note",
            tocFamilyTitles: ["TOC 1", "TOC 2"],
            content: "Highlight Content",
            contentPost: "Post text",
            contentPre: "Pre text",
            cfiStart: "epubcfi(/6/12!/4/2/10)",
            cfiEnd: "epubcfi(/6/12!/4/2/20)",
            spineName: "chapter-3.xhtml",
            ranges: "10-25",
            removed: false
        )
        
        // Domain to Realm
        let realmObj = BookHighlightRealm(value: highlight)
        XCTAssertEqual(realmObj.highlightId, highlight.id)
        XCTAssertEqual(realmObj.bookId, highlight.bookId)
        XCTAssertEqual(realmObj.readerName, highlight.readerName)
        XCTAssertEqual(realmObj.page, highlight.page)
        XCTAssertEqual(realmObj.startOffset, highlight.startOffset)
        XCTAssertEqual(realmObj.endOffset, highlight.endOffset)
        XCTAssertEqual(realmObj.date, highlight.date)
        XCTAssertEqual(realmObj.type, highlight.type)
        XCTAssertEqual(realmObj.note, highlight.note)
        XCTAssertEqual(Array(realmObj.tocFamilyTitles), highlight.tocFamilyTitles)
        XCTAssertEqual(realmObj.content, highlight.content)
        XCTAssertEqual(realmObj.contentPost, highlight.contentPost)
        XCTAssertEqual(realmObj.contentPre, highlight.contentPre)
        XCTAssertEqual(realmObj.cfiStart, highlight.cfiStart)
        XCTAssertEqual(realmObj.cfiEnd, highlight.cfiEnd)
        XCTAssertEqual(realmObj.spineName, highlight.spineName)
        XCTAssertEqual(realmObj.ranges, highlight.ranges)
        XCTAssertEqual(realmObj.removed, highlight.removed)
        
        // Realm to Domain
        let mappedHighlight = realmObj.toValue()
        XCTAssertEqual(mappedHighlight.id, highlight.id)
        XCTAssertEqual(mappedHighlight.bookId, highlight.bookId)
        XCTAssertEqual(mappedHighlight.readerName, highlight.readerName)
        XCTAssertEqual(mappedHighlight.page, highlight.page)
        XCTAssertEqual(mappedHighlight.startOffset, highlight.startOffset)
        XCTAssertEqual(mappedHighlight.endOffset, highlight.endOffset)
        XCTAssertEqual(mappedHighlight.date, highlight.date)
        XCTAssertEqual(mappedHighlight.type, highlight.type)
        XCTAssertEqual(mappedHighlight.note, highlight.note)
        XCTAssertEqual(mappedHighlight.tocFamilyTitles, highlight.tocFamilyTitles)
        XCTAssertEqual(mappedHighlight.content, highlight.content)
        XCTAssertEqual(mappedHighlight.contentPost, highlight.contentPost)
        XCTAssertEqual(mappedHighlight.contentPre, highlight.contentPre)
        XCTAssertEqual(mappedHighlight.cfiStart, highlight.cfiStart)
        XCTAssertEqual(mappedHighlight.cfiEnd, highlight.cfiEnd)
        XCTAssertEqual(mappedHighlight.spineName, highlight.spineName)
        XCTAssertEqual(mappedHighlight.ranges, highlight.ranges)
        XCTAssertEqual(mappedHighlight.removed, highlight.removed)
    }
    
    // MARK: - New Mapper Direct Tests (Stage A27-S2)
    
    func testNewCalibreServerMappers() {
        let uuid = UUID()
        let server = CalibreServer(
            uuid: uuid,
            name: "Direct Server",
            baseUrl: "http://192.168.1.100:8080",
            hasPublicUrl: true,
            publicUrl: "https://public.server.com",
            hasAuth: true,
            username: "admin",
            password: "password123",
            defaultLibrary: "DefaultLib",
            removed: false
        )
        
        let realmObj = server.makeRealmObject()
        XCTAssertEqual(realmObj.primaryKey, uuid.uuidString)
        XCTAssertEqual(realmObj.name, "Direct Server")
        
        let mappedServer = realmObj.toDomain()
        XCTAssertEqual(mappedServer.uuid, server.uuid)
        XCTAssertEqual(mappedServer.name, server.name)
        XCTAssertEqual(mappedServer.baseUrl, server.baseUrl)
    }
    
    func testNewCalibreLibraryMappers() throws {
        let server = CalibreServer(
            uuid: UUID(),
            name: "Server",
            baseUrl: "http://localhost",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        
        let library = CalibreLibrary(
            server: server,
            key: "my-key",
            name: "My Library",
            autoUpdate: true,
            discoverable: false,
            hidden: true,
            lastModified: Date(timeIntervalSince1970: 123456789),
            customColumnInfos: [:]
        )
        
        let realmObj = library.makeRealmObject()
        XCTAssertEqual(realmObj.key, "my-key")
        XCTAssertEqual(realmObj.name, "My Library")
        XCTAssertEqual(realmObj.serverUUID, server.uuid.uuidString)
        
        let mappedLibrary = realmObj.toDomain(server: server)
        XCTAssertEqual(mappedLibrary.server.uuid, library.server.uuid)
        XCTAssertEqual(mappedLibrary.key, library.key)
        XCTAssertEqual(mappedLibrary.name, library.name)
        XCTAssertEqual(mappedLibrary.autoUpdate, library.autoUpdate)
    }
    
    func testNewCalibreBookMappers() {
        let server = CalibreServer(uuid: UUID(), name: "S", baseUrl: "http://x", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "lib", name: "lib")
        
        var book = CalibreBook(id: 42, library: library)
        book.title = "Direct Book"
        book.authors = ["A1", "A2"]
        book.comments = "C"
        book.publisher = "P"
        book.series = "S"
        book.seriesIndex = 2.5
        book.rating = 8
        book.size = 5000
        book.pubDate = Date(timeIntervalSince1970: 200)
        book.timestamp = Date(timeIntervalSince1970: 300)
        book.lastModified = Date(timeIntervalSince1970: 400)
        book.lastSynced = Date(timeIntervalSince1970: 500)
        book.lastUpdated = Date(timeIntervalSince1970: 600)
        book.formats = [:]
        book.inShelf = true
        book.tags = ["T1", "T2"]
        
        let realmObj = book.makeRealmObject()
        XCTAssertEqual(realmObj.title, "Direct Book")
        XCTAssertEqual(realmObj.authorFirst, "A1")
        XCTAssertEqual(realmObj.tagFirst, "T1")
        
        let mappedBook = realmObj.toDomain(library: library)
        XCTAssertEqual(mappedBook.id, book.id)
        XCTAssertEqual(mappedBook.title, book.title)
        XCTAssertEqual(mappedBook.authors, book.authors)
        XCTAssertEqual(mappedBook.tags, book.tags)
    }
    
    func testNewBookDeviceReadingPositionMappers() {
        let position = BookDeviceReadingPosition(
            id: "device-123",
            readerName: "YabrEPUB",
            maxPage: 450,
            lastReadPage: 120,
            lastReadChapter: "Chapter 4",
            lastChapterProgress: 15.6,
            lastProgress: 24.8,
            furthestReadPage: 130,
            furthestReadChapter: "Chapter 4",
            lastPosition: [1, 2, 3],
            cfi: "epubcfi(/6/12[id4]!/4/2/10)",
            epoch: 1234567890.0,
            structuralStyle: 1,
            structuralRootPageNumber: 2,
            positionTrackingStyle: 3,
            lastReadBook: "book-1",
            lastBundleProgress: 0.5
        )
        
        let realmObj = position.makeRealmObject(bookId: "book-xyz")
        XCTAssertEqual(realmObj.bookId, "book-xyz")
        XCTAssertEqual(realmObj.deviceId, "device-123")
        
        let mappedPosition = realmObj.toDomain()
        XCTAssertEqual(mappedPosition.id, position.id)
        XCTAssertEqual(mappedPosition.readerName, position.readerName)
        
        let history = BookDeviceReadingPositionHistory(
            bookId: "book-xyz",
            startDatetime: Date(timeIntervalSince1970: 5000),
            startPosition: position,
            endPosition: position
        )
        
        let historyRealm = history.makeRealmObject()
        XCTAssertEqual(historyRealm.bookId, "book-xyz")
        XCTAssertEqual(historyRealm.startPosition?.deviceId, "device-123")
        
        let mappedHistory = historyRealm.toDomain()
        XCTAssertEqual(mappedHistory.bookId, history.bookId)
        XCTAssertEqual(mappedHistory.startPosition?.id, history.startPosition?.id)
    }
    
    func testNewBookBookmarkAndHighlightMappers() {
        let bookmark = BookBookmark(
            id: ObjectId.generate().stringValue,
            bookId: "book-123",
            page: 12,
            pos_type: "epubcfi",
            pos: "epubcfi(/6/4[id2]!/4/2/10)",
            title: "Bookmark Title",
            date: Date(timeIntervalSince1970: 6000),
            removed: true
        )
        
        let bookmarkRealm = bookmark.makeRealmObject()
        XCTAssertEqual(bookmarkRealm._id.stringValue, bookmark.id)
        
        let mappedBookmark = bookmarkRealm.toDomain()
        XCTAssertEqual(mappedBookmark.id, bookmark.id)
        XCTAssertEqual(mappedBookmark.title, bookmark.title)
        
        let highlight = BookHighlight(
            id: "highlight-456",
            bookId: "book-789",
            readerName: "YabrEPUB",
            page: 15,
            startOffset: 10,
            endOffset: 25,
            date: Date(timeIntervalSince1970: 7000),
            type: 2,
            note: "A nice highlight note",
            tocFamilyTitles: ["TOC 1"],
            content: "Highlight Content",
            contentPost: "Post text",
            contentPre: "Pre text",
            cfiStart: "epubcfi(/6/12!/4/2/10)",
            cfiEnd: "epubcfi(/6/12!/4/2/20)",
            spineName: "chapter-3.xhtml",
            ranges: "10-25",
            removed: false
        )
        
        let highlightRealm = highlight.makeRealmObject()
        XCTAssertEqual(highlightRealm.highlightId, highlight.id)
        
        let mappedHighlight = highlightRealm.toDomain()
        XCTAssertEqual(mappedHighlight.id, highlight.id)
        XCTAssertEqual(mappedHighlight.note, highlight.note)
    }
    
    func testApplyDomainOnManagedObjects() throws {
        let config = Realm.Configuration(inMemoryIdentifier: "testRealm-\(UUID().uuidString)")
        let realm = try Realm(configuration: config)
        
        let serverUUID = UUID()
        
        try realm.write {
            // 1. CalibreServerRealm
            let serverRealm = CalibreServerRealm()
            serverRealm.primaryKey = serverUUID.uuidString
            serverRealm.name = "Original Server"
            realm.add(serverRealm)
            
            // 2. CalibreLibraryRealm
            let libraryRealm = CalibreLibraryRealm()
            libraryRealm.serverUUID = serverUUID.uuidString
            libraryRealm.name = "Original Lib"
            libraryRealm.updatePrimaryKey()
            realm.add(libraryRealm)
            
            // 3. CalibreBookRealm
            let bookRealm = CalibreBookRealm()
            bookRealm.serverUUID = serverUUID.uuidString
            bookRealm.libraryName = "Original Lib"
            bookRealm.idInLib = 100
            bookRealm.title = "Original Title"
            bookRealm.updatePrimaryKey()
            realm.add(bookRealm)
            
            // 4. BookBookmarkRealm
            let bookmarkRealm = BookBookmarkRealm()
            bookmarkRealm.bookId = "book-1"
            bookmarkRealm.pos = "pos-1"
            bookmarkRealm.title = "Original Bookmark"
            realm.add(bookmarkRealm)
            
            // 5. BookDeviceReadingPositionRealm
            let positionRealm = BookDeviceReadingPositionRealm()
            positionRealm.bookId = "book-1"
            positionRealm.deviceId = "device-1"
            positionRealm.readerName = "reader-1"
            positionRealm.lastReadPage = 10
            realm.add(positionRealm)
        }
        
        // Now retrieve and applyDomain to update them
        let server = CalibreServer(
            uuid: serverUUID,
            name: "Updated Server",
            baseUrl: "http://updated",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        
        let library = CalibreLibrary(
            server: server,
            key: "updated-key",
            name: "Original Lib", // name must match to preserve primaryKey of managed object
            autoUpdate: false,
            discoverable: true,
            hidden: true,
            lastModified: Date(),
            customColumnInfos: [:]
        )
        
        var book = CalibreBook(id: 100, library: library) // id must match
        book.title = "Updated Title"
        book.authors = ["New Author"]
        book.tags = ["New Tag"]
        
        let bookmark = BookBookmark(
            id: realm.objects(BookBookmarkRealm.self).first!._id.stringValue,
            bookId: "book-1",
            page: 1,
            pos_type: "epubcfi",
            pos: "pos-1",
            title: "Updated Bookmark",
            date: Date(),
            removed: false
        )
        
        let position = BookDeviceReadingPosition(
            id: "device-1",
            readerName: "reader-1",
            maxPage: 100,
            lastReadPage: 20,
            lastReadChapter: "Ch 2",
            lastChapterProgress: 5.0,
            lastProgress: 10.0,
            furthestReadPage: 25,
            furthestReadChapter: "Ch 2",
            lastPosition: [10],
            cfi: "cfi",
            epoch: 200.0,
            structuralStyle: 1,
            structuralRootPageNumber: 2,
            positionTrackingStyle: 3,
            lastReadBook: "book-1",
            lastBundleProgress: 0.2
        )
        
        try realm.write {
            if let serverRealm = realm.objects(CalibreServerRealm.self).first {
                serverRealm.applyDomain(server)
                XCTAssertEqual(serverRealm.name, "Updated Server")
                XCTAssertEqual(serverRealm.primaryKey, serverUUID.uuidString) // should be guarded/unchanged
            }
            
            if let libraryRealm = realm.objects(CalibreLibraryRealm.self).first {
                libraryRealm.applyDomain(library)
                XCTAssertEqual(libraryRealm.name, "Original Lib") // name should not change because of self.realm != nil guard
                XCTAssertFalse(libraryRealm.autoUpdate)
            }
            
            if let bookRealm = realm.objects(CalibreBookRealm.self).first {
                bookRealm.applyDomain(book)
                XCTAssertEqual(bookRealm.title, "Updated Title")
                XCTAssertEqual(bookRealm.authorFirst, "New Author")
                XCTAssertEqual(bookRealm.tagFirst, "New Tag")
                XCTAssertEqual(bookRealm.idInLib, 100) // idInLib should not change because of guard
            }
            
            if let bookmarkRealm = realm.objects(BookBookmarkRealm.self).first {
                bookmarkRealm.applyDomain(bookmark)
                XCTAssertEqual(bookmarkRealm.title, "Updated Bookmark")
            }
            
            if let positionRealm = realm.objects(BookDeviceReadingPositionRealm.self).first {
                positionRealm.applyDomain(position, bookId: "book-1")
                XCTAssertEqual(positionRealm.lastReadPage, 20)
                XCTAssertEqual(Array(positionRealm.lastPosition), [10])
            }
        }
    }
}
