//
//  DatabaseBootstrapperTests.swift
//  YetAnotherEBookReaderTests
//
//  Created on 2026-06-25.
//
//  Regression coverage for the database bootstrap error path. Verifies
//  that `DatabaseBootstrapper.bootstrap` and `AppContainer.initializeDatabase`
//  surface failures to the caller instead of silently swallowing them
//  (see the AppContainer P1 / DatabaseBootstrapper P2 audit comments).
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
final class DatabaseBootstrapperTests: XCTestCase {
    private var container: AppContainer!
    private var databaseService: DatabaseService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = MockAppContainerFactory.makeContainer(testName: "DatabaseBootstrapperTests")
        databaseService = container.databaseService
    }

    override func tearDownWithError() throws {
        databaseService = nil
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Main Realm open failure

    /// The main Realm open inside `bootstrap` is a `do/try/catch/throw`
    /// against `DatabaseBootstrapError.realmOpenFailed`. A Realm
    /// configuration that targets a non-existent directory forces the
    /// open to fail, and that failure must propagate out of `bootstrap`.
    func testBootstrapRethrowsRealmOpenFailed() throws {
        let nonExistentDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DatabaseBootstrapperTests-\(UUID().uuidString)/nested")
        let badConfig = Realm.Configuration(
            fileURL: nonExistentDir.appendingPathComponent("missing.realm"),
            schemaVersion: 1,
            migrationBlock: { _, _ in }
        )

        let bootstrapper = DatabaseBootstrapper(container: container)

        XCTAssertThrowsError(
            try bootstrapper.bootstrap(realmConf: badConfig),
            "bootstrap must throw when the main Realm cannot be opened"
        ) { error in
            guard case DatabaseBootstrapError.realmOpenFailed = error else {
                XCTFail("Expected .realmOpenFailed, got \(error)")
                return
            }
        }
    }

    // MARK: - initializeDatabase rethrows

    /// `AppContainer.initializeDatabase` previously logged and swallowed
    /// any bootstrap error. It must now rethrow so `YetAnotherEBookReaderApp`
    /// can keep the upgrade overlay up and skip `enableProbeTimer()`.
    func testInitializeDatabaseRethrowsBootstrapErrors() throws {
        let nonExistentDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DatabaseBootstrapperTests-\(UUID().uuidString)/nested")
        let badConfig = Realm.Configuration(
            fileURL: nonExistentDir.appendingPathComponent("missing.realm"),
            schemaVersion: 1,
            migrationBlock: { _, _ in }
        )
        container.databaseService.configure(conf: badConfig)

        XCTAssertThrowsError(
            try container.initializeDatabase(),
            "initializeDatabase must rethrow when bootstrap fails"
        ) { error in
            guard case DatabaseBootstrapError.realmOpenFailed = error else {
                XCTFail("Expected .realmOpenFailed, got \(error)")
                return
            }
        }
    }

    // MARK: - Missing configuration

    /// `initializeDatabase` must throw `.realmConfigurationMissing` when
    /// called before the database runtime has a configuration.
    func testInitializeDatabaseThrowsWhenConfigurationMissing() {
        container.databaseService.reset(clearConfiguration: true)

        XCTAssertThrowsError(
            try container.initializeDatabase(),
            "initializeDatabase must throw when databaseService.realmConf is nil"
        ) { error in
            guard case DatabaseBootstrapError.realmConfigurationMissing = error else {
                XCTFail("Expected .realmConfigurationMissing, got \(error)")
                return
            }
        }
    }

    func testResetDatabaseBootstrapStateClearsPartialInitialization() throws {
        let config = MockDatabaseService.inMemoryConfiguration(identifier: "DatabaseBootstrapperTests-PartialState")
        let realm = try Realm(configuration: config)
        let metadataRealm = try Realm(configuration: config)

        container.databaseService.realm = realm
        container.databaseService.metadataRealm = metadataRealm
        let logger = CalibreActivityLogger(repository: container.activityLogRepository)
        container.logger = logger
        container.calibreServerService.logger = logger
        container.databaseService.configure(conf: config)

        XCTAssertTrue(container.isDatabaseReady)

        container.resetDatabaseBootstrapState(clearConfiguration: false)

        XCTAssertNil(container.databaseService.realm)
        XCTAssertNil(container.databaseService.metadataRealm)
        XCTAssertNil(container.logger)
        XCTAssertNotNil(container.databaseService.realmConf)
        XCTAssertFalse(container.isDatabaseReady)
    }

    // MARK: - Metadata Realm open failure
    //
    // The metadata-Realm error path is wired with the same
    // `do/try/catch/throw` pattern as the main Realm, and the
    // `.metadataRealmOpenFailed(underlying:)` case is reachable from the
    // same `bootstrap` entry point. We do not attempt a behavioural
    // test for this case because the metadata Realm uses the same
    // `Realm.Configuration` value as the main Realm and runs inside a
    // fixed `AppContainer.SaveBooksMetadataRealmQueue`; constructing a
    // configuration that opens on the main thread but fails on the
    // queue is not reliable. The error mapping and queue-bound
    // rethrow are verified by code review of `DatabaseBootstrapper.swift`.

    func testMigrationFrom140To141AppliesSearchIndexes() throws {
        let previousDefaultConfiguration = Realm.Configuration.defaultConfiguration
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DatabaseMigration-\(UUID().uuidString)", isDirectory: true)
        let realmURL = directory.appendingPathComponent("migration.realm")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            Realm.Configuration.defaultConfiguration = previousDefaultConfiguration
            try? FileManager.default.removeItem(at: directory)
        }

        var oldConfiguration = Realm.Configuration()
        oldConfiguration.fileURL = realmURL
        oldConfiguration.schemaVersion = 140
        try autoreleasepool {
            _ = try Realm(configuration: oldConfiguration)
        }
        XCTAssertEqual(try schemaVersionAtURL(realmURL), 140)

        let migrator = DatabaseMigrator()
        let config = try migrator.makeConfiguration(schemaVersion: 141, fileURL: realmURL) { _ in }
        let migratedRealm = try Realm(configuration: config)
        let searchSchema = try XCTUnwrap(
            migratedRealm.schema.objectSchema.first {
                $0.className == CalibreLibrarySearchObject.className()
            }
        )

        XCTAssertEqual(config.schemaVersion, 141)
        XCTAssertEqual(try schemaVersionAtURL(realmURL), 141)
        XCTAssertNil(config.migrationBlock)
        XCTAssertTrue(try XCTUnwrap(searchSchema["libraryId"]).isIndexed)
        XCTAssertTrue(try XCTUnwrap(searchSchema["search"]).isIndexed)
        XCTAssertTrue(try XCTUnwrap(searchSchema["sortAsc"]).isIndexed)
    }

    /// The "Default" Folio profile stored horizontal scrolling (2), which FolioReaderKit counts as the
    /// user's choice, so right-to-left books never paged. Schema 144 makes it "no choice"
    /// (.defaultVertical, 3) and leaves other profiles and other directions alone.
    func testMigrationTo144ResetsTheDefaultProfileScrollDirection() throws {
        let previousDefaultConfiguration = Realm.Configuration.defaultConfiguration
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DatabaseMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            Realm.Configuration.defaultConfiguration = previousDefaultConfiguration
            try? FileManager.default.removeItem(at: directory)
        }

        func migrated(_ rows: [String: Int]) throws -> [String: Int] {
            let realmURL = directory.appendingPathComponent("\(UUID().uuidString).realm")
            var oldConfiguration = Realm.Configuration()
            oldConfiguration.fileURL = realmURL
            oldConfiguration.schemaVersion = 143
            try autoreleasepool {
                let realm = try Realm(configuration: oldConfiguration)
                try realm.write {
                    for (id, direction) in rows {
                        let profile = FolioReaderPreferenceRealm()
                        profile.id = id
                        profile.currentScrollDirection = direction
                        realm.add(profile)
                    }
                }
            }
            let config = try DatabaseMigrator().makeConfiguration(schemaVersion: 144, fileURL: realmURL) { _ in }
            let realm = try Realm(configuration: config)
            return Dictionary(uniqueKeysWithValues: realm.objects(FolioReaderPreferenceRealm.self).map { ($0.id, $0.currentScrollDirection) })
        }

        XCTAssertEqual(try migrated(["Default": 2, "Night": 2]), ["Default": 3, "Night": 2])
        XCTAssertEqual(try migrated(["Default": 1]), ["Default": 1], "A paged default is a choice")
        XCTAssertEqual(try migrated(["Default": 0]), ["Default": 0], "So is vertical")
    }
}
