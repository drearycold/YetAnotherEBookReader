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
    
    var isDark: Bool {
        themeMode == .dark
    }

    func isDark<T>(_ f: T, _ l: T) -> T{
        isDark ? f : l
    }

    var fillColor: CGColor {
        switch (themeMode) {
        case .none:
            return .init(gray: 0.0, alpha: 0.0)
        case .serpia:   //#FBF0D9
            return CGColor(red: 0.98046875, green: 0.9375, blue: 0.84765625, alpha: 1.0)
        case .forest:   //#BAD5C1
            return CGColor(
                red: CGFloat(Int("BA", radix: 16) ?? 255) / 255.0,
                green: CGFloat(Int("D5", radix: 16) ?? 255) / 255.0,
                blue: CGFloat(Int("C1", radix: 16) ?? 255) / 255.0,
                alpha: 1.0)
        case .dark:
            return .init(gray: 0.0, alpha: 1.0)
        }
    }
    
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
}
