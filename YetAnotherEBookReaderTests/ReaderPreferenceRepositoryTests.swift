//
//  ReaderPreferenceRepositoryTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Codex on 2026-06-23.
//

import XCTest
import FolioReaderKit
import RealmSwift
@testable import YetAnotherEBookReader

final class ReaderPreferenceRepositoryTests: XCTestCase {
    private var serverScopedProvider: InMemoryServerScopedRealmConfigurationProvider!
    private var repository: ReaderPreferenceRepositoryProtocol!
    private var folioProfileConfig: Realm.Configuration!
    private var folioProfileRepository: FolioReaderProfileRepositoryProtocol!

    override func setUpWithError() throws {
        serverScopedProvider = InMemoryServerScopedRealmConfigurationProvider(
            identifierPrefix: "ReaderPreferenceRepositoryTests"
        )
        folioProfileConfig = Realm.Configuration(
            inMemoryIdentifier: "ReaderPreferenceRepositoryTests-FolioProfiles",
            schemaVersion: DatabaseSchema.version,
            migrationBlock: { _, _ in },
            objectTypes: [FolioReaderPreferenceRealm.self]
        )
        folioProfileRepository = RealmFolioReaderProfileRepository(realmConfiguration: folioProfileConfig)
        repository = RealmReaderPreferenceRepository { [unowned self] server in
            self.serverScopedProvider.configuration(for: server)
        }
    }

    override func tearDownWithError() throws {
        serverScopedProvider = nil
        repository = nil
        folioProfileRepository = nil
        folioProfileConfig = nil
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
            themeMode: 3,
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
        XCTAssertEqual(loaded?.themeMode, 3)
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

        let config = serverScopedProvider.configuration(for: book.library.server)
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

    func testLoadPDFPreferencesReturnsNilWhenMissing() {
        let book = TestFixtures.makeBook()

        XCTAssertNil(repository.loadPDFPreferences(for: book))
    }

    func testSavePDFPreferencesCreatesOrUpdatesRealmObject() throws {
        let book = TestFixtures.makeBook()
        let preferences = PDFPreferenceValue(
            themeMode: .dark,
            selectedAutoScaler: .Custom,
            pageMode: .Scroll,
            readingDirection: .TtB_RtL,
            scrollDirection: .Horizontal,
            hMarginAutoScaler: 8,
            vMarginAutoScaler: 9,
            hMarginDetectStrength: 3,
            vMarginDetectStrength: 4,
            marginOffset: 2,
            lastScale: 1.8,
            rememberInPagePosition: false
        )

        repository.savePDFPreferences(preferences, for: book)

        let config = serverScopedProvider.configuration(for: book.library.server)
        let realm = try Realm(configuration: config)
        let saved = try XCTUnwrap(
            realm.objects(PDFOptions.self)
                .filter("bookId == %@ AND libraryName == %@", book.id, book.library.name)
                .first
        )

        XCTAssertEqual(saved.toValue(), preferences)
    }

    func testSaveAndLoadPDFPreferencesRoundTrip() {
        let book = TestFixtures.makeBook()
        let preferences = PDFPreferenceValue(
            themeMode: .forest,
            selectedAutoScaler: .Width,
            pageMode: .Page,
            readingDirection: .LtR_TtB,
            scrollDirection: .Vertical,
            hMarginAutoScaler: 6,
            vMarginAutoScaler: 7,
            hMarginDetectStrength: 2,
            vMarginDetectStrength: 5,
            marginOffset: -1,
            lastScale: 2.1,
            rememberInPagePosition: true
        )

        repository.savePDFPreferences(preferences, for: book)

        XCTAssertEqual(repository.loadPDFPreferences(for: book), preferences)
    }

    func testFolioPreferencesSaveAndLoad() throws {
        let book = TestFixtures.makeBook()
        let prefs = ReaderEnginePreferences(
            themeMode: 3,
            fontSizePercentage: 120,
            fontFamily: "Georgia",
            lineHeight: 1.2,
            pageMargins: 1.0,
            scroll: true,
            scrollDirection: 1,
            volumeKeyPaging: false
        )

        repository.savePreferences(prefs, for: book, readerType: .YabrEPUB)

        let config = serverScopedProvider.configuration(for: book.library.server)
        let realm = try Realm(configuration: config)
        let saved = realm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: book.bookPrefId)

        XCTAssertEqual(saved?.nightMode, true)
        XCTAssertEqual(saved?.themeMode, 3)
        XCTAssertEqual(saved?.currentFontSize, "24px")
        XCTAssertEqual(saved?.currentFont, "Georgia")
        XCTAssertEqual(saved?.currentScrollDirection, 1)

        let loaded = repository.loadInitialPreferences(for: book, readerType: .YabrEPUB)
        XCTAssertEqual(loaded?.themeMode, 3)
        XCTAssertEqual(loaded?.fontSizePercentage, 120)
        XCTAssertEqual(loaded?.fontFamily, "Georgia")
        XCTAssertEqual(loaded?.scroll, true)
        XCTAssertEqual(loaded?.scrollDirection, 1)
    }

