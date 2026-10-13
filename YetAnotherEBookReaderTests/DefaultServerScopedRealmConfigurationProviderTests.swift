import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

final class DefaultServerScopedRealmConfigurationProviderTests: XCTestCase {
    private var provider: DefaultServerScopedRealmConfigurationProvider!
    
    override func setUp() {
        super.setUp()
        provider = DefaultServerScopedRealmConfigurationProvider()
    }
    
    override func tearDown() {
        provider = nil
        super.tearDown()
    }
    
    func testConfigurationIsCachedAndConsistent() {
        let server = CalibreServer(
            uuid: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Server A",
            baseUrl: "http://localhost:8080",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        
        let config1 = provider.configuration(for: server)
        let config2 = provider.configuration(for: server)
        
        XCTAssertEqual(config1.fileURL, config2.fileURL)
        XCTAssertEqual(config1.schemaVersion, config2.schemaVersion)
        
        // Assert schema version matches the AppContainer constant
        XCTAssertEqual(config1.schemaVersion, DatabaseSchema.version)
    }
    
    /// Schema 142 had no `spreadMode`/`columnsMode`. A row saved then opens at 143
    /// with both reading Off and its other options kept.
    func testPDFOptionsSavedAtSchema142ReadReadingRegionsAsOff() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFOptionsMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let realmURL = directory.appendingPathComponent("server.realm")

        let oldConfiguration = Realm.Configuration(
            fileURL: realmURL,
            schemaVersion: 142,
            objectTypes: [PDFOptionsAtSchema142.self]
        )
        try autoreleasepool {
            let realm = try Realm(configuration: oldConfiguration)
            try realm.write {
                let row = PDFOptionsAtSchema142()
                row.bookId = 7
                row.libraryName = "Library"
                row.themeMode = "dark"
                row.readingDirection = "TtB_RtL"
                row.lastScale = 1.5
                realm.add(row)
            }
        }

        let server = CalibreServer(
            uuid: UUID(),
            name: "Migration",
            baseUrl: "http://localhost:8080",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        var configuration = provider.configuration(for: server)
        configuration.fileURL = realmURL
        configuration.schemaVersion = 143

        let realm = try Realm(configuration: configuration)
        let value = try XCTUnwrap(realm.objects(PDFOptions.self).first).toValue()
        XCTAssertEqual(value.spreadMode, .Off)
        XCTAssertEqual(value.columnsMode, .Off)
        XCTAssertEqual(value.themeMode, .dark)
        XCTAssertEqual(value.readingDirection, .TtB_RtL)
        XCTAssertEqual(value.lastScale, 1.5)
    }

    /// Schema 144 had no `currentLandscapeSpread`. A book's Folio preferences saved then open at
    /// 145 with no landscape spread choice and their other preferences kept.
    func testFolioPreferencesSavedAtSchema144HaveNoLandscapeSpreadChoice() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolioPreferenceMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let realmURL = directory.appendingPathComponent("server.realm")

        let oldConfiguration = Realm.Configuration(
            fileURL: realmURL,
            schemaVersion: 144,
            objectTypes: [FolioReaderPreferenceRealmAtSchema144.self]
        )
        try autoreleasepool {
            let realm = try Realm(configuration: oldConfiguration)
            try realm.write {
                let row = FolioReaderPreferenceRealmAtSchema144()
                row.id = "book-7"
                row.currentFont = "Avenir"
                row.currentScrollDirection = 1
                row.currentMarginLeft = 23
                realm.add(row)
            }
        }

        let server = CalibreServer(
            uuid: UUID(),
            name: "Migration",
            baseUrl: "http://localhost:8080",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        var configuration = provider.configuration(for: server)
        configuration.fileURL = realmURL
        configuration.schemaVersion = 145

        let realm = try Realm(configuration: configuration)
        let row = try XCTUnwrap(realm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: "book-7"))
        XCTAssertNil(row.currentLandscapeSpread.value)
        let value = row.toValue(defaults: .fallbackDefaults)
        XCTAssertNil(value.currentLandscapeSpread)
        XCTAssertEqual(value.currentFont, "Avenir")
        XCTAssertEqual(value.currentScrollDirection, 1)
        XCTAssertEqual(value.currentMarginLeft, 23)
    }

