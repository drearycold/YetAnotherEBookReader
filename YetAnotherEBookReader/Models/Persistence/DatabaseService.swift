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
    static let defaultVersion: UInt64 = 141
    static var version: UInt64 = defaultVersion
}

class DatabaseService: ObservableObject {
    @Published var realmConf: Realm.Configuration?
    @Published var realm: Realm?
    var metadataRealm: Realm?
    
    private let logger = Logger(subsystem: "io.github.drearycold.DSReader", category: "DatabaseService")
    
    static let shared = DatabaseService()
    
    init() {}

    func installInitialDefaultConfiguration() {
        DatabaseSchema.version = DatabaseSchema.defaultVersion
        let initialConfiguration = Realm.Configuration(
            schemaVersion: DatabaseSchema.version,
            migrationBlock: { _, _ in }
        )
        Realm.Configuration.defaultConfiguration = initialConfiguration
        configure(conf: initialConfiguration)
    }

    func installTestConfiguration(_ configuration: Realm.Configuration) {
        DatabaseSchema.version = configuration.schemaVersion
        Realm.Configuration.defaultConfiguration = configuration
        setup(conf: configuration)
    }

    func prepareProductionConfiguration(statusHandler: @escaping (String) -> Void) throws {
        let schemaVersion = UInt64(YabrAppInfo.shared.build) ?? 1
        DatabaseSchema.version = schemaVersion
        let configuration = try DatabaseMigrator().makeConfiguration(
            schemaVersion: schemaVersion,
            statusHandler: statusHandler
        )
        Realm.Configuration.defaultConfiguration = configuration
        configure(conf: configuration)
    }

    func loggerConfiguration() -> Realm.Configuration {
        realmConf ?? Realm.Configuration.defaultConfiguration
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
