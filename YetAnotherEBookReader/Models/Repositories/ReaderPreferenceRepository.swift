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
    func loadFolioPreferences(for book: CalibreBook) -> FolioReaderPreferenceValue?
    func saveFolioPreferences(_ preferences: FolioReaderPreferenceValue, for book: CalibreBook)
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

struct FolioReaderPreferenceValue: Equatable {
    var nightMode: Bool
    var themeMode: Int
    var currentFont: String
    var currentFontSize: String
    var currentFontWeight: String
    var currentAudioRate: Int
    var currentHighlightStyle: Int
    var currentMediaOverlayStyle: Int
    var currentScrollDirection: Int
    var currentNavigationMenuIndex: Int
    var currentAnnotationMenuIndex: Int
    var currentNavigationMenuBookListStyle: Int
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
    var styleOverride: Int
    var structuralStyle: Int
    var structuralTrackingTocLevel: Int

    init(
        nightMode: Bool,
        themeMode: Int,
        currentFont: String,
        currentFontSize: String,
        currentFontWeight: String,
        currentAudioRate: Int = 1,
        currentHighlightStyle: Int = FolioReaderHighlightStyle.yellow.rawValue,
        currentMediaOverlayStyle: Int = MediaOverlayStyle.default.rawValue,
        currentScrollDirection: Int,
        currentNavigationMenuIndex: Int = 0,
        currentAnnotationMenuIndex: Int = 0,
        currentNavigationMenuBookListStyle: Int = NavigationMenuBookListStyle.List.rawValue,
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
        doClearClass: Bool,
        styleOverride: Int = StyleOverrideTypes.PNode.rawValue,
        structuralStyle: Int = FolioReaderStructuralStyle.atom.rawValue,
        structuralTrackingTocLevel: Int = FolioReaderPositionTrackingStyle.linear.rawValue
    ) {
        self.nightMode = nightMode
        self.themeMode = themeMode
        self.currentFont = currentFont
        self.currentFontSize = currentFontSize
        self.currentFontWeight = currentFontWeight
        self.currentAudioRate = currentAudioRate
        self.currentHighlightStyle = currentHighlightStyle
        self.currentMediaOverlayStyle = currentMediaOverlayStyle
        self.currentScrollDirection = currentScrollDirection
        self.currentNavigationMenuIndex = currentNavigationMenuIndex
        self.currentAnnotationMenuIndex = currentAnnotationMenuIndex
        self.currentNavigationMenuBookListStyle = currentNavigationMenuBookListStyle
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
        self.styleOverride = styleOverride
        self.structuralStyle = structuralStyle
        self.structuralTrackingTocLevel = structuralTrackingTocLevel
    }

    static var fallbackDefaults: FolioReaderPreferenceValue {
        FolioReaderPreferenceValue(
            nightMode: false,
            themeMode: FolioReaderThemeMode.serpia.rawValue,
            currentFont: "Georgia",
            currentFontSize: FolioReader.DefaultFontSize,
            currentFontWeight: FolioReader.DefaultFontWeight,
            currentScrollDirection: FolioReaderScrollDirection.defaultVertical.rawValue,
            currentMarginTop: 10,
            currentMarginBottom: 10,
            currentMarginLeft: 30,
            currentMarginRight: 30,
            currentVMarginLinked: true,
            currentHMarginLinked: true,
            currentLetterSpacing: FolioReader.DefaultLetterSpacing,
            currentLineHeight: FolioReader.DefaultLineHeight,
            currentTextIndent: FolioReader.DefaultTextIndent,
            doWrapPara: false,
            doClearClass: true
        )
    }

    init(defaultsFrom folioReader: FolioReader) {
        self.init(
            nightMode: false,
            themeMode: FolioReaderThemeMode.serpia.rawValue,
            currentFont: "Georgia",
            currentFontSize: FolioReader.DefaultFontSize,
            currentFontWeight: FolioReader.DefaultFontWeight,
            currentAudioRate: 1,
            currentHighlightStyle: FolioReaderHighlightStyle.yellow.rawValue,
            currentMediaOverlayStyle: MediaOverlayStyle.default.rawValue,
            currentScrollDirection: folioReader.defaultScrollDirection.rawValue,
            currentNavigationMenuIndex: 0,
            currentAnnotationMenuIndex: 0,
            currentNavigationMenuBookListStyle: NavigationMenuBookListStyle.List.rawValue,
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
            doClearClass: true,
            styleOverride: StyleOverrideTypes.PNode.rawValue,
            structuralStyle: FolioReaderStructuralStyle.atom.rawValue,
            structuralTrackingTocLevel: FolioReaderPositionTrackingStyle.linear.rawValue
        )
    }

