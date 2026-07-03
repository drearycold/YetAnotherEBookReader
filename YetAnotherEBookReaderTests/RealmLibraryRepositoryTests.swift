//
//  RealmLibraryRepositoryTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-24.
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

class MockServerResolver: ServerResolver {
    var resolvedServers: [String: CalibreServer] = [:]
    func server(forUUID uuid: String) -> CalibreServer? {
        return resolvedServers[uuid]
    }
}

@MainActor
final class RealmLibraryRepositoryTests: XCTestCase {
    private var databaseService: DatabaseService!
    private var repository: RealmLibraryRepository!
    private var realmConfig: Realm.Configuration!
    private var serverResolver: MockServerResolver!
    
    override func setUpWithError() throws {
        realmConfig = MockDatabaseService.inMemoryConfiguration()
        databaseService = DatabaseService.shared
        databaseService.setup(conf: realmConfig)
        serverResolver = MockServerResolver()
        repository = RealmLibraryRepository(databaseService: databaseService, serverResolver: serverResolver)
    }
    
    override func tearDownWithError() throws {
        databaseService = nil
        repository = nil
        realmConfig = nil
        serverResolver = nil
    }
    
    func testLibraryCRUD() throws {
        let server = TestFixtures.makeServer()
        serverResolver.resolvedServers[server.uuid.uuidString] = server
        
        let library = TestFixtures.makeLibrary(server: server, key: "lib_crud", name: "CRUD Library")
        
        // 1. Initially empty
        XCTAssertTrue(repository.getAllLibraries().isEmpty)
        
        // 2. Save
        try repository.saveLibrary(library)
        
        // 3. Fetch
        let allLibraries = repository.getAllLibraries()
        XCTAssertEqual(allLibraries.count, 1)
        XCTAssertEqual(allLibraries.first?.id, library.id)
        XCTAssertEqual(allLibraries.first?.name, "CRUD Library")
        XCTAssertEqual(allLibraries.first?.server.uuid, server.uuid)
        
        // 4. Update
        var updatedField = library
        updatedField.autoUpdate = true
        updatedField.discoverable = false
        updatedField.hidden = true
        try repository.saveLibrary(updatedField)
        
        let allUpdated = repository.getAllLibraries()
        XCTAssertEqual(allUpdated.count, 1)
        XCTAssertTrue(allUpdated.first?.autoUpdate ?? false)
        XCTAssertFalse(allUpdated.first?.discoverable ?? true)
        XCTAssertTrue(allUpdated.first?.hidden ?? false)
        
        // 5. Delete
        try repository.deleteLibrary(serverUUID: server.uuid.uuidString, name: library.name)
        XCTAssertTrue(repository.getAllLibraries().isEmpty)
    }
    
    func testCountBooks() throws {
        let server = TestFixtures.makeServer()
        serverResolver.resolvedServers[server.uuid.uuidString] = server
        let library = TestFixtures.makeLibrary(server: server, name: "Count Library")
        
        try repository.saveLibrary(library)
        XCTAssertEqual(repository.countBooks(for: library), 0)
        
        // Save some CalibreBookRealm records into Realm directly
        let realm = try Realm(configuration: realmConfig)
        try realm.write {
            let book1 = CalibreBookRealm()
            book1.serverUUID = server.uuid.uuidString
            book1.libraryName = library.name
            book1.idInLib = 1
            book1.title = "Book 1"
            book1.updatePrimaryKey()
            
            let book2 = CalibreBookRealm()
            book2.serverUUID = server.uuid.uuidString
            book2.libraryName = library.name
            book2.idInLib = 2
            book2.title = "Book 2"
            book2.updatePrimaryKey()
            
            realm.add([book1, book2])
        }
        
        XCTAssertEqual(repository.countBooks(for: library), 2)
    }

    func testObserveLibraryPublishesInitialRealmNotificationAndUpdates() async throws {
        let server = TestFixtures.makeServer()
        serverResolver.resolvedServers[server.uuid.uuidString] = server

        var library = TestFixtures.makeLibrary(server: server, key: "observe_lib", name: "Observe Library")
        library.discoverable = true
        library.autoUpdate = false
        try repository.saveLibrary(library)

        let initialExpectation = expectation(description: "Initial existing library observed")
        let updateExpectation = expectation(description: "Library update observed")
        var observedLibraries: [CalibreLibrary?] = []

        let task = Task { @MainActor [repository] in
            guard let repository else { return }
            for await observedLibrary in repository.observeLibrary(id: library.id) {
                observedLibraries.append(observedLibrary)
                if observedLibraries.count == 1 {
                    initialExpectation.fulfill()
                } else if observedLibraries.count >= 2 {
                    updateExpectation.fulfill()
                    break
                }
            }
        }

        await fulfillment(of: [initialExpectation], timeout: 2.0)
        try repository.updateLibraryFlags(id: library.id, discoverable: false, autoUpdate: true)

        await fulfillment(of: [updateExpectation], timeout: 2.0)
        task.cancel()

        XCTAssertEqual(observedLibraries.count, 2)
        XCTAssertEqual(observedLibraries[0]?.id, library.id)
        XCTAssertEqual(observedLibraries[0]?.discoverable, true)
        XCTAssertEqual(observedLibraries[0]?.autoUpdate, false)
        XCTAssertEqual(observedLibraries[1]?.id, library.id)
        XCTAssertEqual(observedLibraries[1]?.discoverable, false)
        XCTAssertEqual(observedLibraries[1]?.autoUpdate, true)
    }
}
