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
//      container.realmConf = config
//
//  which is brittle because the mock init ran `try? tryInitializeDatabase`
//  before the test's `container.realmConf = config` line, so the
//  initial `populateLibraries()` and `populateBookShelf()` calls
//  ran against the production disk-backed Realm.
//

import Foundation
import RealmSwift
@testable import YetAnotherEBookReader

enum MockAppContainerFactory {
    /// Recommended entry point: creates an `AppContainer` whose main
    /// Realm and every server-scoped sidecar Realm are in-memory and
    /// uniquely identified by `testName`.
    @MainActor
    static func makeContainer(
        testName: String = "Test-\(UUID().uuidString)"
    ) -> AppContainer {
        let env = TestRealmEnvironment.make(identifier: testName)
        return AppContainer(mock: true, testRealmEnvironment: env)
    }

    /// Variant for callers that need to control the main Realm
    /// configuration directly (e.g. tests that pass a custom schema
    /// version or a custom `inMemoryIdentifier`). The server-scoped
    /// provider is still in-memory.
    @MainActor
    static func makeContainer(
        mainRealmConfiguration: Realm.Configuration,
        testName: String = "Test-\(UUID().uuidString)"
    ) -> AppContainer {
        let env = TestRealmEnvironment(
            mainRealmConfiguration: mainRealmConfiguration,
            serverScopedRealmProvider: InMemoryServerScopedRealmConfigurationProvider(
                identifierPrefix: "\(testName)-sidecar"
            ),
            identifier: testName
        )
        return AppContainer(mock: true, testRealmEnvironment: env)
    }
}
