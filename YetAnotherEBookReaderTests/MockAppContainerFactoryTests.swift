//
//  MockAppContainerFactoryTests.swift
//  YetAnotherEBookReaderTests
//
//  Regression coverage for the test-environment plumbing that
//  MockAppContainerFactory introduces. Verifies that:
//    1. The main Realm returned by the container is in-memory.
//    2. The per-server sidecar Realm returned by the container is
//       in-memory.
//    3. Two containers that share a server UUID do not share sidecar
//       state (the original testEndSession_logsActivity pollution
//       pattern).
//    4. Two containers that share a server UUID still see the same
//       AppContainer (the container's own scope, not sidecar
//       isolation).
//    5. MockAppContainerFactory.makeContainer uses a per-call test
//       name so concurrent test runs do not collide.
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

final class MockAppContainerFactoryTests: XCTestCase {

    // MARK: - Consistency: main and sidecar are wired

    func testMainRealmConfigurationIsInMemory() {
        let container = MockAppContainerFactory.makeContainer(
            testName: "MockAppContainerFactoryTests-MainInMemory"
        )

        XCTAssertNotNil(
            container.databaseService.realmConf?.inMemoryIdentifier,
            "Main Realm must be in-memory for tests"
        )
    }

    func testServerScopedRealmConfigurationIsInMemory() {
        let container = MockAppContainerFactory.makeContainer(
            testName: "MockAppContainerFactoryTests-SidecarInMemory"
        )
        let library = container.libraryManager.calibreLibraries.first?.value
        XCTAssertNotNil(library, "Mock library should be populated")

        let config = container.serverScopedRealmProvider.configuration(
            for: library!.server
        )
        XCTAssertNotNil(
            config.inMemoryIdentifier,
            "Server-scoped sidecar Realm must be in-memory for tests"
        )
    }

    // MARK: - Per-call test name uniqueness

    func testConcurrentContainersUseDistinctMainRealmIdentifiers() {
        let containerA = MockAppContainerFactory.makeContainer(
            testName: "MockAppContainerFactoryTests-DistinctA"
        )
        let containerB = MockAppContainerFactory.makeContainer(
            testName: "MockAppContainerFactoryTests-DistinctB"
        )

        // Check the AppContainer's own realmConf (the instance property),
        // not container.databaseService.realmConf — the latter is the
        // static DatabaseService.shared.realmConf and always reflects
        // the most recently initialized container, which would
        // otherwise mask the per-container isolation we want to
        // verify.
        let idA = containerA.realmConf?.inMemoryIdentifier
        let idB = containerB.realmConf?.inMemoryIdentifier
        XCTAssertNotEqual(
            idA, idB,
            "Each test container must have a unique main Realm identifier"
        )
        XCTAssertNotNil(idA)
        XCTAssertNotNil(idB)
    }

    func testConcurrentContainersUseDistinctSidecarRealmIdentifiers() throws {
        let containerA = MockAppContainerFactory.makeContainer(
            testName: "MockAppContainerFactoryTests-SidecarDistinctA"
        )
        let containerB = MockAppContainerFactory.makeContainer(
            testName: "MockAppContainerFactoryTests-SidecarDistinctB"
        )
        let libraryA = try XCTUnwrap(
            containerA.libraryManager.calibreLibraries.first?.value
        )
        let libraryB = try XCTUnwrap(
            containerB.libraryManager.calibreLibraries.first?.value
        )

        let configA = containerA.serverScopedRealmProvider.configuration(
            for: libraryA.server
        )
        let configB = containerB.serverScopedRealmProvider.configuration(
            for: libraryB.server
        )
        XCTAssertNotEqual(
            configA.inMemoryIdentifier,
            configB.inMemoryIdentifier,
            "Per-server sidecar Realms from different test containers must not collide"
        )
    }

    // MARK: - Re-entry into a reused server UUID

    /// The same server UUID (e.g. the mock LocalServerUUID constant)
    /// resolves to the same in-memory Realm within a single
    /// provider, so two lookups in the same container see each
    /// other's writes.
    func testSameServerUuidResolvesToSameSidecarInOneProvider() throws {
        let container = MockAppContainerFactory.makeContainer(
            testName: "MockAppContainerFactoryTests-SameUuid"
        )
        let library = try XCTUnwrap(
            container.libraryManager.calibreLibraries.first?.value
        )
        let book = CalibreBook(id: 1, library: library)
        let position = TestFixtures.makeReadingPosition(
            id: container.deviceName,
            lastReadPage: 3,
            epoch: 100.0
        )
        container.readingPositionRepository.savePosition(
            position,
            forBookId: book.bookPrefId
        )

        let retrieved = container.readingPositionRepository.getPositions(
            forBookId: book.bookPrefId
        )
        XCTAssertEqual(
            retrieved.count, 1,
            "Repeated lookups against the same provider must observe the same sidecar Realm"
        )
    }

    // MARK: - Original pollution regression: the very test this PR fixes

    /// Run the original failing test (ReadingSessionManagerTests
    /// .testEndSession_logsActivity) inline to ensure the
    /// pre-existing state-pollution failure is no longer reachable
    /// through the new factory.
    func testHistoryEntryCountIsStableAcrossRepeatedSessions() throws {
        func runOnce(testName: String) -> Int {
            let container = MockAppContainerFactory.makeContainer(
                testName: "MockAppContainerFactoryTests-Stable-\(testName)"
            )
            let library = try! XCTUnwrap(
                container.libraryManager.calibreLibraries.first?.value
            )
            let book = CalibreBook(id: 777, library: library)
            let startPos = TestFixtures.makeReadingPosition(
                id: container.deviceName,
                lastReadPage: 5,
                epoch: 500.0
            )
            let endPos = TestFixtures.makeReadingPosition(
                id: container.deviceName,
                lastReadPage: 15,
                epoch: 1500.0
            )

            _ = container.readingPositionRepository.session(
                start: startPos,
                forBookId: book.bookPrefId
            )
            container.readingPositionRepository.session(
                end: endPos,
                forBookId: book.bookPrefId
            )
            return container.readingPositionRepository.sessions(
                forBookId: book.bookPrefId,
                list: nil
            ).count
        }

        // Running the same scenario 3 times in the same process must
        // observe a fresh sidecar each time, so the count must be 1
        // every run.
        XCTAssertEqual(runOnce(testName: "A"), 1)
        XCTAssertEqual(runOnce(testName: "B"), 1)
        XCTAssertEqual(runOnce(testName: "C"), 1)
    }
}
