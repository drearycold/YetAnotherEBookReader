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
    /// can keep the upgrade overlay up and skip `enableProbeTimer()` /
    /// `publishBookReaderActivity(.active)`.
    func testInitializeDatabaseRethrowsBootstrapErrors() throws {
        let nonExistentDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DatabaseBootstrapperTests-\(UUID().uuidString)/nested")
        let badConfig = Realm.Configuration(
            fileURL: nonExistentDir.appendingPathComponent("missing.realm"),
            schemaVersion: 1,
            migrationBlock: { _, _ in }
        )
        container.realmConf = badConfig

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
    /// called before `tryInitializeDatabase` populated the configuration.
    func testInitializeDatabaseThrowsWhenConfigurationMissing() {
        container.realmConf = nil

        XCTAssertThrowsError(
            try container.initializeDatabase(),
            "initializeDatabase must throw when container.realmConf is nil"
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

        container.realm = realm
        container.realmSaveBooksMetadata = metadataRealm
        let logger = CalibreActivityLogger(realmConf: config)
        container.logger = logger
        container.calibreServerService.logger = logger
        container.databaseService.setup(conf: config)

        XCTAssertTrue(container.isDatabaseReady)

        container.resetDatabaseBootstrapState(clearConfiguration: false)

        XCTAssertNil(container.realm)
        XCTAssertNil(container.realmSaveBooksMetadata)
        XCTAssertNil(container.logger)
        XCTAssertNil(container.databaseService.realm)
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
}
