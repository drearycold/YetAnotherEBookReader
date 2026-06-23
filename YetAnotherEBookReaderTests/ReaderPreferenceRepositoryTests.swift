//
//  ReaderPreferenceRepositoryTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Codex on 2026-06-23.
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

final class ReaderPreferenceRepositoryTests: XCTestCase {
    private var configByServerId: [String: Realm.Configuration]!
    private var repository: ReaderPreferenceRepositoryProtocol!

    override func setUpWithError() throws {
        configByServerId = [:]
        repository = RealmReaderPreferenceRepository { [unowned self] server in
            if let config = self.configByServerId[server.id] {
                return config
            }
            let config = Realm.Configuration(
                inMemoryIdentifier: "ReaderPreferenceRepositoryTests-\(server.id)",
                schemaVersion: ModelData.RealmSchemaVersion,
                migrationBlock: { _, _ in },
                objectTypes: [
                    BookDeviceReadingPositionRealm.self,
                    BookDeviceReadingPositionHistoryRealm.self,
                    FolioReaderPreferenceRealm.self,
                    BookHighlightRealm.self,
                    BookBookmarkRealm.self,
                    PDFOptions.self,
                    ReadiumPreferenceRealm.self,
                ]
            )
            self.configByServerId[server.id] = config
            return config
        }
    }

    override func tearDownWithError() throws {
        configByServerId = nil
        repository = nil
    }

    func testLoadInitialPreferencesReturnsNilWhenMissing() throws {
        let book = TestFixtures.makeBook()

        XCTAssertNil(repository.loadInitialPreferences(for: book, readerType: .ReadiumEPUB))
        XCTAssertNil(repository.loadInitialPreferences(for: book, readerType: .YabrPDF))
        XCTAssertNil(repository.loadInitialPreferences(for: book, readerType: .YabrEPUB))
    }

    func testReadiumPreferencesSaveAndLoad() throws {
        let book = TestFixtures.makeBook()
        let prefs = ReaderEnginePreferences(
            themeMode: 2,
            fontSizePercentage: 135,
            fontFamily: "Avenir",
            lineHeight: 1.4,
            pageMargins: 1.6,
            scroll: true,
            scrollDirection: 1,
            volumeKeyPaging: true
        )

        repository.savePreferences(prefs, for: book, readerType: .ReadiumEPUB)

        let loaded = repository.loadInitialPreferences(for: book, readerType: .ReadiumEPUB)
        XCTAssertEqual(loaded?.themeMode, 2)
        XCTAssertEqual(loaded?.fontSizePercentage, 135)
        XCTAssertEqual(loaded?.fontFamily, "Avenir")
        XCTAssertEqual(loaded?.lineHeight, 1.4)
        XCTAssertEqual(loaded?.pageMargins, 1.6)
        XCTAssertEqual(loaded?.scroll, true)
        XCTAssertEqual(loaded?.scrollDirection, 1)
        XCTAssertEqual(loaded?.volumeKeyPaging, true)
    }

    func testPDFPreferencesSaveAndLoad() throws {
        let book = TestFixtures.makeBook()
        let prefs = ReaderEnginePreferences(
            themeMode: 1,
            fontSizePercentage: 100,
            fontFamily: "Original",
            lineHeight: 1.2,
            pageMargins: 1.0,
            scroll: true,
            scrollDirection: 1,
            volumeKeyPaging: false
        )

        repository.savePreferences(prefs, for: book, readerType: .YabrPDF)

        let config = configByServerId[book.library.server.id]!
        let realm = try Realm(configuration: config)
        let saved = realm.objects(PDFOptions.self)
            .filter("bookId == %@ AND libraryName == %@", book.id, book.library.name)
            .first

        XCTAssertEqual(saved?.themeMode, .serpia)
        XCTAssertEqual(saved?.pageMode, .Scroll)
        XCTAssertEqual(saved?.scrollDirection, .Horizontal)

        let loaded = repository.loadInitialPreferences(for: book, readerType: .YabrPDF)
        XCTAssertEqual(loaded?.themeMode, 1)
        XCTAssertEqual(loaded?.scroll, true)
        XCTAssertEqual(loaded?.scrollDirection, 1)
    }

    func testFolioPreferencesSaveAndLoad() throws {
        let book = TestFixtures.makeBook()
        let prefs = ReaderEnginePreferences(
            themeMode: 2,
            fontSizePercentage: 120,
            fontFamily: "Georgia",
            lineHeight: 1.2,
            pageMargins: 1.0,
            scroll: true,
            scrollDirection: 1,
            volumeKeyPaging: false
        )

        repository.savePreferences(prefs, for: book, readerType: .YabrEPUB)

        let config = configByServerId[book.library.server.id]!
        let realm = try Realm(configuration: config)
        let saved = realm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: book.bookPrefId)

        XCTAssertEqual(saved?.nightMode, true)
        XCTAssertEqual(saved?.themeMode, 2)
        XCTAssertEqual(saved?.currentFontSize, "24px")
        XCTAssertEqual(saved?.currentFont, "Georgia")
        XCTAssertEqual(saved?.currentScrollDirection, 1)

        let loaded = repository.loadInitialPreferences(for: book, readerType: .YabrEPUB)
        XCTAssertEqual(loaded?.themeMode, 2)
        XCTAssertEqual(loaded?.fontSizePercentage, 120)
        XCTAssertEqual(loaded?.fontFamily, "Georgia")
        XCTAssertEqual(loaded?.scroll, true)
        XCTAssertEqual(loaded?.scrollDirection, 1)
    }

    func testSavePreferencesCreatesObjectsForAllSupportedReaderTypes() throws {
        let readiumBook = TestFixtures.makeBook(id: 1, library: TestFixtures.makeLibrary(server: TestFixtures.makeServer()))
        let pdfBook = TestFixtures.makeBook(id: 2, library: readiumBook.library)
        let folioBook = TestFixtures.makeBook(id: 3, library: readiumBook.library)

        repository.savePreferences(ReaderEnginePreferences(), for: readiumBook, readerType: .ReadiumCBZ)
        repository.savePreferences(ReaderEnginePreferences(themeMode: 2), for: pdfBook, readerType: .YabrPDF)
        repository.savePreferences(ReaderEnginePreferences(fontSizePercentage: 110), for: folioBook, readerType: .YabrEPUB)

        let config = configByServerId[readiumBook.library.server.id]!
        let realm = try Realm(configuration: config)

        XCTAssertNotNil(realm.object(ofType: ReadiumPreferenceRealm.self, forPrimaryKey: readiumBook.bookPrefId))
        XCTAssertNotNil(realm.objects(PDFOptions.self).filter("bookId == %@ AND libraryName == %@", pdfBook.id, pdfBook.library.name).first)
        XCTAssertNotNil(realm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: folioBook.bookPrefId))
    }
}
