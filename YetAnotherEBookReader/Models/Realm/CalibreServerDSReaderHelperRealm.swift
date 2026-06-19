//
//  CalibreServerDSReaderHelperRealm.swift
//  YetAnotherEBookReader
//

import Foundation
import RealmSwift

class CalibreServerDSReaderHelper: EmbeddedObject, ObjectKeyIdentifiable {
    @Persisted var port: Int = 0
    @Persisted var configurationData: Data?
    
    convenience init(port: Int) {
        self.init()
        self.port = port
    }
    
    var configuration: CalibreDSReaderHelperConfiguration? {
        get {
            guard let data = configurationData else { return nil }
            return try? JSONDecoder().decode(CalibreDSReaderHelperConfiguration.self, from: data)
        }
        set {
            if let newValue = newValue {
                configurationData = try? JSONEncoder().encode(newValue)
            } else {
                configurationData = nil
            }
        }
    }

    func update(from other: CalibreServerDSReaderHelper) {
        self.port = other.port
        self.configurationData = other.configurationData
    }
}
