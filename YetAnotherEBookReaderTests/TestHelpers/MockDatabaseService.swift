//
//  MockDatabaseService.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-23.
//

import Foundation
import RealmSwift
@testable import YetAnotherEBookReader

class MockDatabaseService {
    static func inMemoryConfiguration(identifier: String = UUID().uuidString) -> Realm.Configuration {
        return Realm.Configuration(
            inMemoryIdentifier: identifier,
            schemaVersion: AppContainer.RealmSchemaVersion,
            migrationBlock: { _, _ in }
        )
    }

    @MainActor
    static func setupSharedMock(identifier: String = UUID().uuidString) -> Realm.Configuration {
        let config = inMemoryConfiguration(identifier: identifier)
        DatabaseService.shared.setup(conf: config)
        return config
    }
}
