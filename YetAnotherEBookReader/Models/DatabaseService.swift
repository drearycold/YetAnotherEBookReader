//
//  DatabaseService.swift
//  YetAnotherEBookReader
//
//  Created by Gemini on 2026/4/6.
//

import Foundation
import RealmSwift

class DatabaseService: ObservableObject {
    @Published var realmConf: Realm.Configuration!
    @Published var realm: Realm!
    
    static let shared = DatabaseService()
    
    private init() {}
    
    func setup(conf: Realm.Configuration) {
        self.realmConf = conf
        self.realm = try! Realm(configuration: conf)
    }
}
