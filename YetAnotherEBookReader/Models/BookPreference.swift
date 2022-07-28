//
//  BookPreference.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/30.
//

import Foundation
import RealmSwift



func getBookPreferenceConfig(book: CalibreBook, format: Format) -> Realm.Configuration? {
    guard let bookFileURL = getSavedUrl(book: book, format: format) else { return nil }
    return getBookPreferenceConfig(bookFileURL: bookFileURL)
}

func getBookPreferenceConfig(bookFileURL: URL) -> Realm.Configuration? {
    return Realm.Configuration(
        fileURL: bookFileURL.deletingPathExtension().appendingPathExtension("db"),
        schemaVersion: ModelData.RealmSchemaVersion
    )
}

func readPosToLastReadPosition(book: CalibreBook, format: Format, formatInfo: FormatInfo) {
    guard formatInfo.cached,
          let bookPrefConfig = getBookPreferenceConfig(book: book, format: format),
          let bookPrefRealm = try? Realm(configuration: bookPrefConfig) else { return }
    
    book.readPos.getDevices().forEach { position in
        guard let readerType = ReaderType(rawValue: position.readerName), readerType.format == format else { return }
//                    position.encodeEPUBCFI()
        
        let object = bookPrefRealm.object(ofType: CalibreBookLastReadPositionRealm.self, forPrimaryKey: position.id) ??
        CalibreBookLastReadPositionRealm()

        var position = position
        
        guard object.epoch < position.epoch || object.cfi.count < 3 || !object.cfi.contains("_readerName") else { return }
        
        if position.epoch == 0.0 {
            position.epoch = Date().timeIntervalSince1970
        }
        
        try? bookPrefRealm.write {
            object.cfi = position.encodeEPUBCFI()
            object.pos_frac = position.lastProgress / 100
            object.epoch = position.epoch
            if object.device.isEmpty {
                object.device = position.id
                bookPrefRealm.add(object, update: .all)
            }
        }
    }
}
