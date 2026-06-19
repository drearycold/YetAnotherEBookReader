//
//  ReadiumPreferenceAdapter.swift
//  YetAnotherEBookReader
//

import Foundation
import UIKit
import RealmSwift
import ReadiumNavigator
import ReadiumShared

extension ReadiumPreferenceRealm {
    
    var themeColor: UIColor {
        switch themeMode {
        case 1: // Sepia
            return UIColor(red: 0.98, green: 0.96, blue: 0.91, alpha: 1.0) // #FAF4E8
        case 2: // Dark
            return .black
        default: // Light
            return .white
        }
    }

    func toEPUBPreferences() -> EPUBPreferences {
        EPUBPreferences(
            columnCount: self.columnCount == 0 ? .auto : (self.columnCount == 1 ? .one : .two),
            fit: {
                switch self.fit {
                case 1: return .page
                case 2: return .width
                default: return .auto
                }
            }(),
            fontFamily: self.fontFamily == "Original" ? nil : ReadiumNavigator.FontFamily(rawValue: self.fontFamily),
            fontSize: self.fontSizePercentage / 100.0,
            fontWeight: self.fontWeight,
            hyphens: self.hyphens,
            imageFilter: self.imageFilter == 0 ? nil : (self.imageFilter == 1 ? .darken : .invert),
            letterSpacing: self.letterSpacing,
            ligatures: self.ligatures,
            lineHeight: self.lineHeight,
            offsetFirstPage: self.offsetFirstPage,
            pageMargins: self.pageMargins,
            paragraphIndent: self.paragraphIndent,
            paragraphSpacing: self.paragraphSpacing,
            publisherStyles: self.publisherStyles,
            readingProgression: self.readingProgression == 0 ? .ltr : .rtl,
            scroll: self.scroll,
            spread: {
                switch self.spread {
                case 1: return .never
                case 2: return .always
                default: return .auto
                }
            }(),
            textAlign: {
                switch self.textAlign {
                case 1: return .start
                case 2: return .left
                case 3: return .right
                case 4: return .justify
                default: return nil
                }
            }(),
            textNormalization: self.textNormalization,
            theme: {
                switch self.themeMode {
                case 1: return .sepia
                case 2: return .dark
                default: return .light
                }
            }(),
            typeScale: self.typeScale,
            verticalText: self.verticalText,
            wordSpacing: self.wordSpacing
        )
    }
    
    func toPDFPreferences() -> PDFPreferences {
        PDFPreferences(
            fit: {
                switch self.fit {
                case 1: return .page
                case 2: return .width
                default: return .auto
                }
            }(),
            offsetFirstPage: self.offsetFirstPage,
            pageSpacing: self.pageSpacing,
            readingProgression: self.readingProgression == 0 ? .ltr : .rtl,
            scroll: self.scroll,
            scrollAxis: self.scrollAxis == 1 ? .horizontal : .vertical,
            spread: {
                switch self.spread {
                case 1: return .never
                case 2: return .always
                default: return .auto
                }
            }(),
            visibleScrollbar: self.visibleScrollbar
        )
    }
    
    func update(from settings: EPUBSettings) {
        switch settings.theme {
        case .light: self.themeMode = 0
        case .sepia: self.themeMode = 1
        case .dark: self.themeMode = 2
        }
        
        self.fontSizePercentage = settings.fontSize * 100.0
        self.fontFamily = settings.fontFamily?.rawValue ?? "Original"
        self.lineHeight = settings.lineHeight ?? 1.2
        self.pageMargins = settings.pageMargins
        self.publisherStyles = settings.publisherStyles
        self.scroll = settings.scroll
        self.readingProgression = settings.readingProgression == .rtl ? 1 : 0
        
        switch settings.textAlign {
        case .start: self.textAlign = 1
        case .left: self.textAlign = 2
        case .right: self.textAlign = 3
        case .justify: self.textAlign = 4
        default: self.textAlign = 0
        }
        
        switch settings.columnCount {
        case .auto: self.columnCount = 0
        case .one: self.columnCount = 1
        case .two: self.columnCount = 2
        }
        
        self.fontWeight = settings.fontWeight ?? 1.0
        self.letterSpacing = settings.letterSpacing ?? 0.0
        self.wordSpacing = settings.wordSpacing ?? 0.0
        self.hyphens = settings.hyphens ?? false
        
        switch settings.imageFilter {
        case .darken: self.imageFilter = 1
        case .invert: self.imageFilter = 2
        default: self.imageFilter = 0
        }
        
        self.textNormalization = settings.textNormalization
        self.typeScale = settings.typeScale ?? 1.2
        self.paragraphIndent = settings.paragraphIndent ?? 0.0
        self.paragraphSpacing = settings.paragraphSpacing ?? 0.0
        self.ligatures = settings.ligatures ?? false
        self.offsetFirstPage = settings.offsetFirstPage ?? false
        self.verticalText = settings.verticalText
        
        switch settings.spread {
        case .never: self.spread = 1
        case .always: self.spread = 2
        default: self.spread = 0
        }
        
        switch settings.fit {
        case .page: self.fit = 1
        case .width: self.fit = 2
        default: self.fit = 0
        }
    }
    
