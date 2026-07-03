//
//  ReaderPreferenceRepository.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026/6/23.
//

import Foundation
import FolioReaderKit
import RealmSwift

protocol ReaderPreferenceRepositoryProtocol {
    func loadInitialPreferences(for book: CalibreBook, readerType: ReaderType) -> ReaderEnginePreferences?
    func savePreferences(_ preferences: ReaderEnginePreferences, for book: CalibreBook, readerType: ReaderType)
    func loadReadiumPreferences(for book: CalibreBook) -> ReadiumPreferenceValue?
    func saveReadiumPreferences(_ preferences: ReadiumPreferenceValue, for book: CalibreBook)
    func loadPDFPreferences(for book: CalibreBook) -> PDFPreferenceValue?
    func savePDFPreferences(_ preferences: PDFPreferenceValue, for book: CalibreBook)
}

protocol FolioReaderProfileRepositoryProtocol {
    func ensureDefaultProfile(defaults: FolioReaderProfileValue)
    func loadProfile(named name: String, defaults: FolioReaderProfileValue) -> FolioReaderProfileValue?
    func saveProfile(_ profile: FolioReaderProfileValue, named name: String)
    func listProfiles(filter: String?, defaults: FolioReaderProfileValue) -> [String]
    func removeProfile(named name: String)
}

struct FolioReaderProfileValue: Equatable {
    var nightMode: Bool
    var themeMode: Int
    var currentFont: String
    var currentFontSize: String
    var currentFontWeight: String
    var currentScrollDirection: Int
    var currentMarginTop: Int
    var currentMarginBottom: Int
    var currentMarginLeft: Int
    var currentMarginRight: Int
    var currentVMarginLinked: Bool
    var currentHMarginLinked: Bool
    var currentLetterSpacing: Int
    var currentLineHeight: Int
    var currentTextIndent: Int
    var doWrapPara: Bool
    var doClearClass: Bool

    init(
        nightMode: Bool,
        themeMode: Int,
        currentFont: String,
        currentFontSize: String,
        currentFontWeight: String,
        currentScrollDirection: Int,
        currentMarginTop: Int,
        currentMarginBottom: Int,
        currentMarginLeft: Int,
        currentMarginRight: Int,
        currentVMarginLinked: Bool,
        currentHMarginLinked: Bool,
        currentLetterSpacing: Int,
        currentLineHeight: Int,
        currentTextIndent: Int,
        doWrapPara: Bool,
        doClearClass: Bool
    ) {
        self.nightMode = nightMode
        self.themeMode = themeMode
        self.currentFont = currentFont
        self.currentFontSize = currentFontSize
        self.currentFontWeight = currentFontWeight
        self.currentScrollDirection = currentScrollDirection
        self.currentMarginTop = currentMarginTop
        self.currentMarginBottom = currentMarginBottom
        self.currentMarginLeft = currentMarginLeft
        self.currentMarginRight = currentMarginRight
        self.currentVMarginLinked = currentVMarginLinked
        self.currentHMarginLinked = currentHMarginLinked
        self.currentLetterSpacing = currentLetterSpacing
        self.currentLineHeight = currentLineHeight
        self.currentTextIndent = currentTextIndent
        self.doWrapPara = doWrapPara
        self.doClearClass = doClearClass
    }

    init(defaultsFrom folioReader: FolioReader) {
        self.init(
            nightMode: false,
            themeMode: FolioReaderThemeMode.serpia.rawValue,
            currentFont: "Georgia",
            currentFontSize: FolioReader.DefaultFontSize,
            currentFontWeight: FolioReader.DefaultFontWeight,
            currentScrollDirection: folioReader.defaultScrollDirection.rawValue,
            currentMarginTop: folioReader.defaultMarginTop,
            currentMarginBottom: folioReader.defaultMarginBottom,
            currentMarginLeft: folioReader.defaultMarginLeft,
            currentMarginRight: folioReader.defaultMarginRight,
            currentVMarginLinked: true,
            currentHMarginLinked: true,
            currentLetterSpacing: FolioReader.DefaultLetterSpacing,
            currentLineHeight: FolioReader.DefaultLineHeight,
            currentTextIndent: FolioReader.DefaultTextIndent,
            doWrapPara: false,
            doClearClass: true
        )
    }

