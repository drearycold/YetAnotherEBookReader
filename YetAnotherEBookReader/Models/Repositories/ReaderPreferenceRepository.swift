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
            return ReaderEnginePreferences(
                themeMode: savedPrefs.themeMode,
                fontSizePercentage: savedPrefs.fontSizePercentage,
                fontFamily: savedPrefs.fontFamily,
                lineHeight: savedPrefs.lineHeight,
                pageMargins: savedPrefs.pageMargins,
                scroll: savedPrefs.scroll,
                scrollDirection: savedPrefs.scrollAxis,
                volumeKeyPaging: savedPrefs.volumeKeyPaging
            )

        case .YabrPDF:
            guard let savedPrefs = realm.objects(PDFOptions.self)
                .filter("bookId == %@ AND libraryName == %@", book.id, book.library.name)
                .first else {
                return nil
            }
            return ReaderEnginePreferences(
                themeMode: pdfThemeMode(savedPrefs.themeMode),
                fontSizePercentage: 100.0,
                fontFamily: "Original",
                lineHeight: 1.2,
                pageMargins: 1.0,
                scroll: savedPrefs.pageMode == .Scroll,
                scrollDirection: savedPrefs.scrollDirection == .Horizontal ? 1 : 0,
                volumeKeyPaging: false
            )

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

        try? realm.write {
            switch readerType {
            case .ReadiumEPUB, .ReadiumPDF, .ReadiumCBZ:
                let dbPrefs = realm.object(ofType: ReadiumPreferenceRealm.self, forPrimaryKey: book.bookPrefId) ?? {
                    let newPrefs = ReadiumPreferenceRealm()
                    newPrefs.id = book.bookPrefId
                    realm.add(newPrefs)
                    return newPrefs
                }()
                dbPrefs.themeMode = preferences.themeMode
                dbPrefs.fontSizePercentage = preferences.fontSizePercentage
                dbPrefs.fontFamily = preferences.fontFamily
                dbPrefs.lineHeight = preferences.lineHeight
                dbPrefs.pageMargins = preferences.pageMargins
                dbPrefs.scroll = preferences.scroll
                dbPrefs.scrollAxis = preferences.scrollDirection
                dbPrefs.volumeKeyPaging = preferences.volumeKeyPaging

            case .YabrPDF:
                let dbPrefs = realm.objects(PDFOptions.self)
                    .filter("bookId == %@ AND libraryName == %@", book.id, book.library.name)
                    .first ?? {
                        let newPrefs = PDFOptions()
                        newPrefs.bookId = book.id
                        newPrefs.libraryName = book.library.name
                        realm.add(newPrefs)
                        return newPrefs
                    }()
                dbPrefs.themeMode = pdfThemeMode(preferences.themeMode)
                dbPrefs.pageMode = preferences.scroll ? .Scroll : .Page
                dbPrefs.scrollDirection = preferences.scrollDirection == 0 ? .Vertical : .Horizontal

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

    private func openRealm(for server: CalibreServer) -> Realm? {
        try? Realm(configuration: configurationProvider(server))
    }

    private func pdfThemeMode(_ themeMode: PDFThemeMode) -> Int {
        switch themeMode {
        case .serpia:
            return 1
        case .dark:
            return 2
        default:
            return 0
        }
    }

    private func pdfThemeMode(_ themeMode: Int) -> PDFThemeMode {
        switch themeMode {
        case 1:
            return .serpia
        case 2:
            return .dark
        default:
            return .none
        }
    }
}

private let defaultFolioFontSize = "20px"
private let folioSepiaThemeMode = 1
