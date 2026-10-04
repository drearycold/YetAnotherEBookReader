//
//  PDFOptionsRealm.swift
//  YetAnotherEBookReader
//

import Foundation
import RealmSwift

extension PDFThemeMode: PersistableEnum {}
extension PDFAutoScaler: PersistableEnum {}
extension PDFLayoutMode: PersistableEnum {}
extension PDFReadDirection: PersistableEnum {}
extension PDFScrollDirection: PersistableEnum {}
extension PDFSpreadMode: PersistableEnum {}
extension PDFColumnsMode: PersistableEnum {}

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
    /// Optional (schema 143): rows saved before have no value, which reads as Off.
    /// A non-optional enum column would come back as "" for them and crash on read.
    @Persisted var spreadMode: PDFSpreadMode?
    @Persisted var columnsMode: PDFColumnsMode?
    
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
        self.spreadMode = other.spreadMode
        self.columnsMode = other.columnsMode
    }

}
