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
import UIKit
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

    func testTestConfigurationDoesNotChangeProductionSchemaVersion() {
        let productionVersion = DatabaseSchema.version
        let previousConfiguration = Realm.Configuration.defaultConfiguration
        defer { Realm.Configuration.defaultConfiguration = previousConfiguration }
        let configuration = Realm.Configuration(
            inMemoryIdentifier: UUID().uuidString,
            schemaVersion: 1
        )

        databaseService.installTestConfiguration(configuration)

        XCTAssertEqual(databaseService.realmConf?.schemaVersion, 1)
        XCTAssertEqual(DatabaseSchema.version, productionVersion)
        XCTAssertGreaterThanOrEqual(DatabaseSchema.version, 148, "Do not downgrade databases opened by build 148")
        databaseService.installInitialDefaultConfiguration()
        XCTAssertEqual(databaseService.realmConf?.schemaVersion, DatabaseSchema.version)
    }

    /// Schemas 147 and 148 share the same Activity Log layout.
    func testProductionMigrationPreservesLegacyActivityAndOtherData() throws {
        let previousConfiguration = Realm.Configuration.defaultConfiguration
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DatabaseSchema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            databaseService.reset(clearConfiguration: true)
            Realm.Configuration.defaultConfiguration = previousConfiguration
            try? FileManager.default.removeItem(at: directory)
        }

        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let finishDate = startDate.addingTimeInterval(5)
        let request = ActivityLogRequestSnapshot(
            endpointURL: "http://calibre.local/ajax/books",
            httpMethod: "POST",
            httpBody: Data("payload".utf8),
            headers: [
                ActivityLogHeader(key: "X-Request", value: "request-id"),
                ActivityLogHeader(key: "Content-Type", value: "application/json")
            ]
        )
        let historicalID = ActivityID()
        let unfinishedID = ActivityID()
        for oldVersion: UInt64 in [147, 148] {
            let realmURL = directory.appendingPathComponent("\(oldVersion).realm")
            let oldConfiguration = Realm.Configuration(
                fileURL: realmURL,
                schemaVersion: oldVersion,
                objectTypes: [CalibreActivityLogEntryAtSchema148.self, FolioReaderPreferenceRealm.self]
            )
            try autoreleasepool {
                let realm = try Realm(configuration: oldConfiguration)
                // The Swift schema uses the fixture class name. _realmObjectName aliases the on-disk table.
                let schema = try XCTUnwrap(realm.schema[CalibreActivityLogEntryAtSchema148.className()])
                XCTAssertNotNil(schema["bookId"])
                XCTAssertNil(schema["bookIds"])
                XCTAssertNil(schema["status"])

                try realm.write {
                    let activity = CalibreActivityLogEntryAtSchema148()
                    activity.id = historicalID.rawValue
                    activity.type = "Get Book Metadata"
                    activity.startDatetime = startDate
                    activity.finishDatetime = finishDate
                    activity.bookId = 42
                    activity.libraryId = "library-A"
                    activity.endpoingURL = request.endpointURL
                    activity.httpMethod = request.httpMethod
                    activity.httpBody = request.httpBody
                    activity.requestHeaders.append(objectsIn: request.headers.flatMap { [$0.key, $0.value] })
                    activity.errMsg = "Success"
                    realm.add(activity)

                    let unfinished = CalibreActivityLogEntryAtSchema148()
                    unfinished.id = unfinishedID.rawValue
                    unfinished.type = "Library Summary"
                    unfinished.libraryId = "library-A"
                    unfinished.startDatetime = startDate
                    realm.add(unfinished)

                    let profile = FolioReaderPreferenceRealm()
                    profile.id = "Saved Profile"
                    profile.currentFont = "Avenir"
                    realm.add(profile)
                }
            }
            XCTAssertEqual(try schemaVersionAtURL(realmURL), oldVersion)

            try autoreleasepool {
                try databaseService.prepareProductionConfiguration(fileURL: realmURL) { _ in }
                let configuration = try XCTUnwrap(databaseService.realmConf)
                XCTAssertEqual(configuration.schemaVersion, DatabaseSchema.version)
                XCTAssertEqual(Realm.Configuration.defaultConfiguration.schemaVersion, DatabaseSchema.version)
                XCTAssertEqual(try schemaVersionAtURL(realmURL), DatabaseSchema.version)
                try databaseService.openMainRealm(conf: configuration)
                let realm = try XCTUnwrap(databaseService.realm)
                let profile = try XCTUnwrap(realm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: "Saved Profile"))
                XCTAssertEqual(profile.currentFont, "Avenir")

                let repository = RealmActivityLogRepository(
                    databaseService: databaseService, bookRepository: MockBookRepository(), container: nil
                )
                let bookEntries = repository.fetchTestSnapshots(libraryId: "library-A", bookId: 42, since: startDate)
                XCTAssertEqual(bookEntries.map(\.id), [historicalID])
                let legacy = try XCTUnwrap(bookEntries.first)
                XCTAssertEqual(legacy.startDatetime, startDate)
                XCTAssertEqual(legacy.finishDatetime, finishDate)
                XCTAssertEqual(legacy.bookIds, [42])
                XCTAssertEqual(legacy.request, request)
                XCTAssertEqual(legacy.legacyType, "Get Book Metadata")
                XCTAssertEqual(legacy.legacyResult, "Success")
                XCTAssertNil(legacy.kind)
                XCTAssertEqual(legacy.result, ActivityLogResult())
                XCTAssertEqual(legacy.state, .legacy)
                XCTAssertEqual(legacy.statusText, String(localized: "Legacy Entry"))

                let libraryEntries = repository.fetchTestSnapshots(libraryId: "library-A", bookId: nil, since: startDate)
                XCTAssertEqual(Set(libraryEntries.map(\.id)), [historicalID, unfinishedID])
                let unfinished = try XCTUnwrap(libraryEntries.first { $0.id == unfinishedID })
                XCTAssertEqual(unfinished.state, .legacy)
                XCTAssertTrue(unfinished.bookIds.isEmpty)
                XCTAssertNil(unfinished.legacyResult)
                XCTAssertNil(unfinished.finishDatetime)
            }
        }
    }

    func testSchema149KeepsTypedAndLegacyRowsWithoutRequestDiagnostics() throws {
        let previousConfiguration = Realm.Configuration.defaultConfiguration
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Activity149-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            databaseService.reset(clearConfiguration: true)
            Realm.Configuration.defaultConfiguration = previousConfiguration
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("activity.realm")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try autoreleasepool {
            let realm = try Realm(configuration: Realm.Configuration(
                fileURL: fileURL, schemaVersion: 149,
                objectTypes: [CalibreActivityLogEntryAtSchema149.self, FolioReaderPreferenceRealm.self]
            ))
            let schema = try XCTUnwrap(realm.schema[CalibreActivityLogEntryAtSchema149.className()])
            XCTAssertNotNil(schema["kind"])
            XCTAssertNil(schema["requestDiagnosticsData"])
            try realm.write {
                let typed = CalibreActivityLogEntryAtSchema149()
                typed.id = "typed"
                typed.kind = "batchMetadata"
                typed.status = "failed"
                typed.libraryId = "library"
                typed.bookIds.append(objectsIn: [1, 2])
                typed.startDatetime = date
                typed.finishDatetime = date.addingTimeInterval(1)
                typed.httpStatusCode = 403
                typed.errorCategory = "authentication"
                typed.resultDetail = "Refused"
                typed.endpoingURL = "https://calibre.local/ajax/books"
                realm.add(typed)

                let legacy = CalibreActivityLogEntryAtSchema149()
                legacy.id = "legacy"
                legacy.startDatetime = date
                legacy.errMsg = "Success"
                realm.add(legacy)

                let profile = FolioReaderPreferenceRealm()
                profile.id = "Saved AL1 Profile"
                profile.currentFont = "Avenir"
                realm.add(profile)
            }
        }
        XCTAssertEqual(try schemaVersionAtURL(fileURL), 149)
        try databaseService.prepareProductionConfiguration(fileURL: fileURL) { _ in }
        try databaseService.openMainRealm(conf: XCTUnwrap(databaseService.realmConf))
        XCTAssertEqual(try schemaVersionAtURL(fileURL), DatabaseSchema.version)

        let repository = RealmActivityLogRepository(
            databaseService: databaseService, bookRepository: MockBookRepository(), container: nil
        )
        let typed = try XCTUnwrap(repository.fetchTestSnapshots(libraryId: "library", bookId: 2, since: date).first)
        XCTAssertEqual(typed.id.rawValue, "typed")
        XCTAssertEqual(typed.kind, .batchMetadata)
        XCTAssertEqual(typed.state, .finished(.failed))
        XCTAssertEqual(typed.finishDatetime, date.addingTimeInterval(1))
        XCTAssertEqual(typed.request.endpointURL, "https://calibre.local/ajax/books")
        XCTAssertEqual(typed.result, ActivityLogResult(httpStatusCode: 403, errorCategory: .authentication, detail: "Refused"))
        let legacy = try XCTUnwrap(repository.fetchTestSnapshots(libraryId: nil, bookId: nil, since: date).first { $0.id.rawValue == "legacy" })
        XCTAssertEqual(legacy.state, .legacy)
        XCTAssertEqual(legacy.legacyResult, "Success")
        XCTAssertEqual(databaseService.realm?.object(ofType: FolioReaderPreferenceRealm.self,
                                                       forPrimaryKey: "Saved AL1 Profile")?.currentFont, "Avenir")
    }

    func testSchema150PreservesDiagnosticsAndRecoversUnownedTypedRows() async throws {
        let previousConfiguration = Realm.Configuration.defaultConfiguration
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Activity150-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            databaseService.reset(clearConfiguration: true)
            Realm.Configuration.defaultConfiguration = previousConfiguration
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("activity.realm")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let diagnostic = ActivityLogRequestDiagnostic(
            request: .init(endpointURL: "https://calibre.local/ajax/books", httpMethod: "GET", httpBody: nil, headers: []),
            responseURL: nil, httpStatusCode: 200, duration: 0.25
        )
        let requestData = try JSONEncoder().encode([diagnostic])
        try autoreleasepool {
            let realm = try Realm(configuration: Realm.Configuration(
                fileURL: fileURL, schemaVersion: 150,
                objectTypes: [CalibreActivityLogEntryAtSchema150.self, FolioReaderPreferenceRealm.self]
            ))
            let schema = try XCTUnwrap(realm.schema[CalibreActivityLogEntryAtSchema150.className()])
            XCTAssertNotNil(schema["requestDiagnosticsData"])
            XCTAssertNil(schema["ownerProcessID"])
            try realm.write {
                for (id, kind, status) in [("al2", "librarySummary", "succeeded"),
                                           ("running", "search", "running"), ("legacy", nil, "legacy")] {
                    let entry = CalibreActivityLogEntryAtSchema150()
                    entry.id = id
                    entry.kind = kind
                    entry.status = status
                    entry.startDatetime = date
                    if id == "al2" {
                        entry.finishDatetime = date.addingTimeInterval(1)
                        entry.requestDiagnosticsData = requestData
                    } else if id == "legacy" {
                        entry.errMsg = "OK"
                    }
                    realm.add(entry)
                }
                let profile = FolioReaderPreferenceRealm()
                profile.id = "Saved AL2 Profile"
                profile.currentFont = "Avenir"
                realm.add(profile)
            }
        }

        XCTAssertEqual(try schemaVersionAtURL(fileURL), 150)
        try databaseService.prepareProductionConfiguration(fileURL: fileURL) { _ in }
        try databaseService.openMainRealm(conf: XCTUnwrap(databaseService.realmConf))
        XCTAssertEqual(try schemaVersionAtURL(fileURL), 151)
        let repository = RealmActivityLogRepository(databaseService: databaseService,
                                                     bookRepository: MockBookRepository(), container: nil)
        let recoveredAt = date.addingTimeInterval(30)
        try await repository.writeActivityLogEvents([.recoverAndPrune(at: recoveredAt)])
        let entries = Dictionary(uniqueKeysWithValues: repository.fetchTestSnapshots(
            libraryId: nil, bookId: nil, since: date
        ).map { ($0.id.rawValue, $0) })
        XCTAssertEqual(entries["al2"]?.result.requests, [diagnostic])
        XCTAssertEqual(entries["al2"]?.state, .finished(.succeeded))
        XCTAssertEqual(entries["running"]?.state, .finished(.interrupted))
        XCTAssertEqual(entries["running"]?.finishDatetime, recoveredAt)
        XCTAssertEqual(entries["legacy"]?.state, .legacy)
        XCTAssertEqual(entries["legacy"]?.legacyResult, "OK")
        XCTAssertEqual(databaseService.realm?.object(ofType: FolioReaderPreferenceRealm.self,
                                                     forPrimaryKey: "Saved AL2 Profile")?.currentFont, "Avenir")
    }

    func testBackgroundFlushWaitsForLastSceneAndRunsOncePerTransition() async {
        let repository = MockActivityLogRepository()
        let logger = CalibreActivityLogger(repository: repository, flushDelayNanoseconds: 60_000_000_000)
        container.logger = logger
        let ended = expectation(description: "Background execution lease ended")
        let identifier = UIBackgroundTaskIdentifier(rawValue: 42)
        var starts = 0
        container.activityLogBackgroundFlush = ActivityLogBackgroundFlush(begin: { _ in
            starts += 1
            return identifier
        }, end: {
            XCTAssertEqual($0, identifier)
            ended.fulfill()
        })
        let first = UUID()
        let second = UUID()
        container.markAppSceneActive(id: first)
        container.markAppSceneActive(id: second)
        container.markAppSceneBackground(id: first)
        XCTAssertEqual(starts, 0)
        container.setActivityLogApplicationBackgrounded(true)
        XCTAssertEqual(starts, 0)
        container.markAppSceneBackground(id: second)
        XCTAssertEqual(starts, 1)
        await fulfillment(of: [ended], timeout: 5)
        container.setActivityLogApplicationBackgrounded(true)
        XCTAssertEqual(starts, 1)
        guard case .recoverAndPrune = repository.writeActivityLogBatches.last?.last else {
            return XCTFail("Expected a persisted background maintenance event")
        }
        container.setActivityLogApplicationBackgrounded(false)
    }

    func testBackgroundExpirationReleasesLeaseOnce() async {
        let identifier = UIBackgroundTaskIdentifier(rawValue: 43)
        var expiration: (() -> Void)?
        var releases = [UIBackgroundTaskIdentifier]()
        let coordinator = ActivityLogBackgroundFlush(begin: {
            expiration = $0
            return identifier
        }, end: { releases.append($0) })
        let started = expectation(description: "Flush work started")
        let completed = expectation(description: "Flush work returned")
        var releaseWork: AsyncStream<Void>.Continuation?
        let gate = AsyncStream<Void> { releaseWork = $0 }
        defer { releaseWork?.finish() }
        coordinator.setBackgrounded(true)
        coordinator.requestIfNeeded(hasActiveScenes: false) {
            started.fulfill()
            for await _ in gate {}
            completed.fulfill()
        }
        await fulfillment(of: [started], timeout: 5)
        expiration?()
        expiration?()
        releaseWork?.finish()
        await fulfillment(of: [completed], timeout: 5)
        XCTAssertEqual(releases, [identifier])
    }

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

