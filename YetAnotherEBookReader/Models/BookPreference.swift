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
