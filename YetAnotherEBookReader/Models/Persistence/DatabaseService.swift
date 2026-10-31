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
    // Start at 148 because build 148 already opened production Realms at this version.
    static let version: UInt64 = 148
}

class DatabaseService: ObservableObject {
    static let metadataWriteQueue = DispatchQueue(label: "saveBooksMetadata", qos: .userInitiated)

    @Published var realmConf: Realm.Configuration?
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
        configure(conf: initialConfiguration)
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
        configure(conf: configuration)
    }

    func configure(conf: Realm.Configuration) {
        self.realmConf = conf
    }

    func setup(conf: Realm.Configuration) {
        configure(conf: conf)
        do {
            self.realm = try Realm(configuration: conf)
        } catch {
            logger.fault("Failed to open Realm: \(error.localizedDescription)")
            self.realm = nil
        }
    }

    func openMainRealm(conf: Realm.Configuration) throws {
        configure(conf: conf)
        realm = try Realm(configuration: conf)
    }

    func openMetadataRealm(conf: Realm.Configuration, queue: DispatchQueue) throws {
        metadataRealm = try Realm(configuration: conf, queue: queue)
    }

    func refreshMainRealm() {
        realm?.refresh()
    }

    func reset(clearConfiguration: Bool) {
        realm = nil
        metadataRealm = nil
        if clearConfiguration {
            realmConf = nil
        }
    }
}