    init(values: [String: Any], folioReader: FolioReader) {
        let defaults = FolioReaderPreferenceValue(defaultsFrom: folioReader)
        self.init(
            nightMode: values["nightMode"] as? Bool ?? defaults.nightMode,
            themeMode: values["themeMode"] as? Int ?? defaults.themeMode,
            currentFont: values["currentFont"] as? String ?? defaults.currentFont,
            currentFontSize: values["currentFontSize"] as? String ?? defaults.currentFontSize,
            currentFontWeight: values["currentFontWeight"] as? String ?? defaults.currentFontWeight,
            currentAudioRate: values["currentAudioRate"] as? Int ?? defaults.currentAudioRate,
            currentHighlightStyle: values["currentHighlightStyle"] as? Int ?? defaults.currentHighlightStyle,
            currentMediaOverlayStyle: values["currentMediaOverlayStyle"] as? Int ?? defaults.currentMediaOverlayStyle,
            currentScrollDirection: values["currentScrollDirection"] as? Int ?? defaults.currentScrollDirection,
            currentNavigationMenuIndex: values["currentNavigationMenuIndex"] as? Int ?? defaults.currentNavigationMenuIndex,
            currentAnnotationMenuIndex: values["currentAnnotationMenuIndex"] as? Int ?? defaults.currentAnnotationMenuIndex,
            currentNavigationMenuBookListStyle: values["currentNavigationMenuBookListStyle"] as? Int ?? defaults.currentNavigationMenuBookListStyle,
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
            doClearClass: values["doClearClass"] as? Bool ?? defaults.doClearClass,
            styleOverride: values["styleOverride"] as? Int ?? defaults.styleOverride,
            structuralStyle: values["structuralStyle"] as? Int ?? defaults.structuralStyle,
            structuralTrackingTocLevel: values["structuralTrackingTocLevel"] as? Int ?? defaults.structuralTrackingTocLevel
        )
    }

    func apply(to values: inout [String: Any], folioReader: FolioReader) {
        values["nightMode"] = nightMode
        values["themeMode"] = themeMode
        values["currentFont"] = currentFont
        values["currentFontSize"] = currentFontSize
        values["currentFontWeight"] = currentFontWeight
        values["currentAudioRate"] = currentAudioRate
        values["currentHighlightStyle"] = currentHighlightStyle
        values["currentMediaOverlayStyle"] = currentMediaOverlayStyle
        values["currentScrollDirection"] = currentScrollDirection
        values["currentNavigationMenuIndex"] = currentNavigationMenuIndex
        values["currentAnnotationMenuIndex"] = currentAnnotationMenuIndex
        values["currentNavigationMenuBookListStyle"] = currentNavigationMenuBookListStyle
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
        values["styleOverride"] = styleOverride
        values["structuralStyle"] = structuralStyle
        values["structuralTrackingTocLevel"] = structuralTrackingTocLevel
    }

    func toReaderEnginePreferences() -> ReaderEnginePreferences {
        ReaderEnginePreferences(
            themeMode: ReaderEngineThemeMode.fromSharedRawValue(themeMode).rawValue,
            fontSizePercentage: folioFontSizeToPercentage(currentFontSize),
            fontFamily: currentFont,
            lineHeight: folioLineHeightToShared(currentLineHeight),
            pageMargins: folioPageMarginsToShared(left: currentMarginLeft, right: currentMarginRight),
            scroll: currentScrollDirection != 0,
            scrollDirection: currentScrollDirection,
            volumeKeyPaging: false
        )
    }
}

