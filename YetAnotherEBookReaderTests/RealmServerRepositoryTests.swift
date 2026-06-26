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
}
