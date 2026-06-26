//
//  PDFOptionsRealm.swift
//  YetAnotherEBookReader
//

import Foundation
import UIKit
import RealmSwift

extension PDFThemeMode: PersistableEnum {}
extension PDFAutoScaler: PersistableEnum {}
extension PDFLayoutMode: PersistableEnum {}
extension PDFReadDirection: PersistableEnum {}
extension PDFScrollDirection: PersistableEnum {}

struct PDFPreferenceValue: Equatable {
    var themeMode = PDFThemeMode.serpia
    var selectedAutoScaler = PDFAutoScaler.Width
    var pageMode = PDFLayoutMode.Page
    var readingDirection = PDFReadDirection.LtR_TtB
    var scrollDirection = PDFScrollDirection.Vertical

    var hMarginAutoScaler = 5.0
    var vMarginAutoScaler = 5.0
    var hMarginDetectStrength = 2.0
    var vMarginDetectStrength = 2.0
    var marginOffset = 0.0
    var lastScale = 1.0
    var rememberInPagePosition = true

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

class PDFOptions: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId
    
    @Persisted var bookId: Int32 = 0
    @Persisted var libraryName: String = ""
    
    @Persisted var themeMode = PDFThemeMode.serpia
    @Persisted var selectedAutoScaler = PDFAutoScaler.Width
    @Persisted var pageMode = PDFLayoutMode.Page
    @Persisted var readingDirection = PDFReadDirection.LtR_TtB
    @Persisted var scrollDirection = PDFScrollDirection.Vertical
    
    @Persisted var hMarginAutoScaler = 5.0
    @Persisted var vMarginAutoScaler = 5.0
    @Persisted var hMarginDetectStrength = 2.0
    @Persisted var vMarginDetectStrength = 2.0
    @Persisted var marginOffset = 0.0
    @Persisted var lastScale = 1.0
    @Persisted var rememberInPagePosition = true
    
    public func update(other: PDFOptions) {
        self.themeMode = other.themeMode
        self.selectedAutoScaler = other.selectedAutoScaler
        self.pageMode = other.pageMode
        self.readingDirection = other.readingDirection
        self.scrollDirection = other.scrollDirection
        self.hMarginAutoScaler = other.hMarginAutoScaler
        self.vMarginAutoScaler = other.vMarginAutoScaler
        self.hMarginDetectStrength = other.hMarginDetectStrength
        self.vMarginDetectStrength = other.vMarginDetectStrength
        self.marginOffset = other.marginOffset
        self.lastScale = other.lastScale
        self.rememberInPagePosition = other.rememberInPagePosition
    }

    func toValue() -> PDFPreferenceValue {
        PDFPreferenceValue(
            themeMode: themeMode,
            selectedAutoScaler: selectedAutoScaler,
            pageMode: pageMode,
            readingDirection: readingDirection,
            scrollDirection: scrollDirection,
            hMarginAutoScaler: hMarginAutoScaler,
            vMarginAutoScaler: vMarginAutoScaler,
            hMarginDetectStrength: hMarginDetectStrength,
            vMarginDetectStrength: vMarginDetectStrength,
            marginOffset: marginOffset,
            lastScale: lastScale,
            rememberInPagePosition: rememberInPagePosition
        )
    }

    func apply(_ value: PDFPreferenceValue) {
        themeMode = value.themeMode
        selectedAutoScaler = value.selectedAutoScaler
        pageMode = value.pageMode
        readingDirection = value.readingDirection
        scrollDirection = value.scrollDirection
        hMarginAutoScaler = value.hMarginAutoScaler
        vMarginAutoScaler = value.vMarginAutoScaler
        hMarginDetectStrength = value.hMarginDetectStrength
        vMarginDetectStrength = value.vMarginDetectStrength
        marginOffset = value.marginOffset
        lastScale = value.lastScale
        rememberInPagePosition = value.rememberInPagePosition
    }
}
