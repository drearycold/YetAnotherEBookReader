//
//  YabrReaderSettingsViewModel.swift
//  YetAnotherEBookReader
//
//  Created by Gemini CLI on 2024/03/26.
//

import SwiftUI
import Combine
import ReadiumShared
import ReadiumNavigator

enum ReaderEngineType {
    case readium
    case folio
}

class YabrReaderSettingsViewModel: ObservableObject {
    let engineType: ReaderEngineType
    var onReadiumPreferencesSubmit: ((EPUBPreferences) -> Void)?
    
    private var readiumEditor: EPUBPreferencesEditor?
    private var cancellables = Set<AnyCancellable>()
    
    // Unified UI state
    @Published var themeMode: Int = 0 { didSet { syncToEngine() } }
    @Published var fontSizePercentage: Double = 100.0 { didSet { syncToEngine() } }
    @Published var fontFamily: String = "Original" { didSet { syncToEngine() } }
    @Published var lineHeight: Double = 1.2 { didSet { syncToEngine() } }
    @Published var pageMargins: Double = 1.0 { didSet { syncToEngine() } }
    @Published var publisherStyles: Bool = true { didSet { syncToEngine() } }
    @Published var scroll: Bool = false { didSet { syncToEngine() } }
    @Published var textAlign: Int = 0 { didSet { syncToEngine() } }
    
    // New parameters
    @Published var columnCount: Int = 0 { didSet { syncToEngine() } } // 0: Auto, 1: 1, 2: 2
    @Published var fontWeight: Double = 1.0 { didSet { syncToEngine() } }
    @Published var letterSpacing: Double = 0.0 { didSet { syncToEngine() } }
    @Published var wordSpacing: Double = 0.0 { didSet { syncToEngine() } }
    @Published var hyphens: Bool = false { didSet { syncToEngine() } }
    @Published var imageFilter: Int = 0 { didSet { syncToEngine() } } // 0: None, 1: Darken, 2: Invert
    @Published var textNormalization: Bool = false { didSet { syncToEngine() } }
    @Published var typeScale: Double = 1.2 { didSet { syncToEngine() } }
    @Published var paragraphIndent: Double = 0.0 { didSet { syncToEngine() } }
    @Published var paragraphSpacing: Double = 0.0 { didSet { syncToEngine() } }

    let supportedFontFamilies: [String] = [
        "Original",
        "serif",
        "sans-serif",
        "monospace",
        "IA Writer Duospace",
        "AccessibleDfA",
        "OpenDyslexic",
        "Iowan Old Style",
        "Palatino"
    ]
    
