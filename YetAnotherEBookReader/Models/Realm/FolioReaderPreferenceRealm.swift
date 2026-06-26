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
        
        //skipping currentAudioRate
        //skipping currentHighlightStyle
        //skipping currentMediaOverlayStyle
        
        currentScrollDirection = src.currentScrollDirection
        
        //skipping currentMenuIndex
        
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
        
        //skipping styleOverride
        //skipping structuralStyle
        //skipping structuralTocLevel
    }
}