/// The actual Activity Log table layout before AL1. Only this fixture opens it.
private final class CalibreActivityLogEntryAtSchema148: Object {
    override class func _realmIgnoreClass() -> Bool { true }
    override class func _realmObjectName() -> String { "CalibreActivityLogEntry" }

    @Persisted(primaryKey: true) var id = UUID().uuidString
    @Persisted var type: String?
    @Persisted var startDatetime = Date.distantPast
    @Persisted var finishDatetime: Date?
    @Persisted var bookId: Int32 = 0
    @Persisted var libraryId: String?
    @Persisted var endpoingURL: String?
    @Persisted var httpMethod: String?
    @Persisted var httpBody: Data?
    @Persisted var requestHeaders: List<String>
    @Persisted var errMsg: String?
}


// The AL1 table as shipped at schema 149.
private final class CalibreActivityLogEntryAtSchema149: Object {
    override class func _realmIgnoreClass() -> Bool { true }
    override class func _realmObjectName() -> String { "CalibreActivityLogEntry" }

    @Persisted(primaryKey: true) var id = UUID().uuidString
    @Persisted var kind: String?
    @Persisted var status = "legacy"
    @Persisted var progressRevision = 0

    @Persisted var startDatetime = Date.distantPast
    @Persisted var finishDatetime: Date?
    @Persisted var libraryId: String?
    @Persisted var bookIds: List<Int32>

