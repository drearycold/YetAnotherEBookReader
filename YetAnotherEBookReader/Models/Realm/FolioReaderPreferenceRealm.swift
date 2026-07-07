//
//  FolioReaderPreferenceRealm.swift
//  YetAnotherEBookReader
//

import Foundation
import RealmSwift

class FolioReaderPreferenceRealm: Object {
    override static func primaryKey() -> String? {
        return "id"
    }
    @objc dynamic var id: String = ""
    
    @objc dynamic var nightMode: Bool = false
    @objc dynamic var themeMode: Int = .min
    
    @objc dynamic var currentFont: String?
    @objc dynamic var currentFontSize: String?
    @objc dynamic var currentFontWeight: String?
    
    @objc dynamic var currentAudioRate: Int = .min
    @objc dynamic var currentHighlightStyle: Int = .min
    @objc dynamic var currentMediaOverlayStyle: Int = .min
    
    @objc dynamic var currentScrollDirection: Int = .min
    
    @objc dynamic var currentNavigationMenuIndex: Int = .min
    @objc dynamic var currentAnnotationMenuIndex: Int = .min
    @objc dynamic var currentNavigationMenuBookListStyle: Int = .min
    
    @objc dynamic var currentVMarginLinked: Bool = true
    @objc dynamic var currentMarginTop: Int = .min
    @objc dynamic var currentMarginBottom: Int = .min
    
    @objc dynamic var currentHMarginLinked: Bool = true
    @objc dynamic var currentMarginLeft: Int = .min
    @objc dynamic var currentMarginRight: Int = .min
    
    @objc dynamic var currentLetterSpacing: Int = .min
    @objc dynamic var currentLineHeight: Int = .min
    @objc dynamic var currentTextIndent: Int = .min
    
    @objc dynamic var doWrapPara: Bool = false
    @objc dynamic var doClearClass: Bool = true
    
    @objc dynamic var styleOverride: Int = .min
    @objc dynamic var structuralStyle: Int = 0
    @objc dynamic var structuralTrackingTocLevel: Int = 0
    
    func copyFrom(src: FolioReaderPreferenceRealm) {
        nightMode = src.nightMode
        themeMode = src.themeMode
        
        currentFont = src.currentFont
        currentFontSize = src.currentFontSize
        currentFontWeight = src.currentFontWeight
        
        currentAudioRate = src.currentAudioRate
        currentHighlightStyle = src.currentHighlightStyle
        currentMediaOverlayStyle = src.currentMediaOverlayStyle
        
        currentScrollDirection = src.currentScrollDirection
        
        currentNavigationMenuIndex = src.currentNavigationMenuIndex
        currentAnnotationMenuIndex = src.currentAnnotationMenuIndex
        currentNavigationMenuBookListStyle = src.currentNavigationMenuBookListStyle
        
        currentVMarginLinked = src.currentVMarginLinked
        currentMarginTop = src.currentMarginTop
        currentMarginBottom = src.currentMarginBottom
        
        currentHMarginLinked = src.currentHMarginLinked
        currentMarginLeft = src.currentMarginLeft
        currentMarginRight = src.currentMarginRight
        
        currentLetterSpacing = src.currentLetterSpacing
        currentLineHeight = src.currentLineHeight
        currentTextIndent = src.currentTextIndent
        
        doWrapPara = src.doWrapPara
        doClearClass = src.doClearClass
        
        styleOverride = src.styleOverride
        structuralStyle = src.structuralStyle
        structuralTrackingTocLevel = src.structuralTrackingTocLevel
    }

