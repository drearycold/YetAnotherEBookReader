//
//  TestRealmEnvironment.swift
//  YetAnotherEBookReader
//
//  Test-environment bundle for `AppContainer`. Wraps the two
//  configurations a test needs to be fully isolated:
//    - mainRealmConfiguration: the in-memory Realm.Configuration used
//      for the main database
//    - serverScopedRealmProvider: a ServerScopedRealmConfigurationProviding
//      that returns in-memory per-server Realms (so the sidecar
//      reading-position / reader-preference Realms never touch the
//      disk under Application Support/<server-uuid>.realm)
//
//  Both production call sites (AppContainer.init) and test
//  factories (YetAnotherEBookReaderTests/TestHelpers/
//  MockAppContainerFactory.swift) reference this type; the type
//  itself contains no test-only logic and is safe to keep in the
//  app target.
//

import Foundation
import RealmSwift

struct TestRealmEnvironment {
    let mainRealmConfiguration: Realm.Configuration
    let serverScopedRealmProvider: ServerScopedRealmConfigurationProviding
    let identifier: String

    static func make(
        identifier: String = "Test-\(UUID().uuidString)",
        mainSchemaVersion: UInt64 = AppContainer.RealmSchemaVersion
    ) -> TestRealmEnvironment {
        let main = Realm.Configuration(
            inMemoryIdentifier: "\(identifier)-main",
            schemaVersion: mainSchemaVersion,
            migrationBlock: { _, _ in }
        )
        return TestRealmEnvironment(
            mainRealmConfiguration: main,
            serverScopedRealmProvider: InMemoryServerScopedRealmConfigurationProvider(
                identifierPrefix: "\(identifier)-sidecar"
            ),
            identifier: identifier
        )
    }
}
