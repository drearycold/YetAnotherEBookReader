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
        databaseService = DatabaseService()
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
        let handle = try XCTUnwrap(repository.beginSession(at: pos, forBookId: bookId))
        XCTAssertEqual(handle.bookId, bookId)
        
        let sessionsInitially = repository.sessions(forBookId: bookId, list: nil)
        // Note: sessions() returns only those with endPosition != nil
        XCTAssertTrue(sessionsInitially.isEmpty)
        
        // 2. End Session
        let endPos = TestFixtures.makeReadingPosition(id: "device-1", lastReadPage: 25, epoch: 1500.0)
        repository.endSession(handle, at: endPos)
        
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
    func testSessionReuseWindow() throws {
        let bookId = "session_reuse^test_lib@server-uuid"
        let pos = TestFixtures.makeReadingPosition(id: "device-1", lastReadPage: 5, epoch: 500.0)
        
        // 1. First session
        let handle1 = try XCTUnwrap(repository.beginSession(at: pos, forBookId: bookId))
        
        // 2. Immediate beginSession when end is nil (should reuse since < 300s)
        let handle2 = try XCTUnwrap(repository.beginSession(at: pos, forBookId: bookId))
        XCTAssertEqual(handle1, handle2)
        
        // 3. End session
        let endPos = TestFixtures.makeReadingPosition(id: "device-1", lastReadPage: 25, epoch: Date().timeIntervalSince1970)
        repository.endSession(handle1, at: endPos)
        
        // 4. Begin session again (should reuse since end epoch is less than 60s ago)
        let handle3 = try XCTUnwrap(repository.beginSession(at: pos, forBookId: bookId))
        XCTAssertEqual(handle1, handle3)
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
    
    @MainActor
    func testSyncPositionsLinearizationSpecialCases() throws {
        let bookId = "linear_sync^test_lib@server-uuid"
        
        // 1. Setup local position
        let localIPad = TestFixtures.makeReadingPosition(id: "iPad", readerName: "YabrEPUB", lastReadPage: 10, epoch: 1000.0)
        repository.savePosition(localIPad, forBookId: bookId)
        
        // 2. Setup local position for iPhone (which will be newer than its remote)
        let localIPhone = TestFixtures.makeReadingPosition(id: "iPhone", readerName: "YabrPDF", lastReadPage: 2, epoch: 1200.0)
        repository.savePosition(localIPhone, forBookId: bookId)
        
        // 3. Prepare sync entries:
        // - remoteIPadEPUBNewer: newer epoch for iPad identity -> should update
        // - remoteIPhoneOlder: older epoch for iPhone identity -> should trigger local upload tasks
        // - remoteNewDevice: new device -> should insert
        // - duplicateNewDevice: duplicate entry in same sync list -> should deduplicate
        let remoteIPadEPUBNewer = TestFixtures.makeReadingPosition(id: "iPad", readerName: "YabrEPUB", lastReadPage: 15, epoch: 1500.0)
        let remoteIPhoneOlder = TestFixtures.makeReadingPosition(id: "iPhone", readerName: "YabrPDF", lastReadPage: 1, epoch: 800.0)
        let remoteNewDevice = TestFixtures.makeReadingPosition(id: "Kindle", readerName: "YabrEPUB", lastReadPage: 50, epoch: 3000.0)
        let duplicateNewDevice = TestFixtures.makeReadingPosition(id: "Kindle", readerName: "YabrEPUB", lastReadPage: 55, epoch: 3100.0)
        
        let entries = [
            remoteIPadEPUBNewer.toEntry(),
            remoteIPhoneOlder.toEntry(),
            remoteNewDevice.toEntry(),
            duplicateNewDevice.toEntry()
        ]
        
        let tasks = repository.syncPositions(entries: entries, forBookId: bookId)
        
        // Verify iPad EPUB was updated to newer remote epoch
        let epubPos = try XCTUnwrap(repository.getPosition(forBookId: bookId, policy: .latestForDevice("iPad")))
        XCTAssertEqual(epubPos.lastReadPage, 15)
        XCTAssertEqual(epubPos.epoch, 1500.0)
        
        // Verify Kindle has the newest deduplicated state
        let kindlePos = try XCTUnwrap(repository.getPosition(forBookId: bookId, policy: .latestForDevice("Kindle")))
        XCTAssertEqual(kindlePos.lastReadPage, 55)
        XCTAssertEqual(kindlePos.epoch, 3100.0)
        
        // Tasks should contain upload entry for iPhone since local was newer (epoch 1200.0 vs remote 800.0)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.device, "iPhone")
        XCTAssertTrue(tasks.first?.cfi.contains("vndYabr_epoch=1200.0") == true)
    }
    
    @MainActor
    func testSyncPositionsStressCheck() throws {
        let bookId = "stress_sync^test_lib@server-uuid"
        
        var entries = [CalibreBookLastReadPositionEntry]()
        for i in 1...500 {
            let pos = TestFixtures.makeReadingPosition(id: "device-\(i)", epoch: Double(i))
            entries.append(pos.toEntry())
        }
        
        let tasks = repository.syncPositions(entries: entries, forBookId: bookId)
        XCTAssertTrue(tasks.isEmpty)
        
        let positions = repository.getPositions(forBookId: bookId)
        XCTAssertEqual(positions.count, 500)
    }
    
    func testReadingPositionThreading() throws {
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

    func testExplicitBookContextKeepsServerRealmsIsolated() throws {
        let provider = InMemoryServerScopedRealmConfigurationProvider(
            identifierPrefix: "RealmReadingPositionRepositoryTests-\(UUID().uuidString)"
        )
        let scopedRepository = RealmReadingPositionRepository(
            databaseService: databaseService,
            realmConfigurationProvider: provider
        )
        let firstBook = TestFixtures.makeBook(
            id: 42,
            library: TestFixtures.makeLibrary(
                server: TestFixtures.makeServer(name: "First"),
                key: "shared"
            )
        )
        let secondBook = TestFixtures.makeBook(
            id: 42,
            library: TestFixtures.makeLibrary(
                server: TestFixtures.makeServer(name: "Second"),
                key: "shared"
            )
        )

        scopedRepository.savePosition(
            TestFixtures.makeReadingPosition(id: "first-device", epoch: 1),
            for: firstBook
        )
        scopedRepository.savePosition(
            TestFixtures.makeReadingPosition(id: "second-device", epoch: 2),
            for: secondBook
        )

        XCTAssertEqual(scopedRepository.getPositions(for: firstBook).map(\.id), ["first-device"])
        XCTAssertEqual(scopedRepository.getPositions(for: secondBook).map(\.id), ["second-device"])
    }
}
