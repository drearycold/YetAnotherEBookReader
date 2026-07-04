//
//  ReadiumPreferenceAdapter.swift
//  YetAnotherEBookReader
//

import Foundation
import UIKit
import ReadiumNavigator
import ReadiumShared

extension ReadiumPreferenceValue {
    var themeColor: UIColor {
        switch themeMode {
        case 1:
            return UIColor(red: 0.98, green: 0.96, blue: 0.91, alpha: 1.0)
        case 2:
            return .black
        default:
            return .white
        }
    }

    func toEPUBPreferences() -> EPUBPreferences {
        EPUBPreferences(
            columnCount: columnCount == 0 ? .auto : (columnCount == 1 ? .one : .two),
            fit: {
                switch fit {
                case 1: return .page
                case 2: return .width
                default: return .auto
                }
            }(),
            fontFamily: fontFamily == "Original" ? nil : ReadiumNavigator.FontFamily(rawValue: fontFamily),
            fontSize: fontSizePercentage / 100.0,
            fontWeight: fontWeight,
            hyphens: hyphens,
            imageFilter: imageFilter == 0 ? nil : (imageFilter == 1 ? .darken : .invert),
            letterSpacing: letterSpacing,
            ligatures: ligatures,
            lineHeight: lineHeight,
            offsetFirstPage: offsetFirstPage,
            pageMargins: pageMargins,
            paragraphIndent: paragraphIndent,
            paragraphSpacing: paragraphSpacing,
            publisherStyles: publisherStyles,
            readingProgression: readingProgression == 0 ? .ltr : .rtl,
            scroll: scroll,
            spread: {
                switch spread {
                case 1: return .never
                case 2: return .always
                default: return .auto
                }
            }(),
            textAlign: {
                switch textAlign {
                case 1: return .start
                case 2: return .left
                case 3: return .right
                case 4: return .justify
                default: return nil
                }
            }(),
            textNormalization: textNormalization,
            theme: {
                switch themeMode {
                case 1: return .sepia
                case 2: return .dark
                default: return .light
                }
            }(),
            typeScale: typeScale,
            verticalText: verticalText,
            wordSpacing: wordSpacing
        )
    }

    func toPDFPreferences() -> PDFPreferences {
        PDFPreferences(
            fit: {
                switch fit {
                case 1: return .page
                case 2: return .width
                default: return .auto
                }
            }(),
            offsetFirstPage: offsetFirstPage,
            pageSpacing: pageSpacing,
            readingProgression: readingProgression == 0 ? .ltr : .rtl,
            scroll: scroll,
            scrollAxis: scrollAxis == 1 ? .horizontal : .vertical,
            spread: {
                switch spread {
                case 1: return .never
                case 2: return .always
                default: return .auto
                }
            }(),
            visibleScrollbar: visibleScrollbar
        )
    }

    mutating func update(from settings: EPUBSettings) {
        switch settings.theme {
        case .light: themeMode = 0
        case .sepia: themeMode = 1
        case .dark: themeMode = 2
        }

        fontSizePercentage = settings.fontSize * 100.0
        fontFamily = settings.fontFamily?.rawValue ?? "Original"
        lineHeight = settings.lineHeight ?? 1.2
        pageMargins = settings.pageMargins
        publisherStyles = settings.publisherStyles
        scroll = settings.scroll
        readingProgression = settings.readingProgression == .rtl ? 1 : 0

        switch settings.textAlign {
        case .start: textAlign = 1
        case .left: textAlign = 2
        case .right: textAlign = 3
        case .justify: textAlign = 4
        default: textAlign = 0
        }

        switch settings.columnCount {
        case .auto: columnCount = 0
        case .one: columnCount = 1
        case .two: columnCount = 2
        }

        fontWeight = settings.fontWeight ?? 1.0
        letterSpacing = settings.letterSpacing ?? 0.0
        wordSpacing = settings.wordSpacing ?? 0.0
        hyphens = settings.hyphens ?? false

        switch settings.imageFilter {
        case .darken: imageFilter = 1
        case .invert: imageFilter = 2
        default: imageFilter = 0
        }

        textNormalization = settings.textNormalization
        typeScale = settings.typeScale ?? 1.2
        paragraphIndent = settings.paragraphIndent ?? 0.0
        paragraphSpacing = settings.paragraphSpacing ?? 0.0
        ligatures = settings.ligatures ?? false
        offsetFirstPage = settings.offsetFirstPage
        verticalText = settings.verticalText

        switch settings.spread {
        case .never: spread = 1
        case .always: spread = 2
        default: spread = 0
        }

        switch settings.fit {
        case .page: fit = 1
        case .width: fit = 2
        default: fit = 0
        }
    }

