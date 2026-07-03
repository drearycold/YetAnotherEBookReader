//
//  CalibreServerDSReaderHelperRealm.swift
//  YetAnotherEBookReader
//

import Foundation
import RealmSwift

@objc(CalibreServerDSReaderHelper)
class CalibreServerDSReaderHelperRealm: EmbeddedObject, ObjectKeyIdentifiable {
    @Persisted var port: Int = 0
    @Persisted var configurationData: Data?

    override class func className() -> String {
        "CalibreServerDSReaderHelper"
    }

    convenience init(value: CalibreServerDSReaderHelper) {
        self.init()
        apply(value)
    }

    func apply(_ value: CalibreServerDSReaderHelper) {
        self.port = value.port
        self.configurationData = value.configurationData
    }

    func toValue() -> CalibreServerDSReaderHelper {
        CalibreServerDSReaderHelper(port: port, configurationData: configurationData)
    }
}
