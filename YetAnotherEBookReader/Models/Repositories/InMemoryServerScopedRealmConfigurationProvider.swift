//
//  InMemoryServerScopedRealmConfigurationProvider.swift
//  YetAnotherEBookReader
//
//  Test implementation of `ServerScopedRealmConfigurationProviding`.
//  Generates a unique in-memory `Realm.Configuration` per server UUID
//  (cached for repeat lookups within a single provider instance), so
//  the sidecar Realm never touches the disk under
//  Application Support/<server-uuid>.realm.
//
//  The provider is the test counterpart of
//  `DefaultServerScopedRealmConfigurationProvider`. It exists in the
//  app target (not the test target) so the protocol boundary
//  established by `ServerScopedRealmConfigurationProviding` is the
//  only thing tests need to depend on.
//

import Foundation
import RealmSwift

final class InMemoryServerScopedRealmConfigurationProvider: ServerScopedRealmConfigurationProviding {
    let identifierPrefix: String
    private var cache: [UUID: Realm.Configuration] = [:]
    private let lock = NSLock()

    init(identifierPrefix: String) {
        self.identifierPrefix = identifierPrefix
    }

    func configuration(forServerUUID uuid: UUID) -> Realm.Configuration {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[uuid] { return cached }
        let config = Realm.Configuration(
            inMemoryIdentifier: "\(identifierPrefix)-\(uuid.uuidString)",
            schemaVersion: DatabaseSchema.version,
            migrationBlock: { _, _ in },
            objectTypes: [
                BookDeviceReadingPositionRealm.self,
                BookDeviceReadingPositionHistoryRealm.self,
                FolioReaderPreferenceRealm.self,
                BookHighlightRealm.self,
                BookBookmarkRealm.self,
                PDFOptions.self,
                ReadiumPreferenceRealm.self
            ]
        )
        cache[uuid] = config
        return config
    }
}