    @Persisted var endpoingURL: String?
    @Persisted var httpMethod: String?
    @Persisted var httpBody: Data?
    @Persisted var requestHeaders: List<String> // Alternating keys and values.

    @Persisted var httpStatusCode: Int?
    @Persisted var errorCategory: String?
    @Persisted var resultDetail: String?

    // Historical type and result text. Keep these for reading old logs after the adapter is removed.
    @Persisted var type: String?
    @Persisted var errMsg: String?
}

// The AL2 table as shipped at schema 150.
private final class CalibreActivityLogEntryAtSchema150: Object {
    override class func _realmIgnoreClass() -> Bool { true }
    override class func _realmObjectName() -> String { "CalibreActivityLogEntry" }

    @Persisted(primaryKey: true) var id = UUID().uuidString
    @Persisted var kind: String?
    @Persisted var status = "legacy"
    @Persisted var progressRevision = 0

    @Persisted var startDatetime = Date.distantPast
    @Persisted var finishDatetime: Date?
    @Persisted var libraryId: String?
    @Persisted var bookIds: List<Int32>

    @Persisted var endpoingURL: String?
    @Persisted var httpMethod: String?
    @Persisted var httpBody: Data?
    @Persisted var requestHeaders: List<String> // Alternating keys and values.

    @Persisted var httpStatusCode: Int?
    @Persisted var errorCategory: String?
    @Persisted var resultDetail: String?
    @Persisted var requestDiagnosticsData: Data?

    // Historical type and result text. Keep these for reading old logs after the adapter is removed.
    @Persisted var type: String?
    @Persisted var errMsg: String?
}
