//
//  CalibreDataSplitTests.swift
//  YetAnotherEBookReaderTests
//
//  Created on 2026/6/18.
//  P2/A11: Verifies that the mechanical split of CalibreData.swift preserved
//  type identities, Codable keys, hashing/equality semantics, and color/style
//  mappings for the highest-risk boundaries.
//

import XCTest
@testable import YetAnotherEBookReader

final class CalibreDataSplitTests: XCTestCase {

    // MARK: - CalibreServer identity

    func testCalibreServerIDIsUUIDString() {
        let uuid = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let server = CalibreServer(uuid: uuid,
                                    name: "Server",
                                    baseUrl: "http://localhost",
                                    hasPublicUrl: false,
                                    publicUrl: "",
                                    hasAuth: false,
                                    username: "u",
                                    password: "p")
        XCTAssertEqual(server.id, uuid.uuidString)
    }

    func testCalibreServerEqualityIgnoresNameAndPassword() {
        let uuid = UUID()
        let a = CalibreServer(uuid: uuid, name: "A", baseUrl: "http://x", hasPublicUrl: false, publicUrl: "", hasAuth: true, username: "u", password: "p1")
        let b = CalibreServer(uuid: UUID(), name: "B", baseUrl: "http://x", hasPublicUrl: true, publicUrl: "http://y", hasAuth: false, username: "u", password: "p2")
        XCTAssertEqual(a, b, "CalibreServer equality should only consider baseUrl + username")
        let c = CalibreServer(uuid: uuid, name: "A", baseUrl: "http://x", hasPublicUrl: false, publicUrl: "", hasAuth: true, username: "other", password: "p1")
        XCTAssertNotEqual(a, c)
    }

    func testCalibreServerHashMatchesEquality() {
        let uuid = UUID()
        let a = CalibreServer(uuid: uuid, name: "A", baseUrl: "http://x", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "u", password: "")
        let b = CalibreServer(uuid: UUID(), name: "B", baseUrl: "http://x", hasPublicUrl: true, publicUrl: "http://y", hasAuth: true, username: "u", password: "p")
        XCTAssertEqual(a.hashValue, b.hashValue, "Equal CalibreServer instances must hash equally")
    }

    func testCalibreServerLocalServerUUIDConstant() {
        // UUID.uuidString returns uppercase; the constant preserves the original
        // lowercase string from CalibreData.swift verbatim.
        XCTAssertEqual(CalibreServer.LocalServerUUID.uuidString.lowercased(),
                       "c54ba2ae-67af-46f6-af64-504fd5d756eb")
    }

    // MARK: - CalibreLibrary identity

    func testCalibreLibraryIDUsesPrimaryKey() {
        let uuid = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let server = CalibreServer(uuid: uuid, name: "S", baseUrl: "http://x", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "MyLib", name: "MyLib")
        let expected = CalibreLibrary.identity(serverUUID: uuid.uuidString, libraryName: "MyLib")
        XCTAssertEqual(library.id, expected)
    }

    func testCalibreLibraryEqualityAndHash() {
        let uuid = UUID()
        let serverA = CalibreServer(uuid: uuid, name: "S", baseUrl: "http://x", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "u", password: "")
        let serverB = CalibreServer(uuid: uuid, name: "S-different-name", baseUrl: "http://x", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "u", password: "")

        let a = CalibreLibrary(server: serverA, key: "lib", name: "lib")
        let b = CalibreLibrary(server: serverB, key: "lib", name: "lib")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)

