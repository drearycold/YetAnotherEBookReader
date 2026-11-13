//
//  DatabaseService.swift
//  YetAnotherEBookReader
//
//  Created by Gemini on 2026/4/6.
//

import Foundation
import RealmSwift
import os.log

enum DatabaseSchema {
    // Independent of CFBundleVersion. Increment only for schema or data migrations.
    static let version: UInt64 = 151
}

class DatabaseService: ObservableObject {
    struct CacheConfiguration: Sendable {
        let configuration: Realm.Configuration
        let id = UUID()
    }

    static let metadataWriteQueue = DispatchQueue(label: "saveBooksMetadata", qos: .userInitiated)

    private let configurationLock = NSLock()
    private var configuration: Realm.Configuration?
    private var cacheConfiguration: CacheConfiguration?

    // Bootstrap replaces this value while background repositories take snapshots.
    var realmConf: Realm.Configuration? {
        configurationLock.lock()
        defer { configurationLock.unlock() }
        return configuration
    }

    var cacheConfigurationSnapshot: CacheConfiguration? {
        configurationLock.withLock { cacheConfiguration }
    }
    @Published var realm: Realm?
    var metadataRealm: Realm?
    
    private let logger = Logger(subsystem: "io.github.drearycold.DSReader", category: "DatabaseService")
    
    static let shared = DatabaseService()
    
    init() {}

    func installInitialDefaultConfiguration() {
        let initialConfiguration = Realm.Configuration(
            schemaVersion: DatabaseSchema.version,
            migrationBlock: { _, _ in }
        )
        Realm.Configuration.defaultConfiguration = initialConfiguration
        setConfiguration(initialConfiguration, cacheReady: false)
    }

    func installTestConfiguration(_ configuration: Realm.Configuration) {
        Realm.Configuration.defaultConfiguration = configuration
        setup(conf: configuration)
    }

    func prepareProductionConfiguration(fileURL: URL? = nil, statusHandler: @escaping (String) -> Void) throws {
        let configuration = try DatabaseMigrator().makeConfiguration(
            schemaVersion: DatabaseSchema.version,
            fileURL: fileURL,
            statusHandler: statusHandler
        )
        Realm.Configuration.defaultConfiguration = configuration
        setConfiguration(configuration, cacheReady: false)
    }

    func configure(conf: Realm.Configuration) {
        setConfiguration(conf)
    }

    private func setConfiguration(_ configuration: Realm.Configuration?, cacheReady: Bool = true) {
        configurationLock.lock()
        defer { configurationLock.unlock() }
        self.configuration = configuration
        if var configuration, cacheReady {
            configuration.migrationBlock = nil
            configuration.shouldCompactOnLaunch = nil
            cacheConfiguration = CacheConfiguration(configuration: configuration)
        } else {
            cacheConfiguration = nil
        }
    }

    func setup(conf: Realm.Configuration) {
        do {
            try openMainRealm(conf: conf)
        } catch {
            logger.fault("Failed to open Realm: \(error.localizedDescription)")
            self.realm = nil
        }
    }

    func openMainRealm(conf: Realm.Configuration) throws {
        setConfiguration(conf, cacheReady: false)
        let opened = try Realm(configuration: conf)
        configure(conf: conf)
        realm = opened
    }

    func openMetadataRealm(conf: Realm.Configuration, queue: DispatchQueue) throws {
        metadataRealm = try Realm(configuration: conf, queue: queue)
    }

    func refreshMainRealm() {
        realm?.refresh()
    }

    func reset(clearConfiguration: Bool) {
        configurationLock.withLock {
            if clearConfiguration { configuration = nil }
            cacheConfiguration = nil
        }
        realm = nil
        metadataRealm = nil
    }
}