    func update(from settings: PDFSettings) {
        self.scroll = settings.scroll
        self.readingProgression = settings.readingProgression == .rtl ? 1 : 0
        self.offsetFirstPage = settings.offsetFirstPage
        self.pageSpacing = settings.pageSpacing
        self.scrollAxis = settings.scrollAxis == .horizontal ? 1 : 0
        self.visibleScrollbar = settings.visibleScrollbar
        
        switch settings.fit {
        case .page: self.fit = 1
        case .width: self.fit = 2
        default: self.fit = 0
        }
        
        switch settings.spread {
        case .never: self.spread = 1
        case .always: self.spread = 2
        default: self.spread = 0
        }
    }
    
    func update(from preferences: EPUBPreferences) {
        switch preferences.theme {
        case .light?: self.themeMode = 0
        case .sepia?: self.themeMode = 1
        case .dark?: self.themeMode = 2
        case nil: self.themeMode = 0
        }
        
        self.fontSizePercentage = (preferences.fontSize ?? 1.0) * 100.0
        self.fontFamily = preferences.fontFamily?.rawValue ?? "Original"
        self.lineHeight = preferences.lineHeight ?? 1.2
        self.pageMargins = preferences.pageMargins ?? 1.0
        self.publisherStyles = preferences.publisherStyles ?? true
        self.scroll = preferences.scroll ?? false
        
        if let readingProgression = preferences.readingProgression {
            self.readingProgression = readingProgression == .rtl ? 1 : 0
        } else {
            self.readingProgression = 0
        }
        
        switch preferences.textAlign {
        case .start?: self.textAlign = 1
        case .left?: self.textAlign = 2
        case .right?: self.textAlign = 3
        case .justify?: self.textAlign = 4
        default: self.textAlign = 0
        }
        
        switch preferences.columnCount {
        case .one?: self.columnCount = 1
        case .two?: self.columnCount = 2
        default: self.columnCount = 0
        }
        
        self.fontWeight = preferences.fontWeight ?? 1.0
        self.letterSpacing = preferences.letterSpacing ?? 0.0
        self.wordSpacing = preferences.wordSpacing ?? 0.0
        self.hyphens = preferences.hyphens ?? false
        
        switch preferences.imageFilter {
        case .darken?: self.imageFilter = 1
        case .invert?: self.imageFilter = 2
        default: self.imageFilter = 0
        }
        
        self.textNormalization = preferences.textNormalization ?? false
        self.typeScale = preferences.typeScale ?? 1.2
        self.paragraphIndent = preferences.paragraphIndent ?? 0.0
        self.paragraphSpacing = preferences.paragraphSpacing ?? 0.0
        self.ligatures = preferences.ligatures ?? false
        self.offsetFirstPage = preferences.offsetFirstPage
        self.verticalText = preferences.verticalText ?? false
        
        switch preferences.spread {
        case .never?: self.spread = 1
        case .always?: self.spread = 2
        default: self.spread = 0
        }
        
        switch preferences.fit {
        case .page?: self.fit = 1
        case .width?: self.fit = 2
        default: self.fit = 0
        }
    }
    
    func update(from preferences: PDFPreferences) {
        self.scroll = preferences.scroll ?? false
        
        if let readingProgression = preferences.readingProgression {
            self.readingProgression = readingProgression == .rtl ? 1 : 0
        } else {
            self.readingProgression = 0
        }
        
        self.offsetFirstPage = preferences.offsetFirstPage
        self.pageSpacing = preferences.pageSpacing ?? 0.0
        self.scrollAxis = preferences.scrollAxis == .horizontal ? 1 : 0
        self.visibleScrollbar = preferences.visibleScrollbar ?? true
        
        switch preferences.fit {
        case .page?: self.fit = 1
        case .width?: self.fit = 2
        default: self.fit = 0
        }
        
        switch preferences.spread {
        case .never?: self.spread = 1
        case .always?: self.spread = 2
        default: self.spread = 0
        }
    }
}
