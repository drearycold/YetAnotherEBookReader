//
//  RealmReadingPositionRepositoryTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-24.
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

final class RealmReadingPositionRepositoryTests: XCTestCase {
    private var databaseService: DatabaseService!
    private var repository: RealmReadingPositionRepository!
    private var realmConfig: Realm.Configuration!
    
    override func setUpWithError() throws {
        realmConfig = MockDatabaseService.inMemoryConfiguration()
        databaseService = DatabaseService.shared
        databaseService.setup(conf: realmConfig)
        repository = RealmReadingPositionRepository(databaseService: databaseService)
    }
    
    override func tearDownWithError() throws {
        databaseService = nil
        repository = nil
        realmConfig = nil
    }
    
    @MainActor
    func testSaveAndGetPosition() throws {
        let bookId = "pos^test_lib@server-uuid"
        let position = TestFixtures.makeReadingPosition(id: "device-1", lastReadPage: 15, epoch: 1000.0)
        
        // 1. Get position initially empty
        XCTAssertNil(repository.getPosition(forBookId: bookId, policy: .latestForDevice("device-1")))
        
        // 2. Save
        repository.savePosition(position, forBookId: bookId)
        
        // 3. Get
        let fetched = try XCTUnwrap(repository.getPosition(forBookId: bookId, policy: .latestForDevice("device-1")))
        XCTAssertEqual(fetched.id, "device-1")
        XCTAssertEqual(fetched.lastReadPage, 15)
        XCTAssertEqual(fetched.epoch, 1000.0)
    }
    
    @MainActor
    func testGetPositions() throws {
        let bookId = "pos^test_lib@server-uuid"
        let pos1 = TestFixtures.makeReadingPosition(id: "device-1", epoch: 1000.0)
        let pos2 = TestFixtures.makeReadingPosition(id: "device-2", epoch: 2000.0)
        
        repository.savePosition(pos1, forBookId: bookId)
        repository.savePosition(pos2, forBookId: bookId)
        
        let allPositions = repository.getPositions(forBookId: bookId)
        XCTAssertEqual(allPositions.count, 2)
        // sorted by epoch descending
        XCTAssertEqual(allPositions.first?.id, "device-2")
        XCTAssertEqual(allPositions.last?.id, "device-1")
    }
    
    @MainActor
    func testRemovePosition() throws {
        let bookId = "pos^test_lib@server-uuid"
        let pos1 = TestFixtures.makeReadingPosition(id: "device-1", epoch: 1000.0)
        
        let olderPos = TestFixtures.makeReadingPosition(id: "device-2", epoch: 1000.0)
        let newerPos = TestFixtures.makeReadingPosition(id: "device-2", epoch: 2000.0)
        
        repository.savePosition(pos1, forBookId: bookId)
        repository.savePosition(olderPos, forBookId: bookId)
        
        // 1. Remove by device name
        repository.removePosition(deviceName: "device-1", forBookId: bookId)
        XCTAssertEqual(repository.getPositions(forBookId: bookId).count, 1)
        XCTAssertNil(repository.getPosition(forBookId: bookId, policy: .latestForDevice("device-1")))
        
        // 2. Remove by position object
        repository.removePosition(position: newerPos, forBookId: bookId)
        
        let positionsAfter = repository.getPositions(forBookId: bookId)
        XCTAssertTrue(positionsAfter.isEmpty)
    }
    
    @MainActor
    func testSessionStartAndEnd() throws {
        let bookId = "session^test_lib@server-uuid"
        let pos = TestFixtures.makeReadingPosition(id: "device-1", lastReadPage: 5, epoch: 500.0)
        
        // 1. Start Session
        let startDate = repository.session(start: pos, forBookId: bookId)
        XCTAssertNotNil(startDate)
        
        let sessionsInitially = repository.sessions(forBookId: bookId, list: nil)
        // Note: sessions() returns only those with endPosition != nil
        XCTAssertTrue(sessionsInitially.isEmpty)
        
        // 2. End Session
        let endPos = TestFixtures.makeReadingPosition(id: "device-1", lastReadPage: 25, epoch: 1500.0)
        repository.session(end: endPos, forBookId: bookId)
        
        // 3. Fetch Session
        let sessions = repository.sessions(forBookId: bookId, list: nil)
        XCTAssertEqual(sessions.count, 1)
        let firstSession = try XCTUnwrap(sessions.first)
        let startPosition = try XCTUnwrap(firstSession.startPosition)
        let endPosition = try XCTUnwrap(firstSession.endPosition)
        XCTAssertEqual(startPosition.lastReadPage, 5)
        XCTAssertEqual(endPosition.lastReadPage, 25)
    }
    
    @MainActor
    func testSyncPositions() throws {
        let bookId = "sync^test_lib@server-uuid"
        
        // Local position
        let localPos = TestFixtures.makeReadingPosition(id: "iPad", lastReadPage: 10, epoch: 1000.0)
        repository.savePosition(localPos, forBookId: bookId)
        
        let remotePosIPad = TestFixtures.makeReadingPosition(id: "iPad", lastReadPage: 12, epoch: 2000.0)
        let remotePosIPhone = TestFixtures.makeReadingPosition(id: "iPhone", lastReadPage: 20, epoch: 1500.0)
        let remotePosIPadOld = TestFixtures.makeReadingPosition(id: "iPad", lastReadPage: 4, epoch: 500.0)
        
        let entries = [
            remotePosIPad.toEntry(),
            remotePosIPhone.toEntry(),
            remotePosIPadOld.toEntry()
        ]
        
        let tasks = repository.syncPositions(entries: entries, forBookId: bookId)
        
        // Verify local state
        let ipadPos = try XCTUnwrap(repository.getPosition(forBookId: bookId, policy: .latestForDevice("iPad")))
        XCTAssertEqual(ipadPos.lastReadPage, 12)
        XCTAssertEqual(ipadPos.epoch, 2000.0)
        
        let iphonePos = try XCTUnwrap(repository.getPosition(forBookId: bookId, policy: .latestForDevice("iPhone")))
        XCTAssertEqual(iphonePos.lastReadPage, 20)
        XCTAssertEqual(iphonePos.epoch, 1500.0)
        
        // tasks returns entries for local devices that have newer positions not present or older on server
        // since iPad remote was newer, iPad remote updated local.
        // iPhone was new, iPhone remote added to local.
        // So no local positions were newer than remote. tasks should be empty.
        XCTAssertTrue(tasks.isEmpty)
    }
    
    func testReadingPositionThreading() throws {
        // Use a bookId that does not contain '@' or '^' to avoid accessing actor-isolated AppContainer.shared from background thread
        let bookId = "thread_test_book"
        let repo = repository!
        
        let expectation = self.expectation(description: "Background writes completed")
        expectation.expectedFulfillmentCount = 5
        
        for i in 1...5 {
            // Use default QoS queue to avoid simulator thread throttling
            DispatchQueue.global().async {
                let position = TestFixtures.makeReadingPosition(
                    id: "device-\(i)",
                    epoch: Double(1000 + i)
                )
                repo.savePosition(position, forBookId: bookId)
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 5.0)
        
        // On main thread, verify we can retrieve them all
        let positions = repo.getPositions(forBookId: bookId)
        XCTAssertEqual(positions.count, 5)
        let ids = Set(positions.map { $0.id })
        XCTAssertEqual(ids, Set(["device-1", "device-2", "device-3", "device-4", "device-5"]))
    }
}