    func testDifferentServersHaveDifferentConfigurations() {
        let serverA = CalibreServer(
            uuid: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Server A",
            baseUrl: "http://localhost:8080",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        let serverB = CalibreServer(
            uuid: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            name: "Server B",
            baseUrl: "http://localhost:9090",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        
        let configA = provider.configuration(for: serverA)
        let configB = provider.configuration(for: serverB)
        
        XCTAssertNotEqual(configA.fileURL, configB.fileURL)
        XCTAssertTrue(configA.fileURL?.lastPathComponent.contains("11111111-2222-3333-4444-555555555555") ?? false)
        XCTAssertTrue(configB.fileURL?.lastPathComponent.contains("99999999-8888-7777-6666-555555555555") ?? false)
    }
    
    func testConcurrentConfigurationAccess() {
        let server = CalibreServer(
            uuid: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Server A",
            baseUrl: "http://localhost:8080",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        
        let expectation = self.expectation(description: "Concurrent config loading completed")
        expectation.expectedFulfillmentCount = 20
        
        var results = [Realm.Configuration]()
        let resultsLock = NSLock()
        
        for _ in 0..<20 {
            DispatchQueue.global().async {
                let config = self.provider.configuration(for: server)
                resultsLock.lock()
                results.append(config)
                resultsLock.unlock()
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 5, handler: nil)
        
        XCTAssertEqual(results.count, 20)
        for config in results {
            XCTAssertEqual(config.fileURL, results[0].fileURL)
            XCTAssertEqual(config.schemaVersion, results[0].schemaVersion)
        }
    }
}

/// `PDFOptions` as stored at schema 142, before `spreadMode` and `columnsMode`.
/// Kept out of the default schema; only the migration test opens it.
final class PDFOptionsAtSchema142: Object {
    override class func _realmIgnoreClass() -> Bool { true }
    override class func _realmObjectName() -> String { "PDFOptions" }

    @Persisted(primaryKey: true) var _id: ObjectId
    @Persisted var bookId: Int32 = 0
    @Persisted var libraryName = ""
    @Persisted var themeMode = "serpia"
    @Persisted var selectedAutoScaler = "Width"
    @Persisted var pageMode = "Page"
    @Persisted var readingDirection = "LtR_TtB"
    @Persisted var scrollDirection = "Vertical"
    @Persisted var hMarginAutoScaler = 5.0
    @Persisted var vMarginAutoScaler = 5.0
    @Persisted var hMarginDetectStrength = 2.0
    @Persisted var vMarginDetectStrength = 2.0
    @Persisted var marginOffset = 0.0
    @Persisted var lastScale = 1.0
    @Persisted var rememberInPagePosition = true
}

/// `FolioReaderPreferenceRealm` as stored at schema 144, before `currentLandscapeSpread`.
/// Kept out of the default schema; only the migration test opens it.
final class FolioReaderPreferenceRealmAtSchema144: Object {
    override class func _realmIgnoreClass() -> Bool { true }
    override class func _realmObjectName() -> String { "FolioReaderPreferenceRealm" }

    @Persisted(primaryKey: true) var id = ""
    @Persisted var nightMode = false
    @Persisted var themeMode: Int = .min
    @Persisted var currentFont: String?
    @Persisted var currentFontSize: String?
    @Persisted var currentFontWeight: String?
    @Persisted var currentAudioRate: Int = .min
    @Persisted var currentHighlightStyle: Int = .min
    @Persisted var currentMediaOverlayStyle: Int = .min
    @Persisted var currentScrollDirection: Int = .min
    @Persisted var currentNavigationMenuIndex: Int = .min
    @Persisted var currentAnnotationMenuIndex: Int = .min
    @Persisted var currentNavigationMenuBookListStyle: Int = .min
    @Persisted var currentVMarginLinked = true
    @Persisted var currentMarginTop: Int = .min
    @Persisted var currentMarginBottom: Int = .min
    @Persisted var currentHMarginLinked = true
    @Persisted var currentMarginLeft: Int = .min
    @Persisted var currentMarginRight: Int = .min
    @Persisted var currentLetterSpacing: Int = .min
    @Persisted var currentLineHeight: Int = .min
    @Persisted var currentTextIndent: Int = .min
    @Persisted var doWrapPara = false
    @Persisted var doClearClass = true
    @Persisted var styleOverride: Int = .min
    @Persisted var structuralStyle = 0
    @Persisted var structuralTrackingTocLevel = 0
}
