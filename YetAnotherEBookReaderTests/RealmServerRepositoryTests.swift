//
//  RealmServerRepositoryTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-24.
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
final class RealmServerRepositoryTests: XCTestCase {
    private var databaseService: DatabaseService!
    private var repository: RealmServerRepository!
    private var realmConfig: Realm.Configuration!
    
    override func setUpWithError() throws {
        // Unique in-memory configuration per test
        realmConfig = MockDatabaseService.inMemoryConfiguration()
        databaseService = DatabaseService.shared
        databaseService.setup(conf: realmConfig)
        repository = RealmServerRepository(databaseService: databaseService)
    }
    
    override func tearDownWithError() throws {
        databaseService = nil
        repository = nil
        realmConfig = nil
    }
    
    func testServerCRUD() throws {
        let server = TestFixtures.makeServer(name: "CRUD Server", baseUrl: "http://localhost/crud")
        
        // 1. Initially empty
        XCTAssertTrue(repository.getAllServers().isEmpty)
        
        // 2. Save
        try repository.saveServer(server)
        
        // 3. Fetch
        let allServers = repository.getAllServers()
        XCTAssertEqual(allServers.count, 1)
        XCTAssertEqual(allServers.first?.uuid, server.uuid)
        XCTAssertEqual(allServers.first?.name, "CRUD Server")
        XCTAssertEqual(allServers.first?.baseUrl, "http://localhost/crud")
        
        // 4. Update
        var updated = server
        updated.name = "Updated CRUD Server"
        updated.baseUrl = "http://localhost/updated"
        try repository.saveServer(updated)
        
        let allUpdated = repository.getAllServers()
        XCTAssertEqual(allUpdated.count, 1)
        XCTAssertEqual(allUpdated.first?.name, "Updated CRUD Server")
        XCTAssertEqual(allUpdated.first?.baseUrl, "http://localhost/updated")
        
        // 5. Delete
        try repository.deleteServer(id: server.id)
        XCTAssertTrue(repository.getAllServers().isEmpty)
    }

    func testServerSaveFailsBeforeDatabaseIsReady() {
        let unopened = RealmServerRepository(databaseService: DatabaseService())
        XCTAssertThrowsError(try unopened.saveServer(TestFixtures.makeServer()))
    }

    func testSavingHelperForMissingServerFails() {
        XCTAssertThrowsError(try repository.saveDSReaderHelper(.init(port: 8081), for: UUID().uuidString))
    }

    func testInsertIsAtomicWhenAnInitialLibraryConflicts() throws {
        let server = TestFixtures.makeServer()
        let library = CalibreLibrary(server: server, key: "existing", name: "Existing")
        let fresh = CalibreLibrary(server: server, key: "fresh", name: "Fresh")
        let realm = try XCTUnwrap(databaseService.realm)
        try realm.write { realm.add(library.makeRealmObject()) }

        XCTAssertThrowsError(try repository.insertServer(server, libraries: [fresh, library], helper: .init(port: 8081)))
        XCTAssertTrue(repository.getAllServers().isEmpty)
        XCTAssertNil(realm.object(ofType: CalibreLibraryRealm.self, forPrimaryKey: fresh.id))
        XCTAssertNil(repository.getDSReaderHelper(for: server.id))
    }

    func testConditionalEditAndRemovalPreserveEmbeddedHelperAndRejectStaleTargets() throws {
        let server = TestFixtures.makeServer(baseUrl: "http://old:8080")
        let library = CalibreLibrary(server: server, key: "books", name: "Books")
        let helper = CalibreServerDSReaderHelper(port: 8081, configurationData: Data([1, 2, 3]))
        try repository.insertServer(server, libraries: [library], helper: helper)
        var updated = server
        updated.baseUrl = "http://new:8080"
        updated.hasAuth = true
        updated.password = "updated"
        try repository.updateServer(updated, ifCurrent: server)
        XCTAssertEqual(repository.getAllServers().first?.password, "updated")
        XCTAssertEqual(repository.getDSReaderHelper(for: server.id), helper)
        XCTAssertThrowsError(try repository.removeServerConfiguration(ifCurrent: server))

        try repository.removeServerConfiguration(ifCurrent: updated)
        XCTAssertTrue(repository.getAllServers().first?.removed == true)
        XCTAssertThrowsError(try repository.updateServer(updated, ifCurrent: updated))
        XCTAssertThrowsError(try repository.saveServer(updated))
        let realm = try XCTUnwrap(databaseService.realm)
        XCTAssertNil(realm.object(ofType: CalibreLibraryRealm.self, forPrimaryKey: library.id))
    }
    