    func toValue(defaults: FolioReaderProfileValue) -> FolioReaderProfileValue {
        FolioReaderProfileValue(
            nightMode: nightMode,
            themeMode: themeMode != .min ? themeMode : defaults.themeMode,
            currentFont: currentFont ?? defaults.currentFont,
            currentFontSize: currentFontSize ?? defaults.currentFontSize,
            currentFontWeight: currentFontWeight ?? defaults.currentFontWeight,
            currentAudioRate: currentAudioRate != .min ? currentAudioRate : defaults.currentAudioRate,
            currentHighlightStyle: currentHighlightStyle != .min ? currentHighlightStyle : defaults.currentHighlightStyle,
            currentMediaOverlayStyle: currentMediaOverlayStyle != .min ? currentMediaOverlayStyle : defaults.currentMediaOverlayStyle,
            currentScrollDirection: currentScrollDirection != .min ? currentScrollDirection : defaults.currentScrollDirection,
            currentNavigationMenuIndex: currentNavigationMenuIndex != .min ? currentNavigationMenuIndex : defaults.currentNavigationMenuIndex,
            currentAnnotationMenuIndex: currentAnnotationMenuIndex != .min ? currentAnnotationMenuIndex : defaults.currentAnnotationMenuIndex,
            currentNavigationMenuBookListStyle: currentNavigationMenuBookListStyle != .min ? currentNavigationMenuBookListStyle : defaults.currentNavigationMenuBookListStyle,
            currentMarginTop: currentMarginTop != .min ? currentMarginTop : defaults.currentMarginTop,
            currentMarginBottom: currentMarginBottom != .min ? currentMarginBottom : defaults.currentMarginBottom,
            currentMarginLeft: currentMarginLeft != .min ? currentMarginLeft : defaults.currentMarginLeft,
            currentMarginRight: currentMarginRight != .min ? currentMarginRight : defaults.currentMarginRight,
            currentVMarginLinked: currentVMarginLinked,
            currentHMarginLinked: currentHMarginLinked,
            currentLetterSpacing: currentLetterSpacing != .min ? currentLetterSpacing : defaults.currentLetterSpacing,
            currentLineHeight: currentLineHeight != .min ? currentLineHeight : defaults.currentLineHeight,
            currentTextIndent: currentTextIndent != .min ? currentTextIndent : defaults.currentTextIndent,
            doWrapPara: doWrapPara,
            doClearClass: doClearClass,
            styleOverride: styleOverride != .min ? styleOverride : defaults.styleOverride,
            structuralStyle: structuralStyle,
            structuralTrackingTocLevel: structuralTrackingTocLevel
        )
    }

    func apply(_ value: FolioReaderProfileValue) {
        nightMode = value.nightMode
        themeMode = value.themeMode
        currentFont = value.currentFont
        currentFontSize = value.currentFontSize
        currentFontWeight = value.currentFontWeight
        currentAudioRate = value.currentAudioRate
        currentHighlightStyle = value.currentHighlightStyle
        currentMediaOverlayStyle = value.currentMediaOverlayStyle
        currentScrollDirection = value.currentScrollDirection
        currentNavigationMenuIndex = value.currentNavigationMenuIndex
        currentAnnotationMenuIndex = value.currentAnnotationMenuIndex
        currentNavigationMenuBookListStyle = value.currentNavigationMenuBookListStyle
        currentMarginTop = value.currentMarginTop
        currentMarginBottom = value.currentMarginBottom
        currentMarginLeft = value.currentMarginLeft
        currentMarginRight = value.currentMarginRight
        currentVMarginLinked = value.currentVMarginLinked
        currentHMarginLinked = value.currentHMarginLinked
        currentLetterSpacing = value.currentLetterSpacing
        currentLineHeight = value.currentLineHeight
        currentTextIndent = value.currentTextIndent
        doWrapPara = value.doWrapPara
        doClearClass = value.doClearClass
        styleOverride = value.styleOverride
        structuralStyle = value.structuralStyle
        structuralTrackingTocLevel = value.structuralTrackingTocLevel
    }

    var hasCompletePreferenceValue: Bool {
        currentFont != nil &&
        currentFontSize != nil &&
        currentFontWeight != nil &&
        themeMode != .min &&
        currentAudioRate != .min &&
        currentHighlightStyle != .min &&
        currentMediaOverlayStyle != .min &&
        currentScrollDirection != .min &&
        currentNavigationMenuIndex != .min &&
        currentAnnotationMenuIndex != .min &&
        currentNavigationMenuBookListStyle != .min &&
        currentMarginTop != .min &&
        currentMarginBottom != .min &&
        currentMarginLeft != .min &&
        currentMarginRight != .min &&
        currentLetterSpacing != .min &&
        currentLineHeight != .min &&
        currentTextIndent != .min &&
        styleOverride != .min
    }
}
