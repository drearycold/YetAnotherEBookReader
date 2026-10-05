//
//  PDFPreferenceAdapter.swift
//  YetAnotherEBookReader
//

import Foundation
import UIKit

extension PDFPreferenceValue {
    var isDark: Bool {
        themeMode == .dark
    }

    func isDark<T>(_ darkValue: T, _ lightValue: T) -> T {
        isDark ? darkValue : lightValue
    }

    var themePalette: PDFThemePalette {
        PDFThemePalette(themeMode: themeMode)
    }

    var fillColor: CGColor {
        themePalette.background
    }

    func toReaderEnginePreferences() -> ReaderEnginePreferences {
        ReaderEnginePreferences(
            themeMode: {
                switch themeMode {
                case .serpia:
                    return ReaderEngineThemeMode.sepia.rawValue
                case .forest:
                    return ReaderEngineThemeMode.green.rawValue
                case .dark:
                    return ReaderEngineThemeMode.dark.rawValue
                default:
                    return ReaderEngineThemeMode.light.rawValue
                }
            }(),
            fontSizePercentage: 100.0,
            fontFamily: "Original",
            lineHeight: 1.2,
            pageMargins: 1.0,
            scroll: pageMode == .Scroll,
            scrollDirection: scrollDirection == .Horizontal ? 1 : 0,
            volumeKeyPaging: false
        )
    }

    mutating func apply(_ preferences: ReaderEnginePreferences) {
        switch ReaderEngineThemeMode.fromSharedRawValue(preferences.themeMode) {
        case .sepia:
            themeMode = .serpia
        case .green:
            themeMode = .forest
        case .dark, .night:
            themeMode = .dark
        case .light:
            themeMode = .none
        }
        pageMode = preferences.scroll ? .Scroll : .Page
        scrollDirection = preferences.scrollDirection == 0 ? .Vertical : .Horizontal
    }
}