    mutating func update(from settings: PDFSettings) {
        scroll = settings.scroll
        readingProgression = settings.readingProgression == .rtl ? 1 : 0
        offsetFirstPage = settings.offsetFirstPage
        pageSpacing = settings.pageSpacing
        scrollAxis = settings.scrollAxis == .horizontal ? 1 : 0
        visibleScrollbar = settings.visibleScrollbar

        switch settings.fit {
        case .page: fit = 1
        case .width: fit = 2
        default: fit = 0
        }

        switch settings.spread {
        case .never: spread = 1
        case .always: spread = 2
        default: spread = 0
        }
    }

    mutating func update(from preferences: EPUBPreferences) {
        switch preferences.theme {
        case .light?: themeMode = 0
        case .sepia?: themeMode = 1
        case .dark?: themeMode = 2
        case nil: themeMode = 0
        }

        fontSizePercentage = (preferences.fontSize ?? 1.0) * 100.0
        fontFamily = preferences.fontFamily?.rawValue ?? "Original"
        lineHeight = preferences.lineHeight ?? 1.2
        pageMargins = preferences.pageMargins ?? 1.0
        publisherStyles = preferences.publisherStyles ?? true
        scroll = preferences.scroll ?? false

        if let readingProgression = preferences.readingProgression {
            self.readingProgression = readingProgression == .rtl ? 1 : 0
        } else {
            self.readingProgression = 0
        }

        switch preferences.textAlign {
        case .start?: textAlign = 1
        case .left?: textAlign = 2
        case .right?: textAlign = 3
        case .justify?: textAlign = 4
        default: textAlign = 0
        }

        switch preferences.columnCount {
        case .one?: columnCount = 1
        case .two?: columnCount = 2
        default: columnCount = 0
        }

        fontWeight = preferences.fontWeight ?? 1.0
        letterSpacing = preferences.letterSpacing ?? 0.0
        wordSpacing = preferences.wordSpacing ?? 0.0
        hyphens = preferences.hyphens ?? false

        switch preferences.imageFilter {
        case .darken?: imageFilter = 1
        case .invert?: imageFilter = 2
        default: imageFilter = 0
        }

        textNormalization = preferences.textNormalization ?? false
        typeScale = preferences.typeScale ?? 1.2
        paragraphIndent = preferences.paragraphIndent ?? 0.0
        paragraphSpacing = preferences.paragraphSpacing ?? 0.0
        ligatures = preferences.ligatures ?? false
        offsetFirstPage = preferences.offsetFirstPage
        verticalText = preferences.verticalText ?? false

        switch preferences.spread {
        case .never?: spread = 1
        case .always?: spread = 2
        default: spread = 0
        }

        switch preferences.fit {
        case .page?: fit = 1
        case .width?: fit = 2
        default: fit = 0
        }
    }

    mutating func update(from preferences: PDFPreferences) {
        scroll = preferences.scroll ?? false

        if let readingProgression = preferences.readingProgression {
            self.readingProgression = readingProgression == .rtl ? 1 : 0
        } else {
            self.readingProgression = 0
        }

        offsetFirstPage = preferences.offsetFirstPage
        pageSpacing = preferences.pageSpacing ?? 0.0
        scrollAxis = preferences.scrollAxis == .horizontal ? 1 : 0
        visibleScrollbar = preferences.visibleScrollbar ?? true

        switch preferences.fit {
        case .page?: fit = 1
        case .width?: fit = 2
        default: fit = 0
        }

        switch preferences.spread {
        case .never?: spread = 1
        case .always?: spread = 2
        default: spread = 0
        }
    }

    func toReaderEnginePreferences() -> ReaderEnginePreferences {
        ReaderEnginePreferences(
            themeMode: themeMode,
            fontSizePercentage: fontSizePercentage,
            fontFamily: fontFamily,
            lineHeight: lineHeight,
            pageMargins: pageMargins,
            scroll: scroll,
            scrollDirection: scrollAxis,
            volumeKeyPaging: volumeKeyPaging
        )
    }

    mutating func apply(_ preferences: ReaderEnginePreferences) {
        themeMode = preferences.themeMode
        fontSizePercentage = preferences.fontSizePercentage
        fontFamily = preferences.fontFamily
        lineHeight = preferences.lineHeight
        pageMargins = preferences.pageMargins
        scroll = preferences.scroll
        scrollAxis = preferences.scrollDirection
        volumeKeyPaging = preferences.volumeKeyPaging
    }
}
