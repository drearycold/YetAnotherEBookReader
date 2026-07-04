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

    var fillColor: CGColor {
        switch themeMode {
        case .none:
            return .init(gray: 0.0, alpha: 0.0)
        case .serpia:
            return CGColor(red: 0.98046875, green: 0.9375, blue: 0.84765625, alpha: 1.0)
        case .forest:
            return CGColor(
                red: CGFloat(Int("BA", radix: 16) ?? 255) / 255.0,
                green: CGFloat(Int("D5", radix: 16) ?? 255) / 255.0,
                blue: CGFloat(Int("C1", radix: 16) ?? 255) / 255.0,
                alpha: 1.0
            )
        case .dark:
            return .init(gray: 0.0, alpha: 1.0)
        }
    }

    func toReaderEnginePreferences() -> ReaderEnginePreferences {
        ReaderEnginePreferences(
            themeMode: {
                switch themeMode {
                case .serpia:
                    return 1
                case .dark:
                    return 2
                default:
                    return 0
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
        switch preferences.themeMode {
        case 1:
            themeMode = .serpia
        case 2:
            themeMode = .dark
        default:
            themeMode = .none
        }
        pageMode = preferences.scroll ? .Scroll : .Page
        scrollDirection = preferences.scrollDirection == 0 ? .Vertical : .Horizontal
    }
}