    func testDSReaderHelperCRUD() throws {
        let server = TestFixtures.makeServer(name: "DSR Server")
        try repository.saveServer(server)
        
        // 1. Query initially empty
        XCTAssertNil(repository.getDSReaderHelper(for: server.id))
        
        // 2. Save helper
        let helper = CalibreServerDSReaderHelper(port: 1234)
        try repository.saveDSReaderHelper(helper, for: server.id)
        
        // 3. Get helper
        let retrieved = repository.getDSReaderHelper(for: server.id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.port, 1234)
        
        // 4. Update helper
        let updatedHelper = CalibreServerDSReaderHelper(port: 5678)
        try repository.saveDSReaderHelper(updatedHelper, for: server.id)
        
        let retrievedUpdated = repository.getDSReaderHelper(for: server.id)
        XCTAssertEqual(retrievedUpdated?.port, 5678)
    }

    func testDSReaderHelperRealmMapperPreservesSchemaClassName() throws {
        XCTAssertEqual(CalibreServerDSReaderHelperRealm.className(), "CalibreServerDSReaderHelper")

        var helper = CalibreServerDSReaderHelper(port: 9090)
        helper.configuration = CalibreDSReaderHelperConfiguration(
            dsreader_helper_prefs: CalibreDSReaderHelperPrefs(
                plugin_prefs: .init(Options: .init())
            )
        )

        let realmObject = CalibreServerDSReaderHelperRealm(value: helper)
        let value = realmObject.toValue()

        XCTAssertEqual(value.port, 9090)
        XCTAssertEqual(value.configurationData, helper.configurationData)
        XCTAssertNotNil(value.configuration?.dsreader_helper_prefs)
    }

    func testConditionalHelperWritePreservesNewerConfigurationAndRejectsRemovedServer() throws {
        var server = TestFixtures.makeServer()
        let first = CalibreServerDSReaderHelper(port: 8080)
        let second = CalibreServerDSReaderHelper(port: 8081)
        let stale = CalibreServerDSReaderHelper(port: 8082)
        try repository.saveServer(server)
        let unconfigured = try XCTUnwrap(repository.getDSReaderHelperStoredConfiguration(for: server.id))
        XCTAssertTrue(try repository.replaceDSReaderHelper(first, ifCurrent: unconfigured))
        XCTAssertFalse(try repository.replaceDSReaderHelper(stale, ifCurrent: unconfigured))

        let configured = try XCTUnwrap(repository.getDSReaderHelperStoredConfiguration(for: server.id))
        XCTAssertTrue(try repository.replaceDSReaderHelper(second, ifCurrent: configured))
        let current = try XCTUnwrap(repository.getDSReaderHelperStoredConfiguration(for: server.id))
        server.password = "replacement credentials"
        try repository.saveServer(server)
        XCTAssertFalse(try repository.replaceDSReaderHelper(stale, ifCurrent: current))
        XCTAssertEqual(repository.getDSReaderHelper(for: server.id), second)

        let updated = try XCTUnwrap(repository.getDSReaderHelperStoredConfiguration(for: server.id))
        server.removed = true
        try repository.saveServer(server)
        XCTAssertNil(repository.getDSReaderHelperStoredConfiguration(for: server.id))
        XCTAssertFalse(try repository.replaceDSReaderHelper(stale, ifCurrent: updated))
        XCTAssertEqual(repository.getDSReaderHelper(for: server.id), second)
    }
}
