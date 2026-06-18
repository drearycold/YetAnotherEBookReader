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
    
    private let logger = Logger(subsystem: "io.github.drearycold.DSReader", category: "DatabaseService")
    
    static let shared = DatabaseService()
    
    private init() {}
    
    func setup(conf: Realm.Configuration) {
        self.realmConf = conf
        do {
            self.realm = try Realm(configuration: conf)
        } catch {
            logger.fault("Failed to open Realm: \(error.localizedDescription)")
            self.realm = nil
        }
    }
}