        let c = CalibreLibrary(server: serverA, key: "lib", name: "renamed")
        XCTAssertNotEqual(a, c, "Library identity should depend on library name")
    }

    func testCalibreLibraryPluginNameConstants() {
        XCTAssertEqual(CalibreLibrary.PLUGIN_DSREADER_HELPER, "DSReader Helper")
        XCTAssertEqual(CalibreLibrary.PLUGIN_READING_POSITION, "Reading Position")
        XCTAssertEqual(CalibreLibrary.PLUGIN_DICTIONARY_VIEWER, "Dictionary Viewer")
        XCTAssertEqual(CalibreLibrary.PLUGIN_GOODREADS_SYNC, "Goodreads Sync")
        XCTAssertEqual(CalibreLibrary.PLUGIN_COUNT_PAGES, "Count Pages")
    }

    // MARK: - CalibreBook identity

    func testCalibreBookInShelfIdPrimaryKeyShape() {
        let uuid = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let server = CalibreServer(uuid: uuid, name: "S", baseUrl: "http://x", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "lib", name: "lib")
        let book = CalibreBook(id: 42, library: library)

        let expected = CalibreBook.identity(
            serverUUID: uuid.uuidString,
            libraryName: "lib",
            id: "42"
        )
        XCTAssertEqual(book.inShelfId, expected)
    }

    func testCalibreBookEqualityAndHashByInShelfId() {
        let uuid = UUID()
        let server = CalibreServer(uuid: uuid, name: "S", baseUrl: "http://x", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        let library = CalibreLibrary(server: server, key: "lib", name: "lib")
        let a = CalibreBook(id: 7, library: library)
        var b = CalibreBook(id: 7, library: library)
        b.title = "Different Title"
        XCTAssertEqual(a, b, "CalibreBook equality should be by inShelfId only")
        XCTAssertEqual(a.hashValue, b.hashValue)

        let c = CalibreBook(id: 8, library: library)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - BookHighlightStyle mapping

    func testBookHighlightStyleClassForStyleRoundTrip() {
        for style in BookHighlightStyle.allCases {
            let css = BookHighlightStyle.classForStyle(style.rawValue)
            let resolved = BookHighlightStyle.styleForClass(css)
            XCTAssertEqual(resolved, style, "classForStyle -> styleForClass should round-trip for \(style)")
        }
    }

    func testBookHighlightStyleClassForStyleCalibre() {
        XCTAssertEqual(BookHighlightStyle.classForStyleCalibre(BookHighlightStyle.yellow.rawValue), "yellow")
        XCTAssertEqual(BookHighlightStyle.classForStyleCalibre(BookHighlightStyle.green.rawValue), "green")
        XCTAssertEqual(BookHighlightStyle.classForStyleCalibre(BookHighlightStyle.blue.rawValue), "blue")
        XCTAssertEqual(BookHighlightStyle.classForStyleCalibre(BookHighlightStyle.pink.rawValue), "pink")
        XCTAssertEqual(BookHighlightStyle.classForStyleCalibre(BookHighlightStyle.underline.rawValue), "underline")
    }

    func testBookHighlightStyleDefaultInitIsYellow() {
        XCTAssertEqual(BookHighlightStyle().rawValue, BookHighlightStyle.yellow.rawValue)
    }

    func testBookHighlightStyleStyleForClassFallback() {
        XCTAssertEqual(BookHighlightStyle.styleForClass("unknown"), .yellow)
        XCTAssertEqual(BookHighlightStyle.styleForClass("yellow"), .yellow)
        XCTAssertEqual(BookHighlightStyle.styleForClass("highlight-yellow"), .yellow)
    }

    // MARK: - Plugin preference Codable

    func testCalibreDSReaderHelperPrefsDecoding() throws {
        let json = """
        {
            "plugin_prefs": {
                "Options": {
                    "servicePort": 8080,
                    "goodreadsSyncEnabled": true,
                    "dictViewerEnabled": true,
                    "dictViewerLibraryName": "DictLib",
                    "readingPositionColumnAllLibrary": true,
                    "readingPositionColumnName": "position",
                    "readingPositionColumnPrefix": "#",
                    "readingPositionColumnUserSeparated": false
                }
            }
        }
        """.data(using: .utf8)!

        let prefs = try JSONDecoder().decode(CalibreDSReaderHelperPrefs.self, from: json)
        XCTAssertTrue(prefs.plugin_prefs.Options.goodreadsSyncEnabled)
        XCTAssertTrue(prefs.plugin_prefs.Options.dictViewerEnabled)
        XCTAssertTrue(prefs.plugin_prefs.Options.isEnabled)
        XCTAssertEqual(prefs.plugin_prefs.Options.servicePort, 8080)
    }

    func testCalibreCountPagesPrefsLibraryConfigEnabledWhenColumnsSet() {
        var config = CalibreCountPagesPrefs.LibraryConfig()
        XCTAssertFalse(config.isEnabled)
        config.customColumnPages = "#pages"
        XCTAssertTrue(config.isEnabled)
        config.customColumnPages = "#"
        XCTAssertFalse(config.isEnabled, "Only '#' should not count as enabled")
    }

    func testCalibreGoodreadsSyncPrefsProfileNameFallback() {
        let goodreads = CalibreGoodreadsSyncPrefs.Goodreads()
        let prefs = CalibreGoodreadsSyncPrefs.PluginPrefs(SchemaVersion: 0,
                                                          Goodreads: goodreads,
                                                          Users: ["Default": .init(shelves: [])])
        XCTAssertEqual(prefs.profileName, "Default")
        // isEnabled is `!Users.isEmpty`, so a single Default entry is enabled
        // even with an empty shelves list.
        XCTAssertTrue(prefs.isEnabled)

        let emptyPrefs = CalibreGoodreadsSyncPrefs.PluginPrefs(SchemaVersion: 0,
                                                               Goodreads: goodreads,
                                                               Users: [:])
        XCTAssertFalse(emptyPrefs.isEnabled, "Empty Users dictionary should report isEnabled=false")
    }

    // MARK: - Custom column Codable

    func testCalibreCustomColumnInfoDecodingSnakeCaseKeys() throws {
        let json = """
        {
            "label": "rating",
            "name": "My Rating",
            "datatype": "rating",
            "editable": true,
            "display": {
                "description": "User rating",
                "allow_half_stars": true
            },
            "normalized": false,
            "num": 5,
            "is_multiple": false,
            "multiple_seps": {}
        }
        """.data(using: .utf8)!

        let info = try JSONDecoder().decode(CalibreCustomColumnInfo.self, from: json)
        XCTAssertEqual(info.label, "rating")
        XCTAssertEqual(info.name, "My Rating")
        XCTAssertEqual(info.datatype, "rating")
        XCTAssertEqual(info.num, 5)
        XCTAssertFalse(info.isMultiple)
        XCTAssertEqual(info.display.description, "User rating")
        XCTAssertEqual(info.display.allowHalfStars, true)
    }

    // MARK: - Array.chunks helper

    func testArrayChunksPreservesAllElements() {
        let input = Array(0..<10)
        let chunks = input.chunks(size: 3)
        XCTAssertEqual(chunks.count, 4)
        XCTAssertEqual(chunks[0], [0, 1, 2])
        XCTAssertEqual(chunks[1], [3, 4, 5])
        XCTAssertEqual(chunks[2], [6, 7, 8])
        XCTAssertEqual(chunks[3], [9])
        XCTAssertEqual(chunks.flatMap { $0 }, input)
    }

    func testArrayChunksEmptyInput() {
        let empty: [Int] = []
        XCTAssertEqual(empty.chunks(size: 5), [])
    }

    // MARK: - Activity class hierarchy

    func testCalibreActivityStartFinishInheritType() {
        let url = URL(string: "http://localhost/x")!
        let request = URLRequest(url: url)
        let start = CalibreActivityStart("fetch", request, startDatetime: Date(), bookId: 1, libraryId: "lib")
        let finish = CalibreActivityFinish("fetch", request, startDatetime: Date(), finishDatetime: Date(), errMsg: "ok")

        XCTAssertEqual(start.type, "fetch")
        XCTAssertEqual(finish.type, "fetch")
        XCTAssertTrue(start is CalibreActivity)
        XCTAssertTrue(finish is CalibreActivity)
    }
}