    func testFolioNativePreferencesSaveAndLoadRoundTripAllFields() throws {
        let book = TestFixtures.makeBook(id: 37)
        let preferences = makeFullFolioPreferenceValue()

        repository.saveFolioPreferences(preferences, for: book)

        XCTAssertEqual(repository.loadFolioPreferences(for: book), preferences)

        let config = serverScopedProvider.configuration(for: book.library.server)
        let realm = try Realm(configuration: config)
        let saved = try XCTUnwrap(realm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: book.bookPrefId))
        XCTAssertTrue(saved.hasCompletePreferenceValue)
        XCTAssertEqual(saved.toValue(defaults: .fallbackDefaults), preferences)
    }

    func testFolioCompatibilitySaveDoesNotBecomeFullNativePreferences() {
        let book = TestFixtures.makeBook(id: 38)

        repository.savePreferences(ReaderEnginePreferences(themeMode: 3), for: book, readerType: .YabrEPUB)

        XCTAssertNil(repository.loadFolioPreferences(for: book))
        XCTAssertEqual(repository.loadInitialPreferences(for: book, readerType: .YabrEPUB)?.themeMode, 3)
    }

    func testFolioGreenFallsBackToPDFAndReadiumNearestThemes() {
        let pdfBook = TestFixtures.makeBook(id: 30)
        let readiumBook = TestFixtures.makeBook(id: 31)

        repository.savePreferences(ReaderEnginePreferences(themeMode: 2), for: pdfBook, readerType: .YabrEPUB)
        repository.savePreferences(ReaderEnginePreferences(themeMode: 2), for: readiumBook, readerType: .YabrEPUB)

        XCTAssertEqual(repository.loadInitialPreferences(for: pdfBook, readerType: .YabrPDF)?.themeMode, 2)
        XCTAssertEqual(repository.loadInitialPreferences(for: readiumBook, readerType: .ReadiumEPUB)?.themeMode, 1)
    }

    func testFolioDarkAndNightFallbackToDarkInOtherEngines() {
        let readiumBook = TestFixtures.makeBook(id: 32)
        let pdfBook = TestFixtures.makeBook(id: 33)

        repository.savePreferences(ReaderEnginePreferences(themeMode: 3), for: readiumBook, readerType: .YabrEPUB)
        repository.savePreferences(ReaderEnginePreferences(themeMode: 4), for: pdfBook, readerType: .YabrEPUB)

        XCTAssertEqual(repository.loadInitialPreferences(for: readiumBook, readerType: .ReadiumEPUB)?.themeMode, 3)
        XCTAssertEqual(repository.loadInitialPreferences(for: pdfBook, readerType: .YabrPDF)?.themeMode, 3)
    }

    func testReadiumDarkFallsBackToFolioAsSharedDark() {
        let book = TestFixtures.makeBook(id: 34)

        repository.savePreferences(ReaderEnginePreferences(themeMode: 3), for: book, readerType: .ReadiumEPUB)

        let loaded = repository.loadInitialPreferences(for: book, readerType: .YabrEPUB)
        XCTAssertEqual(loaded?.themeMode, 3)
    }

    func testPDFForestFallsBackToFolioAsSharedGreen() {
        let book = TestFixtures.makeBook(id: 35)

        repository.savePDFPreferences(PDFPreferenceValue(themeMode: .forest), for: book)

        let loaded = repository.loadInitialPreferences(for: book, readerType: .YabrEPUB)
        XCTAssertEqual(loaded?.themeMode, 2)
    }

    func testTargetSpecificPreferencesWinOverFallbackPreferences() {
        let book = TestFixtures.makeBook(id: 36)

        repository.savePreferences(ReaderEnginePreferences(themeMode: 3), for: book, readerType: .YabrEPUB)
        repository.savePDFPreferences(PDFPreferenceValue(themeMode: .forest), for: book)

        let loaded = repository.loadInitialPreferences(for: book, readerType: .YabrPDF)
        XCTAssertEqual(loaded?.themeMode, 2)
    }

    func testNativeFolioPreferencesWinOverCrossEngineFallback() {
        let book = TestFixtures.makeBook(id: 39)
        let folioPreferences = makeFullFolioPreferenceValue(themeMode: 2, currentLineHeight: 9)

        repository.saveReadiumPreferences(ReadiumPreferenceValue(id: book.bookPrefId, themeMode: 2), for: book)
        repository.savePDFPreferences(PDFPreferenceValue(themeMode: .dark), for: book)
        repository.saveFolioPreferences(folioPreferences, for: book)

        let loaded = repository.loadInitialPreferences(for: book, readerType: .YabrEPUB)
        XCTAssertEqual(loaded?.themeMode, 2)
        XCTAssertEqual(loaded?.lineHeight ?? 0, 1.95, accuracy: 0.0001)
        XCTAssertEqual(loaded?.pageMargins ?? 0, 47.0 / 60.0, accuracy: 0.0001)
        XCTAssertEqual(repository.loadFolioPreferences(for: book)?.currentLineHeight, 9)
    }

    func testFolioNativeLayoutPrefsMapIntoCompatibleReaderPreferences() {
        let book = TestFixtures.makeBook(id: 41)
        let folioPreferences = makeFullFolioPreferenceValue(currentLineHeight: 6)

        repository.saveFolioPreferences(folioPreferences, for: book)

        let loaded = repository.loadInitialPreferences(for: book, readerType: .ReadiumEPUB)
        XCTAssertEqual(loaded?.lineHeight, 1.8)
        XCTAssertEqual(loaded?.pageMargins ?? 0, 47.0 / 60.0, accuracy: 0.0001)
    }

    func testSavePreferencesCreatesObjectsForAllSupportedReaderTypes() throws {
        let readiumBook = TestFixtures.makeBook(id: 1, library: TestFixtures.makeLibrary(server: TestFixtures.makeServer()))
        let pdfBook = TestFixtures.makeBook(id: 2, library: readiumBook.library)
        let folioBook = TestFixtures.makeBook(id: 3, library: readiumBook.library)

        repository.savePreferences(ReaderEnginePreferences(), for: readiumBook, readerType: .ReadiumCBZ)
        repository.savePreferences(ReaderEnginePreferences(themeMode: 2), for: pdfBook, readerType: .YabrPDF)
        repository.savePreferences(ReaderEnginePreferences(fontSizePercentage: 110), for: folioBook, readerType: .YabrEPUB)

        let config = serverScopedProvider.configuration(for: readiumBook.library.server)
        let realm = try Realm(configuration: config)

        XCTAssertNotNil(realm.object(ofType: ReadiumPreferenceRealm.self, forPrimaryKey: readiumBook.bookPrefId))
        XCTAssertNotNil(realm.objects(PDFOptions.self).filter("bookId == %@ AND libraryName == %@", pdfBook.id, pdfBook.library.name).first)
        XCTAssertNotNil(realm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: folioBook.bookPrefId))
    }

    func testLoadReadiumPreferencesReturnsNilWhenMissing() {
        let book = TestFixtures.makeBook()

        XCTAssertNil(repository.loadReadiumPreferences(for: book))
    }

    func testSaveReadiumPreferencesCreatesOrUpdatesRealmObject() throws {
        let book = TestFixtures.makeBook()
        let preferences = ReadiumPreferenceValue(
            id: book.bookPrefId,
            themeMode: 2,
            fontSizePercentage: 140,
            fontFamily: "Georgia",
            lineHeight: 1.45,
            pageMargins: 1.8,
            publisherStyles: false,
            scroll: true,
            textAlign: 4,
            columnCount: 2,
            fontWeight: 1.2,
            letterSpacing: 0.1,
            wordSpacing: 0.2,
            hyphens: true,
            imageFilter: 2,
            textNormalization: true,
            typeScale: 1.3,
            paragraphIndent: 0.3,
            paragraphSpacing: 0.4,
            volumeKeyPaging: true,
            verticalMargin: 20,
            readingProgression: 1,
            fit: 2,
            ligatures: true,
            offsetFirstPage: true,
            spread: 2,
            verticalText: true,
            pageSpacing: 8,
            scrollAxis: 1,
            visibleScrollbar: false
        )

        repository.saveReadiumPreferences(preferences, for: book)

        let config = serverScopedProvider.configuration(for: book.library.server)
        let realm = try Realm(configuration: config)
        let saved = try XCTUnwrap(realm.object(ofType: ReadiumPreferenceRealm.self, forPrimaryKey: book.bookPrefId))

        XCTAssertEqual(saved.toValue(), preferences)
    }

    func testSaveAndLoadReadiumPreferencesRoundTrip() {
        let book = TestFixtures.makeBook()
        let preferences = ReadiumPreferenceValue(
            id: book.bookPrefId,
            themeMode: 1,
            fontSizePercentage: 125,
            fontFamily: "Avenir",
            lineHeight: 1.35,
            pageMargins: 1.6,
            publisherStyles: true,
            scroll: false,
            textAlign: 2,
            columnCount: 1,
            fontWeight: 1.1,
            letterSpacing: 0.05,
            wordSpacing: 0.08,
            hyphens: false,
            imageFilter: 1,
            textNormalization: false,
            typeScale: 1.25,
            paragraphIndent: 0.2,
            paragraphSpacing: 0.25,
            volumeKeyPaging: true,
            verticalMargin: 16,
            readingProgression: 0,
            fit: 1,
            ligatures: false,
            offsetFirstPage: false,
            spread: 1,
            verticalText: false,
            pageSpacing: 4,
            scrollAxis: 0,
            visibleScrollbar: true
        )

        repository.saveReadiumPreferences(preferences, for: book)

        XCTAssertEqual(repository.loadReadiumPreferences(for: book), preferences)
    }

    func testReadiumCompatibilitySavePreservesReadiumOnlyFields() {
        let book = TestFixtures.makeBook(id: 40)
        let nativePreferences = ReadiumPreferenceValue(
            id: book.bookPrefId,
            themeMode: 1,
            fontSizePercentage: 125,
            fontFamily: "Avenir",
            lineHeight: 1.35,
            pageMargins: 1.6,
            publisherStyles: false,
            scroll: false,
            textAlign: 4,
            columnCount: 2,
            fontWeight: 1.2,
            letterSpacing: 0.1,
            wordSpacing: 0.2,
            hyphens: true,
            imageFilter: 2,
            textNormalization: true,
            typeScale: 1.3,
            paragraphIndent: 0.3,
            paragraphSpacing: 0.4,
            volumeKeyPaging: true,
            verticalMargin: 20,
            readingProgression: 1,
            fit: 2,
            ligatures: true,
            offsetFirstPage: true,
            spread: 2,
            verticalText: true,
            pageSpacing: 8,
            scrollAxis: 1,
            visibleScrollbar: false
        )

        repository.saveReadiumPreferences(nativePreferences, for: book)
        repository.savePreferences(
            ReaderEnginePreferences(themeMode: 3, fontSizePercentage: 150, fontFamily: "Georgia", scroll: true),
            for: book,
            readerType: .ReadiumEPUB
        )

        let loaded = repository.loadReadiumPreferences(for: book)
        XCTAssertEqual(loaded?.themeMode, 2)
        XCTAssertEqual(loaded?.fontSizePercentage, 150)
        XCTAssertEqual(loaded?.fontFamily, "Georgia")
        XCTAssertEqual(loaded?.publisherStyles, false)
        XCTAssertEqual(loaded?.textAlign, 4)
        XCTAssertEqual(loaded?.columnCount, 2)
        XCTAssertEqual(loaded?.fontWeight, 1.2)
        XCTAssertEqual(loaded?.letterSpacing, 0.1)
        XCTAssertEqual(loaded?.spread, 2)
        XCTAssertEqual(loaded?.pageSpacing, 8)
        XCTAssertEqual(loaded?.visibleScrollbar, false)
    }

    func testFolioProfileRepositoryEnsuresDefaultProfile() throws {
        let folioReader = FolioReader()
        let defaults = FolioReaderProfileValue(defaultsFrom: folioReader)

        folioProfileRepository.ensureDefaultProfile(defaults: defaults)

        let realm = try Realm(configuration: folioProfileConfig)
        let saved = try XCTUnwrap(realm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: "Default"))
        XCTAssertEqual(saved.toValue(defaults: defaults), defaults)
    }

    func testFolioProfileRepositorySaveLoadListAndRemove() {
        let folioReader = FolioReader()
        let defaults = FolioReaderProfileValue(defaultsFrom: folioReader)
        let custom = FolioReaderProfileValue(
            nightMode: true,
            themeMode: 2,
            currentFont: "Avenir",
            currentFontSize: "24px",
            currentFontWeight: "700",
            currentScrollDirection: 1,
            currentMarginTop: 21,
            currentMarginBottom: 22,
            currentMarginLeft: 23,
            currentMarginRight: 24,
            currentVMarginLinked: false,
            currentHMarginLinked: false,
            currentLetterSpacing: 7,
            currentLineHeight: 8,
            currentTextIndent: 9,
            doWrapPara: true,
            doClearClass: false
        )

        folioProfileRepository.saveProfile(custom, named: "DarkAvenir")

        XCTAssertEqual(folioProfileRepository.loadProfile(named: "DarkAvenir", defaults: defaults), custom)
        XCTAssertEqual(folioProfileRepository.listProfiles(filter: "Dark", defaults: defaults), ["DarkAvenir"])
        XCTAssertEqual(Set(folioProfileRepository.listProfiles(filter: nil, defaults: defaults)), Set(["Default", "DarkAvenir"]))

        folioProfileRepository.removeProfile(named: "DarkAvenir")
        XCTAssertEqual(folioProfileRepository.listProfiles(filter: nil, defaults: defaults), ["Default"])
    }

    func testFolioProfileRepositoryRecreatesDefaultAfterRemoval() {
        let folioReader = FolioReader()
        let defaults = FolioReaderProfileValue(defaultsFrom: folioReader)

        folioProfileRepository.ensureDefaultProfile(defaults: defaults)
        folioProfileRepository.removeProfile(named: "Default")

        XCTAssertEqual(folioProfileRepository.listProfiles(filter: nil, defaults: defaults), ["Default"])
    }

    private func makeFullFolioPreferenceValue(
        themeMode: Int = 4,
        currentLineHeight: Int = 8
    ) -> FolioReaderPreferenceValue {
        FolioReaderPreferenceValue(
            nightMode: themeMode >= 3,
            themeMode: themeMode,
            currentFont: "Avenir",
            currentFontSize: "24px",
            currentFontWeight: "700",
            currentAudioRate: 2,
            currentHighlightStyle: FolioReaderHighlightStyle.blue.rawValue,
            currentMediaOverlayStyle: MediaOverlayStyle.textColor.rawValue,
            currentScrollDirection: 2,
            currentNavigationMenuIndex: 1,
            currentAnnotationMenuIndex: 2,
            currentNavigationMenuBookListStyle: NavigationMenuBookListStyle.Grid.rawValue,
            currentMarginTop: 21,
            currentMarginBottom: 22,
            currentMarginLeft: 23,
            currentMarginRight: 24,
            currentVMarginLinked: false,
            currentHMarginLinked: false,
            currentLetterSpacing: 7,
            currentLineHeight: currentLineHeight,
            currentTextIndent: 9,
            doWrapPara: true,
            doClearClass: false,
            styleOverride: StyleOverrideTypes.AllText.rawValue,
            structuralStyle: FolioReaderStructuralStyle.bundle.rawValue,
            structuralTrackingTocLevel: FolioReaderPositionTrackingStyle.level2.rawValue
        )
    }
}
