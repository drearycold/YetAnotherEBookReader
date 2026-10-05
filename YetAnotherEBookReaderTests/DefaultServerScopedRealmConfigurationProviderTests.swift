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
