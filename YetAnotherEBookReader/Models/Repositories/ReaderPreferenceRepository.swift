//
//  ReaderPreferenceRepository.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026/6/23.
//

import Foundation
import RealmSwift

protocol ReaderPreferenceRepositoryProtocol {
    func loadInitialPreferences(for book: CalibreBook, readerType: ReaderType) -> ReaderEnginePreferences?
    func savePreferences(_ preferences: ReaderEnginePreferences, for book: CalibreBook, readerType: ReaderType)
    func loadReadiumPreferences(for book: CalibreBook) -> ReadiumPreferenceValue?
    func saveReadiumPreferences(_ preferences: ReadiumPreferenceValue, for book: CalibreBook)
    func loadPDFPreferences(for book: CalibreBook) -> PDFPreferenceValue?
    func savePDFPreferences(_ preferences: PDFPreferenceValue, for book: CalibreBook)
}

final class RealmReaderPreferenceRepository: ReaderPreferenceRepositoryProtocol {
    typealias ConfigurationProvider = (CalibreServer) -> Realm.Configuration

    private let configurationProvider: ConfigurationProvider

    init(configurationProvider: @escaping ConfigurationProvider = BookAnnotation.getBookPreferenceServerConfig) {
        self.configurationProvider = configurationProvider
    }

    func loadInitialPreferences(for book: CalibreBook, readerType: ReaderType) -> ReaderEnginePreferences? {
        guard let realm = openRealm(for: book.library.server) else { return nil }

        switch readerType {
        case .ReadiumEPUB, .ReadiumPDF, .ReadiumCBZ:
            guard let savedPrefs = realm.object(ofType: ReadiumPreferenceRealm.self, forPrimaryKey: book.bookPrefId) else {
                return nil
            }
            return savedPrefs.toValue().toReaderEnginePreferences()

        case .YabrPDF:
            guard let savedPrefs = loadPDFPreferences(for: book) else {
                return nil
            }
            return savedPrefs.toReaderEnginePreferences()

        case .YabrEPUB:
            guard let savedPrefs = realm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: book.bookPrefId) else {
                return nil
            }
            let fontSizeStr = savedPrefs.currentFontSize ?? defaultFolioFontSize
            return ReaderEnginePreferences(
                themeMode: savedPrefs.themeMode == folioSepiaThemeMode ? 1 : (savedPrefs.nightMode ? 2 : 0),
                fontSizePercentage: folioFontSizeToPercentage(fontSizeStr),
                fontFamily: savedPrefs.currentFont ?? "Georgia",
                lineHeight: 1.2,
                pageMargins: 1.0,
                scroll: savedPrefs.currentScrollDirection != 0,
                scrollDirection: savedPrefs.currentScrollDirection,
                volumeKeyPaging: false
            )

        case .UNSUPPORTED:
            return nil
        }
    }

    func savePreferences(_ preferences: ReaderEnginePreferences, for book: CalibreBook, readerType: ReaderType) {
        guard let realm = openRealm(for: book.library.server) else { return }

        if readerType == .YabrPDF {
            try? realm.write {
                let dbPrefs = realm.objects(PDFOptions.self)
                    .filter("bookId == %@ AND libraryName == %@", book.id, book.library.name)
                    .first ?? {
                        let newPrefs = PDFOptions()
                        newPrefs.bookId = book.id
                        newPrefs.libraryName = book.library.name
                        realm.add(newPrefs)
                        return newPrefs
                    }()
                var updated = dbPrefs.toValue()
                updated.apply(preferences)
                dbPrefs.apply(updated)
            }
            return
        }

        try? realm.write {
            switch readerType {
            case .ReadiumEPUB, .ReadiumPDF, .ReadiumCBZ:
                let dbPrefs = realm.object(ofType: ReadiumPreferenceRealm.self, forPrimaryKey: book.bookPrefId) ?? {
                    let newPrefs = ReadiumPreferenceRealm()
                    newPrefs.id = book.bookPrefId
                    realm.add(newPrefs)
                    return newPrefs
                }()
                var updated = dbPrefs.toValue()
                updated.apply(preferences)
                updated.id = book.bookPrefId
                dbPrefs.apply(updated)

            case .YabrPDF:
                break

            case .YabrEPUB:
                let dbPrefs = realm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: book.bookPrefId) ?? {
                    let newPrefs = FolioReaderPreferenceRealm()
                    newPrefs.id = book.bookPrefId
                    realm.add(newPrefs)
                    return newPrefs
                }()
                dbPrefs.nightMode = (preferences.themeMode == 2)
                dbPrefs.themeMode = preferences.themeMode
                dbPrefs.currentFontSize = percentageToFolioFontSize(preferences.fontSizePercentage)
                dbPrefs.currentFont = preferences.fontFamily
                dbPrefs.currentScrollDirection = preferences.scrollDirection

            case .UNSUPPORTED:
                break
            }
        }
    }

    func loadReadiumPreferences(for book: CalibreBook) -> ReadiumPreferenceValue? {
        guard let realm = openRealm(for: book.library.server),
              let preferences = realm.object(ofType: ReadiumPreferenceRealm.self, forPrimaryKey: book.bookPrefId) else {
            return nil
        }
        return preferences.toValue()
    }

    func saveReadiumPreferences(_ preferences: ReadiumPreferenceValue, for book: CalibreBook) {
        guard let realm = openRealm(for: book.library.server) else { return }

        try? realm.write {
            let dbPrefs = realm.object(ofType: ReadiumPreferenceRealm.self, forPrimaryKey: book.bookPrefId) ?? {
                let newPrefs = ReadiumPreferenceRealm()
                newPrefs.id = book.bookPrefId
                realm.add(newPrefs)
                return newPrefs
            }()
            var preferences = preferences
            preferences.id = book.bookPrefId
            dbPrefs.apply(preferences)
        }
    }

    func loadPDFPreferences(for book: CalibreBook) -> PDFPreferenceValue? {
        guard let realm = openRealm(for: book.library.server),
              let savedPrefs = realm.objects(PDFOptions.self)
                .filter("bookId == %@ AND libraryName == %@", book.id, book.library.name)
                .first else {
            return nil
        }
        return savedPrefs.toValue()
    }

    func savePDFPreferences(_ preferences: PDFPreferenceValue, for book: CalibreBook) {
        guard let realm = openRealm(for: book.library.server) else { return }

        try? realm.write {
            let dbPrefs = realm.objects(PDFOptions.self)
                .filter("bookId == %@ AND libraryName == %@", book.id, book.library.name)
                .first ?? {
                    let newPrefs = PDFOptions()
                    newPrefs.bookId = book.id
                    newPrefs.libraryName = book.library.name
                    realm.add(newPrefs)
                    return newPrefs
                }()
            dbPrefs.apply(preferences)
        }
    }

    private func openRealm(for server: CalibreServer) -> Realm? {
        try? Realm(configuration: configurationProvider(server))
    }

}

private let defaultFolioFontSize = "20px"
private let folioSepiaThemeMode = 1
