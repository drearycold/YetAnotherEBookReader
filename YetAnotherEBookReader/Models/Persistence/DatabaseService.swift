//
//  DatabaseService.swift
//  YetAnotherEBookReader
//
//  Created by Gemini on 2026/4/6.
//

import Foundation
import RealmSwift
import os.log

class DatabaseService: ObservableObject {
    @Published var realmConf: Realm.Configuration?
    @Published var realm: Realm?
    var metadataRealm: Realm?
    
    private let logger = Logger(subsystem: "io.github.drearycold.DSReader", category: "DatabaseService")
    
    static let shared = DatabaseService()
    
    init() {}
    
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