typealias FolioReaderProfileValue = FolioReaderPreferenceValue

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
            DefaultServerScopedRealmConfigurationProvider().configuration(for: server)
        }
    ) {
        self.configurationProvider = configurationProvider
    }

    func loadInitialPreferences(for book: CalibreBook, readerType: ReaderType) -> ReaderEnginePreferences? {
        guard let realm = openRealm(for: book.library.server) else { return nil }

        let preferences: ReaderEnginePreferences?
        switch readerType {
        case .ReadiumEPUB, .ReadiumCBZ:
            preferences = loadReadiumEnginePreferences(from: realm, for: book)
                ?? loadFolioEnginePreferences(from: realm, for: book)
                ?? loadPDFEnginePreferences(from: realm, for: book)

        case .ReadiumPDF:
            preferences = loadReadiumEnginePreferences(from: realm, for: book)
                ?? loadPDFEnginePreferences(from: realm, for: book)
                ?? loadFolioEnginePreferences(from: realm, for: book)

        case .YabrEPUB:
            preferences = loadFolioEnginePreferences(from: realm, for: book)
                ?? loadReadiumEnginePreferences(from: realm, for: book)
                ?? loadPDFEnginePreferences(from: realm, for: book)

        case .YabrPDF:
            preferences = loadPDFEnginePreferences(from: realm, for: book)
                ?? loadReadiumEnginePreferences(from: realm, for: book)
                ?? loadFolioEnginePreferences(from: realm, for: book)

        case .UNSUPPORTED:
            preferences = nil
        }
        return preferences.map { compatibleEnginePreferences($0, for: readerType) }
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
                dbPrefs.nightMode = (preferences.themeMode >= ReaderEngineThemeMode.dark.rawValue)
                dbPrefs.themeMode = preferences.themeMode
                dbPrefs.currentFontSize = percentageToFolioFontSize(preferences.fontSizePercentage)
                dbPrefs.currentFont = preferences.fontFamily
                dbPrefs.currentScrollDirection = preferences.scrollDirection

            case .UNSUPPORTED:
                break
            }
        }
    }

    func loadFolioPreferences(for book: CalibreBook) -> FolioReaderPreferenceValue? {
        guard let realm = openRealm(for: book.library.server),
              let preferences = realm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: book.bookPrefId),
              preferences.hasCompletePreferenceValue else {
            return nil
        }
        return preferences.toValue(defaults: .fallbackDefaults)
    }

    func saveFolioPreferences(_ preferences: FolioReaderPreferenceValue, for book: CalibreBook) {
        guard let realm = openRealm(for: book.library.server) else { return }

        try? realm.write {
            let dbPrefs = realm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: book.bookPrefId) ?? {
                let newPrefs = FolioReaderPreferenceRealm()
                newPrefs.id = book.bookPrefId
                realm.add(newPrefs)
                return newPrefs
            }()
            dbPrefs.apply(preferences)
        }
    }

    private func loadReadiumEnginePreferences(from realm: Realm, for book: CalibreBook) -> ReaderEnginePreferences? {
        realm.object(ofType: ReadiumPreferenceRealm.self, forPrimaryKey: book.bookPrefId)?
            .toValue()
            .toReaderEnginePreferences()
    }

    private func loadPDFEnginePreferences(from realm: Realm, for book: CalibreBook) -> ReaderEnginePreferences? {
        realm.objects(PDFOptions.self)
            .filter("bookId == %@ AND libraryName == %@", book.id, book.library.name)
            .first?
            .toValue()
            .toReaderEnginePreferences()
    }

    private func loadFolioEnginePreferences(from realm: Realm, for book: CalibreBook) -> ReaderEnginePreferences? {
        guard let savedPrefs = realm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: book.bookPrefId) else {
            return nil
        }

        let fontSizeStr = savedPrefs.currentFontSize ?? defaultFolioFontSize
        var preferences = savedPrefs.toValue(defaults: .fallbackDefaults)
        preferences.themeMode = folioSharedThemeMode(from: savedPrefs)
        preferences.currentFontSize = fontSizeStr
        preferences.currentFont = savedPrefs.currentFont ?? "Georgia"
        preferences.currentScrollDirection = savedPrefs.currentScrollDirection != .min ? savedPrefs.currentScrollDirection : 0
        return preferences.toReaderEnginePreferences()
    }

    private func folioSharedThemeMode(from preferences: FolioReaderPreferenceRealm) -> Int {
        if preferences.themeMode != .min {
            return ReaderEngineThemeMode.fromSharedRawValue(preferences.themeMode).rawValue
        }
        return preferences.nightMode ? ReaderEngineThemeMode.night.rawValue : ReaderEngineThemeMode.light.rawValue
    }

    private func compatibleEnginePreferences(_ preferences: ReaderEnginePreferences, for readerType: ReaderType) -> ReaderEnginePreferences {
        var preferences = preferences
        switch readerType {
        case .ReadiumEPUB, .ReadiumPDF, .ReadiumCBZ:
            switch ReaderEngineThemeMode.fromSharedRawValue(preferences.themeMode) {
            case .green, .sepia:
                preferences.themeMode = ReaderEngineThemeMode.sepia.rawValue
            case .dark, .night:
                preferences.themeMode = ReaderEngineThemeMode.dark.rawValue
            case .light:
                preferences.themeMode = ReaderEngineThemeMode.light.rawValue
            }
        case .YabrPDF:
            if ReaderEngineThemeMode.fromSharedRawValue(preferences.themeMode) == .night {
                preferences.themeMode = ReaderEngineThemeMode.dark.rawValue
            }
        case .YabrEPUB, .UNSUPPORTED:
            break
        }
        return preferences
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
