//
//  MockAppContainerFactory.swift
//  YetAnotherEBookReaderTests
//
//  Canonical factory for test-only `AppContainer` instances. Every
//  `AppContainer(mock: true)` call in unit tests should go through
//  this factory so the main Realm and all server-scoped sidecar
//  Realms stay in-memory and uniquely identified per test method.
//
//  Replaces the older pattern of:
//      let config = Realm.Configuration(inMemoryIdentifier: ...)
//      DatabaseService.shared.setup(conf: config)
//      let container = AppContainer(mock: true)
//      container.databaseService.configure(conf: config)
//
//  which is brittle because the mock init ran `try? tryInitializeDatabase`
//  before the test's explicit database configuration line, so the
//  initial `populateLibraries()` and `populateBookShelf()` calls
//  ran against the production disk-backed Realm.
//
//  Realm sharing: per `testName`, the factory caches a single
//  `TestRealmEnvironment` and reuses it for every subsequent call.
//  Callers that pass the same `testName` share the same in-memory
//  main Realm and the same `InMemoryServerScopedRealmConfigurationProvider`
//  (so per-server sidecar Realms are also shared). Tests that want
//  strict per-call isolation must pass a unique `testName`
//  (typically `"\(className)-\(UUID().uuidString)"`).
//
//  Reusing the in-memory Realm across tests in the same class is the
//  recommended pattern: every long unit-test run used to open ~339
//  unique Realms and exhaust the iOS Simulator's per-process
//  file-descriptor limit (the "Too many open files" error). Sharing
//  by class caps the count at the number of test classes (~25).
//  The `AppContainer` instance is still fresh per test, so the
//  per-instance in-memory state (subjects, libraryManager dict,
//  etc.) is reset between tests.
//

import Foundation
import RealmSwift
@testable import YetAnotherEBookReader

enum MockAppContainerFactory {
    /// Cache of `TestRealmEnvironment` keyed by `testName`. The same
    /// `testName` reused across calls returns the same in-memory Realm
    /// configuration and the same `InMemoryServerScopedRealmConfigurationProvider`,
    /// so file descriptors are reused across tests in the same class.
    private static var cachedEnvironments: [String: TestRealmEnvironment] = [:]
    private static let cacheLock = NSLock()

    /// Recommended entry point: creates an `AppContainer` whose main
    /// Realm and every server-scoped sidecar Realm are in-memory and
    /// keyed by `testName`. Repeated calls with the same `testName`
    /// share the same in-memory Realms.
    static func makeContainer(
        testName: String = "Test-\(UUID().uuidString)"
    ) -> AppContainer {
        let env = cachedEnvironment(for: testName)
        return AppContainer(mock: true, testRealmEnvironment: env)
    }

    /// Variant for callers that need to control the main Realm
    /// configuration directly (e.g. tests that pass a custom schema
    /// version or a custom `inMemoryIdentifier`). The server-scoped
    /// provider is still in-memory.
    static func makeContainer(
        mainRealmConfiguration: Realm.Configuration,
        testName: String = "Test-\(UUID().uuidString)"
    ) -> AppContainer {
        // We deliberately do NOT cache by `mainRealmConfiguration`
        // identity: two different Realm.Configuration values with the
        // same `inMemoryIdentifier` are the same Realm on disk, and
        // callers of this variant want explicit control. Cache by
        // `testName` to keep behavior consistent with the simpler
        // entry point, but the cached environment is only built once
        // per `testName`.
        let env: TestRealmEnvironment = cacheLock.withLock {
            if let cached = cachedEnvironments[testName] {
                return cached
            }
            let new = TestRealmEnvironment(
                mainRealmConfiguration: mainRealmConfiguration,
                serverScopedRealmProvider: InMemoryServerScopedRealmConfigurationProvider(
                    identifierPrefix: "\(testName)-sidecar"
                ),
                identifier: testName
            )
            cachedEnvironments[testName] = new
            return new
        }
        return AppContainer(mock: true, testRealmEnvironment: env)
    }

    /// Drop all cached `TestRealmEnvironment`s. Tests that mutate
    /// shared Realm state across classes can call this between test
    /// classes; in normal usage the cache lifetime is the process.
    static func resetCache() {
        cacheLock.withLock { cachedEnvironments.removeAll() }
    }

    private static func cachedEnvironment(for testName: String) -> TestRealmEnvironment {
        cacheLock.withLock {
            if let cached = cachedEnvironments[testName] {
                return cached
            }
            let new = TestRealmEnvironment.make(identifier: testName)
            cachedEnvironments[testName] = new
            return new
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