    init(engineType: ReaderEngineType, 
         readiumPrefs: EPUBPreferences? = nil,
         readiumMetadata: Metadata? = nil,
         readiumDefaults: EPUBDefaults? = nil) {
        self.engineType = engineType
        
        if engineType == .readium {
            let initialPrefs = readiumPrefs ?? EPUBPreferences()
            let editor = EPUBPreferencesEditor(
                initialPreferences: initialPrefs,
                metadata: readiumMetadata ?? Metadata(title: ""),
                defaults: readiumDefaults ?? EPUBDefaults()
            )
            self.readiumEditor = editor
            
            // Use the combined preferences from the editor for initialization
            let prefs = editor.preferences
            
            // Initialize UI state
            let theme = prefs.theme ?? editor.theme.effectiveValue
            switch theme {
            case .light: self.themeMode = 0
            case .sepia: self.themeMode = 1
            case .dark: self.themeMode = 2
            }
            
            self.fontSizePercentage = (prefs.fontSize ?? editor.fontSize.effectiveValue) * 100.0
            
            if let fontFamilyValue = ((prefs.fontFamily ?? editor.fontFamily.effectiveValue) as Any) as? FontFamily {
                self.fontFamily = fontFamilyValue.rawValue
            } else {
                self.fontFamily = "Original"
            }
            
            self.lineHeight = prefs.lineHeight ?? editor.lineHeight.effectiveValue
            self.pageMargins = prefs.pageMargins ?? editor.pageMargins.effectiveValue
            self.publisherStyles = prefs.publisherStyles ?? editor.publisherStyles.effectiveValue
            self.scroll = prefs.scroll ?? editor.scroll.effectiveValue
            
            let textAlignValue = prefs.textAlign ?? editor.textAlign.effectiveValue
            switch textAlignValue {
            case .start: self.textAlign = 1
            case .left: self.textAlign = 2
            case .right: self.textAlign = 3
            case .justify: self.textAlign = 4
            default: self.textAlign = 0
            }
            
            let columnCountValue = prefs.columnCount ?? editor.columnCount.effectiveValue
            switch columnCountValue {
            case .auto: self.columnCount = 0
            case .one: self.columnCount = 1
            case .two: self.columnCount = 2
            }
            
            self.fontWeight = prefs.fontWeight ?? editor.fontWeight.effectiveValue
            self.letterSpacing = prefs.letterSpacing ?? editor.letterSpacing.effectiveValue
            self.wordSpacing = prefs.wordSpacing ?? editor.wordSpacing.effectiveValue
            self.hyphens = prefs.hyphens ?? editor.hyphens.effectiveValue
            
            if let filter = (prefs.imageFilter ?? editor.imageFilter.effectiveValue) as ImageFilter? {
                switch filter {
                case .darken: self.imageFilter = 1
                case .invert: self.imageFilter = 2
                @unknown default: self.imageFilter = 0
                }
            } else {
                self.imageFilter = 0
            }
            
            self.textNormalization = prefs.textNormalization ?? editor.textNormalization.effectiveValue
            self.typeScale = prefs.typeScale ?? editor.typeScale.effectiveValue
            self.paragraphIndent = prefs.paragraphIndent ?? editor.paragraphIndent.effectiveValue
            self.paragraphSpacing = prefs.paragraphSpacing ?? editor.paragraphSpacing.effectiveValue
        }
    }
    
    private func syncToEngine() {
        switch engineType {
        case .readium:
            guard let editor = readiumEditor else { return }
            
            // Sync Theme
            let readiumTheme: ReadiumNavigator.Theme
            switch themeMode {
            case 0: readiumTheme = .light
            case 1: readiumTheme = .sepia
            case 2: readiumTheme = .dark
            default: readiumTheme = .light
            }
            editor.theme.set(readiumTheme)
            
            editor.fontSize.set(fontSizePercentage / 100.0)
            
            if fontFamily == "Original" {
                editor.fontFamily.set(nil)
            } else {
                editor.fontFamily.set(FontFamily(rawValue: fontFamily))
            }
            
            editor.lineHeight.set(lineHeight)
            editor.pageMargins.set(pageMargins)
            editor.publisherStyles.set(publisherStyles)
            editor.scroll.set(scroll)
            
            let readiumAlign: ReadiumNavigator.TextAlignment?
            switch textAlign {
            case 1: readiumAlign = .start
            case 2: readiumAlign = .left
            case 3: readiumAlign = .right
            case 4: readiumAlign = .justify
            default: readiumAlign = nil
            }
            editor.textAlign.set(readiumAlign)
            
            let readiumColumnCount: ColumnCount
            switch columnCount {
            case 1: readiumColumnCount = .one
            case 2: readiumColumnCount = .two
            default: readiumColumnCount = .auto
            }
            editor.columnCount.set(readiumColumnCount)
            
            editor.fontWeight.set(fontWeight)
            editor.letterSpacing.set(letterSpacing)
            editor.wordSpacing.set(wordSpacing)
            editor.hyphens.set(hyphens)
            
            let readiumImageFilter: ImageFilter?
            switch imageFilter {
            case 1: readiumImageFilter = .darken
            case 2: readiumImageFilter = .invert
            default: readiumImageFilter = nil
            }
            editor.imageFilter.set(readiumImageFilter)
            
            editor.textNormalization.set(textNormalization)
            editor.typeScale.set(typeScale)
            editor.paragraphIndent.set(paragraphIndent)
            editor.paragraphSpacing.set(paragraphSpacing)
            
            onReadiumPreferencesSubmit?(editor.preferences)
            
        case .folio:
            break
        }
    }
}