    init(values: [String: Any], folioReader: FolioReader) {
        let defaults = FolioReaderProfileValue(defaultsFrom: folioReader)
        self.init(
            nightMode: values["nightMode"] as? Bool ?? defaults.nightMode,
            themeMode: values["themeMode"] as? Int ?? defaults.themeMode,
            currentFont: values["currentFont"] as? String ?? defaults.currentFont,
            currentFontSize: values["currentFontSize"] as? String ?? defaults.currentFontSize,
            currentFontWeight: values["currentFontWeight"] as? String ?? defaults.currentFontWeight,
            currentScrollDirection: values["currentScrollDirection"] as? Int ?? defaults.currentScrollDirection,
            currentMarginTop: values["currentMarginTop"] as? Int ?? defaults.currentMarginTop,
            currentMarginBottom: values["currentMarginBottom"] as? Int ?? defaults.currentMarginBottom,
            currentMarginLeft: values["currentMarginLeft"] as? Int ?? defaults.currentMarginLeft,
            currentMarginRight: values["currentMarginRight"] as? Int ?? defaults.currentMarginRight,
            currentVMarginLinked: values["currentVMarginLinked"] as? Bool ?? defaults.currentVMarginLinked,
            currentHMarginLinked: values["currentHMarginLinked"] as? Bool ?? defaults.currentHMarginLinked,
            currentLetterSpacing: values["currentLetterSpacing"] as? Int ?? defaults.currentLetterSpacing,
            currentLineHeight: values["currentLineHeight"] as? Int ?? defaults.currentLineHeight,
            currentTextIndent: values["currentTextIndent"] as? Int ?? defaults.currentTextIndent,
            doWrapPara: values["doWrapPara"] as? Bool ?? defaults.doWrapPara,
            doClearClass: values["doClearClass"] as? Bool ?? defaults.doClearClass
        )
    }

    func apply(to values: inout [String: Any], folioReader: FolioReader) {
        values["nightMode"] = nightMode
        values["themeMode"] = themeMode
        values["currentFont"] = currentFont
        values["currentFontSize"] = currentFontSize
        values["currentFontWeight"] = currentFontWeight
        values["currentScrollDirection"] = currentScrollDirection
        values["currentMarginTop"] = currentMarginTop
        values["currentMarginBottom"] = currentMarginBottom
        values["currentMarginLeft"] = currentMarginLeft
        values["currentMarginRight"] = currentMarginRight
        values["currentVMarginLinked"] = currentVMarginLinked
        values["currentHMarginLinked"] = currentHMarginLinked
        values["currentLetterSpacing"] = currentLetterSpacing
        values["currentLineHeight"] = currentLineHeight
        values["currentTextIndent"] = currentTextIndent
        values["doWrapPara"] = doWrapPara
        values["doClearClass"] = doClearClass
    }
}

final class RealmFolioReaderProfileRepository: FolioReaderProfileRepositoryProtocol {
    private let realmConfiguration: Realm.Configuration?

    init(realmConfiguration: Realm.Configuration?) {
        self.realmConfiguration = realmConfiguration
    }

    func ensureDefaultProfile(defaults: FolioReaderProfileValue) {
        guard let realm = openRealm() else { return }
        if realm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: "Default") != nil {
            return
        }

        let profile = FolioReaderPreferenceRealm()
        profile.id = "Default"
        profile.apply(defaults)

        try? realm.write {
            realm.add(profile, update: .modified)
        }
    }

    func loadProfile(named name: String, defaults: FolioReaderProfileValue) -> FolioReaderProfileValue? {
        ensureDefaultProfile(defaults: defaults)
        guard let realm = openRealm(),
              let profile = realm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: name) else {
            return nil
        }
        return profile.toValue(defaults: defaults)
    }

    func saveProfile(_ profile: FolioReaderProfileValue, named name: String) {
        guard let realm = openRealm() else { return }

        try? realm.write {
            let object = realm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: name) ?? {
                let newObject = FolioReaderPreferenceRealm()
                newObject.id = name
                realm.add(newObject)
                return newObject
            }()
            object.apply(profile)
        }
    }

    func listProfiles(filter: String?, defaults: FolioReaderProfileValue) -> [String] {
        ensureDefaultProfile(defaults: defaults)
        guard let realm = openRealm() else {
            return ["Default"]
        }

        var names = Array(realm.objects(FolioReaderPreferenceRealm.self).map(\.id))
        if !names.contains("Default") {
            names.append("Default")
        }
        if let filter, !filter.isEmpty {
            names = names.filter { $0.localizedCaseInsensitiveContains(filter) }
        }
        return names.sorted()
    }

    func removeProfile(named name: String) {
        guard let realm = openRealm(),
              let profile = realm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: name) else {
            return
        }

        try? realm.write {
            realm.delete(profile)
        }
    }

    private func openRealm() -> Realm? {
        guard let realmConfiguration else { return nil }
        return try? Realm(configuration: realmConfiguration)
    }
}

final class RealmReaderPreferenceRepository: ReaderPreferenceRepositoryProtocol {
    typealias ConfigurationProvider = (CalibreServer) -> Realm.Configuration

    private let configurationProvider: ConfigurationProvider

    init(
        configurationProvider: @escaping ConfigurationProvider = { server in
            AppContainer.shared?.serverScopedRealmProvider.configuration(for: server)
                ?? DefaultServerScopedRealmConfigurationProvider().configuration(for: server)
        }
    ) {
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
